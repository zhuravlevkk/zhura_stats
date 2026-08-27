import { writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const TOKEN_URL = "https://www.warcraftlogs.com/oauth/token";
const API_URL = "https://www.warcraftlogs.com/api/v2/client";

const DEFAULTS = {
  outFile: "./WoWLogsStatsPrio.lua",
  threads: 3,
  maxAttempts: 3,
  retryBaseDelaySeconds: 5,
};

const ALL_SPECS = [
  ["death-knight", "blood"], ["death-knight", "frost"], ["death-knight", "unholy"],
  ["demon-hunter", "havoc"], ["demon-hunter", "vengeance"],
  ["druid", "balance"], ["druid", "feral"], ["druid", "guardian"], ["druid", "restoration"],
  ["evoker", "augmentation"], ["evoker", "devastation"], ["evoker", "preservation"],
  ["hunter", "beast-mastery"], ["hunter", "marksmanship"], ["hunter", "survival"],
  ["mage", "arcane"], ["mage", "fire"], ["mage", "frost"],
  ["monk", "brewmaster"], ["monk", "mistweaver"], ["monk", "windwalker"],
  ["paladin", "holy"], ["paladin", "protection"], ["paladin", "retribution"],
  ["priest", "discipline"], ["priest", "holy"], ["priest", "shadow"],
  ["rogue", "assassination"], ["rogue", "outlaw"], ["rogue", "subtlety"],
  ["shaman", "elemental"], ["shaman", "enhancement"], ["shaman", "restoration"],
  ["warlock", "affliction"], ["warlock", "demonology"], ["warlock", "destruction"],
  ["warrior", "arms"], ["warrior", "fury"], ["warrior", "protection"],
];

const ACTIVITIES = [
  {
    slug: "m+",
    request: {
      zoneTypeSlug: "mythic-plus",
      difficultySlug: "10",
      encounterSlug: "all-dungeons",
      affixesSlug: "this-week",
    },
  },
  {
    slug: "raid",
    request: {
      zoneTypeSlug: "raid",
      difficultySlug: "mythic",
      encounterSlug: "all-bosses",
      affixesSlug: null,
    },
    fallbackRequest: {
      zoneTypeSlug: "raid",
      difficultySlug: "heroic",
      encounterSlug: "all-bosses",
      affixesSlug: null,
    },
  },
];

const RETRYABLE_STATUS_CODES = new Set([408, 429, 500, 502, 503, 504]);

const ARCHON_ROOT_QUERY = `
  query FindArchonViewModels {
    __type(name: "Query") {
      fields {
        name
        args {
          name
          type { kind name ofType { kind name ofType { kind name } } }
        }
        type { kind name ofType { kind name ofType { kind name } } }
      }
    }
  }
`;

class ApiError extends Error {
  constructor(message, details = {}) {
    super(message);
    this.name = "ApiError";
    Object.assign(this, details);
  }
}

function parseInteger(value, name, minimum, maximum) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed < minimum || parsed > maximum) {
    throw new Error(`${name} must be between ${minimum} and ${maximum}.`);
  }
  return parsed;
}

function parseArgs(argv) {
  const options = { ...DEFAULTS };
  const mappings = {
    "--out-file": "outFile",
    "--threads": "threads",
    "--max-attempts": "maxAttempts",
    "--retry-base-delay-seconds": "retryBaseDelaySeconds",
  };

  for (let index = 0; index < argv.length; index += 2) {
    const key = mappings[argv[index]];
    const value = argv[index + 1];
    if (!key || value === undefined) {
      throw new Error(`Unknown or incomplete argument: ${argv[index] ?? "<missing>"}`);
    }
    options[key] = value;
  }

  options.threads = parseInteger(options.threads, "threads", 1, 10);
  options.maxAttempts = parseInteger(options.maxAttempts, "max-attempts", 1, 5);
  options.retryBaseDelaySeconds = parseInteger(options.retryBaseDelaySeconds, "retry-base-delay-seconds", 1, 60);
  options.outFile = resolve(options.outFile);
  return options;
}

function requireCredentials() {
  const clientId = process.env.WCL_CLIENT_ID?.trim();
  const clientSecret = process.env.WCL_CLIENT_SECRET?.trim();
  const missing = [];
  if (!clientId) missing.push("WCL_CLIENT_ID");
  if (!clientSecret) missing.push("WCL_CLIENT_SECRET");
  if (missing.length > 0) {
    throw new Error(`Missing required environment variables: ${missing.join(", ")}. Create a Warcraft Logs API client and add both values as GitHub Actions secrets.`);
  }
  return { clientId, clientSecret };
}

function buildJobs() {
  const jobs = [];
  for (const activity of ACTIVITIES) {
    for (const [classSlug, specSlug] of ALL_SPECS) {
      for (const type of ["overview", "talents"]) {
        jobs.push({
          type,
          classSlug,
          specSlug,
          activity: activity.slug,
          request: { ...activity.request, categorySlug: type },
          fallbackRequest: activity.fallbackRequest ? { ...activity.fallbackRequest, categorySlug: type } : null,
        });
      }
    }
  }
  return jobs;
}

function sleep(milliseconds) {
  return new Promise((resolvePromise) => setTimeout(resolvePromise, milliseconds));
}

function luaString(value) {
  return String(value).replaceAll("\\", "\\\\").replaceAll('"', '\\"').replaceAll("\r", "\\r").replaceAll("\n", "\\n");
}

function retryAfterMilliseconds(response) {
  const value = response.headers.get("retry-after");
  if (!value) return null;
  const seconds = Number(value);
  if (Number.isFinite(seconds)) return Math.max(0, seconds * 1000);
  const date = Date.parse(value);
  return Number.isFinite(date) ? Math.max(0, date - Date.now()) : null;
}

function responseErrorMessage(payload, fallback) {
  if (Array.isArray(payload?.errors) && payload.errors.length > 0) {
    return payload.errors.map((error) => error.message).filter(Boolean).join("; ").slice(0, 1000);
  }
  if (typeof payload?.error_description === "string") return payload.error_description.slice(0, 1000);
  if (typeof payload?.error === "string") return payload.error.slice(0, 1000);
  return fallback;
}

async function fetchJson(url, init, label, options) {
  for (let attempt = 1; attempt <= options.maxAttempts; attempt += 1) {
    let response = null;
    try {
      response = await fetch(url, { ...init, signal: AbortSignal.timeout(30_000) });
      const text = await response.text();
      let payload = null;
      try {
        payload = text ? JSON.parse(text) : null;
      } catch {
        throw new ApiError(`${label} returned non-JSON data.`, { status: response.status });
      }
      if (!response.ok) {
        throw new ApiError(`${label} failed: ${responseErrorMessage(payload, `HTTP ${response.status}`)}`, {
          status: response.status,
          retryAfterMilliseconds: retryAfterMilliseconds(response),
        });
      }
      return payload;
    } catch (error) {
      const status = error?.status ?? response?.status ?? null;
      const retryable = status === null || RETRYABLE_STATUS_CODES.has(status);
      if (!retryable || attempt === options.maxAttempts) {
        console.warn(`WCL API request label=${label} attempt=${attempt}/${options.maxAttempts} status=${status ?? "none"} action=fail`);
        throw error;
      }
      const delayMilliseconds = error?.retryAfterMilliseconds ?? options.retryBaseDelaySeconds * 1000 * (2 ** (attempt - 1)) + Math.floor(Math.random() * 1000);
      console.warn(`WCL API request label=${label} attempt=${attempt}/${options.maxAttempts} status=${status ?? "none"} action=retry delay_ms=${delayMilliseconds}`);
      await sleep(delayMilliseconds);
    }
  }
  throw new Error(`${label} attempts exhausted.`);
}

async function getAccessToken(credentials, options) {
  const authorization = Buffer.from(`${credentials.clientId}:${credentials.clientSecret}`, "utf8").toString("base64");
  const payload = await fetchJson(TOKEN_URL, {
    method: "POST",
    headers: {
      Authorization: `Basic ${authorization}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({ grant_type: "client_credentials" }),
  }, "OAuth token", options);
  if (typeof payload?.access_token !== "string" || payload.access_token.length === 0) {
    throw new Error("OAuth token response did not contain access_token.");
  }
  return payload.access_token;
}

async function graphqlRequest(accessToken, query, variables, label, options) {
  const payload = await fetchJson(API_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ query, variables }),
  }, label, options);
  if (Array.isArray(payload?.errors) && payload.errors.length > 0) {
    const message = responseErrorMessage(payload, "GraphQL request failed.");
    throw new ApiError(`${label} failed: ${message}`, { graphqlErrors: payload.errors });
  }
  if (!payload?.data) throw new Error(`${label} response did not contain data.`);
  return payload.data;
}

function namedType(type) {
  let current = type;
  while (current?.ofType) current = current.ofType;
  return current?.name ?? null;
}

function isRequiredType(type) {
  return type?.kind === "NON_NULL";
}

async function discoverArchonRootField(accessToken, options) {
  const data = await graphqlRequest(accessToken, ARCHON_ROOT_QUERY, {}, "schema introspection", options);
  const fields = data?.__type?.fields;
  if (!Array.isArray(fields)) {
    throw new Error("GraphQL introspection did not return Query fields.");
  }
  const field = fields.find((candidate) => namedType(candidate.type) === "ArchonViewModels");
  if (!field) {
    throw new Error("This Warcraft Logs API client cannot access ArchonViewModels. Contact Warcraft Logs support or use an approved endpoint that exposes buildsSpecPage.");
  }
  const requiredArguments = (field.args ?? []).filter((argument) => isRequiredType(argument.type));
  if (requiredArguments.length > 0) {
    throw new Error(`Query.${field.name} requires unsupported arguments: ${requiredArguments.map((argument) => argument.name).join(", ")}.`);
  }
  if (!/^[_A-Za-z][_0-9A-Za-z]*$/.test(field.name)) {
    throw new Error(`GraphQL returned an invalid Query field name: ${field.name}`);
  }
  console.log(`Using Warcraft Logs GraphQL field Query.${field.name} -> ArchonViewModels.`);
  return field.name;
}

function buildsSpecPageQuery(rootField) {
  return `
    query BuildsSpecPage(
      $gameSlug: String,
      $classSlug: String,
      $specSlug: String,
      $zoneTypeSlug: String,
      $categorySlug: String,
      $difficultySlug: String,
      $encounterSlug: String,
      $affixesSlug: String
    ) {
      archon: ${rootField} {
        page: buildsSpecPage(
          gameSlug: $gameSlug,
          classSlug: $classSlug,
          specSlug: $specSlug,
          zoneTypeSlug: $zoneTypeSlug,
          categorySlug: $categorySlug,
          difficultySlug: $difficultySlug,
          encounterSlug: $encounterSlug,
          affixesSlug: $affixesSlug
        )
      }
    }
  `;
}

function normalizePageData(value) {
  let current = value;
  if (typeof current === "string") {
    try {
      current = JSON.parse(current);
    } catch {
      return null;
    }
  }
  const candidates = [
    current?.props?.pageProps?.page,
    current?.pageProps?.page,
    current?.page,
    current,
  ];
  return candidates.find((candidate) => Array.isArray(candidate?.sections)) ?? null;
}

async function fetchBuildsSpecPage(api, jobRequest, label) {
  const variables = {
    gameSlug: "wow",
    classSlug: api.job.classSlug,
    specSlug: api.job.specSlug,
    ...jobRequest,
  };
  const data = await graphqlRequest(api.accessToken, api.query, variables, label, api.options);
  return normalizePageData(data?.archon?.page);
}

function buildOverviewLua(job, pageData, timestamp) {
  const statSection = pageData.sections?.find((section) => section.component === "BuildsStatPrioritySection");
  const stats = statSection?.props?.stats;
  if (!Array.isArray(stats) || stats.length < 2) return { status: "skip:no-stat-data" };

  const primary = stats.find((stat) => stat.order === 1);
  const primaryName = String(primary?.name ?? "primary").toLowerCase();
  const statLines = stats
    .filter((stat) => stat.order >= 2)
    .sort((left, right) => left.order - right.order)
    .map((stat) => {
      const name = String(stat.name).toLowerCase() === "vers" ? "versatility" : String(stat.name).toLowerCase();
      return `        { stat = "${luaString(name)}", rating = ${stat.value}, order = ${stat.order} },`;
    })
    .join("\n");

  const key = `${job.classSlug}/${job.specSlug}/${job.activity}`;
  return {
    status: "ok",
    lua: `WoWLogsStatsPrio["${key}"] = {\n    updated = "${timestamp}",\n    activity = "${job.activity}", class = "${job.classSlug}", spec = "${job.specSlug}",\n    primary = "${luaString(primaryName)}",\n    secondary = {\n${statLines}\n    },\n}\n`,
  };
}

function buildTalentsLua(job, pageData) {
  const heroSection = pageData.sections?.find((section) => section.component === "BuildsHeroTalentsSection");
  const selectedNodes = heroSection?.props?.talentTree?.dehydratedBuild?.selectedNodes;
  if (!Array.isArray(selectedNodes)) return { status: "skip:no-hero-section" };

  const idToName = new Map();
  const rootTalentToTree = new Map();
  for (const blueprint of Object.values(pageData.talentTreeBlueprints ?? {})) {
    for (const heroTree of blueprint.heroTrees ?? []) idToName.set(Number(heroTree.id), heroTree.name);
    for (const node of blueprint.changeSet?.allNodes ?? []) {
      if (node.type !== "subtree") continue;
      for (const ability of node.abilities ?? []) {
        if (ability.heroTreeId != null) rootTalentToTree.set(Number(ability.id), Number(ability.heroTreeId));
      }
    }
  }

  const usageByTree = new Map();
  for (const selection of selectedNodes) {
    const talentId = Number(selection[0]);
    const treeId = rootTalentToTree.get(talentId);
    if (treeId !== undefined) usageByTree.set(treeId, Number(selection[1]));
  }
  const usageTotal = [...usageByTree.values()].reduce((sum, value) => sum + value, 0);
  if (usageByTree.size === 0 || usageTotal <= 0) return { status: "skip:no-hero-usage" };

  const heroLines = [...usageByTree.entries()]
    .sort((left, right) => right[1] - left[1])
    .map(([treeId, usage], index) => {
      const name = idToName.get(treeId) ?? `hero_${treeId}`;
      const slug = String(name).toLowerCase().replaceAll(" ", "-");
      const percentage = Math.round((1000 * usage) / usageTotal) / 10;
      return `        { hero = "${luaString(slug)}", rank = ${index + 1}, usage_pct = ${percentage} },`;
    })
    .join("\n");

  const key = `${job.classSlug}/${job.specSlug}/${job.activity}`;
  return { status: "ok", lua: `WoWLogsStatsPrio["${key}"].heroes = {\n${heroLines}\n}\n` };
}

async function processJob(api, job, timestamp) {
  let label = `${job.type} ${job.classSlug}/${job.specSlug}/${job.activity}`;
  try {
    let pageData = null;
    for (const request of [job.request, job.fallbackRequest]) {
      if (!request) continue;
      const candidate = await fetchBuildsSpecPage({ ...api, job }, request, label);
      if (!candidate) continue;
      if (Object.hasOwn(candidate, "totalParses") && Number(candidate.totalParses) === 0 && request !== job.fallbackRequest) continue;
      pageData = candidate;
      if (request === job.fallbackRequest) label += " [heroic fallback]";
      break;
    }
    if (!pageData) return { ...job, label, status: "skip:no-page-data", lua: null };
    const built = job.type === "overview" ? buildOverviewLua(job, pageData, timestamp) : buildTalentsLua(job, pageData);
    return { ...job, label, lua: built.lua ?? null, status: built.status };
  } catch (error) {
    return { ...job, label, status: `err:${error?.status ?? error?.name ?? "unknown"}`, lua: null, error };
  }
}

async function collectJobs(api, jobs, timestamp, options) {
  const results = [];
  let nextIndex = 0;

  async function worker() {
    while (true) {
      const index = nextIndex;
      nextIndex += 1;
      if (index >= jobs.length) return;
      const result = await processJob(api, jobs[index], timestamp);
      results.push(result);
      const info = result.lua ? "OK" : result.status;
      console.log(`[${String(results.length).padStart(3)}/${jobs.length}] ${result.label.padEnd(55)} ${info}`);
    }
  }

  await Promise.all(Array.from({ length: Math.min(options.threads, jobs.length) }, () => worker()));
  return results;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const credentials = requireCredentials();
  const timestamp = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const jobs = buildJobs();
  console.log(`Authenticating with Warcraft Logs for ${jobs.length} Archon API queries...`);

  const accessToken = await getAccessToken(credentials, options);
  const rootField = await discoverArchonRootField(accessToken, options);
  const api = { accessToken, query: buildsSpecPageQuery(rootField), options };

  const preflight = await processJob(api, jobs[0], timestamp);
  if (!preflight.lua) {
    const reason = preflight.error?.message ?? preflight.status;
    throw new Error(`Preflight failed: ${reason}. Remaining queries were not requested.`);
  }
  console.log(`[  1/${jobs.length}] ${preflight.label.padEnd(55)} OK (preflight)`);

  const remaining = await collectJobs(api, jobs.slice(1), timestamp, options);
  const collected = [preflight, ...remaining];
  const overviews = collected.filter((result) => result.type === "overview" && result.lua).sort((a, b) => `${a.classSlug}/${a.specSlug}/${a.activity}`.localeCompare(`${b.classSlug}/${b.specSlug}/${b.activity}`));
  const heroes = collected.filter((result) => result.type === "talents" && result.lua).sort((a, b) => `${a.classSlug}/${a.specSlug}/${a.activity}`.localeCompare(`${b.classSlug}/${b.specSlug}/${b.activity}`));
  const expectedPerType = ALL_SPECS.length * ACTIVITIES.length;
  if (overviews.length !== expectedPerType || heroes.length !== expectedPerType) {
    throw new Error(`Incomplete API result: expected ${expectedPerType} stat and ${expectedPerType} hero entries, got ${overviews.length} stat and ${heroes.length} hero. Not writing file.`);
  }

  const header = `-- Auto-generated by Get-AllStats.mjs\n-- Source: Warcraft Logs GraphQL API (ArchonViewModels)\n-- ${timestamp}\n-- Fetched: ${overviews.length + heroes.length} entries (${overviews.length} stat, ${heroes.length} hero), skipped: 0\n\nWoWLogsStatsPrio = WoWLogsStatsPrio or {}\n\n`;
  const lua = header + overviews.map((result) => result.lua).join("\n") + "\n" + heroes.map((result) => result.lua).join("\n");
  await writeFile(options.outFile, lua, "utf8");
  console.log(`Done: ${overviews.length + heroes.length} ok, 0 skipped -> ${options.outFile}`);
}

main().catch((error) => {
  console.error(error.stack || error.message || error);
  process.exitCode = 1;
});

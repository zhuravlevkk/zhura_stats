import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { chromium } from "playwright";

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
    overviewPart: "mythic-plus/overview/10/all-dungeons/this-week",
    talentsPart: "mythic-plus/talents/10/all-dungeons/this-week",
  },
  {
    slug: "raid",
    overviewPart: "raid/overview/mythic/all-bosses",
    talentsPart: "raid/talents/mythic/all-bosses",
    fallbackOverviewPart: "raid/overview/heroic/all-bosses",
    fallbackTalentsPart: "raid/talents/heroic/all-bosses",
  },
];

const RETRYABLE_STATUS_CODES = new Set([403, 408, 429, 500, 502, 503, 504]);

class RequestError extends Error {
  constructor(message, details = {}) {
    super(message);
    this.name = "RequestError";
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

function buildJobs() {
  const jobs = [];
  for (const activity of ACTIVITIES) {
    for (const [classSlug, specSlug] of ALL_SPECS) {
      for (const type of ["overview", "talents"]) {
        const partName = type === "overview" ? "overviewPart" : "talentsPart";
        const fallbackName = type === "overview" ? "fallbackOverviewPart" : "fallbackTalentsPart";
        const prefix = `https://www.archon.gg/wow/builds/${specSlug}/${classSlug}/`;
        jobs.push({
          type,
          classSlug,
          specSlug,
          activity: activity.slug,
          url: prefix + activity[partName],
          fallbackUrl: activity[fallbackName] ? prefix + activity[fallbackName] : null,
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

function requestMarker(html) {
  if (/Human Verification|One Quick Check|I am a human and not a bot/i.test(html)) return "human-verification";
  if (/cf_chl_opt|Just a moment|Enable JavaScript and cookies/i.test(html)) return "cloudflare-challenge";
  return "missing-next-data";
}

function logRequestFailure({ attempt, maxAttempts, status, headers, marker, action, delayMilliseconds, url }) {
  const fields = [
    `attempt=${attempt}/${maxAttempts}`,
    `status=${status ?? "none"}`,
    `server=${headers.server ?? "-"}`,
    `cf-ray=${headers["cf-ray"] ?? "-"}`,
    `marker=${marker}`,
    `action=${action}`,
  ];
  if (delayMilliseconds !== undefined) fields.push(`delay_ms=${delayMilliseconds}`);
  fields.push(`url=${url}`);
  console.warn(`Archon request ${fields.join(" ")}`);
}

async function fetchNextData(page, url, options) {
  for (let attempt = 1; attempt <= options.maxAttempts; attempt += 1) {
    let response = null;
    let status = null;
    let headers = {};
    let marker = "unknown";

    try {
      response = await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30_000 });
      status = response?.status() ?? null;
      headers = response ? await response.allHeaders() : {};

      try {
        await page.waitForSelector("script#__NEXT_DATA__", { state: "attached", timeout: 8_000 });
      } catch {}

      const nextData = await page.locator("script#__NEXT_DATA__").textContent().catch(() => null);
      if (!nextData) {
        const html = await page.content().catch(() => "");
        marker = requestMarker(html);
        throw new RequestError("Response is missing __NEXT_DATA__.", { status, headers, marker });
      }
      return JSON.parse(nextData);
    } catch (error) {
      if (error instanceof RequestError) {
        status = error.status ?? status;
        headers = error.headers ?? headers;
        marker = error.marker ?? marker;
      } else {
        marker = error?.name || "Error";
      }

      const retryable = marker === "cloudflare-challenge" || marker === "human-verification" || marker === "missing-next-data" || status === null || RETRYABLE_STATUS_CODES.has(status);
      if (!retryable || attempt === options.maxAttempts) {
        logRequestFailure({ attempt, maxAttempts: options.maxAttempts, status, headers, marker, action: "fail", url });
        throw error;
      }

      const delayMilliseconds = options.retryBaseDelaySeconds * 1000 * (2 ** (attempt - 1)) + Math.floor(Math.random() * 1000);
      logRequestFailure({ attempt, maxAttempts: options.maxAttempts, status, headers, marker, action: "retry", delayMilliseconds, url });
      await sleep(delayMilliseconds);
    }
  }
  throw new Error("Request attempts exhausted.");
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

async function processJob(page, job, timestamp, options) {
  let label = `${job.type} ${job.classSlug}/${job.specSlug}/${job.activity}`;
  try {
    let pageData = null;
    for (const url of [job.url, job.fallbackUrl]) {
      if (!url) continue;
      const nextData = await fetchNextData(page, url, options);
      const candidate = nextData?.props?.pageProps?.page;
      if (!candidate) continue;
      if (Object.hasOwn(candidate, "totalParses") && Number(candidate.totalParses) === 0 && url !== job.fallbackUrl) continue;
      pageData = candidate;
      if (url === job.fallbackUrl) label += " [heroic fallback]";
      break;
    }
    if (!pageData) return { ...job, label, status: "skip:no-page-data", lua: null };
    const built = job.type === "overview" ? buildOverviewLua(job, pageData, timestamp) : buildTalentsLua(job, pageData);
    return { ...job, label, lua: built.lua ?? null, status: built.status };
  } catch (error) {
    return {
      ...job,
      label,
      status: `err:${error?.status ?? error?.name ?? "unknown"}`,
      lua: null,
      diagnostic: {
        name: error?.name ?? "Error",
        message: error?.message ?? String(error),
        status: error?.status ?? null,
        marker: error?.marker ?? null,
        server: error?.headers?.server ?? null,
        cfRay: error?.headers?.["cf-ray"] ?? null,
      },
    };
  }
}

async function savePreflightDiagnostics(page, result, directory) {
  if (!directory) return;
  const outputDirectory = resolve(directory);
  await mkdir(outputDirectory, { recursive: true });
  await page.screenshot({ path: resolve(outputDirectory, "preflight.png"), fullPage: true });
  const details = {
    capturedAt: new Date().toISOString(),
    title: await page.title().catch(() => null),
    url: page.url(),
    visibleText: (await page.locator("body").innerText().catch(() => "")).slice(0, 2000),
    result: result.diagnostic ?? { status: result.status },
  };
  await writeFile(resolve(outputDirectory, "preflight.json"), `${JSON.stringify(details, null, 2)}\n`, "utf8");
  console.error(`Saved preflight diagnostics to ${outputDirectory}`);
}

async function collectJobs(context, jobs, timestamp, options) {
  const results = [];
  let nextIndex = 0;

  async function worker() {
    const page = await context.newPage();
    try {
      while (true) {
        const index = nextIndex;
        nextIndex += 1;
        if (index >= jobs.length) return;
        const result = await processJob(page, jobs[index], timestamp, options);
        results.push(result);
        const info = result.lua ? "OK" : result.status;
        console.log(`[${String(results.length).padStart(3)}/${jobs.length}] ${result.label.padEnd(55)} ${info}`);
      }
    } finally {
      await page.close();
    }
  }

  await Promise.all(Array.from({ length: Math.min(options.threads, jobs.length) }, () => worker()));
  return results;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const timestamp = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const jobs = buildJobs();
  console.log(`Launching Playwright Chromium for ${jobs.length} Archon pages with ${options.threads} pages...`);

  const browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext({
      locale: "en-US",
      userAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
      viewport: { width: 1440, height: 1000 },
      extraHTTPHeaders: { "Accept-Language": "en-US,en;q=0.9" },
    });

    const preflightPage = await context.newPage();
    const preflight = await processJob(preflightPage, jobs[0], timestamp, options);
    if (!preflight.lua) {
      await savePreflightDiagnostics(preflightPage, preflight, process.env.ARCHON_DIAGNOSTICS_DIR);
      await preflightPage.close();
      throw new Error(`Preflight failed: ${preflight.status}. Remaining pages were not requested.`);
    }
    await preflightPage.close();
    console.log(`[  1/${jobs.length}] ${preflight.label.padEnd(55)} OK (preflight)`);

    const remaining = await collectJobs(context, jobs.slice(1), timestamp, options);
    const collected = [preflight, ...remaining];
    const overviews = collected.filter((result) => result.type === "overview" && result.lua).sort((a, b) => `${a.classSlug}/${a.specSlug}/${a.activity}`.localeCompare(`${b.classSlug}/${b.specSlug}/${b.activity}`));
    const heroes = collected.filter((result) => result.type === "talents" && result.lua).sort((a, b) => `${a.classSlug}/${a.specSlug}/${a.activity}`.localeCompare(`${b.classSlug}/${b.specSlug}/${b.activity}`));
    const expectedPerType = ALL_SPECS.length * ACTIVITIES.length;
    if (overviews.length !== expectedPerType || heroes.length !== expectedPerType) {
      throw new Error(`Incomplete scrape: expected ${expectedPerType} stat and ${expectedPerType} hero entries, got ${overviews.length} stat and ${heroes.length} hero. Not writing file.`);
    }

    const header = `-- Auto-generated by Get-AllStats.mjs\n-- Source: archon.gg\n-- ${timestamp}\n-- Fetched: ${overviews.length + heroes.length} entries (${overviews.length} stat, ${heroes.length} hero), skipped: 0\n\nWoWLogsStatsPrio = WoWLogsStatsPrio or {}\n\n`;
    const lua = header + overviews.map((result) => result.lua).join("\n") + "\n" + heroes.map((result) => result.lua).join("\n");
    await writeFile(options.outFile, lua, "utf8");
    console.log(`Done: ${overviews.length + heroes.length} ok, 0 skipped -> ${options.outFile}`);
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  console.error(error.stack || error.message || error);
  process.exitCode = 1;
});

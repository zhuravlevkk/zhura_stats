import { writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const ARCHON_ORIGIN = "https://www.archon.gg";

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
    overview: "mythic-plus/overview/10/all-dungeons/this-week",
    talents: "mythic-plus/talents/10/all-dungeons/this-week",
  },
  {
    slug: "raid",
    overview: "raid/overview/mythic/all-bosses",
    talents: "raid/talents/mythic/all-bosses",
    fallbackOverview: "raid/overview/heroic/all-bosses",
    fallbackTalents: "raid/talents/heroic/all-bosses",
  },
];

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

function sleep(milliseconds) {
  return new Promise((resolvePromise) => setTimeout(resolvePromise, milliseconds));
}

function luaString(value) {
  return String(value)
    .replaceAll("\\", "\\\\")
    .replaceAll('"', '\\"')
    .replaceAll("\r", "\\r")
    .replaceAll("\n", "\\n");
}

function challengeMarker(html) {
  if (/Human Verification|One Quick Check|I am a human and not a bot/i.test(html)) return "human-verification";
  if (/cf_chl_opt|Just a moment|Performing security verification|Verify you are human/i.test(html)) return "cloudflare-challenge";
  return "missing-next-data";
}

function extractNextData(html) {
  const match = html.match(/<script[^>]*\bid=(['"])__NEXT_DATA__\1[^>]*>([\s\S]*?)<\/script>/i);
  if (!match?.[2]) return null;
  try {
    return JSON.parse(match[2]);
  } catch (error) {
    throw new Error(`Invalid __NEXT_DATA__ JSON: ${error.message}`);
  }
}

function buildJobs() {
  const jobs = [];
  for (const activity of ACTIVITIES) {
    for (const [classSlug, specSlug] of ALL_SPECS) {
      for (const type of ["overview", "talents"]) {
        const title = type === "overview" ? "Overview" : "Talents";
        const prefix = `${ARCHON_ORIGIN}/wow/builds/${specSlug}/${classSlug}/`;
        jobs.push({
          type,
          classSlug,
          specSlug,
          activity: activity.slug,
          url: prefix + activity[type],
          fallbackUrl: activity[`fallback${title}`] ? prefix + activity[`fallback${title}`] : null,
        });
      }
    }
  }
  return jobs;
}

async function fetchNextData(url, options) {
  for (let attempt = 1; attempt <= options.maxAttempts; attempt += 1) {
    let status = null;
    let marker = "request-error";
    try {
      const response = await fetch(url, {
        method: "GET",
        redirect: "follow",
        cache: "no-store",
        signal: AbortSignal.timeout(30_000),
        headers: {
          Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
          "Accept-Language": "en-US,en;q=0.9",
          "Cache-Control": "no-cache",
          Pragma: "no-cache",
          "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
        },
      });
      status = response.status;
      const html = await response.text();
      const nextData = extractNextData(html);
      if (response.ok && nextData) return nextData;
      marker = challengeMarker(html);
    } catch (error) {
      marker = error?.name === "Error" ? error.message : (error?.name ?? "request-error");
    }

    if (attempt === options.maxAttempts) {
      throw new Error(`Request failed after ${attempt} attempts: status=${status ?? "none"}, marker=${marker}, url=${url}`);
    }

    const delayMilliseconds = options.retryBaseDelaySeconds * 1000 * (2 ** (attempt - 1)) + Math.floor(Math.random() * 1000);
    console.warn(`Retry ${attempt}/${options.maxAttempts}: status=${status ?? "none"}, marker=${marker}, delay=${delayMilliseconds}ms, url=${url}`);
    await sleep(delayMilliseconds);
  }
  throw new Error(`Request attempts exhausted: ${url}`);
}

function buildOverviewLua(job, page, timestamp) {
  const stats = page.sections?.find((section) => section.component === "BuildsStatPrioritySection")?.props?.stats;
  if (!Array.isArray(stats) || stats.length < 2) return null;

  const primary = stats.find((stat) => stat.order === 1);
  const lines = stats
    .filter((stat) => stat.order >= 2)
    .sort((left, right) => left.order - right.order)
    .map((stat) => {
      const rawName = String(stat.name).toLowerCase();
      const name = rawName === "vers" ? "versatility" : rawName;
      return `        { stat = "${luaString(name)}", rating = ${stat.value}, order = ${stat.order} },`;
    })
    .join("\n");

  const key = `${job.classSlug}/${job.specSlug}/${job.activity}`;
  return `WoWLogsStatsPrio["${key}"] = {\n    updated = "${timestamp}",\n    activity = "${job.activity}", class = "${job.classSlug}", spec = "${job.specSlug}",\n    primary = "${luaString(String(primary?.name ?? "primary").toLowerCase())}",\n    secondary = {\n${lines}\n    },\n}\n`;
}

function buildTalentsLua(job, page) {
  const selectedNodes = page.sections?.find((section) => section.component === "BuildsHeroTalentsSection")
    ?.props?.talentTree?.dehydratedBuild?.selectedNodes;
  if (!Array.isArray(selectedNodes)) return null;

  const names = new Map();
  const talentTrees = new Map();
  for (const blueprint of Object.values(page.talentTreeBlueprints ?? {})) {
    for (const tree of blueprint.heroTrees ?? []) names.set(Number(tree.id), tree.name);
    for (const node of blueprint.changeSet?.allNodes ?? []) {
      if (node.type !== "subtree") continue;
      for (const ability of node.abilities ?? []) {
        if (ability.heroTreeId != null) talentTrees.set(Number(ability.id), Number(ability.heroTreeId));
      }
    }
  }

  const usage = new Map();
  for (const selection of selectedNodes) {
    const treeId = talentTrees.get(Number(selection[0]));
    if (treeId !== undefined) usage.set(treeId, Number(selection[1]));
  }

  const total = [...usage.values()].reduce((sum, value) => sum + value, 0);
  if (usage.size === 0 || total <= 0) return null;

  const lines = [...usage.entries()]
    .sort((left, right) => right[1] - left[1])
    .map(([treeId, value], index) => {
      const name = names.get(treeId) ?? `hero_${treeId}`;
      const slug = String(name).toLowerCase().replaceAll(" ", "-");
      return `        { hero = "${luaString(slug)}", rank = ${index + 1}, usage_pct = ${Math.round(1000 * value / total) / 10} },`;
    })
    .join("\n");

  const key = `${job.classSlug}/${job.specSlug}/${job.activity}`;
  return `WoWLogsStatsPrio["${key}"].heroes = {\n${lines}\n}\n`;
}

async function processJob(job, timestamp, options) {
  let page = null;
  let usedFallback = false;

  for (const url of [job.url, job.fallbackUrl]) {
    if (!url) continue;
    const candidate = (await fetchNextData(url, options))?.props?.pageProps?.page;
    if (!candidate) continue;
    if (Object.hasOwn(candidate, "totalParses") && Number(candidate.totalParses) === 0 && url !== job.fallbackUrl) continue;
    page = candidate;
    usedFallback = url === job.fallbackUrl;
    break;
  }

  if (!page) throw new Error(`No page data for ${job.type} ${job.classSlug}/${job.specSlug}/${job.activity}`);
  const lua = job.type === "overview" ? buildOverviewLua(job, page, timestamp) : buildTalentsLua(job, page);
  if (!lua) throw new Error(`Missing ${job.type} data for ${job.classSlug}/${job.specSlug}/${job.activity}`);
  return { ...job, lua, usedFallback };
}

async function collect(jobs, timestamp, options) {
  const results = new Array(jobs.length);
  let nextIndex = 0;
  let completed = 0;

  async function worker() {
    while (true) {
      const index = nextIndex++;
      if (index >= jobs.length) return;
      const result = await processJob(jobs[index], timestamp, options);
      results[index] = result;
      completed += 1;
      console.log(`[${String(completed).padStart(3)}/${jobs.length}] ${result.type} ${result.classSlug}/${result.specSlug}/${result.activity}${result.usedFallback ? " [heroic fallback]" : ""}`);
    }
  }

  await Promise.all(Array.from({ length: Math.min(options.threads, jobs.length) }, worker));
  return results;
}

function buildLua(results, timestamp) {
  const compare = (left, right) => `${left.classSlug}/${left.specSlug}/${left.activity}`.localeCompare(`${right.classSlug}/${right.specSlug}/${right.activity}`);
  const overviews = results.filter((result) => result?.type === "overview").sort(compare);
  const heroes = results.filter((result) => result?.type === "talents").sort(compare);
  const expected = ALL_SPECS.length * ACTIVITIES.length;

  if (overviews.length !== expected || heroes.length !== expected) {
    throw new Error(`Incomplete result: expected ${expected}/${expected}, got ${overviews.length}/${heroes.length}.`);
  }

  const header = `-- Auto-generated by Get-AllStats.mjs\n-- Source: archon.gg (__NEXT_DATA__ via self-hosted runner)\n-- ${timestamp}\n-- Fetched: ${results.length} entries (${overviews.length} stat, ${heroes.length} hero), skipped: 0\n\nWoWLogsStatsPrio = WoWLogsStatsPrio or {}\n\n`;
  return header + overviews.map((result) => result.lua).join("\n") + "\n" + heroes.map((result) => result.lua).join("\n");
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const timestamp = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const jobs = buildJobs();

  console.log(`Collecting ${jobs.length} Archon entries directly from page __NEXT_DATA__ with ${options.threads} workers...`);
  const results = await collect(jobs, timestamp, options);
  const lua = buildLua(results, timestamp);
  await writeFile(options.outFile, lua, "utf8");
  console.log(`Complete: wrote ${options.outFile} (${results.length} entries).`);
}

main().catch((error) => {
  console.error(error?.stack ?? error);
  process.exitCode = 1;
});

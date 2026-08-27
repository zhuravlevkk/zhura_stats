/*
 * Temporary browser-console fallback for collecting Archon stat priorities.
 * Run from an https://www.archon.gg/wow page after completing human verification.
 * The script downloads WoWLogsStatsPrio.lua only when all 156 entries are valid.
 */
(async () => {
  "use strict";

  const CONFIG = {
    delayMilliseconds: 1500,
    maxAttempts: 3,
    retryBaseDelayMilliseconds: 5000,
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

  function markerFromHtml(html) {
    if (/Human Verification|One Quick Check|I am a human and not a bot/i.test(html)) return "human-verification";
    if (/cf_chl_opt|Just a moment|Performing security verification|Verify you are human/i.test(html)) return "cloudflare-challenge";
    return "missing-next-data";
  }

  function buildJobs() {
    const jobs = [];
    for (const activity of ACTIVITIES) {
      for (const [classSlug, specSlug] of ALL_SPECS) {
        for (const type of ["overview", "talents"]) {
          const partName = type === "overview" ? "overviewPart" : "talentsPart";
          const fallbackName = type === "overview" ? "fallbackOverviewPart" : "fallbackTalentsPart";
          const prefix = location.origin + "/wow/builds/" + specSlug + "/" + classSlug + "/";
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

  async function fetchNextData(url) {
    for (let attempt = 1; attempt <= CONFIG.maxAttempts; attempt += 1) {
      let status = null;
      let marker = "request-error";
      try {
        const response = await fetch(url, {
          method: "GET",
          credentials: "include",
          cache: "no-store",
          redirect: "follow",
          headers: { Accept: "text/html,application/xhtml+xml" },
        });
        status = response.status;
        const html = await response.text();
        const documentCopy = new DOMParser().parseFromString(html, "text/html");
        const nextDataElement = documentCopy.querySelector("script#__NEXT_DATA__");
        if (response.ok && nextDataElement?.textContent) {
          return JSON.parse(nextDataElement.textContent);
        }
        marker = markerFromHtml(html);
      } catch (error) {
        marker = error?.name ?? "request-error";
      }

      if (attempt === CONFIG.maxAttempts) {
        throw new Error(`Request failed after ${attempt} attempts: status=${status ?? "none"}, marker=${marker}, url=${url}`);
      }
      const delay = CONFIG.retryBaseDelayMilliseconds * (2 ** (attempt - 1)) + Math.floor(Math.random() * 1000);
      console.warn(`Retry ${attempt}/${CONFIG.maxAttempts}: status=${status ?? "none"}, marker=${marker}, delay=${delay}ms`);
      await sleep(delay);
    }
    throw new Error(`Request attempts exhausted: ${url}`);
  }

  function buildOverviewLua(job, pageData, timestamp) {
    const section = pageData.sections?.find((candidate) => candidate.component === "BuildsStatPrioritySection");
    const stats = section?.props?.stats;
    if (!Array.isArray(stats) || stats.length < 2) return null;

    const primary = stats.find((stat) => stat.order === 1);
    const primaryName = String(primary?.name ?? "primary").toLowerCase();
    const statLines = stats
      .filter((stat) => stat.order >= 2)
      .sort((left, right) => left.order - right.order)
      .map((stat) => {
        const rawName = String(stat.name).toLowerCase();
        const name = rawName === "vers" ? "versatility" : rawName;
        return `        { stat = "${luaString(name)}", rating = ${stat.value}, order = ${stat.order} },`;
      })
      .join("\n");

    const key = `${job.classSlug}/${job.specSlug}/${job.activity}`;
    return `WoWLogsStatsPrio["${key}"] = {\n    updated = "${timestamp}",\n    activity = "${job.activity}", class = "${job.classSlug}", spec = "${job.specSlug}",\n    primary = "${luaString(primaryName)}",\n    secondary = {\n${statLines}\n    },\n}\n`;
  }

  function buildTalentsLua(job, pageData) {
    const section = pageData.sections?.find((candidate) => candidate.component === "BuildsHeroTalentsSection");
    const selectedNodes = section?.props?.talentTree?.dehydratedBuild?.selectedNodes;
    if (!Array.isArray(selectedNodes)) return null;

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
      const treeId = rootTalentToTree.get(Number(selection[0]));
      if (treeId !== undefined) usageByTree.set(treeId, Number(selection[1]));
    }
    const usageTotal = [...usageByTree.values()].reduce((sum, value) => sum + value, 0);
    if (usageByTree.size === 0 || usageTotal <= 0) return null;

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
    return `WoWLogsStatsPrio["${key}"].heroes = {\n${heroLines}\n}\n`;
  }

  async function processJob(job, timestamp) {
    let pageData = null;
    let usedFallback = false;
    for (const url of [job.url, job.fallbackUrl]) {
      if (!url) continue;
      const nextData = await fetchNextData(url);
      const candidate = nextData?.props?.pageProps?.page;
      if (!candidate) continue;
      if (Object.hasOwn(candidate, "totalParses") && Number(candidate.totalParses) === 0 && url !== job.fallbackUrl) continue;
      pageData = candidate;
      usedFallback = url === job.fallbackUrl;
      break;
    }
    if (!pageData) throw new Error(`No page data for ${job.type} ${job.classSlug}/${job.specSlug}/${job.activity}`);

    const lua = job.type === "overview"
      ? buildOverviewLua(job, pageData, timestamp)
      : buildTalentsLua(job, pageData);
    if (!lua) throw new Error(`Missing ${job.type} data for ${job.classSlug}/${job.specSlug}/${job.activity}`);
    return { ...job, lua, usedFallback };
  }

  function download(filename, contents, type) {
    const blob = new Blob([contents], { type });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = filename;
    anchor.style.display = "none";
    document.body.append(anchor);
    anchor.click();
    anchor.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  if (!/(^|\.)archon\.gg$/i.test(location.hostname)) {
    throw new Error("Open https://www.archon.gg/wow in this tab before running the collector.");
  }

  const timestamp = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const jobs = buildJobs();
  const results = [];
  console.log(`NE Stats: collecting ${jobs.length} Archon entries sequentially. Keep this tab open.`);

  try {
    for (let index = 0; index < jobs.length; index += 1) {
      const result = await processJob(jobs[index], timestamp);
      results.push(result);
      const suffix = result.usedFallback ? " [heroic fallback]" : "";
      console.log(`[${String(index + 1).padStart(3)}/${jobs.length}] ${result.type} ${result.classSlug}/${result.specSlug}/${result.activity}${suffix}`);
      if (index + 1 < jobs.length) {
        await sleep(CONFIG.delayMilliseconds + Math.floor(Math.random() * 500));
      }
    }

    const overviews = results
      .filter((result) => result.type === "overview")
      .sort((left, right) => `${left.classSlug}/${left.specSlug}/${left.activity}`.localeCompare(`${right.classSlug}/${right.specSlug}/${right.activity}`));
    const heroes = results
      .filter((result) => result.type === "talents")
      .sort((left, right) => `${left.classSlug}/${left.specSlug}/${left.activity}`.localeCompare(`${right.classSlug}/${right.specSlug}/${right.activity}`));
    const expectedPerType = ALL_SPECS.length * ACTIVITIES.length;
    if (overviews.length !== expectedPerType || heroes.length !== expectedPerType) {
      throw new Error(`Incomplete result: expected ${expectedPerType}/${expectedPerType}, got ${overviews.length}/${heroes.length}.`);
    }

    const header = `-- Auto-generated by Get-AllStats.browser.js\n-- Source: archon.gg (interactive browser session)\n-- ${timestamp}\n-- Fetched: ${results.length} entries (${overviews.length} stat, ${heroes.length} hero), skipped: 0\n\nWoWLogsStatsPrio = WoWLogsStatsPrio or {}\n\n`;
    const lua = header + overviews.map((result) => result.lua).join("\n") + "\n" + heroes.map((result) => result.lua).join("\n");
    download("WoWLogsStatsPrio.lua", lua, "text/plain;charset=utf-8");
    console.log("NE Stats: complete. WoWLogsStatsPrio.lua was downloaded.");
  } catch (error) {
    console.error("NE Stats collection stopped. No Lua file was generated.", error);
    const diagnostic = JSON.stringify({
      capturedAt: new Date().toISOString(),
      completed: results.length,
      total: jobs.length,
      error: error?.message ?? String(error),
    }, null, 2);
    download("NE-Stats-collection-error.json", `${diagnostic}\n`, "application/json;charset=utf-8");
  }
})();

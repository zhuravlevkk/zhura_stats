// ==UserScript==
// @name         NE Stats: Archon Sync
// @namespace    https://github.com/zhuravlevkk/zhura_stats
// @version      1.0.0
// @description  Manually download complete NE Stats priority data from Archon.
// @match        https://www.archon.gg/wow/*
// @grant        none
// @run-at       document-idle
// ==/UserScript==

(function () {
  "use strict";

  const MAX_CONCURRENCY = 10;
  const MAX_ATTEMPTS = 3;
  const RETRY_DELAY_MS = 5000;

  const SPECS = [
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

  const state = { running: false, cancelled: false };
  const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

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

  function buildJobs() {
    const jobs = [];
    for (const activity of ACTIVITIES) {
      for (const [classSlug, specSlug] of SPECS) {
        for (const type of ["overview", "talents"]) {
          const title = type === "overview" ? "Overview" : "Talents";
          const prefix = `${location.origin}/wow/builds/${specSlug}/${classSlug}/`;
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

  async function fetchNextData(url) {
    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
      if (state.cancelled) throw new Error("Sync cancelled.");
      let status = null;
      let marker = "request-error";
      try {
        const response = await fetch(url, {
          credentials: "include",
          cache: "no-store",
          redirect: "follow",
          headers: { Accept: "text/html,application/xhtml+xml" },
        });
        status = response.status;
        const html = await response.text();
        const parsed = new DOMParser().parseFromString(html, "text/html");
        const nextData = parsed.querySelector("script#__NEXT_DATA__")?.textContent;
        if (response.ok && nextData) return JSON.parse(nextData);
        marker = challengeMarker(html);
      } catch (error) {
        marker = error?.name ?? "request-error";
      }
      if (attempt === MAX_ATTEMPTS) {
        throw new Error(`Request failed: HTTP ${status ?? "none"}, ${marker}, ${url}`);
      }
      await sleep(RETRY_DELAY_MS * (2 ** (attempt - 1)) + Math.floor(Math.random() * 1000));
    }
    throw new Error(`Request attempts exhausted: ${url}`);
  }

  function overviewLua(job, page, timestamp) {
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

  function talentsLua(job, page) {
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

  async function processJob(job, timestamp) {
    let page = null;
    let usedFallback = false;
    for (const url of [job.url, job.fallbackUrl]) {
      if (!url) continue;
      const candidate = (await fetchNextData(url))?.props?.pageProps?.page;
      if (!candidate) continue;
      if (Object.hasOwn(candidate, "totalParses") && Number(candidate.totalParses) === 0 && url !== job.fallbackUrl) continue;
      page = candidate;
      usedFallback = url === job.fallbackUrl;
      break;
    }
    if (!page) throw new Error(`No page data for ${job.type} ${job.classSlug}/${job.specSlug}/${job.activity}`);
    const lua = job.type === "overview" ? overviewLua(job, page, timestamp) : talentsLua(job, page);
    if (!lua) throw new Error(`Missing ${job.type} data for ${job.classSlug}/${job.specSlug}/${job.activity}`);
    return { ...job, lua, usedFallback };
  }

  function download(filename, contents, type) {
    const url = URL.createObjectURL(new Blob([contents], { type }));
    const anchor = Object.assign(document.createElement("a"), { href: url, download: filename });
    document.body.append(anchor);
    anchor.click();
    anchor.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  function createPanel() {
    const panel = document.createElement("section");
    panel.id = "ne-stats-archon-sync";
    panel.innerHTML = `
      <style>
        #ne-stats-archon-sync{position:fixed;right:16px;bottom:16px;z-index:2147483647;width:290px;padding:12px;border:1px solid #4b5563;border-radius:10px;background:#111827;color:#f9fafb;font:13px/1.4 system-ui,sans-serif;box-shadow:0 8px 28px #0009}
        #ne-stats-archon-sync strong{display:block;margin-bottom:8px;font-size:14px}.ne-stats-row{display:flex;align-items:center;gap:8px;margin-top:8px}.ne-stats-row label{flex:1;color:#d1d5db}
        #ne-stats-archon-sync select,#ne-stats-archon-sync button{border:1px solid #6b7280;border-radius:6px;background:#1f2937;color:#fff;padding:6px 8px}#ne-stats-archon-sync button{flex:1;cursor:pointer;background:#2563eb;border-color:#3b82f6;font-weight:600}#ne-stats-archon-sync button[data-running="true"]{background:#991b1b;border-color:#ef4444}
        #ne-stats-archon-sync progress{width:100%;height:10px;margin-top:10px}#ne-stats-sync-status{margin-top:6px;min-height:36px;color:#d1d5db;overflow-wrap:anywhere}
      </style>
      <strong>NE Stats · Archon Sync</strong>
      <div class="ne-stats-row"><label for="ne-stats-sync-concurrency">Parallel requests</label><select id="ne-stats-sync-concurrency"></select></div>
      <div class="ne-stats-row"><button id="ne-stats-sync-button" type="button">Sync and download</button></div>
      <progress id="ne-stats-sync-progress" max="156" value="0"></progress>
      <div id="ne-stats-sync-status">Complete Archon human verification, then start sync.</div>`;
    document.body.append(panel);
    const select = panel.querySelector("#ne-stats-sync-concurrency");
    for (let value = 1; value <= MAX_CONCURRENCY; value += 1) {
      select.add(new Option(String(value), String(value), value === MAX_CONCURRENCY, value === MAX_CONCURRENCY));
    }
    return panel;
  }

  function setStatus(panel, message) {
    panel.querySelector("#ne-stats-sync-status").textContent = message;
  }

  async function sync(panel) {
    const button = panel.querySelector("#ne-stats-sync-button");
    const select = panel.querySelector("#ne-stats-sync-concurrency");
    const progress = panel.querySelector("#ne-stats-sync-progress");
    const concurrency = Math.min(MAX_CONCURRENCY, Math.max(1, Number.parseInt(select.value, 10) || MAX_CONCURRENCY));
    const timestamp = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    const jobs = buildJobs();
    const results = new Array(jobs.length);
    let nextIndex = 0;
    let completed = 0;

    state.running = true;
    state.cancelled = false;
    button.dataset.running = "true";
    button.textContent = "Stop";
    select.disabled = true;
    progress.value = 0;
    setStatus(panel, `Starting ${jobs.length} requests with concurrency ${concurrency}…`);

    async function worker() {
      while (!state.cancelled) {
        const index = nextIndex++;
        if (index >= jobs.length) return;
        const result = await processJob(jobs[index], timestamp);
        results[index] = result;
        completed += 1;
        progress.value = completed;
        setStatus(panel, `${completed}/${jobs.length} · ${result.type} · ${result.classSlug}/${result.specSlug}/${result.activity}${result.usedFallback ? " · heroic fallback" : ""}`);
      }
    }

    try {
      await Promise.all(Array.from({ length: concurrency }, worker));
      if (state.cancelled) {
        setStatus(panel, `Stopped at ${completed}/${jobs.length}. No file generated.`);
        return;
      }
      const compare = (left, right) => `${left.classSlug}/${left.specSlug}/${left.activity}`.localeCompare(`${right.classSlug}/${right.specSlug}/${right.activity}`);
      const overviews = results.filter((result) => result?.type === "overview").sort(compare);
      const heroes = results.filter((result) => result?.type === "talents").sort(compare);
      const expected = SPECS.length * ACTIVITIES.length;
      if (overviews.length !== expected || heroes.length !== expected) {
        throw new Error(`Incomplete result: expected ${expected}/${expected}, got ${overviews.length}/${heroes.length}.`);
      }
      const header = `-- Auto-generated by Get-AllStats.tampermonkey.user.js\n-- Source: archon.gg (interactive browser session)\n-- ${timestamp}\n-- Fetched: ${results.length} entries (${overviews.length} stat, ${heroes.length} hero), skipped: 0\n\nWoWLogsStatsPrio = WoWLogsStatsPrio or {}\n\n`;
      download("WoWLogsStatsPrio.lua", header + overviews.map((result) => result.lua).join("\n") + "\n" + heroes.map((result) => result.lua).join("\n"), "text/plain;charset=utf-8");
      setStatus(panel, `Complete: ${overviews.length} stat + ${heroes.length} hero entries. File downloaded.`);
    } catch (error) {
      const message = error?.message ?? String(error);
      setStatus(panel, `Failed at ${completed}/${jobs.length}: ${message}`);
      download("NE-Stats-collection-error.json", `${JSON.stringify({ capturedAt: new Date().toISOString(), completed, total: jobs.length, concurrency, error: message }, null, 2)}\n`, "application/json;charset=utf-8");
    } finally {
      state.running = false;
      button.dataset.running = "false";
      button.textContent = "Sync and download";
      select.disabled = false;
    }
  }

  if (document.querySelector("#ne-stats-archon-sync")) return;
  const panel = createPanel();
  panel.querySelector("#ne-stats-sync-button").addEventListener("click", () => {
    if (state.running) {
      state.cancelled = true;
      setStatus(panel, "Stopping after active requests finish…");
    } else {
      void sync(panel);
    }
  });
})();

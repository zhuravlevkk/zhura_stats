# Manual Archon sync with Tampermonkey

1. Install the Tampermonkey extension in your browser.
2. Create a new userscript and replace its contents with
   `Get-AllStats.tampermonkey.user.js`.
3. Save the userscript and open any `https://www.archon.gg/wow/...` page.
4. Complete Archon's human verification if it appears.
5. In the **NE Stats · Archon Sync** panel, choose 1-10 parallel requests and
   click **Sync and download**. The default is 10.
6. Replace the addon's `WoWLogsStatsPrio.lua` with the downloaded file.

The userscript downloads `WoWLogsStatsPrio.lua` only after all 156 entries are
collected: 78 stat-priority entries and 78 hero-talent entries. On failure it
downloads `NE-Stats-collection-error.json` instead, so incomplete data cannot
silently replace the addon's working dataset.

#Requires -Version 5.1
<#
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Get-AllStats.ps1
    powershell -ExecutionPolicy Bypass -File .\scripts\Get-AllStats.ps1 -Threads 20
    powershell -ExecutionPolicy Bypass -File .\scripts\Get-AllStats.ps1 -OutFile ".\WoWLogsStatsPrio.lua"
#>

param(
    [string] $OutFile = ".\WoWLogsStatsPrio.lua",
    [int]    $Threads = 15
)

$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$AllSpecs = @(
    @{ class = "death-knight";  spec = "blood"         },
    @{ class = "death-knight";  spec = "frost"         },
    @{ class = "death-knight";  spec = "unholy"        },
    @{ class = "demon-hunter";  spec = "havoc"         },
    @{ class = "demon-hunter";  spec = "vengeance"     },
    @{ class = "druid";         spec = "balance"       },
    @{ class = "druid";         spec = "feral"         },
    @{ class = "druid";         spec = "guardian"      },
    @{ class = "druid";         spec = "restoration"   },
    @{ class = "evoker";        spec = "augmentation"  },
    @{ class = "evoker";        spec = "devastation"   },
    @{ class = "evoker";        spec = "preservation"  },
    @{ class = "hunter";        spec = "beast-mastery" },
    @{ class = "hunter";        spec = "marksmanship"  },
    @{ class = "hunter";        spec = "survival"      },
    @{ class = "mage";          spec = "arcane"        },
    @{ class = "mage";          spec = "fire"          },
    @{ class = "mage";          spec = "frost"         },
    @{ class = "monk";          spec = "brewmaster"    },
    @{ class = "monk";          spec = "mistweaver"    },
    @{ class = "monk";          spec = "windwalker"    },
    @{ class = "paladin";       spec = "holy"          },
    @{ class = "paladin";       spec = "protection"    },
    @{ class = "paladin";       spec = "retribution"   },
    @{ class = "priest";        spec = "discipline"    },
    @{ class = "priest";        spec = "holy"          },
    @{ class = "priest";        spec = "shadow"        },
    @{ class = "rogue";         spec = "assassination" },
    @{ class = "rogue";         spec = "outlaw"        },
    @{ class = "rogue";         spec = "subtlety"      },
    @{ class = "shaman";        spec = "elemental"     },
    @{ class = "shaman";        spec = "enhancement"   },
    @{ class = "shaman";        spec = "restoration"   },
    @{ class = "warlock";       spec = "affliction"    },
    @{ class = "warlock";       spec = "demonology"    },
    @{ class = "warlock";       spec = "destruction"   },
    @{ class = "warrior";       spec = "arms"          },
    @{ class = "warrior";       spec = "fury"          },
    @{ class = "warrior";       spec = "protection"    }
)

$Activities = @(
    @{ slug = "m+";   overviewPart = "mythic-plus/overview/10/all-dungeons/this-week"; talentsPart = "mythic-plus/talents/10/all-dungeons/this-week" },
    @{
        slug                 = "raid"
        overviewPart         = "raid/overview/mythic/all-bosses"
        talentsPart          = "raid/talents/mythic/all-bosses"
        fallbackOverviewPart = "raid/overview/heroic/all-bosses"
        fallbackTalentsPart  = "raid/talents/heroic/all-bosses"
    }
)

# Two job types: "overview" (stat priority) and "talents" (hero breakdown)
$jobs = [System.Collections.Generic.List[hashtable]]::new()
foreach ($act in $Activities) {
    foreach ($s in $AllSpecs) {
        $jobs.Add(@{
            type     = "overview"
            class    = $s.class
            spec     = $s.spec
            activity    = $act.slug
            url         = "https://www.archon.gg/wow/builds/$($s.spec)/$($s.class)/$($act.overviewPart)"
            fallbackUrl = if ($act.fallbackOverviewPart) { "https://www.archon.gg/wow/builds/$($s.spec)/$($s.class)/$($act.fallbackOverviewPart)" } else { $null }
        })
        $jobs.Add(@{
            type     = "talents"
            class    = $s.class
            spec     = $s.spec
            activity    = $act.slug
            url         = "https://www.archon.gg/wow/builds/$($s.spec)/$($s.class)/$($act.talentsPart)"
            fallbackUrl = if ($act.fallbackTalentsPart) { "https://www.archon.gg/wow/builds/$($s.spec)/$($s.class)/$($act.fallbackTalentsPart)" } else { $null }
        })
    }
}

$total = $jobs.Count
Write-Host ""
Write-Host "Firing $total requests with $Threads threads (archon.gg, m+ + raid, stats + hero talents)..." -ForegroundColor Cyan

$worker = {
    param($job, $ts)

    $result = @{
        type     = $job.type
        class    = $job.class
        spec     = $job.spec
        activity = $job.activity
        lua      = $null
        status   = "ok"
        label    = "$($job.type) $($job.class)/$($job.spec)/$($job.activity)"
    }

    $headers = @{
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        "Accept"     = "text/html,application/xhtml+xml"
    }

    try {
        $page = $null
        foreach ($url in @($job.url, $job.fallbackUrl)) {
            if (-not $url) { continue }

            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20 -Headers $headers
            $m    = [regex]::Match($resp.Content, '<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', 'Singleline')
            if (-not $m.Success) { continue }

            $candidatePage = ($m.Groups[1].Value | ConvertFrom-Json).props.pageProps.page
            $hasParseCount = $candidatePage.PSObject.Properties.Name -contains "totalParses"
            if ($hasParseCount -and [long]$candidatePage.totalParses -eq 0 -and $url -ne $job.fallbackUrl) {
                continue
            }

            $page = $candidatePage
            if ($url -eq $job.fallbackUrl) { $result.label += " [heroic fallback]" }
            break
        }
        if (-not $page) { $result.status = "skip:no-page-data"; return $result }

        $sections = $page.sections

        # ---- OVERVIEW: stat priority ----
        if ($job.type -eq "overview") {
            $statSection = $null
            foreach ($sec in $sections) {
                if ($sec.component -eq "BuildsStatPrioritySection") { $statSection = $sec; break }
            }
            if (-not $statSection) { $result.status = "skip:no-stat-section"; return $result }

            $stats       = $statSection.props.stats
            if (-not $stats -or @($stats).Count -lt 2) { $result.status = "skip:no-stat-data"; return $result }
            $primary     = ($stats | Where-Object { $_.order -eq 1 } | Select-Object -First 1)
            $primaryName = if ($primary) { $primary.name.ToLower() } else { "primary" }

            $statLines = ($stats | Where-Object { $_.order -ge 2 } | Sort-Object order | ForEach-Object {
                $name = $_.name.ToLower()
                if ($name -eq "vers") { $name = "versatility" }
                "        { stat = `"$name`", rating = $($_.value), order = $($_.order) },"
            }) -join "`n"

            $key = "$($job.class)/$($job.spec)/$($job.activity)"
            $result.lua = "WoWLogsStatsPrio[`"$key`"] = {`n    updated = `"$ts`",`n    activity = `"$($job.activity)`", class = `"$($job.class)`", spec = `"$($job.spec)`",`n    primary = `"$primaryName`",`n    secondary = {`n$statLines`n    },`n}`n"

        # ---- TALENTS: hero spec breakdown ----
        } else {
            $heroSection = $null
            foreach ($sec in $sections) {
                if ($sec.component -eq "BuildsHeroTalentsSection") { $heroSection = $sec; break }
            }
            if (-not $heroSection) { $result.status = "skip:no-hero-section"; return $result }

            # Build hero tree and root talent maps from talentTreeBlueprints.
            $idToName = @{}
            $rootTalentToTree = @{}
            $blueprints = $page.talentTreeBlueprints
            if ($blueprints) {
                foreach ($bp in $blueprints.PSObject.Properties) {
                    foreach ($ht in $bp.Value.heroTrees) {
                        $idToName[[int]$ht.id] = $ht.name
                    }
                    foreach ($node in $bp.Value.changeSet.allNodes) {
                        if ($node.type -ne "subtree") { continue }
                        foreach ($ability in $node.abilities) {
                            if ($null -ne $ability.heroTreeId) {
                                $rootTalentToTree[[int]$ability.id] = [int]$ability.heroTreeId
                            }
                        }
                    }
                }
            }

            # Usage now lives in selectedNodes. Normalize the root hero talent
            # weights because some parses may not have a recognized hero tree.
            $usageByTree = @{}
            foreach ($selection in $heroSection.props.talentTree.dehydratedBuild.selectedNodes) {
                $talentId = [int]$selection[0]
                if ($rootTalentToTree.ContainsKey($talentId)) {
                    $usageByTree[$rootTalentToTree[$talentId]] = [double]$selection[1]
                }
            }
            $usageTotal = ($usageByTree.Values | Measure-Object -Sum).Sum
            if (-not $usageByTree.Count -or $usageTotal -le 0) { $result.status = "skip:no-hero-usage"; return $result }

            $rank = 0
            $heroLines = ($usageByTree.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
                $rank++
                $id   = [int]$_.Key
                $name = if ($idToName.ContainsKey($id)) { $idToName[$id] } else { "hero_$id" }
                $slug = $name.ToLower() -replace ' ', '-'
                $pct  = [math]::Round(100 * [double]$_.Value / $usageTotal, 1)
                "        { hero = `"$slug`", rank = $rank, usage_pct = $pct },"
            }) -join "`n"
            $key = "$($job.class)/$($job.spec)/$($job.activity)"
            $result.lua = "WoWLogsStatsPrio[`"$key`"].heroes = {`n$heroLines`n}`n"
        }

    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        $result.status = "err:$(if ($code) { $code } else { $_.Exception.Message.Split("`n")[0] })"
    }

    return $result
}

# Fire all jobs at once
$pool = [RunspaceFactory]::CreateRunspacePool(1, $Threads)
$pool.Open()

$pending = [System.Collections.Generic.List[hashtable]]::new()
foreach ($job in $jobs) {
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript($worker).AddArgument($job).AddArgument($Timestamp)
    $pending.Add(@{ ps = $ps; handle = $ps.BeginInvoke() })
}

Write-Host "All $total jobs fired. Collecting..." -ForegroundColor DarkCyan
Write-Host ""

$collected = [System.Collections.Generic.List[hashtable]]::new()
$remaining = [System.Collections.Generic.List[hashtable]]::new($pending)

while ($remaining.Count -gt 0) {
    $stillRunning = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($r in $remaining) {
        if ($r.handle.IsCompleted) {
            $res = $r.ps.EndInvoke($r.handle)[0]
            $r.ps.Dispose()
            $collected.Add($res)

            $color = if ($res.lua) { "Green" } elseif ($res.status -like "skip*") { "DarkGray" } else { "Red" }
            $info  = if ($res.lua) { "OK" } else { $res.status }
            Write-Host ("  [{0,3}/{1}] {2,-55} {3}" -f $collected.Count, $total, $res.label, $info) -ForegroundColor $color
        } else {
            $stillRunning.Add($r)
        }
    }
    $remaining = $stillRunning
    if ($remaining.Count -gt 0) { Start-Sleep -Milliseconds 50 }
}

$pool.Close()
$pool.Dispose()

# Sort: overview entries first (they define the table key), heroes appended after
$overviews = $collected | Where-Object { $_.type -eq "overview" -and $_.lua } | Sort-Object { "$($_.class)/$($_.spec)/$($_.activity)" }
$heroes    = $collected | Where-Object { $_.type -eq "talents"  -and $_.lua } | Sort-Object { "$($_.class)/$($_.spec)/$($_.activity)" }
$ok        = $overviews.Count + $heroes.Count
$skipped   = $total - $ok

$header = "-- Auto-generated by Get-AllStats.ps1`n-- Source: archon.gg`n-- $Timestamp`n-- Fetched: $ok entries ($($overviews.Count) stat, $($heroes.Count) hero), skipped: $skipped`n`nWoWLogsStatsPrio = WoWLogsStatsPrio or {}`n`n"
$lua    = $header + (($overviews | ForEach-Object { $_.lua }) -join "`n") + "`n" + (($heroes | ForEach-Object { $_.lua }) -join "`n")

if ($heroes.Count -ne $overviews.Count) {
    Write-Error ("Incomplete scrape: {0} stat entries but only {1} hero entries. Not writing file." -f $overviews.Count, $heroes.Count)
    exit 1
}

# Lua 5.1 parsers reject a UTF-8 BOM; Windows PowerShell UTF8 encoding writes BOM by default.
$outPath = if ([System.IO.Path]::IsPathRooted($OutFile)) {
    $OutFile
} else {
    [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutFile))
}
[System.IO.File]::WriteAllText($outPath, $lua, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host ("Done: {0} ok, {1} skipped -> {2}" -f $ok, $skipped, $OutFile) -ForegroundColor Green

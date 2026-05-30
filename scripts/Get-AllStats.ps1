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
    @{ slug = "raid"; overviewPart = "raid/overview/mythic/all-bosses";                talentsPart = "raid/talents/mythic/all-bosses" }
)

# Two job types: "overview" (stat priority) and "talents" (hero breakdown)
$jobs = [System.Collections.Generic.List[hashtable]]::new()
foreach ($act in $Activities) {
    foreach ($s in $AllSpecs) {
        $jobs.Add(@{
            type     = "overview"
            class    = $s.class
            spec     = $s.spec
            activity = $act.slug
            url      = "https://www.archon.gg/wow/builds/$($s.spec)/$($s.class)/$($act.overviewPart)"
        })
        $jobs.Add(@{
            type     = "talents"
            class    = $s.class
            spec     = $s.spec
            activity = $act.slug
            url      = "https://www.archon.gg/wow/builds/$($s.spec)/$($s.class)/$($act.talentsPart)"
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
        $resp = Invoke-WebRequest -Uri $job.url -UseBasicParsing -TimeoutSec 20 -Headers $headers
        $m    = [regex]::Match($resp.Content, '<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', 'Singleline')
        if (-not $m.Success) { $result.status = "skip:no-next-data"; return $result }

        $page     = ($m.Groups[1].Value | ConvertFrom-Json).props.pageProps.page
        $sections = $page.sections

        # ---- OVERVIEW: stat priority ----
        if ($job.type -eq "overview") {
            $statSection = $null
            foreach ($sec in $sections) {
                if ($sec.component -eq "BuildsStatPrioritySection") { $statSection = $sec; break }
            }
            if (-not $statSection) { $result.status = "skip:no-stat-section"; return $result }

            $stats       = $statSection.props.stats
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

            # Build id->name map from talentTreeBlueprints
            $idToName = @{}
            $blueprints = $page.talentTreeBlueprints
            if ($blueprints) {
                foreach ($bp in $blueprints.PSObject.Properties) {
                    foreach ($ht in $bp.Value.heroTrees) {
                        $idToName[[int]$ht.id] = $ht.name
                    }
                }
            }

            $subTreeStats = $heroSection.props.subTreeStats
            if (-not $subTreeStats) { $result.status = "skip:no-subtree-stats"; return $result }

            # Parse usage % from description with regex
            $desc        = $heroSection.props.description
            $usageMap    = @{}
            $usageRex    = [regex]'<Styled type=''[^'']+''>([\d.]+)%</Styled> usage'
            $nameRex     = [regex]'<Styled type=''[^'']+''>([\w ]+)</Styled> with'
            $nameMatches = $nameRex.Matches($desc)
            $pctMatches  = $usageRex.Matches($desc)
            for ($i = 0; $i -lt [math]::Min($nameMatches.Count, $pctMatches.Count); $i++) {
                $usageMap[$nameMatches[$i].Groups[1].Value] = [double]$pctMatches[$i].Groups[1].Value
            }

            $heroLines = ($subTreeStats | Sort-Object rank | ForEach-Object {
                $id   = [int]$_.id
                $name = if ($idToName.ContainsKey($id)) { $idToName[$id] } else { "hero_$id" }
                $slug = $name.ToLower() -replace ' ', '-'
                $pct  = if ($usageMap.ContainsKey($name)) { $usageMap[$name] } else { 0 }
                "        { hero = `"$slug`", rank = $($_.rank), usage_pct = $pct },"
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

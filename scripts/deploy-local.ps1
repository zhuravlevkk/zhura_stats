param(
    [string] $TargetPath = 'C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\ZhuraStats'
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$toc = Join-Path $workspace 'ZhuraStats.toc'
$files = Get-Content -LiteralPath $toc | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and $_ -notmatch '^#|^Locales[\\/]' }
$payload = @('ZhuraStats.toc', 'Locales', 'Libs', 'Media') + @($files)

$addonFolder = New-Item -ItemType Directory -Path $TargetPath -Force
foreach ($relativePath in $payload) {
    Copy-Item -LiteralPath (Join-Path $workspace $relativePath) -Destination $addonFolder.FullName -Recurse -Force
}

Write-Host "Deployed ZhuraStats to $($addonFolder.FullName)"

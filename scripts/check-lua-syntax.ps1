$ErrorActionPreference = "Stop"

$luacCandidates = @(
    "C:\Program Files (x86)\Lua\5.1\luac.exe",
    "C:\Program Files\Lua\5.1\luac.exe",
    "C:\Lua\5.1\luac.exe"
)

$luac = $luacCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $luac) {
    $command = Get-Command luac -ErrorAction SilentlyContinue
    if ($command) {
        $luac = $command.Source
    }
}

if (-not $luac) {
    throw "luac.exe not found. Install Lua 5.1 first."
}

$workspace = Split-Path -Parent $PSScriptRoot
$files = Get-ChildItem -Path $workspace -Recurse -Filter *.lua |
    Where-Object { $_.FullName -notmatch '\\Libs\\' -and $_.FullName -notmatch '\\.tools\\' } |
    Sort-Object FullName

if (-not $files) {
    throw "No Lua files found to validate."
}

foreach ($file in $files) {
    Write-Host "Checking $($file.FullName)"
    & $luac -p $file.FullName
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

Write-Host "Lua syntax check passed for $($files.Count) file(s)."

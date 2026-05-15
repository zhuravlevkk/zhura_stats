param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Targets
)

$ErrorActionPreference = "Stop"

$luaCandidates = @(
    "C:\Program Files (x86)\Lua\5.1\lua.exe",
    "C:\Program Files\Lua\5.1\lua.exe",
    "C:\Lua\5.1\lua.exe"
)

$lua = $luaCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $lua) {
    $command = Get-Command lua -ErrorAction SilentlyContinue
    if ($command) {
        $lua = $command.Source
    }
}

if (-not $lua) {
    throw "lua.exe not found. Install Lua first."
}

$busted = Get-Command busted -ErrorAction SilentlyContinue
if (-not $busted) {
    throw "busted not found."
}

$bustedScript = $busted.Source
$bustedRoot = Split-Path -Parent (Split-Path -Parent $bustedScript)
$shareLua = Join-Path $bustedRoot "share\lua"
$libLua = Join-Path $bustedRoot "lib\lua"
$luaVersionDirs = Get-ChildItem -Path $shareLua -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
$luaCVersionDirs = Get-ChildItem -Path $libLua -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending

$luaPathParts = @()
foreach ($dir in $luaVersionDirs) {
    $luaPathParts += Join-Path $dir.FullName "?.lua"
    $luaPathParts += Join-Path $dir.FullName "?\init.lua"
}
$luaPathParts += $env:LUA_PATH

$luaCPathParts = @()
foreach ($dir in $luaCVersionDirs) {
    $luaCPathParts += Join-Path $dir.FullName "?.dll"
}
$luaCPathParts += $env:LUA_CPATH

$env:LUA_PATH = $luaPathParts -join ";"
$env:LUA_CPATH = $luaCPathParts -join ";"

if (-not $Targets -or $Targets.Count -eq 0) {
    $Targets = @("tests")
}

& $lua $bustedScript @Targets
exit $LASTEXITCODE

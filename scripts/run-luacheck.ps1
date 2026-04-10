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
    throw "lua.exe not found. Install Lua 5.1 first."
}

$workspace = Split-Path -Parent $PSScriptRoot
$luacheckScript = Get-ChildItem -Path (Join-Path $workspace ".tools\luarocks\lib\luarocks\rocks\luacheck") -Recurse -Filter luacheck.lua -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $luacheckScript) {
    throw "Local Luacheck install not found under .tools\luarocks."
}

$luarocksLuaPath = Join-Path $workspace ".tools\luarocks\share\lua\5.1"
$luarocksLuaCPath = Join-Path $workspace ".tools\luarocks\lib\lua\5.1"
$luaRoot = Split-Path -Parent $lua

$env:LUA_PATH = @(
    (Join-Path $luarocksLuaPath "?.lua"),
    (Join-Path $luarocksLuaPath "?\init.lua"),
    (Join-Path $luaRoot "lua\?.lua"),
    (Join-Path $luaRoot "lua\?\init.lua"),
    (Join-Path $luaRoot "?.lua"),
    (Join-Path $luaRoot "?\init.lua"),
    $env:LUA_PATH
) -join ";"

$env:LUA_CPATH = @(
    (Join-Path $luarocksLuaCPath "?.dll"),
    (Join-Path $luaRoot "clibs\?.dll"),
    (Join-Path $luaRoot "?.dll"),
    (Join-Path $luaRoot "loadall.dll"),
    $env:LUA_CPATH
) -join ";"

if (-not $Targets -or $Targets.Count -eq 0) {
    $Targets = @("ZhuraStats.lua", "Locales", "--config", ".luacheckrc")
}

& $lua $luacheckScript @Targets
exit $LASTEXITCODE

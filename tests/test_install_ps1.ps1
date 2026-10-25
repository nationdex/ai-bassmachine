# Static + unit checks for install.ps1. Runs on Linux pwsh (CI) and on Windows PowerShell.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $root 'install.ps1'

# 1. Parses cleanly
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) { throw "install.ps1 parse errors: $($errors | ForEach-Object Message)" }

# 2. ASCII only (PowerShell 5.1 reads BOM-less files as ANSI)
$bytes = [IO.File]::ReadAllBytes($script)
$bad = 0; foreach ($b in $bytes) { if ($b -gt 127) { $bad++ } }
if ($bad -gt 0) { throw "install.ps1 contains $bad non-ASCII bytes" }

# 3. No `exit` (kills the terminal under `irm | iex`) and no known-bogus winget IDs
$text = Get-Content $script -Raw
$exits = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ExitStatementAst] }, $true)
if ($exits.Count -gt 0) { throw 'install.ps1 must not call exit' }
foreach ($bogus in @('rweichler.lua', 'Lua.Lua', 'Scoop.Scoop')) {
    if ($text -match [regex]::Escape($bogus)) { throw "bogus winget id still referenced: $bogus" }
}
if ($text -match 'reset --hard') { throw 'hard reset would discard local edits' }

# 4. Load functions without installing
$env:MCP_BASSMACHINE_NOEXEC = '1'
. $script
Remove-Item Env:MCP_BASSMACHINE_NOEXEC

# 5. Wrapper: launches Lua exactly once, propagates exit code, restores code page
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("bassmachine-wrapper-" + [Guid]::NewGuid().ToString('N') + '.cmd')
New-CmdWrapper -Path $tmp -InstallDir 'C:\Users\Jane Doe\.mcp-bassmachine' -LuaPath 'C:\Users\Jane Doe\.mcp-bassmachine-lua\bin\lua54.exe'
$wrapper = [IO.File]::ReadAllText($tmp)
Remove-Item $tmp -Force
$luaCalls = ([regex]::Matches($wrapper, 'src\\main\.lua')).Count
if ($luaCalls -ne 1) { throw "wrapper launches Lua $luaCalls times (expected 1)" }
if ($wrapper -notmatch 'exit /b %MCPBASS_RC%') { throw 'wrapper does not propagate exit code' }
if ($wrapper -notmatch 'cd /d "C:\\Users\\Jane Doe\\.mcp-bassmachine"') { throw 'wrapper must quote install dir' }
if ($wrapper -notmatch "`r`n") { throw 'wrapper must use CRLF' }
if ($wrapper -match 'powershell') { throw 'wrapper must not shell out to powershell' }

# 6. Pinned bundles are well-formed
foreach ($arch in $LuaBundles.Keys) {
    if ($LuaBundles[$arch].Sha256 -notmatch '^[0-9a-f]{64}$') { throw "bad sha256 for $arch" }
    if ($LuaBundles[$arch].Url -notmatch '^https://') { throw "non-https url for $arch" }
}

Write-Host 'PASS: tests/test_install_ps1.ps1'

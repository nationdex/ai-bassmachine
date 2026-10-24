# MCP Bass Machine - Windows PowerShell Installer
# Usage:
#   irm https://raw.githubusercontent.com/nationdex/mcp-bassmachine/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/nationdex/mcp-bassmachine.git"
$InstallDir = if ($env:MCP_BASSMACHINE_HOME) { $env:MCP_BASSMACHINE_HOME } else { "$HOME\.mcp-bassmachine" }
$BinDir = if ($env:MCP_BASSMACHINE_BIN) { $env:MCP_BASSMACHINE_BIN } else { "$HOME\.local\bin" }

Write-Host "🎛  Installing MCP Bass Machine for Windows..." -ForegroundColor Cyan

# 1. Dependency checks: Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Error: 'git' is required to install MCP Bass Machine." -ForegroundColor Red
    Write-Host "Please install Git (e.g. 'winget install Git.Git') and re-run." -ForegroundColor Yellow
    exit 1
}

# Dependency checks: Lua
$LuaCmd = $null
foreach ($cand in @("lua", "lua54", "lua5.4", "luajit")) {
    if (Get-Command $cand -ErrorAction SilentlyContinue) {
        $LuaCmd = $cand
        break
    }
}

if (-not $LuaCmd) {
    Write-Host "Notice: Lua not detected in PATH. Attempting automated install via winget..." -ForegroundColor Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            winget install --id=Lua.Lua -e --silent --accept-package-agreements --accept-source-agreements
            $LuaCmd = "lua"
        } catch {
            Write-Host "Automated winget installation could not complete." -ForegroundColor Yellow
        }
    }

    if (-not $LuaCmd -or -not (Get-Command lua -ErrorAction SilentlyContinue)) {
        Write-Host "Warning: Lua was not found. Please install Lua 5.X or LuaJIT (e.g. 'winget install Lua.Lua' or via Scoop: 'scoop install lua')." -ForegroundColor Yellow
        $LuaCmd = "lua"
    }
}

Write-Host "Using Lua command: $LuaCmd" -ForegroundColor Green

# 2. Clone or Update repository
if (Test-Path "$InstallDir\.git") {
    Write-Host "Existing installation found at $InstallDir. Updating repository..." -ForegroundColor Cyan
    git -C "$InstallDir" fetch --depth=1 origin main
    git -C "$InstallDir" reset --hard origin/main
} else {
    Write-Host "Cloning repository into $InstallDir..." -ForegroundColor Cyan
    if (Test-Path "$InstallDir") {
        Remove-Item -Recurse -Force "$InstallDir"
    }
    git clone --depth=1 "$RepoUrl" "$InstallDir"
}

# 3. Create Windows Command / PowerShell wrappers in BinDir
if (-not (Test-Path "$BinDir")) {
    New-Item -ItemType Directory -Path "$BinDir" -Force | Out-Null
}

$CmdWrapper = "$BinDir\mcp-bassmachine.cmd"
$Ps1Wrapper = "$BinDir\mcp-bassmachine.ps1"

# .cmd wrapper for CMD & general CLI
$CmdContent = @"
@echo off
setlocal
cd /d "$InstallDir"
$LuaCmd src\main.lua %*
"@
Set-Content -Path "$CmdWrapper" -Value $CmdContent -Encoding ASCII

# .ps1 wrapper for PowerShell
$Ps1Content = @"
Push-Location "$InstallDir"
try {
    & $LuaCmd src\main.lua @args
} finally {
    Pop-Location
}
"@
Set-Content -Path "$Ps1Wrapper" -Value $Ps1Content -Encoding UTF8

# 4. Add BinDir to User PATH environment variable if not already present
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($UserPath -notlike "*$BinDir*") {
    Write-Host "Adding $BinDir to User PATH..." -ForegroundColor Cyan
    $NewPath = if ($UserPath) { "$UserPath;$BinDir" } else { "$BinDir" }
    [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
    $env:Path = "$env:Path;$BinDir"
    Write-Host "PATH updated successfully." -ForegroundColor Green
}

# 5. Success Banner
Write-Host ""
Write-Host "✓ MCP Bass Machine installed successfully!" -ForegroundColor Green
Write-Host "Installed to:  $InstallDir" -ForegroundColor Cyan
Write-Host "Binary linked: $CmdWrapper" -ForegroundColor Cyan
Write-Host ""
Write-Host "To launch now in PowerShell or CMD:" -ForegroundColor White
Write-Host "  mcp-bassmachine" -ForegroundColor Magenta
Write-Host ""

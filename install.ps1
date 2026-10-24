# MCP Bass Machine - Windows PowerShell Installer
# Usage:
#   irm https://raw.githubusercontent.com/nationdex/mcp-bassmachine/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/nationdex/mcp-bassmachine.git"
$UserHome = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { "." }
$InstallDir = if ($env:MCP_BASSMACHINE_HOME) { $env:MCP_BASSMACHINE_HOME } else { "$UserHome\.mcp-bassmachine" }
$BinDir = if ($env:MCP_BASSMACHINE_BIN) { $env:MCP_BASSMACHINE_BIN } else { "$UserHome\.local\bin" }
$StandaloneLuaDir = "$InstallDir\bin\lua54"

Write-Host "🎛  Installing MCP Bass Machine for Windows..." -ForegroundColor Cyan

# 1. Dependency check: Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Error: 'git' is required to install MCP Bass Machine." -ForegroundColor Red
    Write-Host "Please install Git (e.g. 'winget install Git.Git') and re-run." -ForegroundColor Yellow
    exit 1
}

# 2. Dependency check & Automated installation: Lua (5.1 - 5.4 or LuaJIT)
function Find-LuaCommand {
    foreach ($cand in @("lua", "lua54", "lua5.4", "lua53", "lua5.3", "luajit")) {
        $found = Get-Command $cand -ErrorAction SilentlyContinue
        if ($found) {
            return $found.Source
        }
    }
    # Check standalone install directory and common default Windows installation paths
    $commonPaths = @(
        "$StandaloneLuaDir\lua54.exe",
        "$StandaloneLuaDir\lua.exe",
        "$env:ProgramFiles\Lua\lua.exe",
        "$env:ProgramFiles\Lua\bin\lua.exe",
        "${env:ProgramFiles(x86)}\Lua\lua.exe",
        "${env:ProgramFiles(x86)}\Lua\bin\lua.exe",
        "$UserHome\scoop\apps\lua\current\bin\lua.exe",
        "$UserHome\scoop\shims\lua.exe",
        "$UserHome\AppData\Local\Programs\Lua\lua.exe"
    )
    foreach ($p in $commonPaths) {
        if (Test-Path $p) {
            return $p
        }
    }
    return $null
}

$LuaPath = Find-LuaCommand

if (-not $LuaPath) {
    Write-Host "Notice: Lua not detected in PATH. Attempting automated installation..." -ForegroundColor Yellow

    # Try winget first with accurate IDs
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Trying winget package managers..." -ForegroundColor Cyan
        $wingetPackages = @(
            "rweichler.lua",
            "Lua.Lua",
            "Scoop.Scoop"
        )
        foreach ($pkg in $wingetPackages) {
            try {
                Write-Host "Attempting winget install $pkg..." -ForegroundColor Cyan
                & winget install --id=$pkg -e --silent --accept-package-agreements --accept-source-agreements 2>$null
                # Refresh current environment PATH after installer run
                $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
                $LuaPath = Find-LuaCommand
                if ($LuaPath) { break }
            } catch {
                # continue
            }
        }
    }

    # Try Scoop if winget did not produce Lua
    if (-not $LuaPath -and (Get-Command scoop -ErrorAction SilentlyContinue)) {
        try {
            Write-Host "Installing Lua via Scoop..." -ForegroundColor Cyan
            & scoop install lua
            $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
            if (Test-Path "$UserHome\scoop\shims") {
                $env:Path = "$env:Path;$UserHome\scoop\shims"
            }
            $LuaPath = Find-LuaCommand
        } catch {}
    }

    # Try Chocolatey if available
    if (-not $LuaPath -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        try {
            Write-Host "Installing Lua via Chocolatey..." -ForegroundColor Cyan
            & choco install lua -y
            $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
            if (Test-Path "$UserHome\AppData\Local\Chocolatey\bin") {
                $env:Path = "$env:Path;$UserHome\AppData\Local\Chocolatey\bin"
            }
            $LuaPath = Find-LuaCommand
        } catch {}
    }

    # Direct automated standalone zip fallback from sourceforge if no package manager succeeded
    if (-not $LuaPath) {
        try {
            Write-Host "Downloading standalone Lua 5.4 binaries for Windows..." -ForegroundColor Cyan
            $luaZipUrl = "https://sourceforge.net/projects/luabinaries/files/5.4.2/Tools%20Executables/lua-5.4.2_Win64_bin.zip/download"
            $tempZip = "$env:TEMP\lua54_win64.zip"
            New-Item -ItemType Directory -Path $StandaloneLuaDir -Force | Out-Null
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $luaZipUrl -OutFile $tempZip -UserAgent "curl/8.0" -UseBasicParsing
            Expand-Archive -Path $tempZip -DestinationPath $StandaloneLuaDir -Force
            Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
            if (Test-Path "$StandaloneLuaDir\lua54.exe") {
                $LuaPath = "$StandaloneLuaDir\lua54.exe"
            } elseif (Test-Path "$StandaloneLuaDir\lua.exe") {
                $LuaPath = "$StandaloneLuaDir\lua.exe"
            }
            if (Test-Path $StandaloneLuaDir) {
                $env:Path = "$env:Path;$StandaloneLuaDir"
            }
        } catch {
            Write-Host "Direct binary download could not complete: $_" -ForegroundColor Yellow
        }
    }
}

if (-not $LuaPath) {
    Write-Host ""
    Write-Host "Warning: Could not automatically detect or install Lua 5.X on this machine." -ForegroundColor Yellow
    Write-Host "Please install Lua using either:" -ForegroundColor Yellow
    Write-Host "  1. Winget: winget install rweichler.lua" -ForegroundColor White
    Write-Host "  2. Scoop:  scoop install lua" -ForegroundColor White
    Write-Host "  3. Choco:  choco install lua" -ForegroundColor White
    Write-Host "  4. Official Windows Binaries: https://luabinaries.sourceforge.net" -ForegroundColor White
    Write-Host ""
    $LuaPath = "lua"
}

Write-Host "Using Lua engine: $LuaPath" -ForegroundColor Green

# 3. Clone or Update repository
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

# 4. Create Windows Command / PowerShell wrappers in BinDir
if (-not (Test-Path "$BinDir")) {
    New-Item -ItemType Directory -Path "$BinDir" -Force | Out-Null
}

$CmdWrapper = "$BinDir\mcp-bassmachine.cmd"
$Ps1Wrapper = "$BinDir\mcp-bassmachine.ps1"

# .cmd wrapper for CMD & general CLI (enables UTF-8 codepage 65001 & virtual terminal processing)
$CmdContent = @"
@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>nul
cd /d "$InstallDir"
"$LuaPath" src\main.lua %*
"@
Set-Content -Path "$CmdWrapper" -Value $CmdContent -Encoding ASCII

# .ps1 wrapper for PowerShell 5.0 through 7+ (forces UTF-8 OutputEncoding & VT ANSI processing)
$Ps1Content = @"
Push-Location "$InstallDir"
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    `$OutputEncoding = [System.Text.Encoding]::UTF8
    try {
        # Enable Virtual Terminal sequences on legacy Windows console hosts
        `$null = [Console]::CursorVisible
    } catch {}
    & "$LuaPath" src\main.lua @args
} finally {
    Pop-Location
}
"@
Set-Content -Path "$Ps1Wrapper" -Value $Ps1Content -Encoding UTF8

# 5. Add BinDir to User PATH environment variable if not already present
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($UserPath -notlike "*$BinDir*") {
    Write-Host "Adding $BinDir to User PATH..." -ForegroundColor Cyan
    $NewPath = if ($UserPath) { "$UserPath;$BinDir" } else { "$BinDir" }
    [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
    $env:Path = "$env:Path;$BinDir"
    Write-Host "PATH updated successfully." -ForegroundColor Green
}

# 6. Success Banner
Write-Host ""
Write-Host "✓ MCP Bass Machine installed successfully!" -ForegroundColor Green
Write-Host "Installed to:  $InstallDir" -ForegroundColor Cyan
Write-Host "Binary linked: $CmdWrapper" -ForegroundColor Cyan
Write-Host ""
Write-Host "To launch now in PowerShell or CMD:" -ForegroundColor White
Write-Host "  mcp-bassmachine" -ForegroundColor Magenta
Write-Host ""

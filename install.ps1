# MCP Bass Machine - Windows PowerShell Installer (Windows PowerShell 5.1 and PowerShell 7+)
# Usage:
#   irm https://raw.githubusercontent.com/nationdex/mcp-bassmachine/main/install.ps1 | iex
#
# Notes for maintainers:
#   * ASCII only: Windows PowerShell 5.1 reads BOM-less files as ANSI and mangles UTF-8 glyphs.
#   * Never `exit` here: under `irm | iex` it closes the user's terminal. Use throw/return.
#   * Native tools (git, winget) write progress to stderr; with $ErrorActionPreference = 'Stop'
#     Windows PowerShell 5.1 turns that into a terminating NativeCommandError. All native calls go
#     through Invoke-Native, which checks the exit code instead.

# TLS 1.2 is not enabled by default on Windows PowerShell 5.1 and GitHub/SourceForge require it.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

# Windows PowerShell 5.1 renders a progress bar for Invoke-WebRequest that slows downloads ~10x.
$ProgressPreference = 'SilentlyContinue'

# Pinned standalone Lua 5.4.2 (LuaBinaries). Dynamically linked (lua54.exe + lua54.dll), which the
# native console helper in bin\windows requires to deliver keystrokes.
$LuaBundles = @{
    'x64' = @{
        Url    = 'https://sourceforge.net/projects/luabinaries/files/5.4.2/Tools%20Executables/lua-5.4.2_Win64_bin.zip/download'
        Sha256 = '5f1e1385ed95a3643f7ed67c4f3767942b2f0f388b66f63e5667e9c3d96293f5'
    }
    'x86' = @{
        Url    = 'https://sourceforge.net/projects/luabinaries/files/5.4.2/Tools%20Executables/lua-5.4.2_Win32_bin.zip/download'
        Sha256 = '5f51dab8f26fc77a1298be1c79debf95de44579f53094ae509c5b4c7c3d6ac91'
    }
}

# Package IDs verified against microsoft/winget-pkgs (manifests/d/DEVCOM/{Lua,LuaJIT}).
$WingetLuaPackages = @('DEVCOM.LuaJIT', 'DEVCOM.Lua')

function Write-Step([string]$Message, [string]$Color = 'Cyan') {
    Write-Host $Message -ForegroundColor $Color
}

function Invoke-Native {
    # Runs a native command, streams its output, and returns the exit code.
    param([Parameter(Mandatory)][string]$File, [string[]]$Arguments = @())
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $File @Arguments 2>&1 | ForEach-Object { Write-Host "$_" }
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
}

function Get-UserHomeDir {
    if ($env:USERPROFILE) { return $env:USERPROFILE }
    if ($env:HOME) { return $env:HOME }
    return '.'
}

function Test-LuaWorks([string]$LuaExe) {
    # A runnable interpreter that also ships a Lua DLL next to it (needed by the keyboard helper).
    try {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $out = & $LuaExe -e "io.write(_VERSION)" 2>$null
        $ErrorActionPreference = $previous
        return ($LASTEXITCODE -eq 0 -and "$out" -like 'Lua*')
    } catch {
        return $false
    }
}

function Test-LuaHasDll([string]$LuaExe) {
    $dir = Split-Path -Parent $LuaExe
    if (-not $dir) { return $false }
    return [bool](Get-ChildItem -Path $dir -Filter 'lua*.dll' -ErrorAction SilentlyContinue | Select-Object -First 1) -or
           [bool](Get-ChildItem -Path $dir -Filter 'luajit*.dll' -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Find-SystemLua([string]$StandaloneDir) {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($name in @('luajit', 'lua54', 'lua5.4', 'lua', 'lua53', 'lua5.3')) {
        $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { $candidates.Add($cmd.Source) }
    }
    foreach ($p in @("$StandaloneDir\lua54.exe", "$StandaloneDir\lua.exe", "$StandaloneDir\luajit.exe")) {
        if (Test-Path $p) { $candidates.Add($p) }
    }
    foreach ($p in $candidates) {
        if ((Test-LuaWorks $p) -and (Test-LuaHasDll $p)) { return $p }
    }
    return $null
}

function Install-BundledLua([string]$StandaloneDir) {
    $arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    $bundle = $LuaBundles[$arch]
    $zip = Join-Path ([IO.Path]::GetTempPath()) ("mcp-bassmachine-lua-" + [Guid]::NewGuid().ToString('N') + '.zip')
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Write-Step "Downloading Lua 5.4.2 ($arch), attempt $attempt of 3..."
            Invoke-WebRequest -Uri $bundle.Url -OutFile $zip -UserAgent 'curl/8.0' -UseBasicParsing
            $hash = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($hash -ne $bundle.Sha256) {
                Remove-Item $zip -Force -ErrorAction SilentlyContinue
                throw "SHA256 mismatch (expected $($bundle.Sha256), got $hash)"
            }
            New-Item -ItemType Directory -Path $StandaloneDir -Force | Out-Null
            Expand-Archive -Path $zip -DestinationPath $StandaloneDir -Force
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
            $exe = Join-Path $StandaloneDir 'lua54.exe'
            if (Test-LuaWorks $exe) { return $exe }
            throw 'Extracted lua54.exe does not run'
        } catch {
            Write-Step "Download attempt failed: $($_.Exception.Message)" 'Yellow'
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds (2 * $attempt)
        }
    }
    return $null
}

function Install-LuaViaWinget([string]$StandaloneDir) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $null }
    foreach ($pkg in $WingetLuaPackages) {
        # Skip IDs the configured sources do not know instead of failing noisily
        if ((Invoke-Native 'winget' @('show', '--id', $pkg, '-e', '--accept-source-agreements')) -ne 0) { continue }
        Write-Step "Installing $pkg via winget..."
        $null = Invoke-Native 'winget' @('install', '--id', $pkg, '-e', '--silent', '--accept-package-agreements', '--accept-source-agreements')
        # winget updates the persistent PATH; merge it into this session without dropping session-only entries
        $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $user = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path = (@($env:Path, $user, $machine) | Where-Object { $_ }) -join ';'
        $found = Find-SystemLua $StandaloneDir
        if ($found) { return $found }
    }
    return $null
}

function Add-ToUserPath([string]$Dir) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @()
    if ($userPath) { $entries = $userPath.Split(';') | Where-Object { $_ } }
    $already = $entries | Where-Object { $_.TrimEnd('\') -ieq $Dir.TrimEnd('\') }
    if (-not $already) {
        Write-Step "Adding $Dir to User PATH..."
        [Environment]::SetEnvironmentVariable('Path', (($entries + $Dir) -join ';'), 'User')
        $env:Path = "$env:Path;$Dir"
        return $true
    }
    return $false
}

function New-CmdWrapper([string]$Path, [string]$InstallDir, [string]$LuaPath) {
    # One launcher for cmd.exe, PowerShell 5.1 and PowerShell 7. The script's own console-mode
    # handling lives in the native helper (bin\windows), so no PowerShell Add-Type is needed.
    # A .ps1 wrapper is deliberately not generated: the default Restricted execution policy blocks it.
    $content = @"
@echo off
setlocal
set "MCPBASS_OLDCP="
for /f "tokens=2 delims=:." %%a in ('chcp') do set "MCPBASS_OLDCP=%%a"
chcp 65001 >nul 2>nul
cd /d "$InstallDir"
"$LuaPath" src\main.lua %*
set "MCPBASS_RC=%errorlevel%"
if defined MCPBASS_OLDCP chcp %MCPBASS_OLDCP% >nul 2>nul
exit /b %MCPBASS_RC%
"@
    # CRLF + ASCII: what cmd.exe expects
    $content = $content -replace "`r?`n", "`r`n"
    [IO.File]::WriteAllText($Path, $content, (New-Object System.Text.ASCIIEncoding))
}

function Install-MCPBassMachine {
    $RepoUrl = 'https://github.com/nationdex/mcp-bassmachine.git'
    $UserHome = Get-UserHomeDir
    $InstallDir = if ($env:MCP_BASSMACHINE_HOME) { $env:MCP_BASSMACHINE_HOME } else { Join-Path $UserHome '.mcp-bassmachine' }
    $BinDir = if ($env:MCP_BASSMACHINE_BIN) { $env:MCP_BASSMACHINE_BIN } else { Join-Path $UserHome '.local\bin' }
    $StandaloneLuaDir = Join-Path $UserHome '.mcp-bassmachine-lua\bin'
    $Ref = if ($env:MCP_BASSMACHINE_REF) { $env:MCP_BASSMACHINE_REF } else { 'main' }

    Write-Step 'Installing MCP Bass Machine for Windows...'

    # 1. Git
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git is required. Install it (winget install --id Git.Git -e) and re-run this installer."
    }

    # 2. Lua: reuse a working dynamically linked one, otherwise the pinned bundle, then winget
    $LuaPath = Find-SystemLua $StandaloneLuaDir
    if (-not $LuaPath) {
        Write-Step 'No suitable Lua found (needs lua.exe plus its Lua DLL). Installing a pinned build...' 'Yellow'
        $LuaPath = Install-BundledLua $StandaloneLuaDir
    }
    if (-not $LuaPath) {
        Write-Step 'Bundled download failed; trying winget...' 'Yellow'
        $LuaPath = Install-LuaViaWinget $StandaloneLuaDir
    }
    if (-not $LuaPath) {
        throw "Could not install Lua automatically. Download lua-5.4.2_Win64_bin.zip from https://luabinaries.sourceforge.net, extract it to '$StandaloneLuaDir', then re-run."
    }
    Write-Step "Using Lua engine: $LuaPath" 'Green'

    # 3. Clone or fast-forward update (never discards local edits such as bassmachine.toml)
    if (Test-Path (Join-Path $InstallDir '.git')) {
        Write-Step "Existing installation found at $InstallDir. Updating..."
        if ((Invoke-Native 'git' @('-C', $InstallDir, 'fetch', '--depth=1', 'origin', $Ref)) -ne 0) {
            throw 'git fetch failed. Check your network connection.'
        }
        if ((Invoke-Native 'git' @('-C', $InstallDir, 'merge', '--ff-only', 'FETCH_HEAD')) -ne 0) {
            throw "Update aborted: local changes in $InstallDir conflict with upstream. Commit or stash them and re-run."
        }
    } else {
        Write-Step "Cloning repository into $InstallDir..."
        if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir }
        if ((Invoke-Native 'git' @('clone', '--depth=1', '--branch', $Ref, $RepoUrl, $InstallDir)) -ne 0) {
            throw 'git clone failed. Check your network connection.'
        }
    }

    # 4. Launcher in BinDir (also removes the old .ps1 wrapper that execution policy could block)
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    $CmdWrapper = Join-Path $BinDir 'mcp-bassmachine.cmd'
    New-CmdWrapper -Path $CmdWrapper -InstallDir $InstallDir -LuaPath $LuaPath
    Remove-Item (Join-Path $BinDir 'mcp-bassmachine.ps1') -Force -ErrorAction SilentlyContinue

    # 5. PATH
    $null = Add-ToUserPath $BinDir

    Write-Host ''
    Write-Step 'MCP Bass Machine installed successfully!' 'Green'
    Write-Step "Installed to:  $InstallDir"
    Write-Step "Launcher:      $CmdWrapper"
    Write-Host ''
    Write-Host 'Open a NEW terminal (Windows Terminal, PowerShell or cmd.exe) and run:' -ForegroundColor White
    Write-Host '  mcp-bassmachine' -ForegroundColor Magenta
    Write-Host 'Git Bash/mintty cannot deliver keyboard input to native Windows programs; use winpty there.' -ForegroundColor DarkGray
    Write-Host ''
}

# MCP_BASSMACHINE_NOEXEC=1 loads the functions without installing (used by tests/test_install_ps1.ps1)
if (-not $env:MCP_BASSMACHINE_NOEXEC) {
    try {
        Install-MCPBassMachine
    } catch {
        Write-Host ''
        Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

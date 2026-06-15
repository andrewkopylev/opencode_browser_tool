# ============================================================
# OpenCode Browser Tool — Windows installer (PowerShell)
# ============================================================

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "OpenCode Browser Tool Installer"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigSrc = Join-Path $ScriptDir "browser_config.template.json"
$ConfigDst = Join-Path $env:USERPROFILE ".config\opencode\browser_config.json"
$ToolsGlobalDir = Join-Path $env:USERPROFILE ".config\opencode\tools"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  OpenCode Browser Tool Installer (Windows)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ---- Step 1: Check Python and dependencies ----
Write-Host "[1/4] Checking Python and dependencies..." -ForegroundColor Yellow

$pythonCmd = $null
foreach ($cmd in @("python3", "python")) {
    try {
        $v = & $cmd --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $pythonCmd = $cmd
            break
        }
    } catch {}
}

if (-not $pythonCmd) {
    Write-Host "Error: Python not found in PATH." -ForegroundColor Red
    Write-Host "Install Python 3.8+ from https://python.org and try again."
    exit 1
}

try {
    & $pythonCmd -c "import selenium" 2>$null
    if ($LASTEXITCODE -ne 0) { throw }
} catch {
    Write-Host "  Selenium is not installed." -ForegroundColor Red
    Write-Host "  Install it with:" -ForegroundColor Red
    Write-Host "    pip install --user selenium" -ForegroundColor Red
    Write-Host "  Then re-run this installer." -ForegroundColor Red
    exit 1
}
Write-Host "  Python + Selenium: OK" -ForegroundColor Green

# ---- Step 2: Check configuration ----
Write-Host "[2/4] Checking configuration..." -ForegroundColor Yellow

function Validate-Config {
    param([string]$Path)
    try {
        $cfg = Get-Content $Path -Raw | ConvertFrom-Json
        $errors = @()
        foreach ($key in @("chrome_binary", "chromedriver_path")) {
            $val = $cfg.$key
            if (-not $val) {
                $errors += "$key is empty"
            } elseif ($val -in @("/path/to/chrome", "/path/to/chromedriver", "chrome", "chromedriver")) {
                $errors += "$key is still a placeholder: $val"
            } elseif (-not (Test-Path $val -PathType Leaf)) {
                $errors += "$key not found: $val"
            }
        }
        if ($errors.Count -gt 0) {
            foreach ($e in $errors) {
                Write-Host "    ERROR: $e" -ForegroundColor Red
            }
            return $false
        }
        return $true
    } catch {
        Write-Host "    ERROR: invalid JSON syntax" -ForegroundColor Red
        return $false
    }
}

if (-not (Test-Path $ConfigDst)) {
    if (Test-Path $ConfigSrc) {
        Write-Host "  Config not found. Creating from template..." -ForegroundColor Yellow
        $cfgDir = Split-Path $ConfigDst -Parent
        New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
        Copy-Item $ConfigSrc $ConfigDst -Force
    } else {
        Write-Host "  Config not found. Creating minimal..." -ForegroundColor Yellow
        $cfgDir = Split-Path $ConfigDst -Parent
        New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
        @"
{
  "chrome_binary": "/path/to/chrome",
  "chromedriver_path": "/path/to/chromedriver",
  "headless": false,
  "screenshot_dir": ""
}
"@ | Set-Content $ConfigDst
    }
    Write-Host "  ========================================" -ForegroundColor Red
    Write-Host "  ACTION REQUIRED" -ForegroundColor Red
    Write-Host "  ========================================" -ForegroundColor Red
    Write-Host "  1. Edit $ConfigDst" -ForegroundColor Red
    Write-Host "  2. Set chrome_binary and chromedriver_path" -ForegroundColor Red
    Write-Host "  3. Download matched pair from:" -ForegroundColor Red
    Write-Host "     https://googlechromelabs.github.io/chrome-for-testing/" -ForegroundColor Red
    Write-Host "  ========================================" -ForegroundColor Red
    Write-Host ""
    Read-Host "  Press Enter when ready (or Ctrl+C to abort)"
}

if (-not (Validate-Config -Path $ConfigDst)) {
    Write-Host ""
    Write-Host "  Fix $ConfigDst and re-run this installer." -ForegroundColor Red
    exit 1
}

Write-Host "  Configuration: OK" -ForegroundColor Green

# ---- Step 3: Choose install target ----
Write-Host "[3/4] Choose installation target..." -ForegroundColor Yellow
Write-Host "  (g) Global     — available in all projects  (~\.config\opencode\tools\)"
Write-Host "  (l) Local      — this project only           (.opencode\tools\)"
$choice = Read-Host "  Choice [g/l]"

if ($choice -eq "l" -or $choice -eq "L" -or $choice -eq "local") {
    $TargetDir = Join-Path $ScriptDir ".opencode\tools"
} else {
    $TargetDir = $ToolsGlobalDir
}

New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null

# ---- Step 4: Copy files ----
Write-Host "[4/4] Installing..." -ForegroundColor Yellow
Copy-Item (Join-Path $ScriptDir "browser.ts") $TargetDir -Force
Copy-Item (Join-Path $ScriptDir "browser.py") $TargetDir -Force

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Files installed to: $TargetDir" -ForegroundColor Cyan
Write-Host "  Config at:          $ConfigDst" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Restart OpenCode for the tools to take effect." -ForegroundColor Yellow
Write-Host ""

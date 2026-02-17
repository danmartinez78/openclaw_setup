# prepare-usb.ps1 - Bundle setup repo + agent workspace onto a USB drive
# Usage: .\prepare-usb.ps1 -UsbDrive "G:" [-WorkspacePath "C:\path\to\workspace"]
# SAFE: Never overwrites existing files on the drive.

param(
    [Parameter(Mandatory=$true)]
    [string]$UsbDrive,

    [Parameter(Mandatory=$false)]
    [string]$WorkspacePath = ""
)

$ErrorActionPreference = 'Stop'

# Normalize drive path
$UsbDrive = $UsbDrive.TrimEnd('\')
if (-not (Test-Path $UsbDrive)) {
    Write-Host 'ERROR: Drive not found.' -ForegroundColor Red
    exit 1
}

$destRoot      = "$UsbDrive\openclaw_deploy"
$destRepo      = "$destRoot\openclaw_setup"
$destWorkspace = "$destRoot\agent-workspace"
$destConfig    = "$destRoot\config.env"

$srcRepo       = $PSScriptRoot
$srcWorkspace  = $WorkspacePath

Write-Host ''
Write-Host '=== OpenClaw USB Deployment Prep ===' -ForegroundColor Cyan
Write-Host "  USB drive:    $UsbDrive"
Write-Host "  Destination:  $destRoot"
Write-Host "  Source repo:  $srcRepo"
if ($srcWorkspace) {
    Write-Host "  Source workspace: $srcWorkspace"
} else {
    Write-Host "  Source workspace: (none — use -WorkspacePath to include agent files)" -ForegroundColor Yellow
}
Write-Host ''

# --- Helper: copy a directory without overwriting ---
function Copy-SafeDir {
    param([string]$Source, [string]$Dest)

    $files = Get-ChildItem -Path $Source -Recurse -File
    $copied = 0
    $skipped = 0
    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($Source.Length)
        $destFile = Join-Path $Dest $relativePath
        $destDir = Split-Path $destFile -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        if (Test-Path $destFile) {
            $skipped++
        } else {
            Copy-Item -Path $file.FullName -Destination $destFile
            $copied++
        }
    }
    Write-Host "    Copied $copied files, skipped $skipped existing" -ForegroundColor Gray
}

# --- Helper: copy a single file without overwriting ---
function Copy-SafeFile {
    param([string]$Source, [string]$Dest)

    if (Test-Path $Dest) {
        Write-Host "    SKIPPED (already exists): $Dest" -ForegroundColor Yellow
    } else {
        $destDir = Split-Path $Dest -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item -Path $Source -Destination $Dest
        Write-Host "    Copied: $Dest" -ForegroundColor Green
    }
}

# --- 1. Copy setup repo (exclude .git, node_modules, logs) ---
Write-Host '[1/3] Copying setup repo...' -ForegroundColor Cyan
if (-not (Test-Path $destRepo)) {
    New-Item -ItemType Directory -Path $destRepo -Force | Out-Null
}

$repoFiles = Get-ChildItem -Path $srcRepo -Recurse -File |
    Where-Object {
        $rel = $_.FullName.Substring($srcRepo.Length + 1)
        $rel -notmatch '^\.git\\' -and
        $rel -notmatch 'node_modules\\' -and
        $rel -ne 'setup.log' -and
        $rel -ne '.checkpoint' -and
        $rel -ne 'prepare-usb.ps1'
    }

$copied = 0
$skipped = 0
foreach ($file in $repoFiles) {
    $relativePath = $file.FullName.Substring($srcRepo.Length)
    $destFile = Join-Path $destRepo $relativePath
    $destDir = Split-Path $destFile -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    if (Test-Path $destFile) {
        $skipped++
    } else {
        Copy-Item -Path $file.FullName -Destination $destFile
        $copied++
    }
}
Write-Host "    Copied $copied files, skipped $skipped existing" -ForegroundColor Gray

# --- 2. Copy agent workspace ---
Write-Host '[2/3] Copying agent workspace...' -ForegroundColor Cyan
if (-not $srcWorkspace -or -not (Test-Path $srcWorkspace)) {
    if (-not $srcWorkspace) {
        Write-Host "    SKIPPED: No workspace path provided (use -WorkspacePath)" -ForegroundColor Yellow
    } else {
        Write-Host "    WARNING: $srcWorkspace not found - skipping" -ForegroundColor Yellow
    }
} else {
    if (-not (Test-Path $destWorkspace)) {
        New-Item -ItemType Directory -Path $destWorkspace -Force | Out-Null
    }
    Copy-SafeDir -Source $srcWorkspace -Dest $destWorkspace
}

# --- 3. Copy config.env template ---
Write-Host '[3/3] Copying config.env...' -ForegroundColor Cyan
$srcConfig = Join-Path $srcRepo 'config.env'
if (-not (Test-Path $srcConfig)) {
    $srcConfig = Join-Path $srcRepo 'config.env.example'
}
Copy-SafeFile -Source $srcConfig -Dest $destConfig

# --- Summary ---
Write-Host ''
Write-Host '=== USB drive ready! ===' -ForegroundColor Green
Write-Host ''

$allFiles = Get-ChildItem -Path $destRoot -Recurse -File
Write-Host "Total files: $($allFiles.Count)" -ForegroundColor Cyan
foreach ($file in $allFiles) {
    $rel = $file.FullName.Substring($destRoot.Length + 1)
    Write-Host "  $rel"
}

Write-Host ''
Write-Host '--- Next steps ---' -ForegroundColor Yellow
Write-Host '1. Edit the config.env on the USB with your real API keys'
Write-Host '2. Plug USB into the Ubuntu machine'
Write-Host '3. Run these commands on Ubuntu:' -ForegroundColor White
Write-Host ''
Write-Host '   sudo mount /dev/sda1 /mnt/usb' -ForegroundColor White
Write-Host '   cp -r /mnt/usb/openclaw_deploy/openclaw_setup ~/openclaw_setup' -ForegroundColor White
Write-Host '   cd ~/openclaw_setup' -ForegroundColor White
Write-Host '   cp /mnt/usb/openclaw_deploy/config.env .' -ForegroundColor White
Write-Host '   # Edit config.env and set:' -ForegroundColor Gray
Write-Host '   # OPENCLAW_MIGRATE_FROM="/mnt/usb/openclaw_deploy/agent-workspace"' -ForegroundColor Gray
Write-Host '   sudo ./setup.sh' -ForegroundColor White
Write-Host ''

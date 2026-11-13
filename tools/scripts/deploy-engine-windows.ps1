<#
.SYNOPSIS
    Deploy the latest fork engine build to Beyond All Reason.

.DESCRIPTION
    Downloads the latest Windows engine release from a GitHub fork and extracts
    it to the BAR engine directory. Automatically downloads a portable 7-Zip
    extractor if 7-Zip is not installed.

.PARAMETER RepoOwner
    GitHub username/org that owns the fork. Default: dunctem

.PARAMETER RepoName
    Repository name. Default: RecoilEngine

.PARAMETER EngineFolder
    Name of the folder to create under data\engine\. Default: recoil_dunctem_dev

.PARAMETER BarPath
    Path to the BAR installation. Default: C:\Program Files\Beyond-All-Reason

.PARAMETER ReleaseTag
    Specific release tag to download. Default: latest release with Windows asset.

.EXAMPLE
    .\deploy-engine-windows.ps1
    
    Downloads and installs the latest release.

.EXAMPLE
    .\deploy-engine-windows.ps1 -EngineFolder "recoil_test" -ReleaseTag "fork-build-dev-main-abc1234"
    
    Downloads a specific release to a custom folder.

.NOTES
    No prerequisites required - downloads portable 7zr.exe if needed.
    Run from an elevated PowerShell if BAR is in Program Files.
#>

param(
    [string]$RepoOwner = "dunctem",
    [string]$RepoName = "RecoilEngine",
    [string]$EngineFolder = "recoil_dunctem_dev",
    [string]$BarPath = "C:\Program Files\Beyond-All-Reason",
    [string]$ReleaseTag = ""
)

$ErrorActionPreference = "Stop"

function Write-Status {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-Failure {
    param([string]$Message)
    Write-Host "[-] $Message" -ForegroundColor Red
}

# Find or download 7-Zip
function Get-7ZipPath {
    # Check common installation paths
    $paths = @(
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe",
        "$env:LOCALAPPDATA\7-Zip\7z.exe"
    )
    
    foreach ($p in $paths) {
        if (Test-Path $p) {
            return $p
        }
    }
    
    # Check if portable 7zr is already downloaded
    $portable7zr = Join-Path $env:TEMP "7zr.exe"
    if (Test-Path $portable7zr) {
        return $portable7zr
    }
    
    # Download portable 7zr.exe (standalone command-line extractor)
    Write-Status "7-Zip not found, downloading portable 7zr.exe..."
    
    # 7zr.exe is a standalone console version that can extract .7z files
    # It's a single ~600KB executable with no dependencies
    $7zrUrl = "https://www.7-zip.org/a/7zr.exe"
    
    try {
        $progressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $7zrUrl -OutFile $portable7zr -UseBasicParsing
        $progressPreference = 'Continue'
        
        if (Test-Path $portable7zr) {
            Write-Success "Downloaded portable 7zr.exe"
            return $portable7zr
        }
    } catch {
        Write-Failure "Failed to download 7zr.exe: $_"
    }
    
    return $null
}

# Get 7-Zip path
$7zPath = Get-7ZipPath
if (-not $7zPath) {
    Write-Failure "Could not find or download 7-Zip"
    Write-Host "Please install 7-Zip from https://www.7-zip.org/ or ensure internet access"
    exit 1
}

Write-Status "Using 7-Zip: $7zPath"

# Check BAR path
if (-not (Test-Path $BarPath)) {
    Write-Failure "BAR not found at $BarPath"
    Write-Host "Please specify the correct path with -BarPath"
    exit 1
}

$engineBasePath = Join-Path $BarPath "data\engine"
if (-not (Test-Path $engineBasePath)) {
    Write-Failure "Engine directory not found: $engineBasePath"
    exit 1
}

# Fetch releases
Write-Status "Fetching releases from $RepoOwner/$RepoName..."

$headers = @{
    "Accept" = "application/vnd.github.v3+json"
    "User-Agent" = "PowerShell-EngineDeployer"
}

if ($ReleaseTag) {
    $releaseUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/tags/$ReleaseTag"
    try {
        $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers
    } catch {
        Write-Failure "Release '$ReleaseTag' not found"
        exit 1
    }
    $releases = @($release)
} else {
    $releasesUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/releases"
    $releases = Invoke-RestMethod -Uri $releasesUrl -Headers $headers
}

# Find a release with Windows .7z asset
$release = $null
$asset = $null

foreach ($r in $releases) {
    $windowsAssets = $r.assets | Where-Object { 
        $_.name -match "amd64-windows.*\.7z$" -and 
        $_.name -notmatch "dbgsym" 
    }
    if ($windowsAssets) {
        $release = $r
        $asset = $windowsAssets | Select-Object -First 1
        break
    }
}

if (-not $asset) {
    Write-Failure "No Windows engine release found"
    Write-Host "Make sure the fork has releases with Windows .7z artifacts"
    exit 1
}

Write-Success "Found release: $($release.tag_name)"
Write-Host "  Asset: $($asset.name)"
Write-Host "  Size: $([math]::Round($asset.size / 1MB, 2)) MB"
Write-Host "  Published: $($release.published_at)"

# Download
$downloadPath = Join-Path $env:TEMP $asset.name
Write-Status "Downloading $($asset.name)..."

$progressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath -UseBasicParsing
$progressPreference = 'Continue'

if (-not (Test-Path $downloadPath)) {
    Write-Failure "Download failed"
    exit 1
}

$fileSize = (Get-Item $downloadPath).Length
Write-Success "Downloaded $([math]::Round($fileSize / 1MB, 2)) MB"

# Prepare target directory
$enginePath = Join-Path $engineBasePath $EngineFolder
Write-Status "Installing to $enginePath..."

if (Test-Path $enginePath) {
    Write-Host "  Removing existing installation..."
    Remove-Item -Recurse -Force $enginePath
}

New-Item -ItemType Directory -Path $enginePath -Force | Out-Null

# Extract
Write-Status "Extracting with 7-Zip..."
$extractResult = & $7zPath x $downloadPath -o"$enginePath" -y 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Failure "Extraction failed"
    Write-Host $extractResult
    exit 1
}

# Verify
$springExe = Join-Path $enginePath "spring.exe"
if (-not (Test-Path $springExe)) {
    Write-Failure "spring.exe not found after extraction"
    Write-Host "Contents of $enginePath`:"
    Get-ChildItem $enginePath | ForEach-Object { Write-Host "  $_" }
    exit 1
}

# Cleanup archive (keep portable 7zr for future use)
Remove-Item $downloadPath -Force

# Print summary
Write-Host ""
Write-Success "Engine deployed successfully!"
Write-Host ""
Write-Host "Installation path: $enginePath" -ForegroundColor Yellow
Write-Host ""
Write-Host "Installed files:"
Get-ChildItem $enginePath -Name | ForEach-Object { Write-Host "  $_" }
Write-Host ""
Write-Host "To use this engine:" -ForegroundColor Cyan
Write-Host "  1. BAR Debug Launcher: https://github.com/beyond-all-reason/bar_debug_launcher"
Write-Host "  2. Direct: cd `"$enginePath`" && spring.exe --write-dir `"$BarPath\data`" --isolation"
Write-Host ""
Write-Host "To verify: Check infolog.txt for 'Spring engine version' with '(dunctem)' suffix"

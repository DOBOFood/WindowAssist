<#
.SYNOPSIS
    Builds the WinGet manifest set for the current WindowAssist version.

.DESCRIPTION
    The version is read from core\App.ahk (single source of truth) and the SHA256 is
    computed from dist\WindowAssist-vX.Y.Z.zip produced by build.bat. The result is
    written to winget\manifests\d\DOBOFood\WindowAssist\<version>\ using the exact
    folder layout of microsoft/winget-pkgs, so the folder can be validated and copied
    into a fork as-is.

.PARAMETER ReleaseNotes
    Optional release notes. When omitted the manifest only carries ReleaseNotesUrl
    (the link to the GitHub release).

.PARAMETER Force
    Overwrite an existing version folder (an error by default).

.EXAMPLE
    .\tools\winget-manifest.ps1 -ReleaseNotes "Fixed hotkey conflicts."

.EXAMPLE
    .\tools\winget-manifest.ps1            # release notes link only
#>
[CmdletBinding()]
param(
    [string]$ReleaseNotes,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$AppFile    = Join-Path $RepoRoot 'core\App.ahk'
$Identifier = 'DOBOFood.WindowAssist'
$RepoUrl    = 'https://github.com/DOBOFood/WindowAssist'
$Publisher  = 'DOBOFood'
$ManifestVersion = '1.28.0'

# --- version ------------------------------------------------------------------
$match = Select-String -Path $AppFile -Pattern 'static Version\s*:=\s*"([^"]+)"' | Select-Object -First 1
if (-not $match) { throw "Could not find 'static Version := ...' in $AppFile" }
$Version = $match.Matches[0].Groups[1].Value

# --- archive and hash ---------------------------------------------------------
$ZipName = "WindowAssist-v$Version.zip"
$ZipPath = Join-Path $RepoRoot "dist\$ZipName"
if (-not (Test-Path $ZipPath)) {
    throw "Missing $ZipPath. Build the release first: build.bat"
}

$Sha256 = (Get-FileHash -Algorithm SHA256 -Path $ZipPath).Hash
$ZipUrl = "$RepoUrl/releases/download/v$Version/$ZipName"
$TagUrl = "$RepoUrl/releases/tag/v$Version"
$TagPath = "v$Version"

# --- output folder ------------------------------------------------------------
$OutDir = Join-Path $RepoRoot "winget\manifests\d\DOBOFood\WindowAssist\$Version"
if (Test-Path $OutDir) {
    if (-not $Force) { throw "$OutDir already exists. Remove it or pass -Force." }
    Remove-Item $OutDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Write-Manifest {
    param([string]$Name, [string]$Content)
    $path = Join-Path $OutDir $Name
    # UTF-8 without BOM, LF endings: same shape as microsoft/winget-pkgs
    [IO.File]::WriteAllText($path, ($Content -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  $Name"
}

$notes = ''
if ($ReleaseNotes) {
    $body = ($ReleaseNotes -split "`r?`n" | ForEach-Object { "  $_" }) -join "`n"
    $notes = "ReleaseNotes: |-`n$body`n"
}

Write-Host "Version $Version, SHA256 $Sha256"

Write-Manifest "$Identifier.yaml" @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.version.$ManifestVersion.schema.json

PackageIdentifier: $Identifier
PackageVersion: $Version
DefaultLocale: en-US
ManifestType: version
ManifestVersion: $ManifestVersion
"@

Write-Manifest "$Identifier.locale.en-US.yaml" @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.defaultLocale.$ManifestVersion.schema.json

PackageIdentifier: $Identifier
PackageVersion: $Version
PackageLocale: en-US
Publisher: $Publisher
PublisherUrl: https://github.com/$Publisher
PublisherSupportUrl: $RepoUrl/issues
Author: $Publisher
PackageName: WindowAssist
PackageUrl: $RepoUrl
License: MIT
LicenseUrl: $RepoUrl/blob/$TagPath/LICENSE
Copyright: Copyright (c) 2026 $Publisher
ShortDescription: Fast per-monitor virtual desktops, visual overview canvas, floating scratchpad, and AltSnap mouse controls for Windows.
Description: |-
  WindowAssist brings instant per-monitor virtual desktops (up to 9 per monitor), a WebView2-powered visual overview canvas, a floating global scratchpad (The Pocket), AltSnap-style drag and resize from anywhere inside a window with native Aero Snap, layer peeker, pinning, auto-hiding title bars, and cross-desktop Alt+Tab switching.
Moniker: windowassist
Tags:
- autohotkey
- desktop-manager
- multitasking
- portable
- virtual-desktops
- window-manager
- windows
${notes}ReleaseNotesUrl: $TagUrl
ManifestType: defaultLocale
ManifestVersion: $ManifestVersion
"@

Write-Manifest "$Identifier.installer.yaml" @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.installer.$ManifestVersion.schema.json

PackageIdentifier: $Identifier
PackageVersion: $Version
Platform:
- Windows.Desktop
MinimumOSVersion: 10.0.17763.0
InstallerType: zip
NestedInstallerType: portable
NestedInstallerFiles:
- RelativeFilePath: WindowAssist.exe
  PortableCommandAlias: windowassist
ReleaseDate: $(Get-Date -Format 'yyyy-MM-dd')
Installers:
- Architecture: x64
  InstallerUrl: $ZipUrl
  InstallerSha256: $Sha256
ManifestType: installer
ManifestVersion: $ManifestVersion
"@

Write-Host ""
Write-Host "Wrote winget\manifests\d\DOBOFood\WindowAssist\$Version"
Write-Host "Validate:  winget validate --manifest `"$OutDir`""
Write-Host "Publish:   wingetcreate update $Identifier --version $Version --urls $ZipUrl --submit"

<#
.SYNOPSIS
    Automates the setup of the VSCode environment.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Use TLS 1.2+ for web requests
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$TotalSteps = 6
$CurrentStep = 1

function Show-Progress {
    param(
        [string]$Status
    )
    $Percent = [math]::Round(($CurrentStep / $TotalSteps) * 100)
    Write-Progress -Activity "VS Code Environment Setup" -Status $Status -PercentComplete $Percent
    Write-Host "[$CurrentStep/$TotalSteps] $Status" -ForegroundColor Cyan
}

# ----------------------------------------------------------------------
# 1. Verification and Setup
# ----------------------------------------------------------------------
Show-Progress "Verifying requirements and setting up..."
if (-not (Get-Command "code" -ErrorAction SilentlyContinue)) {
	throw "Dependency missing: 'code' (VS Code CLI). Ensure VS Code is installed and in PATH."
}

$TempDir = Join-Path $env:TEMP ("vscode-bootstrap-" + [guid]::NewGuid().ToString())
$null = New-Item -ItemType Directory -Path $TempDir -Force

try {
	$CurrentStep++
	# ----------------------------------------------------------------------
	# 2. Install VSCode Settings
	# ----------------------------------------------------------------------
	Show-Progress "Installing VSCode settings..."
	$SettingsUrl = "https://raw.githubusercontent.com/teenageswag/vscode-environment/refs/heads/main/settings/settings.json"
	$VsCodeSettingsDir = Join-Path $env:APPDATA "Code\User"
	if (-not (Test-Path -Path $VsCodeSettingsDir)) {
		$null = New-Item -ItemType Directory -Path $VsCodeSettingsDir -Force
	}

	$SettingsPath = Join-Path $VsCodeSettingsDir "settings.json"
	Invoke-WebRequest -Uri $SettingsUrl -OutFile $SettingsPath -UseBasicParsing
	Write-Host "  -> Successfully installed settings.json" -ForegroundColor Green

	$CurrentStep++
	# ----------------------------------------------------------------------
	# 3. Download and Install Font
	# ----------------------------------------------------------------------
	Show-Progress "Installing font GeistMono..."
	$FontFileName = "GeistMono[wght].ttf"
	# Using the raw URL directly to handle the brackets correctly
	$FontUrl = "https://raw.githubusercontent.com/teenageswag/vscode-environment/refs/heads/main/settings/fonts/GeistMono%5Bwght%5D.ttf"

	$UserFontsDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
	if (-not (Test-Path -Path $UserFontsDir)) {
		$null = New-Item -ItemType Directory -Path $UserFontsDir -Force
	}

	$FontDestPath = Join-Path $UserFontsDir $FontFileName

	if (-not (Test-Path -Path $FontDestPath)) {
		$FontTempPath = Join-Path $TempDir $FontFileName
		Invoke-WebRequest -Uri $FontUrl -OutFile $FontTempPath -UseBasicParsing
		Copy-Item -Path $FontTempPath -Destination $FontDestPath -Force

		# Register font in registry for current user
		$null = New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -Name "Geist Mono (TrueType)" -Value $FontDestPath -PropertyType String -Force

		Write-Host "  -> Successfully installed and registered font: GeistMono" -ForegroundColor Green
	}
	else {
		Write-Host "  -> Font already installed: GeistMono" -ForegroundColor Yellow
	}

	$CurrentStep++
	# ----------------------------------------------------------------------
	# 4. Install Public Extensions (from extensions.txt)
	# ----------------------------------------------------------------------
	Show-Progress "Installing public extensions..."
	$ExtensionsUrl = "https://raw.githubusercontent.com/teenageswag/vscode-environment/refs/heads/main/settings/extensions.txt"
	$ExtensionsTempPath = Join-Path $TempDir "extensions.txt"
	$ExtensionsDownloaded = $false

	try {
		Invoke-WebRequest -Uri $ExtensionsUrl -OutFile $ExtensionsTempPath -UseBasicParsing -ErrorAction Stop
		$ExtensionsDownloaded = $true
	}
	catch {
		Write-Host "  -> Could not fetch extensions.txt (might be missing), skipping public extensions." -ForegroundColor Yellow
	}

	if ($ExtensionsDownloaded) {
		$Extensions = Get-Content -Path $ExtensionsTempPath
		$TotalExts = ($Extensions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
		$ExtIndex = 0

		foreach ($Ext in $Extensions) {
			if (-not [string]::IsNullOrWhiteSpace($Ext)) {
				$ExtIndex++
				$ExtName = $Ext.Trim()

				$Percent = [math]::Round(($CurrentStep / $TotalSteps) * 100)
				Write-Progress -Activity "VS Code Environment Setup" -Status "Installing public extension [$ExtIndex/$TotalExts]: $ExtName" -PercentComplete $Percent
				Write-Host "  -> Installing $ExtName..." -ForegroundColor Cyan

				& code --install-extension $ExtName --force
				if ($LASTEXITCODE -ne 0) {
					throw "Failed to install extension: $ExtName"
				}
			}
		}
		Write-Host "  -> Successfully installed public extensions." -ForegroundColor Green
	}

	$CurrentStep++
	# ----------------------------------------------------------------------
	# 5. Install Custom Theme and Extension from GitHub Releases
	# ----------------------------------------------------------------------
	$Repos = @(
		"teenageswag/vscode-theme",
		"teenageswag/vscode-better-comments"
	)

	$RepoIndex = 0
	foreach ($Repo in $Repos) {
		$RepoIndex++
		Show-Progress "Installing custom extensions ($RepoIndex/$($Repos.Count)): $Repo"
		$ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"

		try {
			# Download release metadata from GitHub API with User-Agent to avoid 403 Forbidden
			$ReleaseInfo = Invoke-RestMethod -Uri $ApiUrl -Headers @{ "User-Agent" = "VSCode-Bootstrap" } -UseBasicParsing
		}
		catch {
			throw "Failed to fetch release info for $Repo.`nCheck if the repository is public and has published releases.`nDetails: $($_.Exception.Message)"
		}

		# Find the first .vsix asset
		$VsixAsset = $ReleaseInfo.assets | Where-Object { $_.name -like "*.vsix" } | Select-Object -First 1

		if (-not $VsixAsset) {
			throw "No .vsix asset found in the latest release of $Repo."
		}

		$DownloadUrl = $VsixAsset.browser_download_url
		$VsixName = $VsixAsset.name
		$DownloadPath = Join-Path $TempDir $VsixName

		Write-Host "  -> Downloading remote asset: $VsixName" -ForegroundColor Cyan
		Invoke-WebRequest -Uri $DownloadUrl -OutFile $DownloadPath -UseBasicParsing

		Write-Host "  -> Installing extension $VsixName..." -ForegroundColor Cyan
		& code --install-extension $DownloadPath --force
		if ($LASTEXITCODE -ne 0) {
			throw "Failed to install extension $VsixName via 'code' CLI."
		}

		Write-Host "  -> Successfully installed extension from $Repo!" -ForegroundColor Green
	}

	$CurrentStep++
	# ----------------------------------------------------------------------
	# 6. Clean up
	# ----------------------------------------------------------------------
	Show-Progress "Cleaning up temporary files..."
	if ($null -ne $TempDir -and (Test-Path -Path $TempDir)) {
		Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
	}

	Write-Progress -Activity "VS Code Environment Setup" -Completed
	Write-Host "`nAll done! Your VSCode environment has been successfully configured." -ForegroundColor Green
	exit 0
}
catch {
	Write-Progress -Activity "VS Code Environment Setup" -Completed
	Write-Host "`n[ERROR] $($_.Exception.Message)" -ForegroundColor Red
	if ($null -ne $TempDir -and (Test-Path -Path $TempDir)) {
		Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
	}
	exit 1
}

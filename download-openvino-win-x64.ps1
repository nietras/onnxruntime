# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
#
# Downloads and extracts the Windows x64 VC MT OpenVINO package required to
# build ONNX Runtime with the OpenVINO Execution Provider.
#
# Prerequisites:
# - PowerShell must have network access to storage.openvinotoolkit.org.
# - Ensure sufficient free disk space for the archive and extracted toolkit.
# - The default URL is pinned to OpenVINO 2026.3.1. Check the OpenVINO release
#   page for a newer stable release before updating this URL.
#
# Example:
#   .\download-openvino-win-x64.ps1
#   .\build-win-x64-openvino.ps1 -OpenVinoRoot .\external\openvino

[CmdletBinding()]
param(
	[string]$Destination = (Join-Path $PSScriptRoot "external\openvino"),

	[string]$PackageUri = "https://storage.openvinotoolkit.org/repositories/openvino/packages/2026.3.1/windows/openvino_toolkit_windows_2026.3.1.22476.56d9685302d_x86_64.zip",

	[switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$destinationPath = [System.IO.Path]::GetFullPath($Destination)
$setupVars = Join-Path $destinationPath "setupvars.ps1"
if ((Test-Path -Path $setupVars -PathType Leaf) -and -not $Force) {
	Write-Output "OpenVINO is already available at: $destinationPath"
	Write-Output "Use -Force to replace the existing toolkit."
	return
}

if (Test-Path -Path $destinationPath) {
	if (-not $Force) {
		throw "Destination already exists: $destinationPath. Use -Force to replace it."
	}

	Remove-Item -Path $destinationPath -Recurse -Force
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("openvino-" + [System.Guid]::NewGuid())
$archivePath = Join-Path $temporaryRoot "openvino.zip"
$extractPath = Join-Path $temporaryRoot "extract"

try {
	New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

	Write-Output "Downloading OpenVINO from $PackageUri"
	$previousProgressPreference = $ProgressPreference
	try {
		$ProgressPreference = "SilentlyContinue"
		Invoke-WebRequest -Uri $PackageUri -OutFile $archivePath -UseBasicParsing
	}
	finally {
		$ProgressPreference = $previousProgressPreference
	}

	[byte[]]$archiveMagic = Get-Content -Path $archivePath -Encoding Byte -TotalCount 4
	if ($archiveMagic.Length -lt 4 -or $archiveMagic[0] -ne 0x50 -or $archiveMagic[1] -ne 0x4B) {
		throw "The downloaded OpenVINO package is not a ZIP archive. Verify -PackageUri or try again later."
	}

	Write-Output "Extracting OpenVINO to $destinationPath"
	Expand-Archive -Path $archivePath -DestinationPath $extractPath -Force

	$innerFolder = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
	if ($null -eq $innerFolder) {
		throw "The OpenVINO archive did not contain the expected top-level directory."
	}

	New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
	Get-ChildItem -Path $innerFolder.FullName -Force | Move-Item -Destination $destinationPath -Force

	if (-not (Test-Path -Path $setupVars -PathType Leaf)) {
		throw "OpenVINO extraction completed, but setupvars.ps1 was not found in $destinationPath."
	}

	Write-Output "OpenVINO extracted to: $destinationPath"
	Write-Output "Build with: .\build-win-x64-openvino.ps1 -OpenVinoRoot $destinationPath"
}
finally {
	if (Test-Path -Path $temporaryRoot) {
		Remove-Item -Path $temporaryRoot -Recurse -Force
	}
}

# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
#
# Builds a native Windows x64 ONNX Runtime shared library with the OpenVINO CPU EP.
#
# Prerequisites:
# - Run from an x64 Developer PowerShell for Visual Studio 2026 with the Desktop
#   development with C++ workload and a Windows SDK installed.
# - Install a 64-bit Python 3.8 or newer, Git, and a CMake version that supports
#   the "Visual Studio 18 2026" generator.
#   If the current shell cannot resolve Python, pass its executable with -PythonPath.
# - Run .\download-openvino-win-x64.ps1 to obtain the latest compatible x64
#   Windows VC MT OpenVINO toolkit (version 2026.0 or newer, required by this
#   checkout). Pass its root directory with -OpenVinoRoot, or set OpenVINORootDir
#   before invoking this script.
# - Ensure this checkout contains the committed patch that enables OpenVINO CPU
#   EP execution on AMD CPUs. This script enables the CPU EP; it does not apply
#   source patches.
# - The first build updates Git submodules and downloads Python/CMake dependencies,
#   so it requires network access and sufficient disk space.
#
# Example:
#   .\build-win-x64-openvino.ps1 -OpenVinoRoot C:\opt\openvino

[CmdletBinding()]
param(
	[ValidateSet("Debug", "MinSizeRel", "Release", "RelWithDebInfo")]
	[string]$Configuration = "RelWithDebInfo",

	[string]$OpenVinoRoot = $env:OpenVINORootDir,

	[string]$PythonPath,

	[ValidateRange(0, [int]::MaxValue)]
	[int]$Parallel = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($OpenVinoRoot)) {
	throw "OpenVINO setupvars.ps1 was not found. Set OpenVINORootDir or pass -OpenVinoRoot with the OpenVINO toolkit root."
}

$setupVars = Join-Path $OpenVinoRoot "setupvars.ps1"
if (-not (Test-Path -Path $setupVars -PathType Leaf)) {
	throw "OpenVINO setupvars.ps1 was not found. Set OpenVINORootDir or pass -OpenVinoRoot with the OpenVINO toolkit root."
}

$pythonPathToUse = $PythonPath
if ([string]::IsNullOrWhiteSpace($pythonPathToUse)) {
	$python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue
	if ($null -ne $python) {
		$pythonPathToUse = $python.Source
	}
}

if ([string]::IsNullOrWhiteSpace($pythonPathToUse) -or -not (Test-Path -Path $pythonPathToUse -PathType Leaf) -or $pythonPathToUse -like "$env:LOCALAPPDATA\Microsoft\WindowsApps\*") {
	throw "Install a 64-bit Python 3.8 or newer and add it to PATH. The Windows Store python.exe alias is not a usable build interpreter."
}

. $setupVars

$buildArguments = @(
	(Join-Path $repoRoot "tools\ci_build\build.py"),
	"--build_dir", (Join-Path $repoRoot "build\Windows-OpenVINO"),
	"--config", $Configuration,
	"--cmake_generator", "Visual Studio 18 2026",
	"--build_shared_lib",
	"--use_openvino", "CPU",
	"--update",
	"--build",
	"--parallel", $Parallel,
	"--cmake_extra_defines", "onnxruntime_BUILD_UNIT_TESTS=OFF"
)

$previousErrorActionPreference = $ErrorActionPreference
try {
	$ErrorActionPreference = "Continue"
	& $pythonPathToUse @buildArguments
}
finally {
	$ErrorActionPreference = $previousErrorActionPreference
}

if ($LASTEXITCODE -ne 0) {
	exit $LASTEXITCODE
}

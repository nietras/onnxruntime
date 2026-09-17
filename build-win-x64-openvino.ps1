# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
#
# Builds a native Windows x64 ONNX Runtime shared library with CPU, CUDA,
# TensorRT, and OpenVINO CPU execution providers.
#
# Prerequisites:
# - Run from an x64 Developer PowerShell for Visual Studio 2026 with the Desktop
#   development with C++ workload and a Windows SDK installed.
# - Install a 64-bit Python 3.8 or newer, Git, and a CMake version that supports
#   the "Visual Studio 18 2026" generator.
#   If the current shell cannot resolve Python, pass its executable with -PythonPath.
# - The script downloads the compatible OpenVINO, CUDA 13.4.2, cuDNN 9.26.0.51,
#   and TensorRT 10.16.1.11 SDKs into externals\ by default. NVIDIA distributes
#   this TensorRT release for CUDA 13.0-13.2; it is built here with CUDA 13.4.2.
# - By default, the script builds only onnxruntime.dll. It exports the CUDA,
#   TensorRT, and OpenVINO append APIs, but their provider DLLs are loaded at
#   runtime and are not built. Use -BuildProviderDlls to build them as well.
# - The first build updates Git submodules and downloads Python/CMake dependencies,
#   so it requires network access and sufficient disk space.
#
# Example:
#   .\build-win-x64-openvino.ps1
#   .\build-win-x64-openvino.ps1 -BuildProviderDlls

[CmdletBinding()]
param(
	[ValidateSet("Debug", "MinSizeRel", "Release", "RelWithDebInfo")]
	[string]$Configuration = "RelWithDebInfo",

	[string]$OpenVinoRoot = (Join-Path $PSScriptRoot "externals\openvino"),

	[string]$CudaRoot = (Join-Path $PSScriptRoot "externals\cuda-13.4.2"),

	[string]$CudnnRoot = (Join-Path $PSScriptRoot "externals\cudnn-9.26.0.51-cuda13"),

	[string]$TensorRtRoot = (Join-Path $PSScriptRoot "externals\tensorrt-10.16.1.11-cuda13.2"),

	[string]$PythonPath,

	[ValidateRange(0, [int]::MaxValue)]
	[int]$Parallel = 8,

	[switch]$BuildProviderDlls,

	[switch]$ForceDownload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSCommandPath
$downloadScript = Join-Path $repoRoot "download-openvino-win-x64.ps1"
& $downloadScript -OpenVinoRoot $OpenVinoRoot -CudaRoot $CudaRoot -CudnnRoot $CudnnRoot -TensorRtRoot $TensorRtRoot -Force:$ForceDownload
if (-not $?) {
	exit 1
}

$setupVars = Join-Path $OpenVinoRoot "setupvars.ps1"
if (-not (Test-Path -Path $setupVars -PathType Leaf)) {
	throw "OpenVINO setupvars.ps1 was not found after SDK provisioning: $OpenVinoRoot"
}

$pythonPathToUse = $PythonPath
if ([string]::IsNullOrWhiteSpace($pythonPathToUse)) {
	$python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($null -ne $python) {
		$pythonPathToUse = $python.Source
	}
}

if ([string]::IsNullOrWhiteSpace($pythonPathToUse) -or -not (Test-Path -Path $pythonPathToUse -PathType Leaf) -or $pythonPathToUse -like "$env:LOCALAPPDATA\Microsoft\WindowsApps\*") {
	throw "Install a 64-bit Python 3.8 or newer and add it to PATH. The Windows Store python.exe alias is not a usable build interpreter."
}

. $setupVars
$env:PATH = (Join-Path $CudaRoot "bin") + ";" + (Join-Path $CudaRoot "bin\x64") + ";" +
	(Join-Path $CudnnRoot "bin\x64") + ";" + (Join-Path $TensorRtRoot "bin") + ";" + (Join-Path $TensorRtRoot "lib") + ";" + $env:PATH

$buildArguments = @(
	(Join-Path $repoRoot "tools\ci_build\build.py"),
	"--build_dir", (Join-Path $repoRoot "build\Windows-OpenVINO-CUDA-TensorRT"),
	"--config", $Configuration,
	"--cmake_generator", "Visual Studio 18 2026",
	"--build_shared_lib",
	"--use_openvino", "CPU",
	"--use_cuda",
	"--cuda_home", $CudaRoot,
	"--cudnn_home", $CudnnRoot,
	"--use_tensorrt",
	"--tensorrt_home", $TensorRtRoot,
	"--update",
	"--build",
	"--parallel", $Parallel,
	"--cmake_extra_defines", "onnxruntime_BUILD_UNIT_TESTS=OFF"
)

if (-not $BuildProviderDlls) {
	$buildArguments += "--target", "onnxruntime"
}

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

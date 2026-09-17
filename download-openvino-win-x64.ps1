# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
#
# Downloads portable Windows x64 SDKs required to build ONNX Runtime with CPU,
# CUDA, TensorRT, and OpenVINO CPU execution providers.
#
# Prerequisites:
# - PowerShell must have network access to storage.openvinotoolkit.org and
#   developer.download.nvidia.com.
# - Ensure sufficient free disk space for archives and extracted SDKs.
#
# Example:
#   .\download-openvino-win-x64.ps1
#   .\build-win-x64-openvino.ps1

[CmdletBinding()]
param(
	[Alias("Destination")]
	[string]$OpenVinoRoot = (Join-Path $PSScriptRoot "externals\openvino"),

	[Alias("PackageUri")]
	[string]$OpenVinoPackageUri = "https://storage.openvinotoolkit.org/repositories/openvino/packages/2026.3.1/windows/openvino_toolkit_windows_2026.3.1.22476.56d9685302d_x86_64.zip",

	[string]$CudaRoot = (Join-Path $PSScriptRoot "externals\cuda-13.4.2"),

	[string]$CudnnRoot = (Join-Path $PSScriptRoot "externals\cudnn-9.26.0.51-cuda13"),

	[string]$TensorRtRoot = (Join-Path $PSScriptRoot "externals\tensorrt-10.16.1.11-cuda13.2"),

	[Alias("ForceDownload")]
	[switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$temporaryRootParent = Join-Path $PSScriptRoot "externals\temp"
$cudaRedistributableUri = "https://developer.download.nvidia.com/compute/cuda/redist/redistrib_13.4.2.json"
$cudnnPackageUri = "https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/windows-x86_64/cudnn-windows-x86_64-9.26.0.51_cuda13-archive.zip"
$tensorRtPackageUri = "https://developer.download.nvidia.com/compute/machine-learning/tensorrt/10.16.1/zip/TensorRT-10.16.1.11.Windows.amd64.cuda-13.2.zip"

function Test-SdkLayout {
	param(
		[string]$Root,
		[string[]]$RequiredPaths
	)

	foreach ($requiredPath in $RequiredPaths) {
		if (-not (Test-Path -Path (Join-Path $Root $requiredPath) -PathType Leaf)) {
			return $false
		}
	}

	return $true
}

function Invoke-ArchiveDownload {
	param(
		[string]$Uri,
		[string]$ArchivePath,
		[string]$Sha256
	)

	Write-Output "Downloading $Uri"
	$previousProgressPreference = $ProgressPreference
	try {
		$ProgressPreference = "SilentlyContinue"
		Invoke-WebRequest -Uri $Uri -OutFile $ArchivePath -UseBasicParsing
	}
	finally {
		$ProgressPreference = $previousProgressPreference
	}

	[byte[]]$archiveMagic = Get-Content -Path $ArchivePath -Encoding Byte -TotalCount 4
	if ($archiveMagic.Length -lt 4 -or $archiveMagic[0] -ne 0x50 -or $archiveMagic[1] -ne 0x4B) {
		throw "The downloaded package is not a ZIP archive: $Uri"
	}

	if (-not [string]::IsNullOrWhiteSpace($Sha256)) {
		$actualSha256 = (Get-FileHash -Path $ArchivePath -Algorithm SHA256).Hash
		if ($actualSha256 -ne $Sha256) {
			throw "SHA256 verification failed for $Uri."
		}
	}
}

function Install-SdkArchive {
	param(
		[string]$Name,
		[string]$Uri,
		[string]$Destination,
		[string[]]$RequiredPaths
	)

	if (Test-SdkLayout -Root $Destination -RequiredPaths $RequiredPaths) {
		if (-not $Force) {
			Write-Output "$Name is already available at: $Destination"
			return
		}
	}
	elseif ((Test-Path -Path $Destination) -and -not $Force) {
		throw "$Name at $Destination is incomplete. Use -Force to replace it."
	}

	if (Test-Path -Path $Destination) {
		Remove-Item -Path $Destination -Recurse -Force
	}

	$temporaryRoot = Join-Path $temporaryRootParent ("$Name-" + [System.Guid]::NewGuid())
	$archivePath = Join-Path $temporaryRoot "$Name.zip"
	$extractPath = Join-Path $temporaryRoot "extract"
	try {
		New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
		Invoke-ArchiveDownload -Uri $Uri -ArchivePath $archivePath
		Expand-Archive -Path $archivePath -DestinationPath $extractPath -Force
		$innerFolder = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
		if ($null -eq $innerFolder) {
			throw "The $Name archive did not contain the expected top-level directory."
		}

		New-Item -ItemType Directory -Path $Destination -Force | Out-Null
		Get-ChildItem -Path $innerFolder.FullName -Force | Move-Item -Destination $Destination -Force
		if (-not (Test-SdkLayout -Root $Destination -RequiredPaths $RequiredPaths)) {
			throw "The $Name archive did not provide the expected SDK layout."
		}
	}
	finally {
		if (Test-Path -Path $temporaryRoot) {
			Remove-Item -Path $temporaryRoot -Recurse -Force
		}
	}
}

function Repair-CudaVisualStudioIntegration {
	$sourceDirectory = Join-Path $CudaRoot "visual_studio_integration\MSBuildExtensions"
	$destinationDirectory = Join-Path $CudaRoot "extras\visual_studio_integration\MSBuildExtensions"
	$cudaProps = Join-Path $destinationDirectory "CUDA 13.4.props"
	if ((Test-Path -Path $sourceDirectory -PathType Container) -and -not (Test-Path -Path $cudaProps -PathType Leaf)) {
		New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
		Copy-Item -Path (Join-Path $sourceDirectory "*") -Destination $destinationDirectory -Force
	}
}

function Install-PortableCuda {
	$requiredPaths = @(
		"bin\nvcc.exe", "include\cuda_runtime.h", "lib\x64\cudart.lib",
		"lib\x64\cublas.lib", "lib\x64\curand.lib", "lib\x64\nvJitLink.lib",
		"extras\visual_studio_integration\MSBuildExtensions\CUDA 13.4.props"
	)
	Repair-CudaVisualStudioIntegration
	if (Test-SdkLayout -Root $CudaRoot -RequiredPaths $requiredPaths) {
		if (-not $Force) {
			Write-Output "CUDA is already available at: $CudaRoot"
			return
		}
	}
	elseif ((Test-Path -Path $CudaRoot) -and -not $Force) {
		throw "CUDA at $CudaRoot is incomplete. Use -Force to replace it."
	}

	if (Test-Path -Path $CudaRoot) {
		Remove-Item -Path $CudaRoot -Recurse -Force
	}

	$redistributables = (Invoke-WebRequest -Uri $cudaRedistributableUri -UseBasicParsing).Content | ConvertFrom-Json
	$componentNames = @(
		"cccl", "cuda_crt", "cuda_cudart", "cuda_cupti", "cuda_nvcc", "cuda_nvrtc",
		"libcublas", "libcufft", "libcurand", "libcusolver", "libcusparse", "libnvfatbin",
		"libnvjitlink", "libnvptxcompiler", "libnvvm", "visual_studio_integration"
	)
	$temporaryRoot = Join-Path $temporaryRootParent ("cuda-" + [System.Guid]::NewGuid())
	try {
		New-Item -ItemType Directory -Path $CudaRoot -Force | Out-Null
		foreach ($componentName in $componentNames) {
			$component = $redistributables.$componentName."windows-x86_64"
			if ($null -eq $component) {
				throw "CUDA redistributable metadata did not contain $componentName for Windows x64."
			}

			$archivePath = Join-Path $temporaryRoot ("$componentName.zip")
			$extractPath = Join-Path $temporaryRoot $componentName
			$componentUri = "https://developer.download.nvidia.com/compute/cuda/redist/$($component.relative_path)"
			New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
			Invoke-ArchiveDownload -Uri $componentUri -ArchivePath $archivePath -Sha256 $component.sha256
			Expand-Archive -Path $archivePath -DestinationPath $extractPath -Force
			$innerFolder = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
			if ($null -eq $innerFolder) {
				throw "CUDA archive did not contain the expected top-level directory: $componentUri"
			}
			Get-ChildItem -Path $innerFolder.FullName -Force | Copy-Item -Destination $CudaRoot -Recurse -Force
		}

		Repair-CudaVisualStudioIntegration
		if (-not (Test-SdkLayout -Root $CudaRoot -RequiredPaths $requiredPaths)) {
			throw "Portable CUDA extraction completed, but the required compiler files were not found in $CudaRoot."
		}
	}
	catch {
		if (Test-Path -Path $CudaRoot) {
			Remove-Item -Path $CudaRoot -Recurse -Force
		}
		throw
	}
	finally {
		if (Test-Path -Path $temporaryRoot) {
			Remove-Item -Path $temporaryRoot -Recurse -Force
		}
	}
}

Install-SdkArchive -Name "openvino" -Uri $OpenVinoPackageUri -Destination $OpenVinoRoot -RequiredPaths @("setupvars.ps1")
Install-PortableCuda
Install-SdkArchive -Name "cudnn" -Uri $cudnnPackageUri -Destination $CudnnRoot -RequiredPaths @("include\cudnn.h", "lib\x64\cudnn.lib", "bin\x64\cudnn64_9.dll")
Install-SdkArchive -Name "tensorrt" -Uri $tensorRtPackageUri -Destination $TensorRtRoot -RequiredPaths @("include\NvInfer.h", "lib\nvinfer_10.lib", "bin\nvinfer_10.dll")

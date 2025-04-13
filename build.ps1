# Build script for Odin SDL3 project
#
# Logging Color Scheme:
# - White:  INFO messages (general progress and status updates)
# - Green:  SUCCESS messages (successful operations)
# - Red:    ERROR messages (errors and failures)
# - Yellow: WARNING messages (non-critical issues)
#
# Directory Structure:
# - bin/:              Contains the compiled executable and SDL3.dll
# - assets/shaders/:   Contains GLSL shader source files
# - assets/shaders/bin/: Contains compiled SPIR-V shader files
#
# Dependencies:
# - glslc:  Required for shader compilation
# - SDL3.dll: Expected at C:\Users\anton\odin\vendor\sdl3\SDL3.dll
# - Odin:   Required for building the project
#
# Usage:
#   .\build.ps1 [options]
#
# Options:
#   -clean     Clean build artifacts before building
#   -help      Show this help message
#   -version   Show version information
#
$ErrorActionPreference = "Stop"
$script:Version = "1.0.0"

# ASCII Art Header
$header = @"
............................................................
......%%%%...%%%%%...%%%%%%..%%..%%.........................                        
.....%%..%%..%%..%%....%%....%%%.%%.........................                        
.....%%..%%..%%..%%....%%....%%.%%%.........................                       
.....%%..%%..%%..%%....%%....%%..%%.........................                        
......%%%%...%%%%%...%%%%%%..%%..%%.........................                        
....................................                        
.....%%%%%...%%..%%..%%%%%%..%%......%%%%%...%%%%%%..%%%%%..
.....%%..%%..%%..%%....%%....%%......%%..%%..%%......%%..%%.
.....%%%%%...%%..%%....%%....%%......%%..%%..%%%%....%%%%%..
.....%%..%%..%%..%%....%%....%%......%%..%%..%%......%%..%%.
.....%%%%%....%%%%...%%%%%%..%%%%%%..%%%%%...%%%%%%..%%..%%.
............................................................

Odin Builder $Version

"@

# Function to format log messages with timestamp and level
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Color = "White"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp [$Level] $Message" -ForegroundColor $Color
}

# Function to show help message
function Show-Help {
    Write-Host "Odin SDL3 Build Script v$Version" -ForegroundColor Cyan
    Write-Host "Usage: .\build.ps1 [options]" -ForegroundColor White
    Write-Host "Options:" -ForegroundColor White
    Write-Host "  -clean     Clean build artifacts before building" -ForegroundColor White
    Write-Host "  -help      Show this help message" -ForegroundColor White
    Write-Host "  -version   Show version information" -ForegroundColor White
    exit 0
}

# Function to show version
function Show-Version {
    Write-Host "Odin SDL3 Build Script v$Version" -ForegroundColor Cyan
    exit 0
}

# Function to clean build artifacts
function Clean-BuildArtifacts {
    Write-Log "Cleaning build artifacts..." "INFO" "White"
    
    # Remove bin directory
    if (Test-Path "bin") {
        Remove-Item -Path "bin" -Recurse -Force
        Write-Log "Removed bin directory" "SUCCESS" "Green"
    }
    
    # Remove compiled shaders
    if (Test-Path "assets/shaders/bin") {
        Remove-Item -Path "assets/shaders/bin" -Recurse -Force
        Write-Log "Removed compiled shaders" "SUCCESS" "Green"
    }
    
    Write-Log "Clean completed" "SUCCESS" "Green"
}

# Function to check dependencies
function Check-Dependencies {
    Write-Log "Checking dependencies..." "INFO" "White"
    $missingDeps = @()
    
    # Check for glslc
    try {
        $null = Get-Command glslc -ErrorAction Stop
        Write-Log "Found glslc" "SUCCESS" "Green"
    } catch {
        $missingDeps += "glslc (shader compiler)"
    }
    
    # Check for Odin
    try {
        $null = Get-Command odin -ErrorAction Stop
        Write-Log "Found Odin compiler" "SUCCESS" "Green"
    } catch {
        $missingDeps += "Odin compiler"
    }
    
    # Check for SDL3.dll
    $sdl3_dll_path = "C:\Users\anton\odin\vendor\sdl3\SDL3.dll"
    if (Test-Path $sdl3_dll_path) {
        Write-Log "Found SDL3.dll" "SUCCESS" "Green"
    } else {
        $missingDeps += "SDL3.dll at $sdl3_dll_path"
    }
    
    if ($missingDeps.Count -gt 0) {
        Write-Log "Missing dependencies:" "ERROR" "Red"
        foreach ($dep in $missingDeps) {
            Write-Log "  - $dep" "ERROR" "Red"
        }
        Write-Log "Please install the missing dependencies and try again" "ERROR" "Red"
        exit 1
    }
    
    Write-Log "All dependencies found" "SUCCESS" "Green"
}

# Parse command line arguments
$clean = $false
foreach ($arg in $args) {
    switch ($arg) {
        "-clean" { $clean = $true }
        "-help" { Show-Help }
        "-version" { Show-Version }
        default {
            Write-Log "Unknown option: $arg" "ERROR" "Red"
            Show-Help
        }
    }
}

# Show header
Write-Host $header -ForegroundColor Cyan

# Check dependencies
Check-Dependencies

# Clean if requested
if ($clean) {
    Clean-BuildArtifacts
}

# Create bin directory if it doesn't exist
if (-not (Test-Path "bin")) {
    New-Item -ItemType Directory -Path "bin"
}

# Create shaders/bin directory if it doesn't exist
if (-not (Test-Path "assets/shaders/bin")) {
    New-Item -ItemType Directory -Path "assets/shaders/bin"
}

# Compile shaders
Write-Log "Compiling shaders..." "INFO" "White"
$shaderFiles = Get-ChildItem -Path "assets/shaders" -Include "*.glsl.vert","*.glsl.frag" -Recurse
$shaderCount = 0

foreach ($shader in $shaderFiles) {
    # Skip files in the bin directory
    if ($shader.DirectoryName -like "*\bin") {
        continue
    }
    $shaderCount++
    # Extract the shader type (vert or frag) from the filename
    $shaderType = if ($shader.Name -like "*.vert") { "vert" } else { "frag" }
    # Replace .glsl with .spv in the filename
    $outputName = $shader.BaseName -replace "\.glsl$", ".spv"
    $outputPath = "assets/shaders/bin/$outputName.$shaderType"
    Write-Log "Compiling $($shader.Name)..." "INFO" "White"
    glslc $shader.FullName -o $outputPath
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Successfully compiled $($shader.Name)" "SUCCESS" "Green"
    } else {
        Write-Log "Failed to compile $($shader.Name)" "ERROR" "Red"
        exit 1
    }
}

if ($shaderCount -eq 0) {
    Write-Log "No shaders found in assets/shaders directory" "WARNING" "Yellow"
} else {
    Write-Log "Shader compilation completed. Compiled $shaderCount shader(s)" "SUCCESS" "Green"
}

# Build the project
Write-Log "Building Odin project..." "INFO" "White"
odin build src -out:bin/main.exe -strict-style -debug

if ($LASTEXITCODE -eq 0) {
    Write-Log "Build successful! Output is in bin/main.exe" "SUCCESS" "Green"
    
    # Copy SDL3.dll to bin directory
    $sdl3_dll_path = "C:\Users\anton\odin\vendor\sdl3\SDL3.dll"
    if (Test-Path $sdl3_dll_path) {
        Write-Log "Copying SDL3.dll to bin directory..." "INFO" "White"
        Copy-Item $sdl3_dll_path -Destination ".\bin\" -Force
        Write-Log "SDL3.dll copied successfully!" "SUCCESS" "Green"
    } else {
        Write-Log "SDL3.dll not found at $sdl3_dll_path" "ERROR" "Red"
    }
    
    Write-Log "Running the program..." "INFO" "White"
    & "./bin/main.exe"
} else {
    Write-Log "Build failed!" "ERROR" "Red"
    exit 1
} 
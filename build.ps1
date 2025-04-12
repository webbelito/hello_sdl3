# Build script for Odin SDL3 project
$ErrorActionPreference = "Stop"

# ASCII Art Header
$header = @"
Odin Builder
"@

Write-Host $header -ForegroundColor Cyan

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

# Create bin directory if it doesn't exist
if (-not (Test-Path "bin")) {
    New-Item -ItemType Directory -Path "bin"
}

# Build the project
Write-Log "Building Odin project..." "INFO" "White"
odin build src -out:bin/main.exe -strict-style -debug

if ($LASTEXITCODE -eq 0) {
    Write-Log "Build successful! Output is in bin/main.exe" "SUCCESS" "Green"
    
    # Copy SDL3.dll to bin directory
    $sdl3_dll_path = "C:\Users\anton\odin\vendor\sdl3\SDL3.dll"
    if (Test-Path $sdl3_dll_path) {
        Write-Log "Copying SDL3.dll to bin directory..." "INFO" "Yellow"
        Copy-Item $sdl3_dll_path -Destination ".\bin\" -Force
        Write-Log "SDL3.dll copied successfully!" "SUCCESS" "Green"
    } else {
        Write-Log "SDL3.dll not found at $sdl3_dll_path" "ERROR" "Red"
    }
    
    Write-Log "Running the program..." "INFO" "Yellow"
    & "./bin/main.exe"
} else {
    Write-Log "Build failed!" "ERROR" "Red"
    exit 1
} 
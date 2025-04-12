# Build script for Odin SDL3 project
$ErrorActionPreference = "Stop"

# Create bin directory if it doesn't exist
if (-not (Test-Path "bin")) {
    New-Item -ItemType Directory -Path "bin"
}

# Build the project
Write-Host "Building Odin project..."
odin build src -out:bin/main.exe -strict-style -debug

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful! Output is in bin/main.exe" -ForegroundColor Green
    Write-Host "Running the program..." -ForegroundColor Yellow
    & "./bin/main.exe"
} else {
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
} 
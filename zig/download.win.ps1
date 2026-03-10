$ErrorActionPreference = "Stop"

$ZIG_MIRROR="https://pkg.machengine.org/zig"
$ZIG_RELEASE = "0.15.2"
$ZIG_CHECKSUMS = @"
$ZIG_MIRROR/0.15.2/zig-aarch64-windows-0.15.2.zip b926465f8872bf983422257cd9ec248bb2b270996fbe8d57872cca13b56fc370
$ZIG_MIRROR/0.15.2/zig-x86_64-windows-0.15.2.zip 3a0ed1e8799a2f8ce2a6e6290a9ff22e6906f8227865911fb7ddedc3cc14cb0c
"@

$ZIG_ARCH = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
    "aarch64"
} elseif ($env:PROCESSOR_ARCHITECTURE -eq "AMD64") {
    "x86_64"
} else {
    Write-Error "Unsupported architecture: $($env:PROCESSOR_ARCHITECTURE)"
    exit 1
}
$ZIG_OS = "windows"
$ZIG_EXTENSION = ".zip"

# Build URL:
$ZIG_URL = "$ZIG_MIRROR/$ZIG_RELEASE/zig-$ZIG_ARCH-$ZIG_OS-$ZIG_RELEASE$ZIG_EXTENSION"
$ZIG_ARCHIVE = [System.IO.Path]::GetFileName("$ZIG_URL")
$ZIG_DIRECTORY = "$ZIG_ARCHIVE" -replace [regex]::Escape($ZIG_EXTENSION), ""

# Find expected checksum from list:
$ZIG_CHECKSUM_EXPECTED = ($ZIG_CHECKSUMS -split "`n" | Where-Object { $_ -like "*$ZIG_URL*" }) -split ' ' | Select-Object -Last 1

Write-Output "Downloading Zig $ZIG_RELEASE for Windows..."
Invoke-WebRequest -Uri "$ZIG_URL" -OutFile "$ZIG_ARCHIVE"

# Verify the checksum.
$ZIG_CHECKSUM_ACTUAL=(Get-FileHash "${ZIG_ARCHIVE}").Hash

if ($ZIG_CHECKSUM_ACTUAL -ne $ZIG_CHECKSUM_EXPECTED) {
    Write-Error "Checksum mismatch. Expected '$ZIG_CHECKSUM_EXPECTED' but got '$ZIG_CHECKSUM_ACTUAL'."
    exit 1
}

# Extract and then remove the downloaded archive:
Write-Output "Extracting $ZIG_ARCHIVE..."
Expand-Archive -Path "$ZIG_ARCHIVE" -DestinationPath .
Remove-Item "$ZIG_ARCHIVE"

# Replace these existing directories and files so that we can install or upgrade:
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue zig/doc, zig/lib
Move-Item "$ZIG_DIRECTORY/LICENSE" zig/
Move-Item "$ZIG_DIRECTORY/README.md" zig/
Move-Item "$ZIG_DIRECTORY/doc" zig/
Move-Item "$ZIG_DIRECTORY/lib" zig/
Move-Item "$ZIG_DIRECTORY/zig.exe" zig/

# We expect to have now moved all directories and files out of the extracted directory.
# Do not force remove so that we can get an error if the above list of files ever changes:
Remove-Item "$ZIG_DIRECTORY"

# It's up to the user to add this to their path if they want to:
$ZIG_BIN = Join-Path (Get-Location) "zig\zig.exe"
Write-Output "Downloading completed ($ZIG_BIN)! Enjoy!"

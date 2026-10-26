# build_freetype.ps1
# Cross-compile FreeType as a static library for HarmonyOS (OHOS) using the SDK's CMake/Ninja/toolchain.
#
# Usage:
#   & D:\harmony\deps\build_freetype.ps1
#   & D:\harmony\deps\build_freetype.ps1 -Clean -Jobs 14
#
# All tool output is also written to build_freetype.log next to this script (overwritten each run).
#
# Source must already exist at <DepsRoot>\src\freetype-<Version> (tarball from download.savannah.gnu.org).

param(
    [string]$Version   = "2.13.3",
    [string]$Arch      = "arm64-v8a",
    [int]   $Jobs      = 14,
    [string]$DepsRoot  = "D:\harmony\deps",
    [string]$SdkNative = "D:\DevEco Studio\sdk\default\openharmony\native",
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

$cmake     = Join-Path $SdkNative "build-tools\cmake\bin\cmake.exe"
$ninja     = Join-Path $SdkNative "build-tools\cmake\bin\ninja.exe"
$toolchain = Join-Path $SdkNative "build\cmake\ohos.toolchain.cmake"
$srcDir    = Join-Path $DepsRoot "src\freetype-$Version"
$buildDir  = Join-Path $DepsRoot "build\freetype-$Version-$Arch"
$installDir = Join-Path $DepsRoot "install\$Arch"

foreach ($p in @($cmake, $ninja, $toolchain, $srcDir)) {
    if (-not (Test-Path $p)) { throw "Not found: $p" }
}

if ($Clean -and (Test-Path $buildDir)) {
    Remove-Item -Recurse -Force $buildDir
}
New-Item -ItemType Directory -Force $buildDir, $installDir | Out-Null

# Native tools write warnings to stderr; in Windows PowerShell 5.1 that would abort under "Stop".
# From here on, success is judged by $LASTEXITCODE only.
$ErrorActionPreference = "Continue"

# Mirror all tool output to <script name>.log (UTF-8) while still printing it
$log = [IO.Path]::ChangeExtension($PSCommandPath, ".log")
Set-Content -Path $log -Value "=== build_freetype $(Get-Date -Format s)  Version=$Version Arch=$Arch Jobs=$Jobs ===" -Encoding utf8
filter Log { $s = "$_"; Add-Content -Path $log -Value $s -Encoding utf8; $s }

# CMake paths use forward slashes to avoid escaping issues
$fw = { param($s) $s -replace '\\', '/' }

& $cmake -S (& $fw $srcDir) -B (& $fw $buildDir) -G Ninja `
    "-DCMAKE_MAKE_PROGRAM=$(& $fw $ninja)" `
    "-DCMAKE_TOOLCHAIN_FILE=$(& $fw $toolchain)" `
    "-DOHOS_ARCH=$Arch" `
    -DOHOS_PLATFORM=OHOS `
    -DOHOS_STL=c++_shared `
    -DCMAKE_BUILD_TYPE=Release `
    "-DCMAKE_INSTALL_PREFIX=$(& $fw $installDir)" `
    -DBUILD_SHARED_LIBS=OFF `
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON `
    -DFT_DISABLE_ZLIB=TRUE `
    -DFT_DISABLE_BZIP2=TRUE `
    -DFT_DISABLE_PNG=TRUE `
    -DFT_DISABLE_HARFBUZZ=TRUE `
    -DFT_DISABLE_BROTLI=TRUE 2>&1 | Log
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed ($LASTEXITCODE)" }

& $cmake --build (& $fw $buildDir) --config Release --parallel $Jobs 2>&1 | Log
if ($LASTEXITCODE -ne 0) { throw "Build failed ($LASTEXITCODE)" }

& $cmake --install (& $fw $buildDir) --config Release 2>&1 | Log
if ($LASTEXITCODE -ne 0) { throw "Install failed ($LASTEXITCODE)" }

"FreeType $Version installed to $installDir" | Log

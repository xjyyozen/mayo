# build_occt.ps1
# Cross-compile OpenCascade (OCCT) 7.9.x as shared libraries for HarmonyOS (OHOS), GLES2 (TKOpenGles) variant.
#
# Usage (run in the current PowerShell session, no execution-policy change needed):
#   & D:\harmony\deps\build_occt.ps1
#   & D:\harmony\deps\build_occt.ps1 -Clean -Jobs 14
#
# All tool output is also written to build_occt.log next to this script (overwritten each run).
#
# Prerequisites:
#   - FreeType installed to <DepsRoot>\install\<Arch> (build_freetype.ps1)
#   - OCCT source at <DepsRoot>\src\OCCT-<Tag>, cloned from https://github.com/Open-Cascade-SAS/OCCT
#   - OHOS patch applied: git -C <src> apply <DepsRoot>\patches\occt.patch (done automatically below)
#   - RapidJSON (header-only, enables the glTF reader RWGltf_CafReader) at <DepsRoot>\src\rapidjson:
#       git clone https://github.com/Tencent/rapidjson.git <DepsRoot>\src\rapidjson
#       git -C <DepsRoot>\src\rapidjson checkout <RapidJsonCommit>
#     Without it OCCT still builds TKDEGLTF, but reading glTF fails at runtime.
#
# Re-running without -Clean is incremental: only the toolkits affected by changed options are rebuilt.

param(
    [string]$Tag       = "7_9_3",
    # RapidJSON has had no release since v1.1.0 (2016); pin a master commit instead
    [string]$RapidJsonCommit = "24b5e7a8b27f42fa16b96fc70aade9106cf7102f",
    [string]$Arch      = "arm64-v8a",
    [int]   $Jobs      = 14,
    [string]$DepsRoot  = "D:\harmony\deps",
    [string]$SdkNative = "D:\DevEco Studio\sdk\default\openharmony\native",
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

$cmake      = Join-Path $SdkNative "build-tools\cmake\bin\cmake.exe"
$ninja      = Join-Path $SdkNative "build-tools\cmake\bin\ninja.exe"
$toolchain  = Join-Path $SdkNative "build\cmake\ohos.toolchain.cmake"
$srcDir     = Join-Path $DepsRoot "src\OCCT-$Tag"
$patch      = Join-Path $DepsRoot "patches\occt.patch"
$buildDir   = Join-Path $DepsRoot "build\occt-$Tag-$Arch"
$installDir = Join-Path $DepsRoot "install\$Arch"
$rapidJson  = Join-Path $DepsRoot "src\rapidjson"

foreach ($p in @($cmake, $ninja, $toolchain, $srcDir, $patch, (Join-Path $installDir "lib\libfreetype.a"),
                 (Join-Path $rapidJson "include\rapidjson\rapidjson.h"))) {
    if (-not (Test-Path $p)) { throw "Not found: $p" }
}
$rjHead = git -C $rapidJson rev-parse HEAD
if ($rjHead -ne $RapidJsonCommit) {
    throw "RapidJSON at $rapidJson is $rjHead, expected $RapidJsonCommit (git -C $rapidJson checkout $RapidJsonCommit)"
}

# Apply the OHOS patch if not applied yet (reverse-check succeeds => already applied)
git -C $srcDir apply --reverse --check $patch 2>$null
if ($LASTEXITCODE -ne 0) {
    git -C $srcDir apply $patch
    if ($LASTEXITCODE -ne 0) { throw "Failed to apply $patch" }
    Write-Host "Applied $patch"
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
Set-Content -Path $log -Value "=== build_occt $(Get-Date -Format s)  Tag=$Tag Arch=$Arch Jobs=$Jobs ===" -Encoding utf8
filter Log { $s = "$_"; Add-Content -Path $log -Value $s -Encoding utf8; $s }

# CMake paths use forward slashes to avoid escaping issues
$fw = { param($s) $s -replace '\\', '/' }
$inst = & $fw $installDir

& $cmake -S (& $fw $srcDir) -B (& $fw $buildDir) -G Ninja `
    "-DCMAKE_MAKE_PROGRAM=$(& $fw $ninja)" `
    "-DCMAKE_TOOLCHAIN_FILE=$(& $fw $toolchain)" `
    "-DOHOS_ARCH=$Arch" `
    -DOHOS_PLATFORM=OHOS `
    -DOHOS_STL=c++_shared `
    -DCMAKE_BUILD_TYPE=Release `
    "-DCMAKE_INSTALL_PREFIX=$inst" `
    "-DINSTALL_DIR=$inst" `
    -DINSTALL_DIR_LAYOUT=Unix `
    "-DCMAKE_FIND_ROOT_PATH=$inst" `
    -DBUILD_LIBRARY_TYPE=Shared `
    -DCMAKE_PLATFORM_NO_VERSIONED_SONAME=ON `
    -DBUILD_USE_VCPKG=OFF `
    -DBUILD_USE_PCH=OFF `
    -DBUILD_DOC_Overview=OFF `
    -DBUILD_SAMPLES_QT=OFF `
    -DBUILD_Inspector=OFF `
    -DINSTALL_SAMPLES=OFF `
    -DINSTALL_TEST_CASES=OFF `
    -DBUILD_MODULE_FoundationClasses=ON `
    -DBUILD_MODULE_ModelingData=ON `
    -DBUILD_MODULE_ModelingAlgorithms=ON `
    -DBUILD_MODULE_Visualization=ON `
    -DBUILD_MODULE_ApplicationFramework=ON `
    -DBUILD_MODULE_DataExchange=ON `
    -DBUILD_MODULE_DETools=OFF `
    -DBUILD_MODULE_Draw=OFF `
    -DUSE_OPENGL=OFF `
    -DUSE_GLES2=ON `
    -DUSE_XLIB=OFF `
    -DUSE_D3D=OFF `
    -DUSE_FREETYPE=ON `
    "-D3RDPARTY_FREETYPE_DIR=$inst" `
    "-D3RDPARTY_FREETYPE_LIBRARY_DIR=$inst/lib" `
    "-D3RDPARTY_FREETYPE_LIBRARY=$inst/lib/libfreetype.a" `
    -DUSE_TK=OFF `
    -DUSE_FREEIMAGE=OFF `
    -DUSE_FFMPEG=OFF `
    -DUSE_OPENVR=OFF `
    -DUSE_TBB=OFF `
    -DUSE_VTK=OFF `
    -DUSE_DRACO=OFF `
    -DUSE_RAPIDJSON=ON `
    "-D3RDPARTY_RAPIDJSON_INCLUDE_DIR=$(& $fw (Join-Path $rapidJson 'include'))" `
    -DUSE_EIGEN=OFF 2>&1 | Log
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed ($LASTEXITCODE)" }

& $cmake --build (& $fw $buildDir) --config Release --parallel $Jobs 2>&1 | Log
if ($LASTEXITCODE -ne 0) { throw "Build failed ($LASTEXITCODE)" }

& $cmake --install (& $fw $buildDir) --config Release 2>&1 | Log
if ($LASTEXITCODE -ne 0) { throw "Install failed ($LASTEXITCODE)" }

"OCCT $Tag installed to $installDir" | Log

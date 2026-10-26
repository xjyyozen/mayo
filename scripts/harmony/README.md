# HarmonyOS 依赖构建脚本

在 Windows 上，用 HarmonyOS SDK 自带的 CMake / Ninja / `ohos.toolchain.cmake`，
交叉编译 FreeType 和 OpenCascade（OCCT），目标平台是 **HarmonyOS arm64-v8a**。

| 文件 | 用途 |
|---|---|
| `build_freetype.ps1` | 编译 FreeType（静态库 `libfreetype.a`） |
| `build_occt.ps1` | 编译 OCCT（动态库 `libTK*.so`，GLES 版，带 RapidJSON 以支持读取 glTF） |
| `patches/occt.patch` | 让 OCCT 支持 OHOS 平台的补丁（4 处修改，原因见下文） |

这些文件是 `D:\harmony\deps\` 下同名文件的副本。修改其中一份后，记得同步另一份。

## 依赖版本

| 依赖 | 版本 | 来源 |
|---|---|---|
| FreeType | **2.13.x**（当前 2.13.3） | <https://download.savannah.gnu.org/releases/freetype/> |
| OCCT | **7.9.3**（tag `V7_9_3`，提交 `a016080b`） | <https://github.com/Open-Cascade-SAS/OCCT> |
| RapidJSON | master 提交 **`24b5e7a8`**（2025-02-05；只有头文件，不用编译） | <https://github.com/Tencent/rapidjson> |
| HarmonyOS SDK | API 26.0.0，CMake 3.28.2，Ninja 1.13.2，Clang 15.0.4 | `D:\DevEco Studio\sdk\default\openharmony\native` |

## 目录约定

```
D:\harmony\deps\
  src\freetype-2.13.3\        FreeType 源码
  src\OCCT-7_9_3\             OCCT 源码（git clone）
  src\rapidjson\              RapidJSON 源码（git clone，只用其中的 include\）
  patches\occt.patch          OCCT 补丁
  build\<name>-<ver>-<arch>\  构建目录
  install\arm64-v8a\          安装目录（include\、lib\）
```

## 构建顺序

请在 PowerShell 会话中直接调用脚本，**不要**用 `powershell -ExecutionPolicy Bypass`
（Claude Code 的安全策略会拦截这种写法）。

```powershell
# 1. 获取源码（只需一次）
#    FreeType：下载 freetype-2.13.3.tar.xz，解压到 D:\harmony\deps\src\
git clone --depth 1 --branch V7_9_3 https://github.com/Open-Cascade-SAS/OCCT.git D:\harmony\deps\src\OCCT-7_9_3
#    RapidJSON：只有头文件，固定到脚本参数 -RapidJsonCommit 指定的提交（脚本会检查）
git clone https://github.com/Tencent/rapidjson.git D:\harmony\deps\src\rapidjson
git -C D:\harmony\deps\src\rapidjson checkout 24b5e7a8b27f42fa16b96fc70aade9106cf7102f

# 2. FreeType（OCCT 依赖它，必须先编）
& D:\harmony\deps\build_freetype.ps1

# 3. OCCT（脚本会自动检测并打上 patches\occt.patch）
& D:\harmony\deps\build_occt.ps1
```

两个脚本的通用参数：
- `-Clean`：删除构建目录，从头编译
- `-Jobs N`：并行线程数，默认 14

产物：
- `install\arm64-v8a\lib\libfreetype.a`
- 49 个 `libTK*.so`：包含 `libTKOpenGles.so`，**不包含** `libTKOpenGl.so`
- 头文件：`install\arm64-v8a\include\opencascade\`

OCCT 运行时还需要 SDK 里的 `libc++_shared.so`，打包 HAP 时要一起带上。

## glTF 支持：RapidJSON

OCCT 读 glTF（`RWGltf_CafReader`，在 `TKDEGLTF` / `TKRWMesh` 里）要用 RapidJSON 解析 JSON。
不开 RapidJSON 时这两个库照样会编出来、链接也不报错，但**运行时读 glTF 直接失败**，
日志里是 `Error: glTF reader is unavailable - OCCT has been built without RapidJSON support`。

脚本里的相关设置：

- `-DUSE_RAPIDJSON=ON`
- `-D3RDPARTY_RAPIDJSON_INCLUDE_DIR=D:/harmony/deps/src/rapidjson/include`：直接给出头文件目录。
  不要只给 `3RDPARTY_RAPIDJSON_DIR` 让 CMake 去找：OHOS 工具链把查找根目录限制在 `CMAKE_FIND_ROOT_PATH`（install 目录）里，
  `src\rapidjson` 不在其中，可能找不到。
- RapidJSON 自 v1.1.0（2016 年）以后没有再发版，v1.1.0 在较新的编译器上有已知编译错误，所以固定用 master 的一个提交。

验证方法：`libTKRWMesh.so` 里不应再包含 `built without RapidJSON` 字符串。

> **增量编译说明**：在已有构建目录上直接重新运行脚本（不加 `-Clean`）即可。
> 但 `HAVE_RAPIDJSON` 是加给所有工程的全局宏，打开它会让几乎全部编译单元重新编译（实测 5480 个，约 6 分钟），
> 而不是只编 glTF 相关的库。

## 并行度：`-j 14`

开发机是 Ryzen 7 9800X3D（8 核 16 线程），内存 32GB。
所有 Ninja / CMake 编译统一用 **14 线程**（`--parallel 14`），给系统留 2 个线程。
OCCT 全量编译约 5500 个编译单元。

## 日志

脚本运行时，输出一边显示在屏幕上，一边写进**脚本旁边的同名 `.log` 文件**（UTF-8，每次运行覆盖）：

- `build_freetype.ps1` → `build_freetype.log`
- `build_occt.ps1` → `build_occt.log`

日志第一行记录运行时间和参数。查看进度：

```powershell
Get-Content D:\harmony\deps\build_occt.log -Tail 5 -Wait
```

本目录里的 `.log` 文件已经被 `.gitignore` 忽略，不会提交到 git。

## OCCT 补丁说明（`patches/occt.patch`）

OCCT 的 CMake 和源码只认识 Android、iOS、Emscripten 这几个"移动端 GLES、无 X11"的平台。
`ohos.toolchain.cmake` 会设置 `CMAKE_SYSTEM_NAME=OHOS` 和 `UNIX`，编译器会预定义
`__OHOS__` 和 `__linux__`，所以不打补丁的话，OHOS 会被当成**桌面 Linux**。

下面 4 处修改都是照着 OCCT 对 Android 的现有处理来做的。

1. **`CMakeLists.txt`**
   - 当 `CMAKE_SYSTEM_NAME` 为 `OHOS` 时，定义 `OHOS=1`。
   - `BUILD_SOVERSION_NUMBERS=0`：输出普通的 `libTKxxx.so`，不带 `.so.7.9` 版本后缀和符号链接，因为 HAP 包放不了这些文件。
   - 不使用 Xlib，因为系统里没有 X11。
   - 默认 `USE_GLES2=ON`、`USE_OPENGL=OFF`，因为系统只有 OpenGL ES + EGL。这样编出来的是 `TKOpenGles`，而不是 `TKOpenGl`。
2. **`adm/cmake/occt_csf.cmake`**：为 OHOS 新增一个系统库分支。
   通用的 UNIX 分支会链接 `pthread rt stdc++` 和 `fontconfig`，但 OHOS 使用 musl + libc++，
   既没有 libstdc++，也没有 fontconfig。改为和 Android 一样，链接 `c` 和 `EGL GLESv2`。
3. **`src/Font/Font_FontMgr.cxx`**：在 `__OHOS__` 下不包含 `<fontconfig/fontconfig.h>`，也不读 X11 字体服务配置。
   字体改为扫描默认目录来查找，默认目录里已经有 `/system/fonts`（OHOS 的系统字体就在这里）。
4. **`src/OpenGl/OpenGl_GraphicDriver.cxx`**：`<X11/Xlib.h>` 和 `<GL/glx.h>` 是否包含，
   是按操作系统列表判断的，而不是看 `HAVE_XLIB`。所以 OHOS 上会报错
   `fatal error: 'X11/Xlib.h' file not found`。改为像 `__ANDROID__` 一样排除 `__OHOS__`。

脚本里另外还有两处设置，不需要改 OCCT 源码：

- **`-D3RDPARTY_FREETYPE_LIBRARY=.../libfreetype.a`**（以及 `..._LIBRARY_DIR`）：
  OCCT 的 `adm/cmake/freetype.cmake` 在 Linux 类系统上只找 `.so`，还会把 `.a` 改写成 `.so`，
  导致报错 `Could not find libraries of used third-party products: 3RDPARTY_FREETYPE_LIBRARY_DIR`。
  显式指定库的路径后，CMake 会跳过自动搜索。我们的 `libfreetype.a` 是用 `-fPIC` 编译的，可以安全地链接进 `.so`。
- **`-DCMAKE_PLATFORM_NO_VERSIONED_SONAME=ON`**：Android 上这个变量由 CMake 自带的平台文件设置，
  OHOS 工具链没有设置。不加的话，即使 `SOVERSION=0`，也会生成 `libTKxxx.so.7.9.3`。

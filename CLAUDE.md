# CLAUDE.md — 鸿蒙原生 3D 查看器（基于 Mayo C++ 核心）

## 目标

基于开源 3D CAD 查看器 **Mayo**（Qt + OpenCascade）做一个**鸿蒙原生 3D 查看器**，
目标**一套代码覆盖鸿蒙 PC（2in1）/ 平板 / 手机**。不再整体移植 Qt 版 Mayo，架构为：

- **前端**：ArkUI 原生界面
- **核心**：复用 Mayo 的 C++ 核心（`base`、`graphics`、`gui`、`io_*`、`measure`），
  编译成 `.so`，通过 **NAPI** 供 ArkTS 调用
- **渲染**：XComponent + EGL + OCCT **TKOpenGles**

> Mayo 的 Qt 界面代码（`src/app`、`src/qtbackend`、`src/qtcommon`）**不移植**，只作为功能参考。

- 工作分支：`harmonyos-port`（上游主分支为 `develop`）
- 移植分析笔记：[docs/HARMONY_PORT_NOTES.md](docs/HARMONY_PORT_NOTES.md)

## 平台约束

- API 版本：**26.0.0**；CPU 架构：**arm64-v8a**
- 图形：**只有 OpenGL ES + EGL，没有桌面 OpenGL**（没有 GLX / WGL / 兼容模式 profile）
- 应用沙箱：应用只能直接读写自己的沙箱目录；**访问用户文件必须走 DocumentViewPicker**
  （不能假设随意路径可读写；C++ 核心拿到的是 Picker 返回的 URI/文件描述符，不是任意路径）

## 环境

| 项目 | 位置 / 说明 |
|---|---|
| 开发机 | Windows 11 |
| DevEco Studio | `D:\DevEco Studio` |
| HarmonyOS SDK | `D:\DevEco Studio\sdk\default` |
| 测试机 | MateBook Pro S |
| hdc 设备地址 | `192.168.124.14:38291`（**IP/端口可能变化**，连不上先用 `hdc list targets` 确认） |

## 阶段计划

| 阶段 | 内容 | 完成标志 |
|---|---|---|
| S1 | 交叉编译 FreeType + OCCT 7.9.x（GLES 版） | 设备上读取 STEP 成功 |
| S2 | XComponent + EGL + OCCT 渲染 | 设备上显示立方体并可旋转 |
| S3 | Mayo 核心编译 + NAPI 接口 | ArkUI 调用 C++ 打开 STEP 并显示 |
| S4 | ArkUI 界面 MVP | 打开文件、视图操作、模型树、剖切、基础测量 |
| S5 | 一多适配 + 上架 | PC / 平板 / 手机均可运行 |

**当前阶段：S2**（S1 已于 2026-10-26 完成：`D:\harmony\OcctProbe` 在 MateBook 上读取 `screw.step` 成功，
1 个实体、10 个面、包围盒 20.001 × 20.001 × 42.300，耗时 21.9 ms）

## 目录约定

第三方依赖（FreeType、OCCT 等）统一放 `D:\harmony\deps\`：

| 目录 | 用途 |
|---|---|
| `D:\harmony\deps\src\` | 源码 |
| `D:\harmony\deps\build\` | 构建目录 |
| `D:\harmony\deps\install\arm64-v8a\` | 安装产物（头文件、`.so`、`.a`） |

## 许可

- Mayo 采用 **BSD-2-Clause** 许可：复用的代码**保留原版权声明**和 LICENSE 文本。
- 产品**另起名字**，不直接叫 "Mayo"。

## 工作规则

1. 每次只做**一个可验证的小目标**，做完先验证再进行下一步。
2. 报错**保留原文**，不要猜测、不要改写；分析时引用原始报错。
3. 鸿蒙相关问题**先用 `devecocli` 查官方文档**，再动手。
4. 每完成一步就 `git commit` 一次。
5. 大体积编译产物（OCCT 等构建目录、安装目录，见"目录约定"）放 **D 盘或 F 盘**，**不要放 C 盘**。
6. 向用户解释时用**通俗比喻**（用户几乎没有编程基础）。
7. 编译并行度：开发机为 Ryzen 7 9800X3D（8 核 16 线程）+ 32GB 内存，所有 Ninja/CMake 编译
   统一使用 **`-j 14`**（`cmake --build ... --parallel 14` / `ninja -j 14`）。
   构建脚本须同时把输出写入**与脚本同名的 `.log` 文件**（如 `build_occt.ps1` → `build_occt.log`），
   方便随时查看进度。
8. 凡是修改了本文件（`CLAUDE.md`），都要**同步 `git commit`**，不要留成未提交改动。

## 安全规则

- 签名证书（`*.p12` `*.cer` `*.p7b` `*.csr`）、密码、`build-profile.json5` 中的 `signingConfigs`
  **绝不提交到 git**。
- 提交前检查 `git diff --cached`，发现上述内容立即移出暂存区。

## 已知坑

<!-- 后续踩坑后在此追加：现象 / 原始报错 / 原因 / 解决办法 -->

### 1. OCCT 找不到静态 FreeType（S1b）
- **原始报错**：`CMake Error at CMakeLists.txt:959 (message): Could not find libraries of used third-party products: 3RDPARTY_FREETYPE_LIBRARY_DIR`
- **原因**：OCCT 的 `adm/cmake/freetype.cmake` 在 Linux 类系统上只搜索 `.so`（`CMAKE_FIND_LIBRARY_SUFFIXES` 只有 `.lib .so .dylib`），
  而且会把找到的 `.a` 改写成 `.so`。我们的 FreeType 是静态库 `libfreetype.a`。
- **解决**：显式传入 `-D3RDPARTY_FREETYPE_LIBRARY=<install>/lib/libfreetype.a` 和 `-D3RDPARTY_FREETYPE_LIBRARY_DIR=<install>/lib`，
  CMake 会跳过自动搜索，不需要改 OCCT 源码。前提是 FreeType 用 `-fPIC` 编译（`build_freetype.ps1` 已开启）。

### 2. OHOS 被 OCCT 当成桌面 Linux（S1b）
- **原始报错**：`OpenGl_GraphicDriver.cxx:45:12: fatal error: 'X11/Xlib.h' file not found`
- **原因**：OHOS 工具链会设置 `UNIX`，编译器预定义 `__OHOS__` 和 `__linux__`，但不会定义 `__ANDROID__`。
  OCCT 的 CMake 和源码只按 `ANDROID` / `__ANDROID__` 识别"移动端、无 X11、GLES"，所以 OHOS 走进了桌面 Linux 分支，
  去找 X11、fontconfig、libstdc++。
- **解决**：参照 Android 的写法打补丁 `scripts/harmony/patches/occt.patch`，在 CMake 里加 `OHOS`，在源码里加 `!defined(__OHOS__)`。
  另外，CMake 还要加 `-DCMAKE_PLATFORM_NO_VERSIONED_SONAME=ON`，否则生成的是 `.so.7.9.3`。
  以后遇到其他三方库，先搜索它的 `__ANDROID__` / `ANDROID` 分支。

### 3. PowerShell 5.1 把 stderr 误判为失败
- **现象**：脚本开头设置了 `$ErrorActionPreference = "Stop"` 时，只要 cmake/clang 往 stderr 写一行（哪怕只是 warning），
  就会被包装成 `NativeCommandError` 并立刻中止，真正的报错原文也被截断了。
- **解决**：路径检查之后改成 `$ErrorActionPreference = "Continue"`，原生命令是否成功只看 `$LASTEXITCODE`。
  输出用 `2>&1 | Log` 同时写进日志（见 `scripts/harmony/build_*.ps1`）。
  另外，`powershell -ExecutionPolicy Bypass -File ...` 会被 Claude Code 的安全策略拦截，要在当前会话里用 `& script.ps1` 调用。

### 4. 应用和 OCCT 必须用同一份 libc++（S1c）
- **现象**：模板工程 `build-profile.json5` 设了 `"nativeCompiler": "BiSheng"`，打包进 HAP 的是
  `hms/native/BiSheng/.../libc++_shared.so`；而 OCCT 是用 SDK 的 `openharmony/native/llvm` 编译的，两份 libc++ 不一样（md5 不同）。
- **解决**：删掉 `nativeCompiler: BiSheng`，用默认编译器，并把 `openharmony/native/llvm/lib/aarch64-linux-ohos/libc++_shared.so`
  放进 `entry/libs/arm64-v8a`。预构建 OCCT 库只有 arm64，`abiFilters` 只保留 `arm64-v8a`。
- 另外，Hvigor 默认的 C++ 标准低于 C++17：`std::string::data()` 返回 const，原始报错
  `error: no matching function for call to 'napi_get_value_string_utf8' ... would lose const qualifier`，改用 `&str[0]`。

### 5. `devecocli log --keyword` 读不到日志
- `devecocli log --keyword OCCT_PROBE --from 2m` 没有输出任何日志行。用 `hdc -t <设备> shell "hilog -x -T OCCT_PROBE"` 直接读。
- 点击按钮可以用 `devecocli ui click --device <设备> --id <组件 id>`（ArkUI 组件要先设 `.id(...)`）。

### 6. Git Bash 下 `hdc file recv` 路径被改写（S2a）
- **原始报错**：`[Fail]Error opening file: no such file or directory, path:C:/Program Files/Git/data/local/tmp/v1.jpeg`
- **原因**：Git Bash 把 `/data/...` 这种以 `/` 开头的参数当成 Windows 路径改写了。
- **解决**：`hdc file send/recv` 改在 PowerShell 里执行。
- 设备上截图：`hdc -t <设备> shell "snapshot_display -f /data/local/tmp/x.jpeg"`；
  模拟点击/拖动（测最大化、改窗口大小）：`uitest uiInput click x y`、`uitest uiInput drag x1 y1 x2 y2 速度`，坐标是屏幕物理像素。

### 7. `OH_ArkUI_SurfaceHolder_Create` 返回空（S2b）
- **现象**：ArkTS 侧 `XComponent({ type: XComponentType.SURFACE })` + `onAttach` 里把 FrameNode 传给 C++，
  `OH_ArkUI_SurfaceHolder_Create` 返回 `nullptr`，`OH_ArkUI_XComponent_RegisterOnFrameCallback` 返回 `401`，hilog 里没有任何框架报错。
- **原因**（查 OpenHarmony 源码 `native_node_napi.cpp` 得知）：`OH_ArkUI_GetNodeHandleFromNapiValue` 要靠 ArkUI NDK 的实现表判断
  "这是新式 XComponent"，而实现表要等第一次调用 `OH_ArkUI_QueryModuleInterfaceByName` 才加载。没加载时句柄不会被标记为
  XComponent（`isBindNative=false`），后续 SurfaceHolder 接口全部失败。
- **解决**：先调用 `OH_ArkUI_QueryModuleInterfaceByName(ARKUI_NATIVE_NODE, "ArkUI_NativeNodeAPI_1")`，
  **再**调用 `OH_ArkUI_GetNodeHandleFromNapiValue`（Viewer3D 的 `SurfaceHost::Create` 已按此顺序封装）。

### 8. OCCT 在 OHOS 上找不到 "sans-serif" 字体（S2b）
- **原始警告**：`Font_FontMgr, warning: unable to find font 'sans-serif' [regular]; 'DejaVu Math TeX Gyre' [aspects: regular] [paths: /system/fonts/DejaVuMathTeXGyre.ttf] is used instead`
- **原因**：`/system/fonts` 能正常扫描（673 个字体），ViewCube 文字也能显示，不是方块；但 OCCT 在 OHOS 上走的是 X11 的字体别名表
  （arial / helvetica / freesans / dejavu sans），设备上一个都没有，于是回退到任意字体，ViewCube 上的字变成了衬线数学字体。
- **解决**：应用启动时 `Font_FontMgr::GetInstance()->AddFontAlias("sans-serif", "HarmonyOS Sans")`（`serif` 同理），
  见 Viewer3D `occt_renderer.cpp`。以后也可以在 `occt.patch` 的 `Font_FontMgr.cxx` 里给 OHOS 加别名分支。

### 9. PowerShell 5.1 脚本里的中文注释会吃掉下一行代码
- **现象**：`sync_occt_libs.ps1` 运行时报 `You cannot call a method on a null-valued expression` / `Cannot index into a null array`，
  明明前面已经给变量赋了值。
- **原因**：Windows PowerShell 5.1 把**不带 BOM 的 UTF-8** 按 GBK 读取，中文注释被读乱，行尾换行被吞掉，紧跟的下一行代码变成了注释的一部分。
- **解决**：含中文的 `.ps1` 一律保存为 **UTF-8 with BOM**（`deps` 下的构建脚本是纯英文，所以没踩到）。

### 10. ArkUI NDK 输入事件的坐标是 vp，不是 px（S2c）
- **现象**：点击 ViewCube 没反应；日志里点击位置是 `(1014,56)`，实际应为 `(1926,107)`，正好差屏幕密度 1.9 倍。拖动旋转不受影响（只用相对位移）。
- **原因**：`OH_ArkUI_PointerEvent_GetX/GetY`、`OH_ArkUI_UIInputEvent_GetEventTargetWidth` 头文件注释写的是 px，实测（API 26，MateBook）都是 vp。
- **解决**：Viewer3D `SurfaceHost::PixelScale` 用"Surface 像素宽度 / 事件里的组件宽度"换算，不依赖坐标单位。

### 11. OCCT 灯光与交互的几个坑（S2c）
- 对 `V3d_AmbientLight` 调用 `SetHeadlight()` 会抛 `Standard_ProgramError`，未捕获直接闪退（SIGABRT）；平行光用构造函数参数指定是否头灯。
- 非 PBR（Phong）着色下**平行光的 `SetIntensity()` 被忽略**（`OpenGl_ShaderManager.cxx`："used by PBR and ignored by old shading model"），要调亮度就改灯光颜色；环境光的强度有效。
- `V3d_DirectionalLight` 的方向是**光线前进方向**（从灯指向场景）。
- 默认黄铜材质高光强，辅光的反光会让背光面反而最亮；需要看清面的明暗时用哑光材质（如 `Graphic3d_NameOfMaterial_Plastered`）。
- `AIS_ViewController::HandleViewEvents` 返回前会清零"还要画下一帧"标志，在 `FlushViewEvents` 之后读 `toAskNextFrame()` 永远是 false（ViewCube 动画停在第一帧）；要在重写的 `handleViewRedraw` 里读。

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

**当前阶段：S4**（S3、S3.5 已完成，S4a 应用骨架已完成；下面按时间列出各检查点。S1 已于 2026-10-26 完成：`D:\harmony\OcctProbe` 在 MateBook 上读取 `screw.step` 成功，
1 个实体、10 个面、包围盒 20.001 × 20.001 × 42.300，耗时 21.9 ms）
- S3a（2026-10-26）：Mayo 核心（MayoCore + MayoIO 源码，无 Qt）由 `harmony/mayo_core/CMakeLists.txt` 编成静态库 `mayo_core`，
  Viewer3D 通过 `add_subdirectory` 引入；设备上用 Mayo IO 系统导入 `screw.step`：文档树 1 个节点、根节点 `the product name`、导入约 20 ms
- S3b（2026-10-26）：导入的文档由 Mayo 的 GuiDocument 显示在 Viewer3D 的 3D 视图中（替换测试立方体），
  保留 S2 的交互 / ViewCube / 按需重绘 / 头灯；XCAF 颜色生效，无颜色零件为中性灰，显示边线，导入后 FitAll
- S3c（2026-10-26）：临时"打开"按钮 → DocumentViewPicker（限定 STEP/STP、IGES/IGS、STL、OBJ、BREP、glTF/GLB）→
  复制到 `cacheDir/import/`（每次打开前清空）→ NAPI 异步任务在后台线程导入，屏幕中央显示"正在加载 xx%"（Mayo 的 TaskProgress），
  失败时显示通俗原因；新文档显示后关闭并释放旧文档。OCCT 开启 RapidJSON 以支持 glTF。
  设备实测：38.8 MB 的 PCB STEP（2121 个节点）后台导入 20.3 s，界面不卡；GLB / STL / OBJ / STEP 均可打开
- S3d（2026-10-27）：分段计时 + 内存峰值 + 拖动帧率，结果见 Viewer3D `docs/perf-s3.md`。
  交互不是瓶颈（单帧最长 12.8 ms）；大 STEP 慢在 OCCT 形状修复（RK3506 的 21.6 s 里约 10.7 s），
  导入期间内存峰值达 2.3 GB；生成显示对象在 UI 线程卡约 1 s。建议 S4 前先做 S3e：精简形状修复 + 显示阶段不卡 UI
- S3e-1（2026-10-27）：STEP 默认"精简形状修复"（Mayo STEP 读取器新参数 `quickShapeFix`），三角化失败的面 > 1% 时自动用完整修复重导；
  IGES 保持完整修复。9 个文件回归截图与修改前一致，大 STEP 导入快 9~13%（RK3506 21.6 → 18.7 s），远小于预期；
  拖动时关闭悬停高亮（H）实测无效果，S3d 的归因有误。加载提速改走"转换结果缓存"（方案 I，S5）。详见 Viewer3D `docs/perf-s3.md`
- S3e-2（2026-10-27）：按阶段记录内存峰值；按零件分批三角化（G，Viewer3D `MeshEntityByParts`）+ 转换后立即释放读取器（D，Mayo `io_system.cpp`）
  让大 STEP 内存峰值降 61~71%（C300 4.1 → 1.2 GB，RK3506 2.1 → 0.84 GB），三角化还快了 21~48%；显示对象分帧创建（C，Mayo
  `GuiDocument::setDefaultDeferredDisplay` + Viewer3D 每帧一批），UI 线程最长占用从 1.7 s 降到一帧，代价是全部显示完的时间变长 1.4~4 倍。
  9 个文件回归截图一致（GearBox.IGS 三角形少 0.9%，看不出差别）。详见 Viewer3D `docs/perf-s3.md`

- S3.5（2026-10-27）：UI 规范 + 玻璃面板。`systemMaterial` 在目标设备（MateBook Pro S，系统 7.0.0.111）的通用组件上无效（只有 Select 等系统组件自带材质有效），
  GlassPanel 改用 `backgroundEffect`（`GLASS_IMPL` 开关可切回 `systemMaterial`）；C300 拖动旋转有 / 无面板开销在噪声内（见 Viewer3D `docs/perf-s3.md` "S3.5 材质开销"）。详见 `docs/UI_SPEC.md`、`docs/UI_RESEARCH.md` 第 6 节
- S4a（2026-10-27）：应用骨架。应用名"观棱"（英文 Guanleng）+ 占位图标；`@Env` 断点（sm < 600 ≤ md < 840 ≤ lg）切换布局：文件胶囊、右上角按钮组、模型树面板 / 把手、属性卡片位置、Dock（6 / 5 个按钮）、
  sm 底部上滑面板（可拖动吸附）、空状态 / 加载 / 错误卡片；深色 ViewCube 改中性灰；窗口从最大化缩到最窄布局正确；6 张截图在 `docs/screenshots/s4a/`；pick_check 回归通过。详见 `docs/UI_SPEC.md` 第 10 节
- S4b–S4d（2026-10-27 ~ 10-28）：模型树、视图工具 / 属性卡片 / 隔离 / 右键菜单、剖切（裁剪面 + 截面封口）；各自带回归脚本与截图。详见 Viewer3D `docs/UI_SPEC.md` 第 12–14 节、`docs/perf-s4.md` 第 6–7 节
- S4e（2026-10-29）：测量。Dock"测量"打开子对象级拾取（点 / 边 / 面），复用 Mayo `MeasureToolBRep` + `BaseMeasureDisplay`（不重写算法）：
  距离（最小距离，两侧都是圆时补圆心距离）、直径 / 半径、角度、长度、面积、点坐标；结果同时出 3D 标注（琥珀色 `measure_annotation`）和面板列表，可保留多条 / 单删 / 全部清除；
  进入 / 切换 / 退出按帧分批激活选择模式（每帧 12 ms，C300 首轮 6.3 s、单步最坏 79.6 ms）；与剖切共存（只测未剖掉的部分）。回归 `scripts/measure_check.ps1`（22 项，±0.05），已并入 `regress.ps1`；
  截图 `docs/screenshots/s4e/`。详见 Viewer3D `docs/UI_SPEC.md` 第 15 节、`docs/perf-s4.md` 第 8 节
- S4e-1（2026-10-29）：修复测量面板出结果后被"全部清除"按钮撑满屏幕（按钮在 Column 里的 `layoutWeight(1)` 被当作纵向占满，改为整行 `width('100%')`）；
  `measure_check.ps1` 增加面板高度布局检查（23 项），重拍 S4e 截图

### S4 待办

- 单个大网格对象（如 Part1.STL，一个对象 77 万三角形）分帧显示时一步仍要 400 ms：考虑拆块或后台线程计算显示数据
- 分帧显示期间每帧都重画已显示部分，C300 全部显示完要 4.8 s（一次性显示 1.7 s）：可考虑没人操作时隔几帧才画一次

- 菜单提供"以完整修复模式重新打开"（精简形状修复下个别文件可能显示异常，让用户手动切到完整修复；底层已有 `MayoSession::ShapeFixMode::Full`）

### S3.5 待办

- 排查 `systemMaterial` 在自定义组件上无效的原因（最小工程验证、检查系统沉浸光感设置、查 2in1 支持范围），系统更新后复测；
  通过后把 Viewer3D `GlassPanel.ets` 的 `GLASS_IMPL` 切回 `SYSTEM_MATERIAL`。现用 `backgroundEffect` 替代，详见 Viewer3D `docs/UI_RESEARCH.md` 第 6 节

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
9. 每完成一个检查点（如 S3a），**两个仓库都要 push**：
   - `D:\harmony\mayo` 的 `harmonyos-port` 分支 → `origin`（https://github.com/xjyyozen/mayo.git）
   - `D:\harmony\Viewer3D` 的 `main` 分支 → `origin`（https://github.com/xjyyozen/viewer3d.git，私有）
   - push 前按"安全规则"检查：`build-profile.json5`、证书文件、`entry/libs/` 都不在提交内容里
10. **回复和文档一律使用中文**（代码标识符、命令、原始报错保持原文）。
11. **测试用的临时文件（截图、日志、中间产物）一律放 `D:\harmony\Viewer3D\tmp\`**，不要放 C 盘系统临时目录；
    该目录已加入 Viewer3D 的 `.gitignore`，不提交。需要留档的截图 / 数据再复制到 `docs/` 下。
12. 所有 hdc、uitest、构建命令都要加超时（`timeout N ...`，或后台运行并把输出写入日志）；单个命令超过 3 分钟没有输出就中止并报告，不要无限等待。设备命令、测量和回归脚本另须遵守下面的"命令超时"。

## 命令超时（设备命令、测量和回归脚本必须遵守）

真机是网络设备（`hdc tconn`），会掉线；应用也可能没起来。没有保护的等待循环在设备不可达时每次都要等超时，总共可能卡 10 分钟以上。所以：

1. **每次操作前先确认设备在线**：`hdc list targets` 里有这台设备。不在线就立即报错停止，不要继续等待（重连：`hdc tconn <ip:port>`）。
2. **`aa start` 之后用 `pidof` 确认应用进程存在**：10 秒内没有进程就报错停止，不能只打印"started"就往下走。
3. **所有等待循环都设总时限（最多 2 分钟）**：超时就停止，并报告当时的日志（`hilog` 里 VIEWER3D 最近的行）。等待期间每一轮也先检查设备在线、应用进程还在。

实现：
- PowerShell 脚本（Viewer3D `scripts/*.ps1`）：开头 `. (Join-Path $PSScriptRoot "device_guard.ps1")`，用 `Assert-DeviceOnline` / `Restart-App`（结束 + 启动 + 确认进程）/ `Wait-Until`（总时限 ≤ 120 s，每轮检查设备和进程，超时打日志）；出错时 `exit 2`（2 = 设备 / 应用 / 等待出了问题，1 = 检查项失败）。`-TimeoutSeconds` 参数默认 120，大于 120 按 120 处理。
- 临时的 bash 命令（Git Bash 里直接调 hdc）：每条 hdc 命令加 `timeout 20`；写循环时同样先检查在线、有总时限；不要把 `aa start` 的结果当成成功。
- 后台命令（`run_in_background`）也一样：不能无限等待。
- 给脚本传文件列表参数时用 `powershell -Command "& scripts\x.ps1 -Files a,b"`；`-File x.ps1 -Files a,b` 会把 `a,b` 当成一个字符串。

## UI 规则

所有界面开发必须遵守 Viewer3D 的 `docs/UI_SPEC.md`：

- 颜色和尺寸（圆角、间距、字号、触控目标等）一律引用资源（`$r('app.color.*')` / `$r('app.float.*')` / `$r('sys.*')`），页面代码里不写死数值（唯一例外 `Color.Transparent`）。
- 玻璃面板统一用 `GlassPanel`，页面代码不直接调用 `systemMaterial` / `backgroundBlurStyle` / `backgroundEffect` / `backdropBlur`。
- 图标优先用 HM Symbol；新增颜色 / 尺寸先加资源（深浅色同名），再改 UI_SPEC.md 的表格。

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
- **解决**：`hdc file send/recv` 改在 PowerShell 里执行；或在 Git Bash 里设 `MSYS_NO_PATHCONV=1`，本地路径用 `cygpath -w` 转成 Windows 反斜杠路径（正斜杠路径会被 hdc 当成相对路径）。
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
- `V3d_DirectionalLight` 的方向是**光线前进方向**（从灯指向场景）。头灯（构造函数最后一个参数 `true`）的方向按**视图坐标**解释
  （X 向右、Y 向上、Z 从屏幕指向观察者），非头灯按世界坐标解释。
- **平行光要用头灯**（CAD 通用做法）：固定在世界坐标里的灯，旋转时总是同样几个面亮、另几个面暗，转到背面一片暗。
  Viewer3D 现用：环境光强度 0.3；主光头灯方向 `(0.6, -0.6, -1)`（灯在视线左上前方约 30°）；
  辅光头灯方向 `(-0.7, 0.7, 0.3)`、颜色 0.4 灰（灯在视线右下后方，主光的 40%）。
- 默认黄铜材质高光强，辅光的反光会让背光面反而最亮；需要看清面的明暗时用哑光材质（如 `Graphic3d_NameOfMaterial_Plastered`）。
- `AIS_ViewController::HandleViewEvents` 返回前会清零"还要画下一帧"标志，在 `FlushViewEvents` 之后读 `toAskNextFrame()` 永远是 false（ViewCube 动画停在第一帧）；要在重写的 `handleViewRedraw` 里读。

### 12. 用 Mayo 的 GuiDocument 显示模型（S3b）
- **驱动**：Mayo 新建 `V3d_Viewer` 时通过 `graphicsCreateDriver()` 取驱动，可用 `setFunctionCreateGraphicsDriver()`（定义在
  `graphics/graphics_create_driver.cpp`，没有头文件，要自己声明）换成我们在 EGL 上下文上建的 `OpenGl_GraphicDriver`。
  `GuiApplication` 开着自动映射时 `newDocument()` 当场就建 GuiDocument，所以**驱动必须先于任何文档存在**。
- **视图**：每个 GuiDocument 自带 Viewer / View / AIS 上下文；不用改 Mayo，把我们的 `Aspect_NeutralWindow` + EGL 上下文
  `SetWindow` 到 `guiDoc->v3dView()` 即可（Mayo 的 Qt 控件也是这样做的）。Mayo 建 Viewer 时调了 `SetDefaultLights()`，
  GuiDocument 构造时设了自己的背景、左下角 ViewCube 和 `PerfCounters_Extended` 统计采集，都要换掉 / 关掉。
- **AIS 上下文**：`GraphicsScene::aisContextPtr()` 原本是 private（Qt 界面只走 `highlightAt` / `select`），
  而 `AIS_ViewController` 必须拿到上下文，已在 harmonyos-port 改为 public。
- **网格**：`GraphicsShapeObjectDriver` 关掉了自动三角化（`SetAutoTriangulation(false)`），不在导入时网格化就**什么都不显示**；
  按 Mayo 界面版的做法在 `setEntityPostProcess` 里调 `BRepMeshingUtils::compute`（`src/app/brep_meshing.cpp`，无 Qt，已加进 mayo_core）。
- **无颜色零件**：`XCAFPrs_AISObject::DefaultStyle()` 默认白色；Viewer3D 用子类覆盖成中性灰（`mayo_session.cpp` 的 `NeutralShapeObjectDriver`）。
- `snapshot_display -f xxx.png` 不会生成 PNG（只支持 jpeg），要 PNG 就先截 jpeg 再在电脑上转换。

### 13. 后台线程导入 + Picker 文件（S3c）
- **线程划分**：`GuiApplication` 默认在 `newDocument()` 时当场建 GuiDocument（V3d_View、AIS 上下文），不能放到后台线程。
  Viewer3D 关掉自动映射（`setAutomaticDocumentMapping(false)`），后台线程只建纯 OCAF 文档并导入（读取 + 转换 + 网格化），
  回到 UI 线程再调 protected 的 `onDocumentAdded()` 建 GuiDocument（`GuiDocument` 构造时会映射已有实体）。
  新建 / 关闭文档用同一把锁（`TDocStd_Application` 的文档表不是线程安全的），见 Viewer3D `mayo_session.cpp`。
- **进度**：`importInDocument` 要传 `TaskProgress`；在后台线程上建一个 `TaskManager`，用 `exec()` 同步执行任务，
  进度从 `signalProgressChanged` 拿；`setEntityPostProcessInfoProgress(20, ...)` 让网格化占 20%（默认 0，网格化期间进度不动）。
  经 `napi_threadsafe_function` 回到 UI 线程。
- **Picker 只给 URI**：ArkTS 侧 `fileIo.open(uri)` 拿 fd，`fileIo.copyFile(fd, cacheDir/import/<文件名>)`，再把路径交给 C++。
  `.gltf` 引用的外部 `.bin` / 贴图不会一起复制，所以只能打开自包含的 `.glb`（或 bin 内嵌的 .gltf）。
- **格式识别**：Mayo 按扩展名也会认格式，内容不是 STEP 的 `.step` 文件报的是"读取失败"而不是"格式不支持"。
- **glTF 要 RapidJSON**：不开时 TKDEGLTF 照样编出来，运行时报 `glTF reader is unavailable - OCCT has been built without RapidJSON support`。
  开启方法见 `scripts/harmony/README.md`；`HAVE_RAPIDJSON` 是全局宏，打开后几乎全量重编。
- 在 Picker 里自动点选文件时，"安全访问文件"提示条会让列表整体下移，点之前先截图确认坐标。

### 14. 性能日志被挤出 hilog 缓冲区（S3d）
- **现象**：连续打开 8 个文件后 `hilog -x -T VIEWER3D_PERF` 只剩最后一个文件的记录。
- **原因**：app 日志缓冲区默认只有 512 KB（`hilog -g` 查看），导入 STEP / IGES 时 OCCT 的 `[OCCT]` 警告大量刷屏，把前面的记录覆盖了。
- **解决**：`hilog -G 16M -t app` 调大缓冲区（重启可能恢复）；Viewer3D 的 `LOGPERF` 同时追加写入沙箱文件
  `files/perf-s3.log`，用 `hdc file recv /data/app/el2/100/base/com.xjy.viewer3d/haps/entry/files/perf-s3.log` 取回。
- 另外：OCCT 读取器会经 Mayo 的 `TaskProgress::setStep` 报自己的子步骤（如 STEP 的 "Fixing face"），按 Mayo 步骤顺序计数会错，要按标题精确匹配。

### 15. 精简 STEP / IGES 形状修复（S3e-1）
- **接口**（OCCT 7.8+）：`STEPCAFControl_Reader::SetShapeFixParameters(DE_ShapeFixParameters)` + `SetShapeProcessFlags`。
  **同一格式的所有读取器共用一个读取 actor**（`STEPControl_Controller` 里的全局对象），参数设一次会一直留着，
  所以每次转换前都要显式设置（Mayo `io_occ_caf.cpp` 的 `cafSetShapeFix`，完整修复时也要设回默认值）。
- **不能整个关掉 Fixing face（`FixFaceMode=0`）**：MiniPCIe 有 2 个面三角化失败、包围盒出错，画面只剩一条竖线；RK3506 导入卡死。
  只关 `FixSameParameterMode` 也一样。能安全关的只有 Fixing face 里的相交 / 小特征 / 线框方向检查，省下约 30%。
- **IGES 不能精简**：同样的参数下 GearBox.IGS 有近 30% 的面三角化失败、出现杂乱曲线。
- 三角化失败面的比例不是可靠的判据：坏掉的 MiniPCIe 只有 0.26% 的面失败。新文件显示异常时，先用调试入口 `--ps shapeFix full` 对比。
- **调试入口（只在 debug 构建生效）**：`hdc shell aa start -b com.xjy.viewer3d -a EntryAbility --ps autoOpen testmodels/<文件> --ps shapeFix full|quick|auto`
  直接打开沙箱 `files/` 下的文件。C++ 接口 `setShapeFixMode` 用 `#ifndef NDEBUG` 包住，release 的 .so 里没有；
  ArkTS 的处理代码仍在 release 字节码里，但入口处判断 `BuildProfile.DEBUG`（release 为常量 false），不会生效。
- 往 debug 应用沙箱放文件：`hdc file send -b com.xjy.viewer3d <本地目录> data/storage/el2/base/haps/entry/files/`
  （不带 `-b` 时报 permission denied；目标子目录不存在时发单个文件会失败，要发整个目录）。回归脚本：Viewer3D `scripts/s3e_regress.ps1`。

### 16. 分帧显示与内存峰值（S3e-2）
- **三角化的中间数据远大于结果**：`BRepMesh_IncrementalMesh` 一次处理整个 C300 装配时 RSS 多出约 3 GB，而最终网格只有几十 MB。
  按去重零件分批（每批约 2000 个面，同一个弦高）后只多出约 400 MB，而且更快。IGES 每个零件是一个实体，弦高本来就按实体算。
- **读取器要尽早释放**：Mayo 原来在整个导入结束才析构读取器，STEP 读取器（实体图 + 转换映射）在 C300 上约 490 MB，正好叠在三角化峰值上。
- **GuiDocument 延迟显示**：`GuiDocument` 构造时就 `mapEntity()` 并 `Display()` 所有对象（计算显示数据 + 选择），只能用全局开关
  `setDefaultDeferredDisplay(true)` 在建 GuiDocument 之前打开；之后用 `displayPendingObjects(fnStop)` 分步处理，一步 = 显示一个对象
  （`AddObjectDisableSelectionMode`）或激活一个对象的选择。延迟显示期间 `graphicsBoundingBox()` 不全，FitAll 要用自己算的包围盒。
- 触控拖动时绘制明显比没有输入时快（同一场景 7 ms 对 11 ms），推测是系统 touch boost 提频；对比帧耗时要注意输入方式。


### 17. 测量：OCCT 的面优先拾取与"适配到选中"（S4e）
- **现象**：按像素点选一条边，命中的却是面（角度测量报 `All entities must be edges`）；换视图 / 适配之后所有取点全部失准。
- **原因**：① 同一像素同时落在面和它的边界边上时，OCCT 选择器**给面**；只有轮廓边（背面是"边缘朝向相机"的面，例如侧视图的上下轮廓边、俯视的上盖前后边、右侧竖边）能稳定命中边。② `FitView` / `SetStandardView` 在 `NbSelected() > 0` 时按选中对象适配，而测量已拾取的第一个子形状也是一个选中 → 换视图时相机放大到那个边 / 面，后续取点全部偏掉（表现为测量全部失败或算出错的实体）。
- **解决**：`FitView` / `SetStandardView` 在测量态（`measureKind_ != MeasureDisabled`）忽略子形状选中、按整个模型适配；回归脚本只用轮廓边 / 面内部取点，并且每次拾取后校验 native 打的 `measure entity: type=vertex|edge|face`（`scripts/measure_check.ps1`）。

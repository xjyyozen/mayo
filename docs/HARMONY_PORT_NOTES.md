# Mayo → HarmonyOS 移植笔记

> 基于 Mayo 0.11.0 源码（`CMakeLists.txt` + `src/`）的初步分析，供后续阶段（S1–S5）参考。
> 标注「需验证」的结论需要在真机上确认。

---

## 1. Mayo 由哪几块组成？（用"餐厅"打比方）

把 Mayo 想成一家餐厅：

| 比喻 | 对应代码 | 说明 |
|---|---|---|
| **食材仓库 + 菜谱** | OpenCascade（OCCT，外部库） | 真正懂 3D 几何的"专家"：读 STEP/IGES、算网格、负责 3D 绘图 |
| **后厨** | `MayoCore` 静态库：`src/base`、`src/graphics`、`src/gui` | `base` 是文档/属性/任务等通用底座；`graphics` 把模型交给 OCCT 画出来；`gui` 管"哪个文档在哪个 3D 视图里显示" |
| **进货部（各国供应商）** | `MayoIO` 静态库：`src/io_occ`、`io_dxf`、`io_ply`、`io_off`、`io_image`，可选 `io_assimp` | 每个 `io_xxx` 负责一种或几种文件格式的读/写 |
| **前厅（服务员、菜单、餐桌）** | `mayo` 可执行程序：`src/app`、`src/measure`、`src/qtbackend`、`src/qtcommon` | 基于 Qt Widgets 的主窗口、菜单、对话框、3D 视图控件、测量工具 |
| **外卖窗口** | `mayo-conv` 命令行程序：`src/cli` | 不开界面，纯命令行做格式转换 |
| **调料架** | `src/3rdparty` | 随源码自带的小库：fmt、gsl、magic_enum、fast_float、kdbindings、miniply、stb |

**好消息**：后厨（`base`）和进货部（`io_*`）几乎不碰窗口和显卡，属于"换个城市照样能开"的部分。
**难点**集中在两处：**前厅的 3D 视图控件**（怎么拿到一块能画图的屏幕）和 **OCCT 的绘图模块**（只会桌面 OpenGL 还是也会 OpenGL ES）。

---

## 2. 依赖清单

### 2.1 Qt 模块（支持 Qt 5.12+ 或 Qt 6）

| 模块 | 用途 | 谁需要 |
|---|---|---|
| Qt Core | 基础（字符串、文件、设置、线程、翻译） | mayo + mayo-conv |
| Qt Gui | 图像、字体、`QOpenGLContext`、`QWindow` | mayo |
| Qt Widgets | 全部界面（主窗口、对话框、树控件、`QFileDialog`） | mayo |
| Qt Svg | SVG 图标 | mayo |
| Qt OpenGLWidgets（仅 Qt 6） | `QOpenGLWidget`，3D 视图首选承载控件 | mayo |
| Qt WinExtras（仅 Windows + Qt 5） | 任务栏进度条 | 与鸿蒙无关，可忽略 |

> 移植时用 Qt 6（Qt for HarmonyOS 基于 Qt 6），所以需要 **Core / Gui / Widgets / Svg / OpenGLWidgets** 五个模块都在鸿蒙版 Qt 中可用。没有用到 Qt Quick/QML。

### 2.2 OpenCascade 模块（要求 OCCT ≥ 7.4，建议 ≥ 7.8）

| 分组 | 工具包（Toolkit） |
|---|---|
| 基础类 | TKernel、TKMath |
| 建模数据 | TKG2d、TKG3d、TKGeomBase、TKBRep |
| 建模算法 | TKBO、TKBool、TKGeomAlgo、TKHLR、TKMesh、TKPrim、TKShHealing、TKTopAlgo |
| **可视化（移植重点）** | **TKOpenGl**、TKService、TKV3d、TKMeshVS |
| 应用框架 | TKBin、TKBinL、TKBinXCAF、TKCAF、TKCDF、TKLCAF、TKVCAF、TKXml、TKXmlL |
| 数据交换 | TKXCAF、TKXmlXCAF、TKXSBase |
| 文件格式（OCCT ≥ 7.8） | TKDE、TKDEIGES、TKDESTEP、TKDESTL、TKDEVRML、TKDEOBJ、TKDEGLTF、TKRWMesh |
| 文件格式（OCCT < 7.8） | TKIGES、TKXDEIGES、TKSTEP*、TKXDESTEP、TKSTL、TKVRML、TKXDE、TKRWMesh |

⚠️ **关键**：CMake 里写死链接 `TKOpenGl`（桌面 OpenGL 版）。鸿蒙只有 OpenGL ES，
应改为编译/链接 OCCT 的 **`TKOpenGles`**（OCCT 官方为 Android/iOS/WebGL 提供的 GLES 版本，
源码与 TKOpenGl 共用，只是编译宏不同）。S2 交叉编译 OCCT 时要打开它、关掉 X11 依赖。

OCCT 自身的第三方依赖（S2 时可先全部关闭，只保留必需项）：FreeType（文字渲染，**必需**）、
可选 FreeImage / TBB / RapidJSON（glTF 读写需要 RapidJSON）/ Draco / VTK。

### 2.3 可选依赖

| 依赖 | 开关 | 说明 |
|---|---|---|
| **Assimp** | `Mayo_BuildPluginAssimp`（默认 OFF） | 额外的网格格式（FBX、3DS、Collada 等）。**S4 阶段先不开**，主流程跑通后再考虑交叉编译 |
| Git | 自动检测 | 只用来生成版本号，缺失也能编译 |
| 测试套件 | `Mayo_BuildTests`（默认 OFF） | 鸿蒙上不需要 |
| `mayo-conv` | `Mayo_BuildConvCli`（默认 ON） | 鸿蒙应用里用不上，**移植时建议设为 OFF** |

---

## 3. 移植最可能出问题的地方（按风险排序）

### 🔴 3.1 OpenGL / 3D 视图（最高风险）

比喻：Mayo 原本是在"油画布"（桌面 OpenGL）上作画，而鸿蒙只给"水彩纸"（OpenGL ES）。
画笔、颜料都得换，而且画布从哪里拿（EGL）也不一样。

| 文件 | 问题点 |
|---|---|
| `CMakeLists.txt` | 链接 `TKOpenGl`，需改为 `TKOpenGles`；Windows 才链接 `Opengl32` |
| `src/graphics/graphics_create_driver.cpp` | 创建 `OpenGl_GraphicDriver`，GLES 版头文件/类名相同但来自 TKOpenGles，需确认编译宏 |
| `src/graphics/opengl_utils.cpp/.h` | `glNativeWindow()`、`initializeGlWindow()`、FBO 包装；有 Windows/Apple 分支，没有 EGL 分支 |
| `src/app/qtopengl_utils.cpp/.h` | **`surfaceFormat()` 强制申请 `CompatibilityProfile`（桌面 GL 概念）**；`resetGlStateBeforeOcct()` 用到 `GL_ALPHA_TEST` 等 GLES 不存在的状态（已有 `core11ffp` 判空保护，但需验证）；`platformSetup()` 在 Linux 下会强制 `QT_QPA_PLATFORM=xcb`（见 3.2） |
| `src/app/widget_occ_view.cpp/.h`、`widget_occ_view_impl.cpp` | 两套 3D 视图控件：`QOpenGLWidgetOccView`（借用 Qt 的 GL 上下文，首选）和 `QWidgetOccView`（用原生窗口句柄，后备） |
| `src/app/main.cpp`（约 215–285 行） | `queryGlVersionString()` 读 `GL_VERSION` 后用 `QVersionNumber::fromString` 解析。GLES 返回 `"OpenGL ES 3.2 ..."`，**解析会失败 → 误判"版本太旧" → 退回到后备控件**。这是一个很具体的必改点 |
| `src/io_image/io_image.cpp` | 导出截图时直接取 `OpenGl_Context` 做离屏渲染 |
| `src/measure/measure_display.cpp` | 通过 `OpenGl_GraphicDriver` 查询上下文能力 |
| `src/app/command_system_information*.cpp` | 打印 OpenGL 信息，非核心，出问题可先屏蔽 |

### 🔴 3.2 窗口 / 平台判断

比喻：Mayo 认识的"国家"只有 Windows、macOS、Linux（X11），鸿蒙这个"新国家"它不认识，
很可能被当成 Linux，然后去找鸿蒙上并不存在的 X11 显示服务器。

| 文件 | 问题点 |
|---|---|
| `src/base/global.h` | 平台宏 `MAYO_OS_*`。没有鸿蒙（`__OHOS__`）分支；鸿蒙工具链很可能同时定义 `__linux__`（需验证），会被识别为 `MAYO_OS_LINUX`。另外 `__ANDROID__` 分支排在 `__linux__` 之后，永远走不到——说明作者本来也没把移动端当真 |
| `src/graphics/graphics_utils.cpp`（`AspectDisplayConnection_create`，约 205 行） | 非 Windows/Mac 时用 `getenv("DISPLAY")` 连接 X11 |
| `src/graphics/graphics_create_virtual_window.cpp` | Linux 下创建 `Xw_Window`（X11 窗口）；鸿蒙应走 `Aspect_NeutralWindow` 分支（与 Android 相同） |
| `src/app/occt_window.cpp/.h` | 后备方案用 `QWidget::winId()` 作原生句柄交给 OCCT；鸿蒙上句柄类型（`OHNativeWindow`？）需验证 |
| `src/app/qtopengl_utils.cpp`（`platformSetup`） | `Q_OS_LINUX && !Q_OS_ANDROID` 时强制 `xcb` 平台插件——若 Qt for HarmonyOS 也定义 `Q_OS_LINUX`，程序会直接起不来 |
| `src/app/mainwindow.cpp`、`win_taskbar_global_progress.*` | Windows 专用代码，已有宏保护，影响小 |

### 🟠 3.3 文件对话框 / 文件访问（沙箱）

比喻：鸿蒙应用住在"带门禁的公寓"（沙箱）里，想拿外面的文件必须请"前台"（DocumentViewPicker）帮忙递进来，
不能自己随便去别人家拿。

| 文件 | 问题点 |
|---|---|
| `src/app/commands_file.cpp`（约 108、116、438 行） | 打开/导入/导出：`QFileDialog::getOpenFileName(s)`、`getSaveFileName`；还处理拖放（`QDragEnterEvent`，约 317 行） |
| `src/app/dialog_save_image_view.cpp`（约 73 行） | 保存截图：`getSaveFileName` |
| `src/app/dialog_options.cpp`（约 349、372 行） | 导入/导出设置文件 |
| `src/app/recent_files.cpp` | 最近文件列表保存的是**路径字符串**；沙箱里通过 Picker 拿到的通常是 URI/临时授权，重启后路径可能失效 |
| `src/app/commands_help.cpp` | `QDesktopServices::openUrl` 打开网页（需验证是否能拉起浏览器） |
| `src/app/theme.cpp` | 仅有 `QFileDialog` 的样式表，无风险 |
| `src/qtbackend/`（`QSettings` 持久化设置） | 设置文件存放位置需落在沙箱内（Qt 一般会处理，需验证） |

需要确认：Qt for HarmonyOS 的 `QFileDialog` 是否已经桥接到 DocumentViewPicker。
若没有，就需要写一个小的"转接层"（C++ 调 ArkTS/NAPI）替换上面这几处调用。

### 🟢 3.4 风险较低的部分

- `src/base`、`src/io_*`、`src/3rdparty`：纯 C++/算法，只要 OCCT 交叉编译成功，基本可直接编译。
- 多线程：使用 `std::thread` / Qt 线程，鸿蒙支持。
- Qt Widgets 界面本身：取决于 Qt for HarmonyOS 的完成度；主要风险是触控/高 DPI/窗口缩放体验（S5 处理）。

---

## 4. 移植难度初步判断

**总体：中等偏难**，难点高度集中，不是"全面重写"。

| 部分 | 难度 | 理由 |
|---|---|---|
| S1 Qt Hello World | ⭐⭐ | 主要是环境搭建与签名，依赖 Qt for HarmonyOS 工具链是否顺手 |
| S2 OCCT 交叉编译 | ⭐⭐⭐ | OCCT 已支持 Android（同为 arm64 + GLES + 无 X11），可参照其配置；FreeType 也需要交叉编译 |
| S3 OCCT 渲染打通 | ⭐⭐⭐⭐ | **全项目最难点**：让 OCCT 的 GLES 渲染画进 Qt 在鸿蒙上创建的 EGL 表面。建议先走 `QOpenGLWidget` 方案（OCCT 只"借用"Qt 已建好的上下文，不自己碰原生窗口），可绕开大部分窗口句柄问题 |
| S4 Mayo 整体移植 | ⭐⭐⭐ | 改动点已基本列在第 3 节：平台宏、GL 版本判断、surface format、X11 分支、文件对话框。预计改动集中在约 10–15 个文件 |
| S5 PC 适配与发布 | ⭐⭐ ~ ⭐⭐⭐ | 文件选择体验、窗口管理、签名上架；扩展到平板/手机时 Widgets 界面的触控适配会更费力 |

**最大的不确定因素**（S1 阶段就该尽早验证）：

1. Qt for HarmonyOS 是否提供 **Widgets + OpenGLWidgets**，且 `QOpenGLWidget` 在设备上能正常出图；
2. 它定义了哪些平台宏（`Q_OS_LINUX`？`Q_OS_OHOS`？）以及编译器是否定义 `__linux__`；
3. `QFileDialog` 在沙箱下的实际行为。

这三点决定了后面是"改几处宏和判断"还是"需要自己写桥接层"。

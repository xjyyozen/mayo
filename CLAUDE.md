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

**当前阶段：S1**

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

## 安全规则

- 签名证书（`*.p12` `*.cer` `*.p7b` `*.csr`）、密码、`build-profile.json5` 中的 `signingConfigs`
  **绝不提交到 git**。
- 提交前检查 `git diff --cached`，发现上述内容立即移出暂存区。

## 已知坑

<!-- 后续踩坑后在此追加：现象 / 原始报错 / 原因 / 解决办法 -->

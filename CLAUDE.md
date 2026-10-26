# CLAUDE.md — Mayo HarmonyOS 移植项目

## 目标

把开源 3D CAD 查看器 **Mayo**（Qt + OpenCascade）移植到 **HarmonyOS 7.0 PC（2in1 设备）**，
PC 版稳定后再扩展到平板、手机。

- 工作分支：`harmonyos-port`（上游主分支为 `develop`）
- 移植分析笔记：[docs/HARMONY_PORT_NOTES.md](docs/HARMONY_PORT_NOTES.md)

## 平台约束

- API 版本：**26.0.0**；CPU 架构：**arm64-v8a**
- 图形：**只有 OpenGL ES + EGL，没有桌面 OpenGL**（没有 GLX / WGL / 兼容模式 profile）
- 应用沙箱：应用只能直接读写自己的沙箱目录；**访问用户文件必须走 DocumentViewPicker**
  （不能假设随意路径可读写，`QFileDialog` 的原生行为需要验证/替换）

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
| S1 | Qt for HarmonyOS Hello World | 一个 Qt 窗口在 MateBook Pro S 上显示出来 |
| S2 | OCCT 交叉编译 | 得到 arm64-v8a 的 OCCT 库（GLES 版 TKOpenGles） |
| S3 | OCCT 渲染打通 | 在设备上用 OCCT 显示一个立方体并能旋转 |
| S4 | Mayo 整体移植 | Mayo 能打开 STEP/STL 等文件并显示 |
| S5 | PC 适配与发布 | 键鼠/窗口/文件选择体验完善，签名打包发布 |

**当前阶段：S1**

## 工作规则

1. 每次只做**一个可验证的小目标**，做完先验证再进行下一步。
2. 报错**保留原文**，不要猜测、不要改写；分析时引用原始报错。
3. 鸿蒙相关问题**先用 `devecocli` 查官方文档**，再动手。
4. 每完成一步就 `git commit` 一次。
5. 大体积编译产物（OCCT/Qt 构建目录、安装目录等）放 **D 盘或 F 盘**，**不要放 C 盘**。
6. 向用户解释时用**通俗比喻**（用户几乎没有编程基础）。

## 安全规则

- 签名证书（`*.p12` `*.cer` `*.p7b` `*.csr`）、密码、`build-profile.json5` 中的 `signingConfigs`
  **绝不提交到 git**。
- 提交前检查 `git diff --cached`，发现上述内容立即移出暂存区。

## 已知坑

<!-- 后续踩坑后在此追加：现象 / 原始报错 / 原因 / 解决办法 -->

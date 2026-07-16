# CF优选工具 (cfnb_app)

Cloudflare 边缘节点优选工具的 **Flutter 跨端重写版**（Windows + 安卓一套代码）。

> 旧版为 Python + tkinter（`cfnb` 仓库）。本仓库用 Dart 重写全部业务逻辑，
> 目标：真正可分发的原生软件（Windows 单文件/安装包、安卓 APK/AAB），
> 摆脱"依托项目文件夹 + pythonw 启动"，并解决 tkinter 卡顿/拖影。

## 技术栈

- Flutter 3.x / Dart 3.x
- 状态管理：`flutter_riverpod`
- 存储：`shared_preferences` + `path_provider`（配置/历史落应用私有目录）
- 网络：`dio`
- 测速/探测：`dart:io` Socket + HttpClient
- 图表（规划）：`fl_chart`

## 架构

```
lib/
├─ core/        # 纯业务逻辑，无 UI 依赖，可单测、可 Isolate 隔离
│  ├─ config/       # AppConfig 模型 + 持久化
│  ├─ fetch/        # 节点源拉取 + 文本/JSON/RIPE 解析
│  ├─ latency/      # TCP 延迟探测 + 优选 + 历史
│  ├─ speed/        # 带宽测速（两轮漏斗 + 重试）
│  ├─ subscription/ # 订阅解析(vmess/ss/trojan...) + 禁用状态
│  ├─ output/       # 写 ip.txt + 摘要
│  ├─ github/       # 推送到独立 cf-ip 仓库
│  └─ pipeline/     # 6 阶段编排（对应旧 _run_all）
└─ features/     # UI 层（运行/订阅器/设置/结果）
```

## 开发

```powershell
. .\env.ps1                 # 启用 Flutter + 代理(127.0.0.1:7890)
flutter pub get
flutter test                # 全部 core 单测
flutter run -d windows      # 运行桌面（需 VS C++ 桌面负载 + 开发者模式）
flutter build windows       # 构建 Release
flutter build apk           # 构建安卓 APK
```

## 当前进度

- [x] P1 核心层（config/fetch/latency/output/speed/subscription/github/pipeline），**55 个单测全绿**
- [ ] P2 UI 层（运行页 stepper + 仪表盘 + 可拖拽日志抽屉；设置/结果/订阅器页；橙主题）
- [ ] P3 Windows 桌面构建（需 VS C++ 桌面负载 + 开发者模式）
- [ ] P4 安卓适配（底部导航、权限、前台服务应对 Doze）
- [ ] P5 打包（Win msix / 安卓 AAB）

## GitHub 数据隔离

IP 数据仍推送到独立的 `cf-ip` 仓库（与代码仓库隔离），由 `core/github` 调用
GitHub Contents API 完成，token 不落盘明文。

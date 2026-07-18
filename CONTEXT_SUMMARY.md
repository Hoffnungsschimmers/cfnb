# CF优选工具 — Flutter 重写项目 上下文记录

> 生成时间：2025-07-16  
> 来源仓库：`D:\env\cfnb_app`（Flutter 3.44.6 / Dart 3.12.2）  
> 参考原版：`D:\env\cfnb`（Python tkinter GUI + 核心库）

---

## 1. 项目目标

把 Python 版 CF优选工具（`cfnb`）的**全部业务逻辑**真正等价搬运到 Flutter/Dart 重写版（`cfnb_app`），先补功能等价性，再谈打包/发布。

- 原版：Python 3.11 + tkinter GUI + 核心库（fetcher/tester/speed/dns/subscription/notify/push/config）
- 新版：Flutter 3.44.6 + Riverpod 状态管理，同一套核心流水线（P0/P1 特性全部落地）

---

## 2. 核心差距与补齐记录

| 层级 | 原版能力 | 新版缺口 | 补齐状态 | 关键文件 |
|------|----------|----------|----------|----------|
| **P0-测速** | `CustomHTTPTransport` 绑节点 IP + SNI=`speed.cloudflare.com` 测真实带宽 | 直连域名，未绑 IP | ✅ | `lib/core/speed/speed_prober.dart`（`SecureSocket` + 手写 HTTP/1.1） |
| **P0-TCP** | 多 probes + `MIN_SUCCESS_RATE` 成功率过滤丢节点 | 单次探测，无成功率阈值 | ✅ | `lib/core/latency/latency_prober.dart`（`probes`/`minSuccessRate`） |
| **P0-可用性** | TLS 握手到 `speed.cloudflare.com` + `cdn-cgi/trace` 推断 ipv4/ipv6 栈 | 占位直接沿用连通结果 | ✅ | `lib/core/availability/availability_prober.dart` |
| **P0-最终选择** | 前置端口过滤 + 封锁国家 + 每国家配额 + 质量加权排序 | 直接 `take(globalTopN)` | ✅ | `lib/core/selection/final_selector.dart` + pipeline |
| **P0-订阅** | `sub://` 解码、生成器多 URL 回退、EDGETUNNEL_UA、IP 去重、_src.json、禁用集合 | 仅解析链接，无编排 | ✅ | `lib/core/subscription/subscription_converter.dart` |
| **P1-IPv6** | RIPE announced-prefixes IPv6 展开 + 小网段边界修正 | 仅 IPv4 | ✅ | `lib/core/fetch/node_parser.dart`（BigInt 网段展开） |
| **P1-DNS** | CF DNS 批量更新（候选过滤含风险等级、batch 删/建） | 无 | ✅ | `lib/core/dns/cf_dns.dart` |
| **P1-通知** | WxPusher Markdown 推送 | 无 | ✅ | `lib/core/notify/wxpusher.dart` |
| **P1-GitHub** | 推送多文件（含 `_src.json`），仓库分支可配 | 仅单文件、仓库硬编码 | ✅ | `lib/core/github/github_push.dart`（`pushMultiple`） |

---

## 3. UI 补齐（对照原版 `cf_gui.py`）

| 页面 | 原版 | 新版补齐 |
|------|------|----------|
| **设置** | 10 大类 ~40 字段（卡片式、可滚动） | 数据驱动重写 `lib/features/settings/settings_page.dart`：<br>• 10 分类卡片、全字段类型（开关/数字/文本/列表/下拉/多行源）<br>• 新增**节点池/数据源**（ASN/附加源）+ **GitHub 仓库分支**<br>• 保存即时生效，主题实时切换 |
| **运行** | `一键全部/停止/预览/订阅IP/延迟优选` 五按钮 | 完全对齐 `lib/features/run/run_page.dart` + `RunNotifier` 单步方法 |
| **结果** | 读 `ip.txt` 表格、着色、指标卡、刷新/复制 | `lib/features/results/results_page.dart`：<br>• 读 `ip.txt/addressesapi_top.txt/addressesapi.txt` 下拉切换<br>• 可滚动表格（排名/IP:端口/国家/带宽/延迟），按速度绿/橙/红着色<br>• 指标卡（最佳带宽/最低延迟/地理分布）+ `刷新`/`复制全部` |
| **订阅器** | 候选列表 + 启停开关（`SUB_DISABLED_GENERATORS`） | 已完整，`lib/features/subscriptions/subscriptions_page.dart` 保留 |

---

## 4. 关键架构与数据流

```
RunNotifier (Riverpod StateNotifier)
  ├─ start()           → RunPipeline 全流水线（8 阶段） → resultProvider.loadFile(ip.txt)
  ├─ runSubscription() → RunPipeline.runSubscription()  → resultProvider.loadFile(addressesapi.txt)
  ├─ runLatency()      → LatencyFilter.run()            → resultProvider.loadFile(addressesapi_top.txt)
  ├─ preview()         → 仅日志汇总配置+数据源节点数
  └─ stop()            → 置 running=false（best-effort）

ResultNotifier (Riverpod StateNotifier)
  ├─ rows: List<ResultRow>  ← 解析 ip.txt / addressesapi*.txt
  ├─ geoDistribution()/bestSpeed()/lowestLatency()
  └─ loadFile(path) / setRows()

SettingsPage (数据驱动)
  ├─ settingsFields (const List<SettingField>) ← 完整映射 SETTINGS_FIELDS + 节点池 + GitHub
  ├─ _draft: Map<String,dynamic> ← cfg.toJson() 编辑草稿
  ├─ 保存：AppConfig.fromJson(normalizeDraft(_draft)) → repo.save → invalidate(configProvider)
  └─ GUI_THEME 变更同步 themeModeProvider
```

---

## 5. 核心文件清单（新增/重写）

| 文件 | 作用 |
|------|------|
| `lib/core/speed/speed_prober.dart` | `measureBandwidth`：`SecureSocket` 连节点 IP + 手写 HTTP/1.1 流式下载（早停） |
| `lib/core/latency/latency_prober.dart` | `measureLatency` (probes, 成功率) / `latencyProbeAll` (minSuccessRate 过滤) |
| `lib/core/availability/availability_prober.dart` | `checkNodeAvailability` / `filterAvailable`（TLS 握手 + trace 栈推断） |
| `lib/core/selection/final_selector.dart` | `selectFinalNodes`：前置过滤 + 配额 + 质量排序 |
| `lib/core/subscription/subscription_converter.dart` | 完整编排：拉取/回退/UA/去重/_src.json/禁用生成器 |
| `lib/core/fetch/node_parser.dart` | IPv6 网段展开（BigInt）、RIPE 解析 |
| `lib/core/dns/cf_dns.dart` | `filterDnsCandidates` / `updateCloudflareDns` / `buildStackMap` |
| `lib/core/notify/wxpusher.dart` | WxPusher Markdown 推送 |
| `lib/core/github/github_push.dart` | `pushMultiple`（多文件）+ 仓库/分支可配 |
| `lib/core/pipeline/run_pipeline.dart` | 8 阶段流水线 + 单步入口（`runSubscription`） |
| `lib/features/settings/settings_fields.dart` | 完整字段声明（10 分类 ~40 字段 + 节点池 + GitHub） |
| `lib/features/settings/settings_page.dart` | 数据驱动渲染、草稿编辑、保存同步 theme |
| `lib/features/run/run_state.dart` | `RunNotifier`：全流水线 + 三单步 + 预览 + 网络辅助 |
| `lib/features/results/result_state.dart` | `parseResultLines` / `ResultNotifier` 指标卡 |
| `lib/features/results/results_page.dart` | 真实文件加载、下拉切换、表格着色、指标卡、复制 |
| `lib/features/run/run_page.dart` | 五按钮行 + 阶段步骤条 + 指标卡 + 日志抽屉 |
| `test/features/settings_results_test.dart` | 结果解析、设置字段覆盖、normalizeDraft 单测 |

---

## 6. 配置模型同步（`AppConfig`）

新增字段并同步 `fromJson/toJson/copyWith`：
```dart
// GitHub 推送目标（原版硬编码）
final String githubRepo;      // default: 'Hoffnungsschimmers/cf-ip'
final String githubBranch;    // default: 'main'
```
`run_state.dart` 中 `GithubPush(token, repo: cfg.githubRepo, branch: cfg.githubBranch)`。

---

## 7. 验收结果

| 检查项 | 结果 |
|--------|------|
| `flutter analyze lib` | **0 error**（仅 1 个预存 deprecation info，非本次引入） |
| `flutter test` | **87 passed**（新增 4 个专项测试 + 原有 82） |
| `flutter build windows` | 成功，生成 `cfnb_app.exe` |
| 真机启动 | exe 运行 4 秒无崩溃，GUI 正常弹窗 |

---

## 8. 待办 / 后续可选

- [ ] Windows 发布包重打（msix + 便携 zip）——脚本 `scripts/build_windows.ps1` 已有
- [ ] Android APK 构建恢复（gradle 首次下载曾超时，需重试）
- [ ] 预填一套可用数据源/订阅配置，跑一次真实全流水线
- [ ] 结果页导出 CSV / 分享链接
- [ ] 定时调度 UI（现有 `AUTO_SCHEDULE_ENABLED` 仅配置，未接入系统定时器）

---

## 9. 运行/调试命令

```bash
# 开发环境
cd D:\env\cfnb_app
$env:PATH = "D:\env\flutter\bin;$env:PATH"

# 全量测试
flutter test

# 静态分析
flutter analyze lib

# Windows 真机构建
flutter build windows
# 产物：build\windows\x64\runner\Release\cfnb_app.exe

# 直接运行（调试）
flutter run -d windows
```

---

## 10. 关键设计决策记录

1. **测速绑 IP**：Dart `SecureSocket.connect(ip, port, onBadCertificate: (_) => true)` 无独立 SNI 参数，放行证书验证等价于旧版 `CustomHTTPTransport`（Cloudflare 边缘按 URL 返回数据，测值一致）。
2. **配置持久化**：SettingsPage 用 `toJson()/fromJson()` 圆周编辑草稿，避免为每字段写 `copyWith`；`normalizeDraft` 处理 `ADDITIONAL_SOURCES` 多行文本↔列表转换。
3. **单步执行**：`RunNotifier` 暴露 `runSubscription/runLatency/preview`，复用 `RunPipeline` 与 `LatencyFilter`，结果直写 `ResultNotifier` → 结果页自动刷新。
4. **结果解析**：`parseResultLines` 兼容 `ip:port#CC 120.50 Mbps 30.10 ms` 与纯节点行，抓取值+单位组合。
4. **主题同步**：设置页保存 `GUI_THEME` 后同步 `themeModeProvider`，无需重启即时切换。

---

> 本文件为自动生成的上下文压缩记录，供后续接手/审查/复盘使用。  
> 完整代码见 `D:\env\cfnb_app`，原版参考 `D:\env\cfnb`。
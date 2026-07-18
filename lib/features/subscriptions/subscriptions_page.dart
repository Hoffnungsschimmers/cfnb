import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/config/app_config.dart';
import '../widgets/common.dart';
import '../../app/providers.dart';
import 'subscriptions_state.dart';

class SubscriptionsPage extends ConsumerStatefulWidget {
  const SubscriptionsPage({super.key});
  @override
  ConsumerState<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends ConsumerState<SubscriptionsPage> {
  final _genCtl = <TextEditingController>[];
  final _urlCtl = <TextEditingController>[];
  final _hostCtl = TextEditingController();
  final _uuidCtl = TextEditingController();
  final _countryCtl = TextEditingController();
  final _latencyOutCtl = TextEditingController();
  final double _logWidth = 320;
  bool _logCollapsed = false;

  @override
  void dispose() {
    for (final c in _genCtl) {
      c.dispose();
    }
    for (final c in _urlCtl) {
      c.dispose();
    }
    _hostCtl.dispose();
    _uuidCtl.dispose();
    _countryCtl.dispose();
    _latencyOutCtl.dispose();
    super.dispose();
  }

  void _syncControllers(AppConfig cfg) {
    _syncList(_genCtl, cfg.subGenerators, (s) => s);
    _syncList(_urlCtl, cfg.subUrls, (s) => s);
    _hostCtl.text = cfg.subNodeHost;
    _uuidCtl.text = cfg.subNodeUuid;
    _countryCtl.text = cfg.subDefaultCountry;
  }

  void _syncList(
    List<TextEditingController> ctl,
    List<String> values,
    String Function(String) extract,
  ) {
    while (ctl.length < values.length) {
      ctl.add(TextEditingController());
    }
    while (ctl.length > values.length) {
      ctl.removeLast().dispose();
    }
    for (var i = 0; i < values.length; i++) {
      if (ctl[i].text != values[i]) ctl[i].text = values[i];
    }
  }

  Future<void> _save(AppConfig cfg) async {
    final repo = await ref.read(configRepositoryProvider.future);
    await repo.save(cfg);
    ref.invalidate(configProvider);
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(configProvider);
    final run = ref.watch(subProvider);
    final subLogger = ref.watch(subLoggerProvider);
    final t = AppThemeExt.of(context);

    final content = cfgAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (cfg) {
        _syncControllers(cfg);
    if (_latencyOutCtl.text != cfg.subLatencyOutputFile) {
      _latencyOutCtl.text = cfg.subLatencyOutputFile;
    }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: sectionTitle(context, '订阅器优选 (${cfg.subGenerators.length})')),
                  AppButton('订阅IP', icon: Icons.cloud_download,
                      onPressed: run.running ? null : () => ref.read(subProvider.notifier).runSubscription()),
                  const SizedBox(width: 10),
                  AppButton('延迟优选', icon: Icons.speed,
                      onPressed: run.running ? null : () => ref.read(subProvider.notifier).runLatency(), primary: false),
                ],
              ),
              const SizedBox(height: 12),
              card(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionTitle(context, '输入模式 (SUB_INPUT_MODE)'),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      selected: {cfg.subInputMode},
                      onSelectionChanged: (s) => _save(cfg.copyWith(subInputMode: s.first)),
                      segments: const [
                        ButtonSegment(value: 'node', label: Text('订阅器')),
                        ButtonSegment(value: 'url', label: Text('订阅链接')),
                        ButtonSegment(value: 'both', label: Text('两者')),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildGenerators(context, cfg, run),
              const SizedBox(height: 12),
              _buildUrls(context, cfg, run),
              const SizedBox(height: 12),
              card(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionTitle(context, '高级参数'),
                    const SizedBox(height: 8),
                    _textField(context, '节点 Host (SUB_NODE_HOST)', _hostCtl,
                        (v) => _save(cfg.copyWith(subNodeHost: v))),
                    const SizedBox(height: 8),
                    _textField(context, '节点 UUID (SUB_NODE_UUID)', _uuidCtl,
                        (v) => _save(cfg.copyWith(subNodeUuid: v))),
                    const SizedBox(height: 8),
                    _textField(context, '默认国家码 (SUB_DEFAULT_COUNTRY)', _countryCtl,
                        (v) => _save(cfg.copyWith(subDefaultCountry: v.toUpperCase()))),
                    const SizedBox(height: 8),
                    _switchRow(context, '解析域名 (SUB_RESOLVE_DOMAIN)', cfg.subResolveDomain,
                        (v) => _save(cfg.copyWith(subResolveDomain: v))),
                    const SizedBox(height: 8),
                    _switchRow(context, '启用订阅转换 (SUB_CONVERT_ENABLED)', cfg.subConvertEnabled,
                        (v) => _save(cfg.copyWith(subConvertEnabled: v))),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              card(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionTitle(context, '延迟优选设置'),
                    const SizedBox(height: 8),
                    _slider(context, '延迟低于 (ms)', cfg.subLatencyMaxMs.toDouble(), 10, 1000,
                        (v) => _save(cfg.copyWith(subLatencyMaxMs: v.round()))),
                    const SizedBox(height: 8),
                    _doubleSlider(context, '延迟权重 (综合优选, 带宽=1-该值)', cfg.subQualityLatencyWeight, 0, 1,
                        (v) => _save(cfg.copyWith(subQualityLatencyWeight: v))),
                    const SizedBox(height: 8),
                    _doubleSlider(context, '连接超时 (秒)', cfg.subLatencyTimeout, 0.1, 10,
                        (v) => _save(cfg.copyWith(subLatencyTimeout: v))),
                    const SizedBox(height: 8),
                    _slider(context, '并发数', cfg.subLatencyWorkers.toDouble(), 1, 200,
                        (v) => _save(cfg.copyWith(subLatencyWorkers: v.round()))),
                    const SizedBox(height: 8),
                    _text(context, '输出文件 (SUB_LATENCY_OUTPUT_FILE)', _latencyOutCtl,
                        (v) => _save(cfg.copyWith(subLatencyOutputFile: v))),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              card(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionTitle(context, '带宽测速 (仅对延迟好的节点)'),
                    const SizedBox(height: 8),
                    _switchRow(context, '启用带宽测速 (SUB_SPEED_ENABLED)', cfg.subSpeedEnabled,
                        (v) => _save(cfg.copyWith(subSpeedEnabled: v))),
                    const SizedBox(height: 8),
                    _slider(context, '仅测延迟 ≤ (ms)', cfg.subSpeedLatencyLimit.toDouble(), 50, 500,
                        (v) => _save(cfg.copyWith(subSpeedLatencyLimit: v.round()))),
                    const SizedBox(height: 8),
                    _doubleSlider(context, '测速超时 (秒)', cfg.subSpeedTimeout, 1, 60,
                        (v) => _save(cfg.copyWith(subSpeedTimeout: v))),
                    const SizedBox(height: 8),
                    _slider(context, '测速并发', cfg.subSpeedWorkers.toDouble(), 1, 100,
                        (v) => _save(cfg.copyWith(subSpeedWorkers: v.round()))),
                    const SizedBox(height: 8),
                    _doubleSlider(context, '下载大小 (MB)', cfg.subSpeedSizeMb, 0.1, 10,
                        (v) => _save(cfg.copyWith(subSpeedSizeMb: v))),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    return Row(
      children: [
        Expanded(child: content),
        if (!_logCollapsed)
          Container(
            width: _logWidth,
            decoration: BoxDecoration(
              color: t.logBg,
              border: Border(left: BorderSide(color: t.border)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: t.border)),
                  ),
                  child: Row(
                    children: [
                      Text('运行日志', style: TextStyle(color: t.logFg, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close, size: 18, color: t.textDim),
                        onPressed: () => setState(() => _logCollapsed = true),
                        tooltip: '隐藏日志',
                      ),
                    ],
                  ),
                ),
                Expanded(child: LogView(logger: subLogger)),
              ],
            ),
          ),
        if (_logCollapsed)
          GestureDetector(
            onTap: () => setState(() => _logCollapsed = false),
            child: Container(
              width: 22,
              color: t.surface,
              child: RotatedBox(
                quarterTurns: 3,
                child: Center(
                  child: Text('◀ 日志', style: TextStyle(color: t.textDim, fontSize: 12)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGenerators(BuildContext context, AppConfig cfg, SubscriptionsState run) {
    final disabled = cfg.subDisabledGenerators;
    return card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionTitle(context, '订阅器列表 (SUB_GENERATORS，格式: 名称|域名)'),
          const SizedBox(height: 8),
          for (var i = 0; i < cfg.subGenerators.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _genCtl[i],
                      onChanged: (v) {
                        final list = [...cfg.subGenerators];
                        list[i] = v;
                        _save(cfg.copyWith(subGenerators: list));
                      },
                      style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
                      decoration: _dec(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(disabled.contains(_genName(cfg.subGenerators[i]))
                        ? Icons.toggle_off : Icons.toggle_on,
                        color: disabled.contains(_genName(cfg.subGenerators[i]))
                            ? null : AppTheme.edgeOrange),
                    onPressed: () {
                      final name = _genName(cfg.subGenerators[i]);
                      final set = {...disabled};
                      if (set.contains(name)) {
                        set.remove(name);
                      } else {
                        set.add(name);
                      }
                      _save(cfg.copyWith(subDisabledGenerators: set));
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () {
                      final list = [...cfg.subGenerators]..removeAt(i);
                      _save(cfg.copyWith(subGenerators: list));
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('添加订阅器'),
            onPressed: () => _save(cfg.copyWith(subGenerators: [...cfg.subGenerators, '名称|域名'])),
          ),
        ],
      ),
    );
  }

  Widget _buildUrls(BuildContext context, AppConfig cfg, SubscriptionsState run) {
    return card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionTitle(context, '订阅链接 (SUB_URLS，支持 sub:// 与 http(s))'),
          const SizedBox(height: 8),
          for (var i = 0; i < cfg.subUrls.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlCtl[i],
                      onChanged: (v) {
                        final list = [...cfg.subUrls];
                        list[i] = v;
                        _save(cfg.copyWith(subUrls: list));
                      },
                      style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
                      decoration: _dec(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () {
                      final list = [...cfg.subUrls]..removeAt(i);
                      _save(cfg.copyWith(subUrls: list));
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('添加订阅链接'),
            onPressed: () => _save(cfg.copyWith(subUrls: [...cfg.subUrls, ''])),
          ),
        ],
      ),
    );
  }

  String _genName(String entry) => entry.split('|').first.trim();

  InputDecoration _dec() => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppThemeExt.of(context).bg,
        border: OutlineInputBorder(
          borderRadius: AppThemeExt.of(context).radius,
          borderSide: BorderSide(color: AppThemeExt.of(context).border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      );

  Widget _textField(BuildContext context, String label, TextEditingController ctl, ValueChanged<String> onChanged) {
    final t = AppThemeExt.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: t.textDim)),
        const SizedBox(height: 4),
        TextField(
          controller: ctl,
          onChanged: onChanged,
          style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
          decoration: _dec(),
        ),
      ],
    );
  }

  Widget _switchRow(BuildContext context, String label, bool value, ValueChanged<bool> onChanged) {
    final t = AppThemeExt.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(color: t.text))),
        Switch(value: value, activeThumbColor: AppTheme.edgeOrange, onChanged: onChanged),
      ],
    );
  }

  Widget _slider(BuildContext context, String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    final t = AppThemeExt.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(color: t.text))),
            Text(value.round().toString(),
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.edgeOrange)),
          ],
        ),
        Slider(value: value, min: min, max: max, activeColor: AppTheme.edgeOrange, onChanged: onChanged),
      ],
    );
  }

  Widget _doubleSlider(BuildContext context, String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    final t = AppThemeExt.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(color: t.text))),
            Text(value.toStringAsFixed(1),
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.edgeOrange)),
          ],
        ),
        Slider(value: value, min: min, max: max, divisions: ((max - min) * 10).round(),
            activeColor: AppTheme.edgeOrange, onChanged: onChanged),
      ],
    );
  }

  Widget _text(BuildContext context, String label, TextEditingController ctl, ValueChanged<String> onChanged) {
    final t = AppThemeExt.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: t.textDim)),
        const SizedBox(height: 4),
        TextField(
          controller: ctl,
          onChanged: onChanged,
          style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
          decoration: _dec(),
        ),
      ],
    );
  }
}

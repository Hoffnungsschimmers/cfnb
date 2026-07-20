import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/config/app_config.dart';
import '../widgets/common.dart';

class ConfigTab extends ConsumerStatefulWidget {
  const ConfigTab({super.key});
  @override
  ConsumerState<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends ConsumerState<ConfigTab> {
  final _genCtl = <TextEditingController>[];
  final _urlCtl = <TextEditingController>[];
  final _hostCtl = TextEditingController();
  final _uuidCtl = TextEditingController();
  final _countryCtl = TextEditingController();
  final _latencyOutCtl = TextEditingController();
  final _tokenCtl = TextEditingController();
  final _repoCtl = TextEditingController();
  final _branchCtl = TextEditingController();

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
    _tokenCtl.dispose();
    _repoCtl.dispose();
    _branchCtl.dispose();
    super.dispose();
  }

  void _syncIf(TextEditingController ctl, String v) {
    if (ctl.text != v) ctl.text = v;
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

  void _syncControllers(AppConfig cfg) {
    _syncList(_genCtl, cfg.subGenerators, (s) => s);
    _syncList(_urlCtl, cfg.subUrls, (s) => s);
    _syncIf(_hostCtl, cfg.subNodeHost);
    _syncIf(_uuidCtl, cfg.subNodeUuid);
    _syncIf(_countryCtl, cfg.subDefaultCountry);
    _syncIf(_tokenCtl, cfg.githubToken);
    _syncIf(_repoCtl, cfg.githubRepo);
    _syncIf(_branchCtl, cfg.githubBranch);
  }

  Future<void> _save(AppConfig cfg) async {
    final repo = await ref.read(configRepositoryProvider.future);
    await repo.save(cfg);
    ref.invalidate(configProvider);
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(configProvider);

    return cfgAsync.when(
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
              card(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionTitle(context, '外观'),
                    const SizedBox(height: 8),
                    labeledSwitch(
                      context,
                      '深色主题',
                      ref.watch(themeModeProvider) == ThemeMode.dark,
                      (v) => ref.read(themeModeProvider.notifier).state =
                          v ? ThemeMode.dark : ThemeMode.light,
                    ),
                  ],
                ),
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
              _buildGenerators(context, cfg),
              const SizedBox(height: 12),
              _buildUrls(context, cfg),
              const SizedBox(height: 12),
              card(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionTitle(context, '高级参数'),
                    const SizedBox(height: 8),
                    labeledTextField(context, '节点 Host (SUB_NODE_HOST)', _hostCtl,
                        (v) => _save(cfg.copyWith(subNodeHost: v))),
                    const SizedBox(height: 8),
                    labeledTextField(context, '节点 UUID (SUB_NODE_UUID)', _uuidCtl,
                        (v) => _save(cfg.copyWith(subNodeUuid: v))),
                    const SizedBox(height: 8),
                    labeledTextField(context, '默认国家码 (SUB_DEFAULT_COUNTRY)', _countryCtl,
                        (v) => _save(cfg.copyWith(subDefaultCountry: v.toUpperCase()))),
                    const SizedBox(height: 8),
                    labeledSwitch(context, '解析域名 (SUB_RESOLVE_DOMAIN)', cfg.subResolveDomain,
                        (v) => _save(cfg.copyWith(subResolveDomain: v))),
                    const SizedBox(height: 8),
                    labeledSwitch(context, '启用订阅转换 (SUB_CONVERT_ENABLED)', cfg.subConvertEnabled,
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
                    labeledSlider(context, '延迟低于 (ms)', cfg.subLatencyMaxMs.toDouble(), 10, 1000,
                        (v) => _save(cfg.copyWith(subLatencyMaxMs: v.round()))),
                    const SizedBox(height: 8),
                    labeledSlider(context, '保留前 N 名 (按延迟, 0=全部)', cfg.subLatencyTopN.toDouble(), 0, 500,
                        (v) => _save(cfg.copyWith(subLatencyTopN: v.round()))),
                    const SizedBox(height: 8),
                    labeledDoubleSlider(context, 'TCP 探测成功率下限 (0-1)', cfg.subLatencyMinSuccessRate, 0, 1,
                        (v) => _save(cfg.copyWith(subLatencyMinSuccessRate: v))),
                    const SizedBox(height: 8),
                    labeledSwitch(context, '跳过 TLS 证书校验 (SUB_INSECURE)', cfg.subInsecure,
                        (v) => _save(cfg.copyWith(subInsecure: v))),
                    const SizedBox(height: 8),
                    labeledDoubleSlider(context, '连接超时 (秒)', cfg.subLatencyTimeout, 0.1, 10,
                        (v) => _save(cfg.copyWith(subLatencyTimeout: v))),
                    const SizedBox(height: 8),
                    labeledSlider(context, '并发数', cfg.subLatencyWorkers.toDouble(), 1, 200,
                        (v) => _save(cfg.copyWith(subLatencyWorkers: v.round()))),
                    const SizedBox(height: 8),
                    labeledSlider(context, '探测次数', cfg.subLatencyProbes.toDouble(), 1, 10,
                        (v) => _save(cfg.copyWith(subLatencyProbes: v.round()))),
                    const SizedBox(height: 8),
                    labeledTextField(context, 'SNI (SUB_LATENCY_SNI)', _latencySniCtl(cfg),
                        (v) => _save(cfg.copyWith(subLatencySni: v))),
                    const SizedBox(height: 8),
                    labeledTextField(context, '输出文件 (SUB_LATENCY_OUTPUT_FILE)', _latencyOutCtl,
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
                    sectionTitle(context, 'GitHub 推送 (独立 cf-ip 仓)'),
                    const SizedBox(height: 8),
                    labeledTextField(context, 'Token', _tokenCtl,
                        (v) => _save(cfg.copyWith(githubToken: v)), obscure: true),
                    const SizedBox(height: 8),
                    labeledTextField(context, '仓库 (owner/repo)', _repoCtl,
                        (v) => _save(cfg.copyWith(githubRepo: v))),
                    const SizedBox(height: 8),
                    labeledTextField(context, '分支', _branchCtl,
                        (v) => _save(cfg.copyWith(githubBranch: v))),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  TextEditingController _latencySniCtl(AppConfig cfg) {
    if (_sniCtl == null) {
      _sniCtl = TextEditingController();
    }
    if (_sniCtl!.text != cfg.subLatencySni) {
      _sniCtl!.text = cfg.subLatencySni;
    }
    return _sniCtl!;
  }

  TextEditingController? _sniCtl;

  Widget _buildGenerators(BuildContext context, AppConfig cfg) {
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
                      decoration: inputDecorationFor(context),
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

  Widget _buildUrls(BuildContext context, AppConfig cfg) {
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
                      decoration: inputDecorationFor(context),
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
}

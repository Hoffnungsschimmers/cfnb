import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/config/app_config.dart';
import '../widgets/common.dart';
import '../../app/providers.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _scroll = ScrollController();

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(configProvider);
    return cfgAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载配置失败: $e')),
      data: (cfg) => SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sectionTitle(context, '基本设置'),
            const SizedBox(height: 12),
            card(context, child: _switchRow(context, '启用全局模式', cfg.useGlobalMode,
                (v) => _save(cfg.copyWith(useGlobalMode: v)))),
            card(context, child: _sliderRow(context, '保留节点数 (TOP N)', cfg.globalTopN.toDouble(), 1, 200,
                (v) => _save(cfg.copyWith(globalTopN: v.round())))),
            card(context, child: _sliderRow(context, '带宽测速并发', cfg.bandwidthWorkers.toDouble(), 1, 200,
                (v) => _save(cfg.copyWith(bandwidthWorkers: v.round())))),
            card(context, child: _switchRow(context, '启用 Cloudflare DNS 更新', cfg.cfEnabled,
                (v) => _save(cfg.copyWith(cfEnabled: v)))),
            card(context, child: _switchRow(context, '启用订阅转换', cfg.subConvertEnabled,
                (v) => _save(cfg.copyWith(subConvertEnabled: v)))),
            card(context, child: _switchRow(context, '启用自动调度', cfg.autoScheduleEnabled,
                (v) => _save(cfg.copyWith(autoScheduleEnabled: v)))),
            const SizedBox(height: 12),
            AppButton('保存设置', icon: Icons.save, onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('设置已保存')),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _save(AppConfig next) async {
    final repo = await ref.read(configRepositoryProvider.future);
    await repo.save(next);
    ref.invalidate(configProvider);
  }
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

Widget _sliderRow(BuildContext context, String label, double value, double min, double max,
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
      Slider(value: value, min: min, max: max, activeThumbColor: AppTheme.edgeOrange, onChanged: onChanged),
    ],
  );
}


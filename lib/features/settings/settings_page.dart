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
  final Map<String, TextEditingController> _ctl = {};

  TextEditingController _c(String key, [String initial = '']) =>
      _ctl.putIfAbsent(key, () => TextEditingController(text: initial));

  @override
  void dispose() {
    for (final c in _ctl.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save(AppConfig next) async {
    final repo = await ref.read(configRepositoryProvider.future);
    await repo.save(next);
    ref.invalidate(configProvider);
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(configProvider);
    return cfgAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载配置失败: $e')),
      data: (cfg) {
        // 文本控制器：仅在首次或外部值变化时同步
        void sync(String k, String v) {
          final c = _ctl[k];
          if (c != null && c.text != v) c.text = v;
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sectionTitle(context, 'GitHub 推送 (独立 cf-ip 仓)'),
              const SizedBox(height: 12),
              card(context, child: _text(context, 'Token', cfg.githubToken, sync, 'githubToken',
                  (v) => _save(cfg.copyWith(githubToken: v)), obscure: true)),
              card(context, child: _text(context, '仓库 (owner/repo)', cfg.githubRepo, sync, 'githubRepo',
                  (v) => _save(cfg.copyWith(githubRepo: v)))),
              card(context, child: _text(context, '分支', cfg.githubBranch, sync, 'githubBranch',
                  (v) => _save(cfg.copyWith(githubBranch: v)))),
              const SizedBox(height: 16),

              sectionTitle(context, '订阅转换'),
              const SizedBox(height: 12),
              card(context, child: _switch(context, '启用订阅转换', cfg.subConvertEnabled,
                  (v) => _save(cfg.copyWith(subConvertEnabled: v)))),
              const SizedBox(height: 12),

              AppButton('保存设置', icon: Icons.save, onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('设置已保存')),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _switch(BuildContext context, String label, bool value, ValueChanged<bool> onChanged) {
    final t = AppThemeExt.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(color: t.text))),
        Switch(value: value, activeThumbColor: AppTheme.edgeOrange, onChanged: onChanged),
      ],
    );
  }

  Widget _text(BuildContext context, String label, String value, void Function(String, String) sync, String key,
      ValueChanged<String> onChanged, {bool obscure = false}) {
    sync(key, value);
    final t = AppThemeExt.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: t.textDim)),
        const SizedBox(height: 4),
        TextField(
          controller: _c(key, value),
          onChanged: onChanged,
          obscureText: obscure,
          style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: t.bg,
            border: OutlineInputBorder(borderRadius: t.radius, borderSide: BorderSide(color: t.border)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
      ],
    );
  }

}

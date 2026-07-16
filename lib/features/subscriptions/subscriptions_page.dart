import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/config/app_config.dart';
import '../widgets/common.dart';
import '../../app/providers.dart';

class SubscriptionsPage extends ConsumerStatefulWidget {
  const SubscriptionsPage({super.key});
  @override
  ConsumerState<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends ConsumerState<SubscriptionsPage> {
  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(configProvider);
    return cfgAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (cfg) {
        final gens = cfg.subGenerators;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sectionTitle(context, '订阅器管理（${gens.length}）'),
              const SizedBox(height: 12),
              if (gens.isEmpty)
                card(context, child: const Text('未配置订阅器。在设置中填写 SUB_GENERATORS（格式：名称|域名）。')),
              for (final g in gens)
                _GenRow(name: _name(g), disabled: cfg.subDisabledGenerators.contains(_name(g)),
                    onChanged: (v) => _toggle(cfg, _name(g), v)),
            ],
          ),
        );
      },
    );
  }

  String _name(String entry) => entry.split('|').first.trim();

  void _toggle(AppConfig cfg, String name, bool disabled) async {
    final set = {...cfg.subDisabledGenerators};
    if (disabled) {
      set.add(name);
    } else {
      set.remove(name);
    }
    final repo = await ref.read(configRepositoryProvider.future);
    await repo.save(cfg.copyWith(subDisabledGenerators: set));
    ref.invalidate(configProvider);
  }
}

class _GenRow extends StatelessWidget {
  final String name;
  final bool disabled;
  final ValueChanged<bool> onChanged;
  const _GenRow({required this.name, required this.disabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: card(
        context,
        child: Row(
          children: [
            Icon(disabled ? Icons.toggle_off : Icons.toggle_on,
                color: disabled ? t.textDim : AppTheme.edgeOrange, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(name, style: TextStyle(color: t.text))),
            Switch(value: !disabled, activeColor: AppTheme.edgeOrange, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}



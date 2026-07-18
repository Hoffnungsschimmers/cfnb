import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/providers.dart';
import '../widgets/common.dart';
import '../../core/config/app_config.dart';

/// 运行数据源编辑器：编辑 ADDITIONAL_SOURCES（URL + 启用开关 + 增删）。
class SourceEditor extends ConsumerStatefulWidget {
  const SourceEditor({super.key});
  @override
  ConsumerState<SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends ConsumerState<SourceEditor> {
  final List<TextEditingController> _ctl = [];

  @override
  void dispose() {
    for (final c in _ctl) {
      c.dispose();
    }
    super.dispose();
  }

  void _sync(int n, List<SourceConfig> sources) {
    while (_ctl.length < n) {
      final i = _ctl.length;
      final c = TextEditingController(text: sources.length > i ? sources[i].url : '');
      _ctl.add(c);
    }
    while (_ctl.length > n) {
      _ctl.removeLast().dispose();
    }
  }

  Future<void> _save(AppConfig next) async {
    final repo = await ref.read(configRepositoryProvider.future);
    await repo.save(next);
    ref.invalidate(configProvider);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(configProvider);
    return cfg.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (cfg) {
        _sync(cfg.additionalSources.length, cfg.additionalSources);
        final t = AppThemeExt.of(context);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sectionTitle(context, '运行数据源 (ADDITIONAL_SOURCES)'),
              const SizedBox(height: 8),
              card(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('这些源会在「单步：获取数据源」与一键执行时拉取并合并去重。',
                        style: TextStyle(fontSize: 12, color: t.textDim)),
                    const SizedBox(height: 10),
                    for (var i = 0; i < cfg.additionalSources.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _ctl[i],
                                onChanged: (v) {
                                  final list = [...cfg.additionalSources];
                                  list[i] = SourceConfig(
                                      url: v.trim(), enabled: list[i].enabled);
                                  _save(cfg.copyWith(additionalSources: list));
                                },
                                style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
                                decoration: _dec(context),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(
                                cfg.additionalSources[i].enabled
                                    ? Icons.toggle_on
                                    : Icons.toggle_off,
                                color: cfg.additionalSources[i].enabled
                                    ? AppTheme.edgeOrange
                                    : null,
                              ),
                              onPressed: () {
                                final list = [...cfg.additionalSources];
                                list[i] = SourceConfig(
                                    url: list[i].url,
                                    enabled: !list[i].enabled);
                                _save(cfg.copyWith(additionalSources: list));
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent),
                              onPressed: () {
                                final list = [...cfg.additionalSources]..removeAt(i);
                                _save(cfg.copyWith(additionalSources: list));
                              },
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('添加数据源'),
                      onPressed: () => _save(cfg.copyWith(
                          additionalSources: [...cfg.additionalSources, const SourceConfig(url: '')])),
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      icon: const Icon(Icons.restore),
                      label: const Text('恢复为默认数据源'),
                      onPressed: () => _save(cfg.copyWith(
                          additionalSources: defaultAdditionalSources)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  InputDecoration _dec(BuildContext context) => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppThemeExt.of(context).bg,
        border: OutlineInputBorder(
          borderRadius: AppThemeExt.of(context).radius,
          borderSide: BorderSide(color: AppThemeExt.of(context).border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      );
}

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 卡片容器。
Widget card(BuildContext context, {required Widget child, EdgeInsets? padding}) {
  final t = AppThemeExt.of(context);
  return Container(
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: t.surface,
      borderRadius: t.radius,
      border: Border.all(color: t.border),
    ),
    child: child,
  );
}

/// 状态药丸。
Widget pill(BuildContext context, String text, Color bg, Color fg) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
  );
}

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final IconData? icon;
  const AppButton(this.label, {this.onPressed, this.primary = true, this.icon, super.key});

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) Icon(icon, size: 18),
        if (icon != null) const SizedBox(width: 8),
        Text(label),
      ],
    );
    return primary
        ? FilledButton(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);
  }
}

/// 区块标题。
Widget sectionTitle(BuildContext context, String text) {
  final t = AppThemeExt.of(context);
  return Text(
    text,
    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: t.textDim),
  );
}

/// 单一强调色进度条。
Widget appProgress({double? value}) => LinearProgressIndicator(
      value: value,
      backgroundColor: Colors.orange.withValues(alpha: 0.15),
      color: AppTheme.edgeOrange,
      minHeight: 6,
      borderRadius: BorderRadius.circular(999),
    );

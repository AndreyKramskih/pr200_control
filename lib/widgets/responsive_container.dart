// lib/widgets/responsive_container.dart
import 'dart:io';
import 'package:flutter/material.dart';

/// Ограничивает ширину контента на десктопе и центрирует его.
/// На мобильных платформах возвращает контент без изменений.
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth = 900,
    this.padding = EdgeInsets.zero,
  });

  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) {
      return Padding(padding: padding, child: child);
    }
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

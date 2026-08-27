import 'package:flutter/material.dart';

class ThemeUtils {
  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color textColor(BuildContext context) {
    return isDark(context) ? Colors.white : Colors.black87;
  }

  static Color textSecondaryColor(BuildContext context) {
    return isDark(context) ? Colors.grey[400]! : Colors.black54;
  }

  static Color textHintColor(BuildContext context) {
    return isDark(context) ? Colors.grey[500]! : Colors.grey[600]!;
  }

  static Color cardColor(BuildContext context) {
    return isDark(context) ? Colors.grey[850]! : Colors.white;
  }

  static Color scaffoldColor(BuildContext context) {
    return isDark(context) ? Colors.grey[900]! : Colors.grey[50]!;
  }

  static Color cardBorderColor(BuildContext context) {
    return isDark(context) ? Colors.grey[700]! : Colors.grey[300]!;
  }

  static Color dividerColor(BuildContext context) {
    return isDark(context) ? Colors.grey[700]! : Colors.grey[300]!;
  }

  static Color getSensorValueColor(
    BuildContext context,
    dynamic value, {
    int? min,
    int? max,
  }) {
    if (value == null) return Colors.grey;
    if (min != null && max != null) {
      final numValue = double.tryParse(value.toString());
      if (numValue != null) {
        if (numValue < min || numValue > max) {
          return Colors.red;
        }
        return isDark(context) ? Colors.green[400]! : Colors.green;
      }
    }
    return isDark(context) ? Colors.white : Colors.black87;
  }
}

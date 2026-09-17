import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/config_model.dart';
import '../core/utils/theme_utils.dart';

class SystemScreen extends StatelessWidget {
  final String systemId;

  const SystemScreen({super.key, required this.systemId});

  @override
  Widget build(BuildContext context) {
    final config = Provider.of<ConfigModel>(context);
    final system = config.systems[systemId];
    final isDark = ThemeUtils.isDark(context);

    if (system == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Ошибка'),
          backgroundColor: Colors.blue[800],
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Container(
          color: ThemeUtils.scaffoldColor(context),
          child: const Center(child: Text('Система не найдена')),
        ),
      );
    }

    final filteredSubmenus = system.submenus.entries.where((entry) {
      final submenu = entry.value;
      if (submenu.items != null && submenu.items!.isNotEmpty) {
        return true;
      }
      if (submenu.type == 'settings' &&
          submenu.groups != null &&
          submenu.groups!.isNotEmpty) {
        for (final group in submenu.groups!) {
          if (group.items.isNotEmpty) {
            return true;
          }
        }
        return false;
      }
      if (submenu.type == 'alarms' &&
          submenu.alarms != null &&
          submenu.alarms!.isNotEmpty) {
        return true;
      }
      if (submenu.type == 'valve' &&
          submenu.controls != null &&
          submenu.controls!.isNotEmpty) {
        return true;
      }
      return false;
    }).toList();

    if (filteredSubmenus.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text('${system.icon} ${system.name}'),
          backgroundColor: Colors.blue[800],
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Container(
          color: ThemeUtils.scaffoldColor(context),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Нет доступных подменю',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                Text(
                  'Проверьте конфигурацию',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${system.icon} ${system.name}'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        color: ThemeUtils.scaffoldColor(context),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // ✅ Адаптивные размеры под платформу и ширину окна
            final isDesktop =
                Platform.isWindows || Platform.isLinux || Platform.isMacOS;

            int crossAxisCount;
            double iconSize;
            double titleSize;
            double badgeSize;
            double aspectRatio;

            if (isDesktop) {
              // Windows: подбираем число колонок от ширины окна
              final width = constraints.maxWidth;
              if (width < 600) {
                crossAxisCount = 2;
              } else if (width < 900) {
                crossAxisCount = 3;
              } else if (width < 1300) {
                crossAxisCount = 4;
              } else {
                crossAxisCount = 5;
              }
              iconSize = 28; // было 42
              titleSize = 13; // было 14
              badgeSize = 10; // было 11
              aspectRatio = 1.3; // было 0.75 — карточки шире и ниже
            } else {
              // Android/мобильные — как было
              crossAxisCount = 2;
              iconSize = 42;
              titleSize = 14;
              badgeSize = 11;
              aspectRatio = 0.75;
            }

            return GridView.count(
              padding: EdgeInsets.all(isDesktop ? 12 : 16),
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: isDesktop ? 12 : 16,
              mainAxisSpacing: isDesktop ? 12 : 16,
              childAspectRatio: aspectRatio,
              children: filteredSubmenus.map((entry) {
                final submenu = entry.value;

                return Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(isDesktop ? 12 : 16),
                  ),
                  color: isDark ? Colors.grey[850] : Colors.white,
                  child: InkWell(
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        '/submenu',
                        arguments: {
                          'systemId': systemId,
                          'submenuId': entry.key,
                        },
                      );
                    },
                    borderRadius: BorderRadius.circular(isDesktop ? 12 : 16),
                    child: Container(
                      padding: EdgeInsets.all(isDesktop ? 8 : 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [
                                  Colors.blue[900]!.withValues(alpha: 0.3),
                                  Colors.blue[800]!.withValues(alpha: 0.2),
                                ]
                              : [Colors.blue[50]!, Colors.blue[100]!],
                        ),
                        borderRadius: BorderRadius.circular(
                          isDesktop ? 12 : 16,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ✅ Иконка
                          Text(
                            submenu.icon,
                            style: TextStyle(fontSize: iconSize),
                          ),
                          SizedBox(height: isDesktop ? 4 : 8),
                          // ✅ Название
                          Flexible(
                            child: Text(
                              submenu.name,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: titleSize,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(height: isDesktop ? 2 : 4),
                          // ✅ Бейдж типа
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isDesktop ? 6 : 8,
                              vertical: isDesktop ? 1 : 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.blue[800]
                                  : Colors.blue[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _getTypeName(submenu.type),
                              style: TextStyle(
                                fontSize: badgeSize,
                                color: isDark ? Colors.white : Colors.blue[800],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }

  String _getTypeName(String type) {
    switch (type) {
      case 'sensors':
        return 'Датчики';
      case 'relays':
        return 'Реле';
      case 'pumps':
        return 'Насосы';
      case 'valve':
        return 'Клапан';
      case 'settings':
        return 'Настройки';
      case 'alarms':
        return 'Аварии';
      case 'startstop':
        return 'Управление';
      default:
        return type;
    }
  }
}

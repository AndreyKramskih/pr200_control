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
        child: GridView.count(
          padding: const EdgeInsets.all(16),
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.75,
          children: filteredSubmenus.map((entry) {
            final submenu = entry.value;

            return Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: isDark ? Colors.grey[850] : Colors.white,
              child: InkWell(
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    '/submenu',
                    arguments: {'systemId': systemId, 'submenuId': entry.key},
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              Colors.blue[900]!.withOpacity(0.3),
                              Colors.blue[800]!.withOpacity(0.2),
                            ]
                          : [Colors.blue[50]!, Colors.blue[100]!],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            submenu.icon,
                            style: const TextStyle(fontSize: 42),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: Text(
                          submenu.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.blue[800] : Colors.blue[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _getTypeName(submenu.type),
                          style: TextStyle(
                            fontSize: 11,
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

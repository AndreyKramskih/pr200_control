import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/config_model.dart';

class SystemScreen extends StatelessWidget {
  final String systemId;

  const SystemScreen({super.key, required this.systemId});

  @override
  Widget build(BuildContext context) {
    final config = Provider.of<ConfigModel>(context);
    final system = config.systems[systemId];

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
        body: const Center(child: Text('Система не найдена')),
      );
    }

    // Фильтруем подменю - показываем только те, у которых есть элементы
    final filteredSubmenus = system.submenus.entries.where((entry) {
      final submenu = entry.value;

      // Проверяем, есть ли элементы в подменю
      if (submenu.items != null && submenu.items!.isNotEmpty) {
        return true;
      }

      // Для настроек проверяем группы
      if (submenu.type == 'settings' &&
          submenu.groups != null &&
          submenu.groups!.isNotEmpty) {
        // Проверяем, есть ли хотя бы одна группа с элементами
        for (final group in submenu.groups!) {
          if (group.items.isNotEmpty) {
            return true;
          }
        }
        return false;
      }

      // Для аварий проверяем alarms
      if (submenu.type == 'alarms' &&
          submenu.alarms != null &&
          submenu.alarms!.isNotEmpty) {
        return true;
      }

      // Для клапана проверяем controls
      if (submenu.type == 'valve' &&
          submenu.controls != null &&
          submenu.controls!.isNotEmpty) {
        return true;
      }

      return false;
    }).toList();

    // Если нет подменю - показываем сообщение
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
        body: const Center(
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.grey[50]!, Colors.grey[200]!],
          ),
        ),
        child: GridView.count(
          padding: const EdgeInsets.all(16),
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.75,
          children: filteredSubmenus.map((entry) {
            final submenu = entry.value;
            final hasItems = _hasItems(submenu);

            return Card(
              elevation: hasItems ? 4 : 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Opacity(
                opacity: hasItems ? 1.0 : 0.5,
                child: InkWell(
                  onTap: hasItems
                      ? () {
                          Navigator.pushNamed(
                            context,
                            '/submenu',
                            arguments: {
                              'systemId': systemId,
                              'submenuId': entry.key,
                            },
                          );
                        }
                      : null,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: hasItems
                            ? [Colors.blue[50]!, Colors.blue[100]!]
                            : [Colors.grey[50]!, Colors.grey[200]!],
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
                              style: TextStyle(
                                fontSize: 42,
                                color: hasItems ? null : Colors.grey,
                              ),
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
                              color: hasItems ? Colors.black87 : Colors.grey,
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
                            color: hasItems
                                ? Colors.blue[200]
                                : Colors.grey[300],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _getTypeName(submenu.type),
                            style: TextStyle(
                              fontSize: 11,
                              color: hasItems
                                  ? Colors.blue[800]
                                  : Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (!hasItems) ...[
                          const SizedBox(height: 4),
                          const Text(
                            'нет данных',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  bool _hasItems(SubmenuConfig submenu) {
    // Проверяем items
    if (submenu.items != null && submenu.items!.isNotEmpty) {
      return true;
    }

    // Для настроек проверяем группы
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

    // Для аварий проверяем alarms
    if (submenu.type == 'alarms' &&
        submenu.alarms != null &&
        submenu.alarms!.isNotEmpty) {
      return true;
    }

    // Для клапана проверяем controls
    if (submenu.type == 'valve' &&
        submenu.controls != null &&
        submenu.controls!.isNotEmpty) {
      return true;
    }

    return false;
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

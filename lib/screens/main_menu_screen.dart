// lib/screens/main_menu_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/config_model.dart';
import '../providers/theme_provider.dart';
import '../services/modbus_service.dart';
import '../screens/load_config_screen.dart';
// ✅ Добавляем импорт для экрана логов
import '../screens/log_screen.dart';

import '../services/report_service.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  String _statusText = 'Не подключено';
  Color _statusColor = Colors.red;
  String _connectionInfo = '';

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkConnection();
  }

  void _checkConnection() {
    final modbus = Provider.of<ModbusService>(context, listen: false);
    final config = Provider.of<ConfigModel>(context, listen: false);

    setState(() {
      _statusText = modbus.connected ? 'Подключено' : 'Не подключено';
      _statusColor = modbus.connected ? Colors.green : Colors.red;
      if (modbus.connected) {
        _connectionInfo =
            '${config.modbusServer.ip}:${config.modbusServer.port}';
      } else {
        _connectionInfo = '';
      }
    });
  }

  Future<void> _createReport(BuildContext context) async {
    try {
      final config = Provider.of<ConfigModel>(context, listen: false);
      final modbus = Provider.of<ModbusService>(context, listen: false);

      if (!modbus.connected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Нет подключения к устройству'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Сбор данных...'),
                ],
              ),
            ),
          ),
        ),
      );

      // ✅ Изменяем структуру: теперь храним имя системы и параметры
      final systemData = <String, Map<String, dynamic>>{};
      final systemNames = <String, String>{}; // ✅ Храним названия систем

      print('📊 Начинаем сбор данных...');
      print('📋 Систем в конфиге: ${config.systems.length}');

      for (var entry in config.systems.entries) {
        final systemId = entry.key;
        final system = entry.value;
        final data = <String, dynamic>{};

        // ✅ Сохраняем название системы
        systemNames[systemId] = system.name;

        print('📁 Система: $systemId (${system.name})');

        for (var submenuEntry in system.submenus.entries) {
          final submenu = submenuEntry.value;

          if (submenu.items != null) {
            for (var item in submenu.items!) {
              try {
                final value = await modbus.readParameterValue(item);

                data[item.name] = {
                  'value': value ?? '--',
                  'unit': item.unit ?? '',
                  'bit': item.bit,
                  'states': item.states,
                };

                print('  ✅ ${item.name} = $value');
              } catch (e) {
                print('  ❌ Ошибка чтения ${item.name}: $e');
                data[item.name] = {
                  'value': 'Ошибка',
                  'unit': item.unit ?? '',
                  'bit': item.bit,
                  'states': item.states,
                };
              }
            }
          }

          if (submenu.groups != null) {
            for (var group in submenu.groups!) {
              for (var item in group.items) {
                try {
                  final value = await modbus.readParameterValue(item);

                  data[item.name] = {
                    'value': value ?? '--',
                    'unit': item.unit ?? '',
                    'bit': item.bit,
                    'states': item.states,
                  };

                  print('  ✅ ${item.name} = $value');
                } catch (e) {
                  print('  ❌ Ошибка чтения ${item.name}: $e');
                  data[item.name] = {
                    'value': 'Ошибка',
                    'unit': item.unit ?? '',
                    'bit': item.bit,
                    'states': item.states,
                  };
                }
              }
            }
          }
        }

        systemData[systemId] = data;
        print('✅ Система $systemId: ${data.length} параметров');
      }

      Navigator.pop(context);

      print('📊 Всего систем с данными: ${systemData.length}');

      // ✅ Выводим названия систем
      for (var entry in systemData.entries) {
        final systemId = entry.key;
        final systemName = systemNames[systemId] ?? systemId;
        print(
          '📊 Система $systemName ($systemId): ${entry.value.length} параметров',
        );
      }

      if (systemData.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Нет данных для отчета'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final reportService = ReportService();
      await reportService.generateAndShareReport(
        projectName: config.projectName,
        ip: config.modbusServer.ip,
        port: config.modbusServer.port,
        slaveId: config.modbusServer.slaveId,
        systemData: systemData,
        systemNames: systemNames, // ✅ Передаем названия систем
        reportTime: DateTime.now(),
      );
    } catch (e) {
      try {
        Navigator.pop(context);
      } catch (_) {}

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Ошибка создания отчета: $e'),
          backgroundColor: Colors.red,
        ),
      );
      print('❌ Ошибка создания отчета: $e');
    }
  }

  Future<void> _reloadConfig() async {
    setState(() {});
    _checkConnection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Конфигурация обновлена'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = Provider.of<ConfigModel>(context);
    final modbus = Provider.of<ModbusService>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PR200 Управление'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          // Кнопка переключения темы
          IconButton(
            icon: Icon(
              themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
            ),
            onPressed: () {
              themeProvider.toggleTheme();
            },
            tooltip: themeProvider.isDarkMode ? 'Светлая тема' : 'Темная тема',
          ),
          // Кнопка загрузки конфигурации
          IconButton(
            icon: const Icon(Icons.cloud_download),
            onPressed: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => const LoadConfigScreen(),
                ),
              );
              if (result == true) {
                _reloadConfig();
              }
            },
            tooltip: 'Загрузить конфигурацию',
          ),
          IconButton(
            icon: const Icon(Icons.settings_ethernet),
            onPressed: () {
              Navigator.pushNamed(context, '/connection');
            },
            tooltip: 'Подключение',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _checkConnection();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Статус обновлен'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            tooltip: 'Обновить статус',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: themeProvider.isDarkMode
                ? [Colors.grey[900]!, Colors.grey[800]!]
                : [Colors.grey[50]!, Colors.grey[200]!],
          ),
        ),
        child: Column(
          children: [
            // Статус
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: themeProvider.isDarkMode
                  ? Colors.grey[850]
                  : Colors.grey[100],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _statusColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _statusText,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _statusColor,
                        ),
                      ),
                      if (_connectionInfo.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          '($_connectionInfo)',
                          style: TextStyle(
                            fontSize: 12,
                            color: themeProvider.isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      if (modbus.lastError.isNotEmpty && !modbus.connected)
                        Tooltip(
                          message: modbus.lastError,
                          child: const Icon(
                            Icons.error_outline,
                            color: Colors.orange,
                            size: 20,
                          ),
                        ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.bug_report, size: 20),
                        onPressed: () {
                          _showDebugInfo(context);
                        },
                        tooltip: 'Отладка',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Заголовок
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Выберите систему управления',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: themeProvider.isDarkMode
                      ? Colors.white
                      : Colors.black87,
                ),
              ),
            ),

            // Список систем
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ...config.systems.entries.map((entry) {
                    return Card(
                      elevation: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        leading: Text(
                          entry.value.icon,
                          style: const TextStyle(fontSize: 32),
                        ),
                        title: Text(
                          entry.value.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: themeProvider.isDarkMode
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          '${entry.value.submenus.length} подменю',
                          style: TextStyle(
                            fontSize: 12,
                            color: themeProvider.isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey,
                          ),
                        ),
                        trailing: Icon(
                          Icons.arrow_forward_ios,
                          color: themeProvider.isDarkMode
                              ? Colors.grey[400]
                              : Colors.grey,
                        ),
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/system',
                            arguments: entry.key,
                          );
                        },
                      ),
                    );
                  }).toList(),

                  // Кнопка подключения
                  Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      leading: Text(
                        config.connection.icon,
                        style: const TextStyle(fontSize: 32),
                      ),
                      title: Text(
                        config.connection.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: themeProvider.isDarkMode
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        modbus.connected
                            ? 'Подключено'
                            : 'Требуется подключение',
                        style: TextStyle(
                          fontSize: 12,
                          color: modbus.connected
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        color: themeProvider.isDarkMode
                            ? Colors.grey[400]
                            : Colors.grey,
                      ),
                      onTap: () {
                        Navigator.pushNamed(context, '/connection');
                      },
                    ),
                  ),
                  // ✅ ========== НОВАЯ КНОПКА "СОЗДАТЬ ОТЧЕТ" ==========
                  Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      leading: const Text('📄', style: TextStyle(fontSize: 32)),
                      title: Text(
                        'Создать отчет',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: themeProvider.isDarkMode
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        modbus.connected
                            ? 'Экспорт в PDF'
                            : 'Требуется подключение',
                        style: TextStyle(
                          fontSize: 12,
                          color: modbus.connected
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                      trailing: Icon(
                        Icons.picture_as_pdf,
                        color: themeProvider.isDarkMode
                            ? Colors.grey[400]
                            : Colors.red,
                      ),
                      onTap: modbus.connected
                          ? () {
                              _createReport(context);
                            }
                          : null, // Если нет подключения - кнопка неактивна
                    ),
                  ),

                  // ✅ Информация о версии с долгим нажатием
                  Padding(
                    padding: const EdgeInsets.only(top: 20, bottom: 10),
                    child: Center(
                      child: GestureDetector(
                        onLongPress: () {
                          // Переход на экран логов
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LogScreen(),
                            ),
                          );
                        },
                        child: Text(
                          'PR200 v1.0.4',
                          style: TextStyle(
                            fontSize: 12,
                            color: themeProvider.isDarkMode
                                ? Colors.grey[600]
                                : Colors.grey[400],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDebugInfo(BuildContext context) {
    final modbus = Provider.of<ModbusService>(context, listen: false);
    final config = Provider.of<ConfigModel>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отладочная информация'),
        backgroundColor: themeProvider.isDarkMode
            ? Colors.grey[800]
            : Colors.white,
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDebugRow(
                'Статус',
                modbus.connected ? 'Подключено' : 'Не подключено',
              ),
              const Divider(),
              _buildDebugRow('IP', config.modbusServer.ip),
              _buildDebugRow('Порт', config.modbusServer.port.toString()),
              _buildDebugRow(
                'Slave ID',
                config.modbusServer.slaveId.toString(),
              ),
              _buildDebugRow('Таймаут', '${config.modbusServer.timeout}с'),
              const Divider(),
              _buildDebugRow('Систем', config.systems.length.toString()),
              _buildDebugRow(
                'Последняя ошибка',
                modbus.lastError.isNotEmpty ? modbus.lastError : 'Нет',
              ),
              const Divider(),
              _buildDebugRow(
                'Размер кеша',
                modbus.registerCache.length.toString(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugRow(String label, String value) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: themeProvider.isDarkMode
                    ? Colors.grey[400]
                    : Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

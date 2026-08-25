// lib/screens/main_menu_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/config_model.dart';
import '../providers/theme_provider.dart';
import '../services/modbus_service.dart';
import '../services/modbus_rtu_service.dart';
import '../screens/load_config_screen.dart';
import '../screens/log_screen.dart';
import '../screens/trends_screen.dart';
import '../services/report_service.dart';
import '../services/pin_service.dart';
import '../screens/pin_screen.dart';
import '../screens/config_list_screen.dart';
import '../main.dart';

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

    // ✅ Подписываемся на изменения
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final modbus = Provider.of<ModbusService>(context, listen: false);
      final rtuService = Provider.of<ModbusRtuService>(context, listen: false);
      modbus.addListener(_onConnectionChanged);
      rtuService.addListener(_onConnectionChanged);
    });
  }

  @override
  void dispose() {
    final modbus = Provider.of<ModbusService>(context, listen: false);
    final rtuService = Provider.of<ModbusRtuService>(context, listen: false);
    modbus.removeListener(_onConnectionChanged);
    rtuService.removeListener(_onConnectionChanged);
    super.dispose();
  }

  void _onConnectionChanged() {
    _checkConnection();
  }

  void _checkConnection() {
    final modbus = Provider.of<ModbusService>(context, listen: false);
    final rtuService = Provider.of<ModbusRtuService>(context, listen: false);

    setState(() {
      // ✅ Проверяем RTU первым (он имеет приоритет)
      if (rtuService.connected) {
        _statusText = 'Подключено (USB)';
        _statusColor = Colors.green;
        _connectionInfo = rtuService.portName;
      } else if (modbus.connected) {
        _statusText = 'Подключено (WiFi)';
        _statusColor = Colors.green;
        _connectionInfo = '${modbus.ip}:${modbus.port}';
      } else {
        _statusText = 'Не подключено';
        _statusColor = Colors.red;
        _connectionInfo = '';
      }
    });
  }

  Future<void> _createReport(BuildContext context) async {
    try {
      final config = Provider.of<ConfigModel>(context, listen: false);
      final modbus = Provider.of<ModbusService>(context, listen: false);
      final rtuService = Provider.of<ModbusRtuService>(context, listen: false);

      // ✅ Проверяем подключение - RTU или TCP
      final bool isConnected = rtuService.connected || modbus.connected;

      if (!isConnected) {
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

      final systemData = <String, Map<String, dynamic>>{};
      final systemNames = <String, String>{};

      print('📊 Начинаем сбор данных...');
      print('📋 Систем в конфиге: ${config.systems.length}');

      for (var entry in config.systems.entries) {
        final systemId = entry.key;
        final system = entry.value;
        final data = <String, dynamic>{};
        systemNames[systemId] = system.name;

        print('📁 Система: $systemId (${system.name})');

        for (var submenuEntry in system.submenus.entries) {
          final submenu = submenuEntry.value;

          if (submenu.items != null) {
            for (var item in submenu.items!) {
              try {
                dynamic value;
                // ✅ Используем активный сервис
                if (rtuService.connected) {
                  value = await rtuService.readParameterValue(item);
                } else {
                  value = await modbus.readParameterValue(item);
                }
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
                  dynamic value;
                  if (rtuService.connected) {
                    value = await rtuService.readParameterValue(item);
                  } else {
                    value = await modbus.readParameterValue(item);
                  }
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
        systemNames: systemNames,
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

  @override
  Widget build(BuildContext context) {
    final config = Provider.of<ConfigModel>(context);
    final modbus = Provider.of<ModbusService>(context);
    final rtuService = Provider.of<ModbusRtuService>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    // ✅ Определяем подключение по состоянию сервисов
    final bool isRtu = rtuService.connected;
    final bool isConnected = rtuService.connected || modbus.connected;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('PR200'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          // Версия (долгое нажатие → Логи)
          GestureDetector(
            onLongPress: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LogScreen()),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'v1.0.6',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // Тема
          IconButton(
            icon: Icon(
              themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
            ),
            onPressed: themeProvider.toggleTheme,
            tooltip: themeProvider.isDarkMode ? 'Светлая тема' : 'Темная тема',
          ),
          // Загрузка конфигурации
          IconButton(
            icon: const Icon(Icons.cloud_download),
            onPressed: () async {
              final result = await Navigator.push<ConfigModel>(
                context,
                MaterialPageRoute(
                  builder: (context) => const LoadConfigScreen(),
                ),
              );
              if (result != null && mounted) {
                final myApp = context.findAncestorStateOfType<MyAppState>();
                myApp?.updateConfig(result);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '✅ Конфигурация "${result.projectName}" загружена',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            tooltip: 'Загрузить конфигурацию',
          ),
          // Список конфигураций
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: () async {
              final result = await Navigator.push<ConfigModel>(
                context,
                MaterialPageRoute(
                  builder: (context) => ConfigListScreen(
                    onConfigSelected: (config) {
                      Navigator.pop(context, config);
                    },
                  ),
                ),
              );
              if (result != null && mounted) {
                final myApp = context.findAncestorStateOfType<MyAppState>();
                myApp?.updateConfig(result);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '✅ Конфигурация "${result.projectName}" загружена',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            tooltip: 'Список конфигураций',
          ),
          // Подключение
          IconButton(
            icon: const Icon(Icons.settings_ethernet),
            onPressed: () {
              Navigator.pushNamed(context, '/connection');
            },
            tooltip: 'Подключение',
          ),
          // // Обновить статус
          // IconButton(
          //   icon: const Icon(Icons.refresh),
          //   onPressed: () {
          //     _checkConnection();
          //     ScaffoldMessenger.of(context).showSnackBar(
          //       const SnackBar(
          //         content: Text('Статус обновлен'),
          //         duration: Duration(seconds: 1),
          //       ),
          //     );
          //   },
          //   tooltip: 'Обновить статус',
          // ),
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
                  Expanded(
                    child: Row(
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
                        Expanded(
                          child: Text(
                            _statusText,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _statusColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_connectionInfo.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '($_connectionInfo)',
                              style: TextStyle(
                                fontSize: 12,
                                color: themeProvider.isDarkMode
                                    ? Colors.grey[400]
                                    : Colors.grey,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      if (!isConnected)
                        Tooltip(
                          message: isRtu
                              ? rtuService.lastError
                              : modbus.lastError,
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
                        isConnected
                            ? (isRtu ? 'Подключено по USB' : 'Подключено')
                            : 'Требуется подключение',
                        style: TextStyle(
                          fontSize: 12,
                          color: isConnected ? Colors.green : Colors.orange,
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
                  // Кнопка "Настройки PIN-кода"
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
                      leading: const Text('🔐', style: TextStyle(fontSize: 32)),
                      title: Text(
                        'Настройки PIN-кода',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: themeProvider.isDarkMode
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                      subtitle: const Text(
                        'Установить или отключить PIN-код',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        color: themeProvider.isDarkMode
                            ? Colors.grey[400]
                            : Colors.grey,
                      ),
                      onTap: () async {
                        final pinService = PinService();
                        final isSet = await pinService.isPinSet();

                        if (isSet) {
                          // Если PIN установлен - предлагаем удалить
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Удалить PIN-код?'),
                              content: const Text(
                                'Вы уверены, что хотите отключить PIN-код?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Отмена'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text(
                                    'Удалить',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            await pinService.removePin();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('🔓 PIN-код удален'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          }
                        } else {
                          // Если PIN не установлен - переходим к установке
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PinScreen(
                                onSuccess: () {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('🔐 PIN-код установлен'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                },
                                isSettingPin: true,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  // Кнопка "Создать отчет"
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
                        isConnected ? 'Экспорт в PDF' : 'Требуется подключение',
                        style: TextStyle(
                          fontSize: 12,
                          color: isConnected ? Colors.green : Colors.orange,
                        ),
                      ),
                      trailing: Icon(
                        Icons.picture_as_pdf,
                        color: themeProvider.isDarkMode
                            ? Colors.grey[400]
                            : Colors.red,
                      ),
                      onTap: isConnected ? () => _createReport(context) : null,
                    ),
                  ),
                  // Кнопка "Тренды"
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
                      leading: const Text('📊', style: TextStyle(fontSize: 32)),
                      title: Text(
                        'Тренды',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: themeProvider.isDarkMode
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        isConnected
                            ? 'Графики датчиков'
                            : 'Требуется подключение',
                        style: TextStyle(
                          fontSize: 12,
                          color: isConnected ? Colors.green : Colors.orange,
                        ),
                      ),
                      trailing: Icon(
                        Icons.show_chart,
                        color: themeProvider.isDarkMode
                            ? Colors.grey[400]
                            : Colors.purple,
                      ),
                      onTap: isConnected
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const TrendsScreen(),
                                ),
                              );
                            }
                          : null,
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
    final rtuService = Provider.of<ModbusRtuService>(context, listen: false);
    final config = Provider.of<ConfigModel>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final bool isRtu = rtuService.connected;

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
              _buildDebugRow('Тип подключения', isRtu ? 'RTU (USB)' : 'TCP/IP'),
              _buildDebugRow(
                'Статус',
                isRtu
                    ? (rtuService.connected ? 'Подключено' : 'Не подключено')
                    : (modbus.connected ? 'Подключено' : 'Не подключено'),
              ),
              const Divider(),
              if (isRtu) ...[
                _buildDebugRow('Порт', rtuService.portName),
                _buildDebugRow('Скорость', '${rtuService.baudRate} bps'),
                _buildDebugRow('Slave ID', rtuService.slaveId.toString()),
              ] else ...[
                _buildDebugRow('IP', config.modbusServer.ip),
                _buildDebugRow('Порт', config.modbusServer.port.toString()),
                _buildDebugRow(
                  'Slave ID',
                  config.modbusServer.slaveId.toString(),
                ),
              ],
              _buildDebugRow('Таймаут', '${config.modbusServer.timeout}с'),
              const Divider(),
              _buildDebugRow('Систем', config.systems.length.toString()),
              _buildDebugRow(
                'Последняя ошибка',
                isRtu
                    ? (rtuService.lastError.isNotEmpty
                          ? rtuService.lastError
                          : 'Нет')
                    : (modbus.lastError.isNotEmpty ? modbus.lastError : 'Нет'),
              ),
              const Divider(),
              _buildDebugRow(
                'Размер кеша',
                isRtu
                    ? rtuService.registerCache.length.toString()
                    : modbus.registerCache.length.toString(),
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

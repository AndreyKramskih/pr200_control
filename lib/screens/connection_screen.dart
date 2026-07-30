import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/modbus_service.dart';
import '../models/config_model.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  // Контроллеры для полей ввода
  late TextEditingController ipController;
  late TextEditingController portController;
  late TextEditingController slaveIdController;
  late TextEditingController timeoutController;

  // Флаги загрузки для кнопок
  bool _isConnecting = false;
  bool _isPinging = false;

  @override
  void initState() {
    super.initState();

    // ✅ Получаем конфиг из провайдера
    final config = Provider.of<ConfigModel>(context, listen: false);

    // ✅ Инициализируем контроллеры с данными из конфига
    ipController = TextEditingController(text: config.modbusServer.ip);
    portController = TextEditingController(
      text: config.modbusServer.port.toString(),
    );
    slaveIdController = TextEditingController(
      text: config.modbusServer.slaveId.toString(),
    );
    timeoutController = TextEditingController(
      text: config.modbusServer.timeout.toString(),
    );
  }

  @override
  void dispose() {
    ipController.dispose();
    portController.dispose();
    slaveIdController.dispose();
    timeoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Получаем сервисы из провайдера
    final modbusService = Provider.of<ModbusService>(context);
    final config = Provider.of<ConfigModel>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки подключения'),
        centerTitle: true,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        actions: [
          // Кнопка "Сохранить в конфиг"
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Сохранить настройки в конфигурацию',
            onPressed: () {
              _saveSettingsToConfig(context, config);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ========== ИНДИКАТОР СТАТУСА ==========
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: modbusService.connected
                    ? Colors.green[50]
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: modbusService.connected
                      ? Colors.green
                      : Colors.grey[400]!,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    modbusService.connected
                        ? Icons.check_circle
                        : Icons.error_outline,
                    color: modbusService.connected
                        ? Colors.green
                        : Colors.grey[600],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          modbusService.connected
                              ? '✅ ПОДКЛЮЧЕНО'
                              : '❌ НЕТ ПОДКЛЮЧЕНИЯ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: modbusService.connected
                                ? Colors.green[800]
                                : Colors.grey[700],
                          ),
                        ),
                        if (modbusService.connected) ...[
                          const SizedBox(height: 4),
                          Text(
                            'IP: ${modbusService.ip}:${modbusService.port} | Slave ID: ${modbusService.slaveId}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                        if (!modbusService.connected &&
                            modbusService.lastError.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Ошибка: ${modbusService.lastError}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red[700],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Кнопка "Отключиться"
                  if (modbusService.connected)
                    IconButton(
                      icon: const Icon(Icons.link_off, color: Colors.red),
                      onPressed: () {
                        modbusService.disconnect();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🔌 Отключено от устройства'),
                            backgroundColor: Colors.grey,
                          ),
                        );
                      },
                      tooltip: 'Отключиться',
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ========== ИНФОРМАЦИЯ О КОНФИГЕ ==========
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      // ✅ Используем connection.name из ConfigModel
                      'Настройки загружены из конфигурации: ${config.connection.name}',
                      style: TextStyle(fontSize: 14, color: Colors.blue[800]),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ========== ПОЛЯ ВВОДА ==========
            const Text(
              'Параметры подключения',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // IP-адрес
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: 'IP-адрес',
                hintText: 'Например: 192.168.1.100',
                prefixIcon: Icon(Icons.dns),
              ),
            ),
            const SizedBox(height: 12),

            // Порт
            TextField(
              controller: portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Порт',
                hintText: 'По умолчанию: 502',
                prefixIcon: Icon(Icons.settings_ethernet),
              ),
            ),
            const SizedBox(height: 12),

            // Slave ID
            TextField(
              controller: slaveIdController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Slave ID',
                hintText: 'По умолчанию: 1',
                prefixIcon: Icon(Icons.numbers),
              ),
            ),
            const SizedBox(height: 12),

            // Таймаут
            TextField(
              controller: timeoutController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Таймаут (сек)',
                hintText: 'По умолчанию: 3',
                prefixIcon: Icon(Icons.timer),
              ),
            ),

            const SizedBox(height: 24),

            // ========== КНОПКИ ==========
            Row(
              children: [
                // Кнопка "ПОДКЛЮЧИТЬСЯ"
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isConnecting || _isPinging
                        ? null
                        : () async {
                            // Показываем загрузку
                            setState(() => _isConnecting = true);

                            // Пытаемся подключиться
                            final ip = ipController.text;
                            final port =
                                int.tryParse(portController.text) ?? 502;
                            final slaveId =
                                int.tryParse(slaveIdController.text) ?? 1;
                            final timeout =
                                int.tryParse(timeoutController.text) ?? 3;

                            final success = await modbusService.connect(
                              ip,
                              port: port,
                              slaveId: slaveId,
                              timeout: timeout,
                            );

                            setState(() => _isConnecting = false);

                            // Показываем результат
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ Подключено успешно'),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '❌ Ошибка: ${modbusService.lastError}',
                                  ),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: modbusService.connected
                          ? Colors.orange
                          : Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: _isConnecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            modbusService.connected
                                ? Icons.refresh
                                : Icons.link,
                          ),
                    label: Text(
                      _isConnecting
                          ? 'ПОДКЛЮЧЕНИЕ...'
                          : (modbusService.connected
                                ? 'ПЕРЕПОДКЛЮЧИТЬСЯ'
                                : 'ПОДКЛЮЧИТЬСЯ'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Кнопка "ПРОВЕРКА СВЯЗИ"
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isConnecting || _isPinging
                        ? null
                        : () async {
                            // Проверяем, есть ли подключение
                            if (!modbusService.connected) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '⚠️ Сначала подключитесь к устройству',
                                  ),
                                  backgroundColor: Colors.orange,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              return;
                            }

                            // Показываем загрузку
                            setState(() => _isPinging = true);

                            // Выполняем пинг
                            final isAlive = await modbusService.ping();

                            setState(() => _isPinging = false);

                            // Показываем результат
                            if (isAlive) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '✅ Устройство отвечает! Связь есть.',
                                  ),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '❌ Устройство не отвечает: ${modbusService.lastError}',
                                  ),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: _isPinging
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.network_check),
                    label: Text(
                      _isPinging ? 'ПРОВЕРКА...' : 'ПРОВЕРКА СВЯЗИ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ========== КНОПКА СОХРАНИТЬ В КОНФИГ ==========
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  _saveSettingsToConfig(context, config);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Colors.blue),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.save),
                label: const Text(
                  'СОХРАНИТЬ В КОНФИГУРАЦИЮ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========== МЕТОД СОХРАНЕНИЯ НАСТРОЕК В КОНФИГ ==========
  void _saveSettingsToConfig(BuildContext context, ConfigModel config) {
    // Получаем значения из полей
    final ip = ipController.text;
    final port = int.tryParse(portController.text) ?? 502;
    final slaveId = int.tryParse(slaveIdController.text) ?? 1;
    final timeout = int.tryParse(timeoutController.text) ?? 3;

    // Обновляем конфиг
    config.modbusServer.ip = ip;
    config.modbusServer.port = port;
    config.modbusServer.slaveId = slaveId;
    config.modbusServer.timeout = timeout;

    // Показываем уведомление
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Настройки сохранены в конфигурацию'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );

    // Опционально: можно вызвать метод сохранения в файл
    // Например: await ConfigManager.saveConfig(config);
  }
}

// lib/screens/load_config_screen.dart
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/config_model.dart';
import '../services/config_service.dart';
import '../services/config_manager.dart';

class LoadConfigScreen extends StatefulWidget {
  const LoadConfigScreen({super.key});

  @override
  State<LoadConfigScreen> createState() => _LoadConfigScreenState();
}

class _LoadConfigScreenState extends State<LoadConfigScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false;
  String _status = '';

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadConfigFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _status = '❌ Введите URL конфигурации';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _status = '⏳ Загрузка конфигурации...';
    });

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки: ${response.statusCode}');
      }

      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;

      if (!jsonData.containsKey('systems') ||
          !jsonData.containsKey('modbus_server')) {
        throw Exception('Неверный формат JSON: отсутствуют обязательные поля');
      }

      final config = ConfigModel.fromJson(jsonData);

      // Сохраняем в папку configs/
      final projectName = config.projectName.replaceAll(' ', '_');
      final fileName =
          '${projectName}_${DateTime.now().millisecondsSinceEpoch}.json';
      await ConfigManager.saveConfig(config, name: fileName);

      // Активируем как текущую
      await ConfigManager.setActiveConfig(fileName);

      // Сохраняем как config.json для обратной совместимости
      final configService = ConfigService();
      await configService.saveConfig(config);

      setState(() {
        _status = '✅ Конфигурация успешно загружена и сохранена!';
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Конфигурация "${config.projectName}" сохранена'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // ✅ Закрываем экран и возвращаем конфигурацию для обновления главного меню
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          Navigator.pop(context, config);
        }
      });
    } catch (e) {
      setState(() {
        _status = '❌ Ошибка: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Загрузка конфигурации'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Загрузите конфигурацию для вашего проекта',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Введите ссылку на JSON-конфигурацию',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),

            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        labelText: 'URL конфигурации',
                        hintText: 'https://example.com/project1.json',
                        prefixIcon: const Icon(Icons.link),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _loadConfigFromUrl,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download),
                      label: Text(_isLoading ? 'Загрузка...' : 'Загрузить'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            if (_status.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _status.contains('✅')
                      ? Colors.green[50]
                      : _status.contains('❌')
                      ? Colors.red[50]
                      : Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _status.contains('✅')
                        ? Colors.green
                        : _status.contains('❌')
                        ? Colors.red
                        : Colors.blue,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _status.contains('✅')
                          ? Icons.check_circle
                          : _status.contains('❌')
                          ? Icons.error
                          : Icons.info,
                      color: _status.contains('✅')
                          ? Colors.green
                          : _status.contains('❌')
                          ? Colors.red
                          : Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _status,
                        style: TextStyle(
                          color: _status.contains('✅')
                              ? Colors.green[800]
                              : _status.contains('❌')
                              ? Colors.red[800]
                              : Colors.blue[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💡 Как получить ссылку:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '1. Наведите камеру на QR код\n'
                    '2. Получите прямую ссылку на файл\n'
                    '3. Вставьте ссылку в это поле\n'
                    '4. Нажмите "Загрузить"',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

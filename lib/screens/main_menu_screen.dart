import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/modbus_service.dart';
import '../providers/theme_provider.dart';
// ✅ ДОБАВЛЯЕМ импорт для экрана логов
import '../screens/log_screen.dart';

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final modbusService = Provider.of<ModbusService>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PR200 Управление'),
        centerTitle: true,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Icon(
                  modbusService.connected ? Icons.wifi : Icons.wifi_off,
                  color: modbusService.connected ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  modbusService.connected ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: modbusService.connected ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
            ),
            onPressed: () {
              themeProvider.toggleTheme();
            },
            tooltip: 'Переключить тему',
          ),
        ],
        // ✅ ДОБАВЛЯЕМ bottom для версии с долгим нажатием
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ✅ Версия с долгим нажатием
                GestureDetector(
                  onLongPress: () {
                    // Переход на экран логов
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LogScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Версия 1.0.0',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // ========== СТАТУС ПОДКЛЮЧЕНИЯ ==========
            Card(
              color: modbusService.connected
                  ? Colors.green[50]
                  : Colors.grey[100],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      modbusService.connected
                          ? Icons.check_circle
                          : Icons.error_outline,
                      color: modbusService.connected
                          ? Colors.green
                          : Colors.red,
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            modbusService.connected
                                ? '✅ Устройство подключено'
                                : '❌ Нет подключения',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: modbusService.connected
                                  ? Colors.green[800]
                                  : Colors.red[800],
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
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ========== МЕНЮ ==========
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.2,
                children: [
                  _buildMenuItem(
                    context,
                    icon: Icons.settings_ethernet,
                    title: 'Подключение',
                    subtitle: 'Настройки связи',
                    color: Colors.blue,
                    onTap: () {
                      Navigator.pushNamed(context, '/connection');
                    },
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.folder_open,
                    title: 'Загрузка конфига',
                    subtitle: 'Выбор профиля',
                    color: Colors.orange,
                    onTap: () {
                      Navigator.pushNamed(context, '/load_config');
                    },
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.build,
                    title: 'Системы',
                    subtitle: 'Управление параметрами',
                    color: Colors.purple,
                    onTap: () {
                      // Здесь можно показать список систем или перейти на экран систем
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Функция в разработке'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.info_outline,
                    title: 'О программе',
                    subtitle: 'Версия 1.0.0',
                    color: Colors.teal,
                    onTap: () {
                      _showAboutDialog(context);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========== ВСПОМОГАТЕЛЬНЫЙ МЕТОД ДЛЯ СОЗДАНИЯ ПУНКТА МЕНЮ ==========
  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ========== ДИАЛОГ "О ПРОГРАММЕ" ==========
  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('О программе'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PR200 Управление'),
            SizedBox(height: 8),
            Text('Версия: 1.0.0', style: TextStyle(fontSize: 14)),
            SizedBox(height: 8),
            Text(
              'Приложение для управления устройством PR200 через протокол Modbus TCP/IP.',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 8),
            Text(
              '💡 Подсказка: удерживайте версию в заголовке для просмотра логов',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
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
}

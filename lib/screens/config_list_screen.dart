// lib/screens/config_list_screen.dart
import 'package:flutter/material.dart';
import '../services/config_manager.dart';
import '../models/config_model.dart';

class ConfigListScreen extends StatefulWidget {
  final Function(ConfigModel) onConfigSelected;

  const ConfigListScreen({super.key, required this.onConfigSelected});

  @override
  State<ConfigListScreen> createState() => _ConfigListScreenState();
}

class _ConfigListScreenState extends State<ConfigListScreen> {
  List<String> _configs = [];
  String? _activeConfig;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    setState(() => _isLoading = true);
    try {
      _configs = await ConfigManager.getConfigList();
      _activeConfig = await ConfigManager.getActiveConfig();

      if (_activeConfig != null && _configs.contains(_activeConfig)) {
        _configs.remove(_activeConfig);
        _configs.insert(0, _activeConfig!);
      }
    } catch (e) {
      // Игнорируем
    }
    setState(() => _isLoading = false);
  }

  Future<void> _selectConfig(String name) async {
    final config = await ConfigManager.loadConfig(name);
    if (config != null) {
      await ConfigManager.setActiveConfig(name);
      if (mounted) {
        // ✅ Возвращаем конфигурацию
        Navigator.pop(context, config);
      }
    }
  }

  Future<void> _deleteConfig(String name) async {
    if (name == _activeConfig) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Нельзя удалить активную конфигурацию'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить конфигурацию?'),
        content: Text('Вы уверены, что хотите удалить "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ConfigManager.deleteConfig(name);
      await _loadConfigs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Конфигурация "$name" удалена'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Конфигурации'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadConfigs,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [Colors.grey[900]!, Colors.grey[800]!]
                : [Colors.grey[50]!, Colors.grey[200]!],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _configs.isEmpty
            ? _buildEmptyState()
            : _buildConfigList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Нет сохранённых конфигураций',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            'Загрузите конфигурацию через URL',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _configs.length,
      itemBuilder: (context, index) {
        final name = _configs[index];
        final isActive = name == _activeConfig;

        return Card(
          elevation: isActive ? 4 : 1,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isActive
                ? const BorderSide(color: Colors.green, width: 2)
                : BorderSide.none,
          ),
          color: isActive
              ? (isDark ? Colors.green[900] : Colors.green[50])
              : (isDark ? Colors.grey[850] : Colors.white),
          child: ListTile(
            leading: Icon(
              isActive ? Icons.check_circle : Icons.description,
              color: isActive ? Colors.green : Colors.grey,
            ),
            title: Text(
              name.replaceAll('.json', ''),
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            subtitle: Text(
              isActive ? '✅ Активна' : 'Нажмите для активации',
              style: TextStyle(
                fontSize: 12,
                color: isActive ? Colors.green : Colors.grey,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isActive)
                  IconButton(
                    icon: Icon(Icons.check, color: Colors.green),
                    onPressed: () => _selectConfig(name),
                    tooltip: 'Активировать',
                  ),
                if (!isActive)
                  IconButton(
                    icon: Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteConfig(name),
                    tooltip: 'Удалить',
                  ),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'АКТИВНА',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            onTap: () => _selectConfig(name),
          ),
        );
      },
    );
  }
}

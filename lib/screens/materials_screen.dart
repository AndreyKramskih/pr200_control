// lib/screens/materials_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../models/config_model.dart';
import '../services/config_service.dart';
import '../services/config_manager.dart';
import '../services/logger_service.dart';
import '../core/utils/theme_utils.dart';
import 'package:android_intent_plus/android_intent.dart';

class MaterialsScreen extends StatefulWidget {
  const MaterialsScreen({super.key});

  @override
  State<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends State<MaterialsScreen> {
  List<File> _files = [];
  bool _isLoading = false;
  String? _error;

  static const List<String> _allowedExtensions = [
    '.pdf',
    '.docx',
    '.doc',
    '.xlsx',
    '.xls',
    '.png',
    '.jpg',
    '.jpeg',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFiles());
  }

  ConfigModel get _config => Provider.of<ConfigModel>(context, listen: false);

  // ✅ ПРОВЕРКА И ЗАПРОС РАЗРЕШЕНИЯ
  Future<bool> _ensureStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Уже разрешено?
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }

    // Показываем диалог с объяснением
    if (!mounted) return false;
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Нужен доступ к файлам'),
        content: const Text(
          'Чтобы приложение могло показывать документы, '
          'разрешите доступ ко всем файлам.\n\n'
          'Нажмите «Открыть настройки», найдите в списке PR200 '
          'и включите переключатель «Доступ ко всем файлам».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Открыть настройки'),
          ),
        ],
      ),
    );

    if (open == true) {
      // Открываем системный экран «Доступ ко всем файлам»
      final intent = AndroidIntent(
        action: 'android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION',
        data: 'package:com.example.pr200_control',
      );
      try {
        await intent.launch();
      } catch (e) {
        LoggerService().log(
          '⚠️ Не удалось открыть настройки: $e',
          level: LogLevel.warning,
        );
        // Fallback — откроем общие настройки приложения
        await openAppSettings();
      }
    }

    return false;
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _files = [];
    });

    // ✅ Проверяем разрешение
    final hasPermission = await _ensureStoragePermission();
    if (!hasPermission) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Нет доступа к файлам.\nРазрешите доступ в настройках.';
      });
      return;
    }

    final path = _config.materialsPath;
    if (path == null || path.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = null;
      });
      return;
    }

    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        setState(() {
          _isLoading = false;
          _error = 'Папка не найдена:\n$path';
        });
        return;
      }

      // ✅ Отладочный вывод
      final all = await dir.list().toList();
      LoggerService().log('📂 Папка $path содержит ${all.length} элементов');
      for (final e in all) {
        LoggerService().log('   → ${e.path} (${e is File ? "файл" : "папка"})');
      }

      final filtered = all.whereType<File>().where((e) {
        final lower = e.path.toLowerCase();
        return _allowedExtensions.any((ext) => lower.endsWith(ext));
      }).toList();

      filtered.sort(
        (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
      );

      if (!mounted) return;
      setState(() {
        _files = filtered;
        _isLoading = false;
      });
      LoggerService().log('✅ Загружено ${filtered.length} файлов');
    } catch (e) {
      LoggerService().log('❌ Ошибка чтения папки: $e', level: LogLevel.error);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Ошибка чтения папки:\n$e';
      });
    }
  }

  Future<void> _pickFolder() async {
    // ✅ Проверяем разрешение ПЕРЕД выбором папки
    final hasPermission = await _ensureStoragePermission();
    if (!hasPermission) return;

    try {
      final selected = await getDirectoryPath();
      if (selected == null || selected.isEmpty) return;

      _config.materialsPath = selected;
      LoggerService().log('📁 Выбрана папка: $selected');

      await _saveConfigPath();
      await _loadFiles();
    } catch (e) {
      LoggerService().log('❌ Ошибка выбора папки: $e', level: LogLevel.error);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка выбора папки: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveConfigPath() async {
    try {
      final configService = ConfigService();
      await configService.saveConfig(_config);

      final activeName = await ConfigManager.getActiveConfig();
      if (activeName != null) {
        await ConfigManager.saveConfig(_config, name: activeName);
        LoggerService().log(
          '✅ Путь к материалам сохранён в активный конфиг: $activeName',
        );
      } else {
        final fileName =
            '${_config.projectName.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.json';
        await ConfigManager.saveConfig(_config, name: fileName);
        await ConfigManager.setActiveConfig(fileName);
        LoggerService().log('✅ Создан новый активный конфиг: $fileName');
      }
    } catch (e) {
      LoggerService().log(
        '⚠️ Не удалось сохранить путь: $e',
        level: LogLevel.warning,
      );
    }
  }

  Future<void> _openFile(File file) async {
    try {
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorText(result)),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      LoggerService().log('❌ Ошибка открытия: $e', level: LogLevel.error);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка открытия: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _errorText(OpenResult result) {
    switch (result.type) {
      case ResultType.noAppToOpen:
        return 'Нет приложения для открытия этого файла. '
            'Установите PDF-просмотрщик или Microsoft Office.';
      case ResultType.fileNotFound:
        return 'Файл не найден.';
      case ResultType.permissionDenied:
        return 'Нет доступа к файлу.';
      default:
        return 'Не удалось открыть файл';
    }
  }

  IconData _iconForFile(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (lower.endsWith('.docx') || lower.endsWith('.doc')) {
      return Icons.description;
    }
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      return Icons.table_chart;
    }
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg')) {
      return Icons.image;
    }
    return Icons.insert_drive_file;
  }

  Color _colorForFile(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) return Colors.red;
    if (lower.endsWith('.docx') || lower.endsWith('.doc')) {
      return Colors.blue;
    }
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      return Colors.green;
    }
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg')) {
      return Colors.purple;
    }
    return Colors.grey;
  }

  String _displayName(String path) {
    final parts = path.split(Platform.pathSeparator);
    return parts.isNotEmpty ? parts.last : path;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeUtils.isDark(context);
    final path = _config.materialsPath;
    final hasPath = path != null && path.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('📁 Документы проекта'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFiles,
            tooltip: 'Обновить',
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _pickFolder,
            tooltip: hasPath ? 'Выбрать другую папку' : 'Выбрать папку',
          ),
        ],
      ),
      body: Container(
        color: ThemeUtils.scaffoldColor(context),
        child: Column(
          children: [
            if (hasPath)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                color: isDark ? Colors.grey[850] : Colors.grey[200],
                child: Row(
                  children: [
                    Icon(
                      Icons.folder,
                      size: 16,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        path,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(child: _buildContent(isDark, hasPath)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark, bool hasPath) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!hasPath) {
      return _buildEmptyState(
        isDark,
        icon: Icons.folder_open,
        title: 'Папка с документами не выбрана',
        subtitle: 'Выберите папку со схемами, спецификациями и инструкциями.',
        buttonLabel: 'Выбрать папку',
        buttonIcon: Icons.folder_open,
        onPressed: _pickFolder,
      );
    }

    if (_error != null) {
      return _buildEmptyState(
        isDark,
        icon: Icons.folder_off,
        title: _error!,
        subtitle: null,
        buttonLabel: 'Повторить',
        buttonIcon: Icons.refresh,
        onPressed: _loadFiles,
      );
    }

    if (_files.isEmpty) {
      return _buildEmptyState(
        isDark,
        icon: Icons.inbox,
        title: 'В папке нет документов',
        subtitle: 'Поддерживаются: PDF, DOCX, XLSX, PNG, JPG',
        buttonLabel: 'Обновить',
        buttonIcon: Icons.refresh,
        onPressed: _loadFiles,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFiles,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _files.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final file = _files[index];
          final name = _displayName(file.path);
          final icon = _iconForFile(file.path);
          final color = _colorForFile(file.path);

          return Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            color: ThemeUtils.cardColor(context),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color),
              ),
              title: Text(
                name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: ThemeUtils.textColor(context),
                ),
              ),
              trailing: Icon(
                Icons.open_in_new,
                color: isDark ? Colors.grey[500] : Colors.grey[400],
                size: 20,
              ),
              onTap: () => _openFile(file),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(
    bool isDark, {
    required IconData icon,
    required String title,
    required String? subtitle,
    required String buttonLabel,
    required IconData buttonIcon,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey[500] : Colors.grey[500],
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(buttonIcon),
              label: Text(buttonLabel),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

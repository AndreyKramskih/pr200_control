import 'package:flutter/material.dart';
import '../services/logger_service.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final ScrollController _scrollController = ScrollController();
  List<LogEntry> _logs = [];
  LogLevel _filterLevel = LogLevel.debug;
  bool _autoScroll = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final logger = LoggerService();
    _logs = logger.logs;

    logger.addListener(_onLogsUpdate);
  }

  @override
  void dispose() {
    LoggerService().removeListener(_onLogsUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogsUpdate(List<LogEntry> logs) {
    setState(() {
      _logs = logs;
    });

    if (_autoScroll && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  List<LogEntry> get _filteredLogs {
    return _logs
        .where((log) => log.level.index >= _filterLevel.index)
        .where(
          (log) =>
              _searchQuery.isEmpty ||
              log.message.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }

  String _getLevelIcon(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return '🔍';
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filteredLogs = _filteredLogs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Логи приложения'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<LogLevel>(
            icon: const Icon(Icons.filter_list),
            onSelected: (level) {
              setState(() {
                _filterLevel = level;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: LogLevel.debug,
                child: Row(
                  children: [Text('🔍'), SizedBox(width: 8), Text('Все')],
                ),
              ),
              const PopupMenuItem(
                value: LogLevel.info,
                child: Row(
                  children: [Text('ℹ️'), SizedBox(width: 8), Text('Инфо+')],
                ),
              ),
              const PopupMenuItem(
                value: LogLevel.warning,
                child: Row(
                  children: [
                    Text('⚠️'),
                    SizedBox(width: 8),
                    Text('Предупреждения+'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: LogLevel.error,
                child: Row(
                  children: [
                    Text('❌'),
                    SizedBox(width: 8),
                    Text('Только ошибки'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: Icon(
              _autoScroll
                  ? Icons.vertical_align_bottom
                  : Icons.vertical_align_top,
            ),
            onPressed: () {
              setState(() {
                _autoScroll = !_autoScroll;
              });
            },
            tooltip: _autoScroll ? 'Автоскролл включен' : 'Автоскролл выключен',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () {
              _showClearDialog(context);
            },
            tooltip: 'Очистить логи',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              _exportLogs(context);
            },
            tooltip: 'Экспорт логов',
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
        child: Column(
          children: [
            // Поиск
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Поиск по логам...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      hintStyle: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
              ),
            ),
            // Информация
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Всего: ${_logs.length} записей',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  Text(
                    'Показано: ${filteredLogs.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            // Список логов
            Expanded(
              child: filteredLogs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inbox,
                            size: 64,
                            color: isDark ? Colors.grey[600] : Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'Ничего не найдено'
                                : 'Логов пока нет',
                            style: TextStyle(
                              fontSize: 16,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                          if (_searchQuery.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Попробуйте изменить поисковый запрос',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.grey[500]
                                    : Colors.grey[400],
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: filteredLogs.length,
                      itemBuilder: (context, index) {
                        final log = filteredLogs[index];
                        final levelColor = _getLevelColor(log.level);

                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[850] : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border(
                              left: BorderSide(color: levelColor, width: 4),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _getLevelIcon(log.level),
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        log.message,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${log.timestamp.toString().substring(0, 19)}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isDark
                                              ? Colors.grey[500]
                                              : Colors.grey[400],
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить логи?'),
        content: const Text('Все логи будут удалены. Вы уверены?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              await LoggerService().clearLogs();
              Navigator.pop(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Логи очищены'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
  }

  void _exportLogs(BuildContext context) async {
    try {
      final file = await LoggerService().exportLogs();
      if (file != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Логи сохранены: ${file.path}'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка экспорта логов'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

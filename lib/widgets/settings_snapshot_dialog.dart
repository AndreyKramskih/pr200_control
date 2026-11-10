// lib/widgets/settings_snapshot_dialog.dart
import 'package:flutter/material.dart';
import '../services/settings_snapshot_service.dart';

/// Диалог сохранения снимка (в общий пул).
Future<String?> showSaveSnapshotDialog(
  BuildContext context, {
  required String projectName,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _SaveSnapshotDialog(projectName: projectName),
  );
}

class _SaveSnapshotDialog extends StatefulWidget {
  final String projectName;
  const _SaveSnapshotDialog({required this.projectName});

  @override
  State<_SaveSnapshotDialog> createState() => _SaveSnapshotDialogState();
}

class _SaveSnapshotDialogState extends State<_SaveSnapshotDialog> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: 'Снимок ${DateTime.now().toString().substring(0, 16)}',
    );
    // Запрашиваем фокус после первого кадра, чтобы клавиатура
    // открывалась уже с нужным типом.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Сохранить настройки в память'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Проект: ${widget.projectName}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Снимок сохраняется в общий список. Его можно будет '
              'применить на любом объекте с такой же программой ПЛК.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: false,
              keyboardType: TextInputType
                  .multiline, // ✅ даёт текстовую клавиатуру на Android
              maxLines: 1,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              enableSuggestions: true,
              autocorrect: false,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Имя снимка',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Сохранить')),
      ],
    );
  }
}

/// Диалог выбора снимка (все снимки, из любых проектов).
/// Внутри можно удалять снимки.
Future<MapEntry<String, Map<String, dynamic>>?> showLoadSnapshotDialog(
  BuildContext context,
) async {
  return showDialog<MapEntry<String, Map<String, dynamic>>>(
    context: context,
    builder: (_) => const _LoadSnapshotDialog(),
  );
}

class _LoadSnapshotDialog extends StatefulWidget {
  const _LoadSnapshotDialog();

  @override
  State<_LoadSnapshotDialog> createState() => _LoadSnapshotDialogState();
}

class _LoadSnapshotDialogState extends State<_LoadSnapshotDialog> {
  bool _loading = true;
  Map<String, Map<String, String>> _snapshots = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final data = await SettingsSnapshotService.listSnapshots();
    if (!mounted) return;
    setState(() {
      _snapshots = data;
      _loading = false;
    });
  }

  Future<void> _selectSnapshot(String name) async {
    final values = await SettingsSnapshotService.loadSnapshot(
      snapshotName: name,
    );
    if (!mounted) return;
    if (values == null) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context, MapEntry(name, values));
  }

  Future<void> _confirmDelete(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить снимок?'),
        content: Text('Снимок «$name» будет удалён безвозвратно.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await SettingsSnapshotService.deleteSnapshot(name);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_snapshots.isEmpty) {
      return AlertDialog(
        title: const Text('Загрузить настройки из памяти'),
        content: const Text('Снимков пока нет.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      );
    }

    final names = _snapshots.keys.toList()..sort();

    return SimpleDialog(
      title: const Text('Загрузить настройки из памяти'),
      children: [
        ...names.map((name) {
          final meta = _snapshots[name]!;
          final project = meta['projectName'] ?? '';
          final savedAt = meta['saved_at'] ?? '';
          final shortDate = savedAt.length >= 16
              ? savedAt.substring(0, 16).replaceAll('T', ' ')
              : savedAt;

          return SimpleDialogOption(
            onPressed: () => _selectSnapshot(name),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.history, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      if (project.isNotEmpty || shortDate.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            [
                              if (project.isNotEmpty) 'Проект: $project',
                              if (shortDate.isNotEmpty) shortDate,
                            ].join(' • '),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 20,
                  ),
                  tooltip: 'Удалить',
                  onPressed: () => _confirmDelete(name),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

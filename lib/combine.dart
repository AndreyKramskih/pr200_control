import 'dart:io';

void main() async {
  // Находим корневую директорию проекта (на один уровень выше папки lib)
  final projectRoot = Directory.current.path;
  final libDir = Directory('$projectRoot/lib');
  final outputFile = File('$projectRoot/flutter_code_all.txt');

  if (!await libDir.exists()) {
    print('Ошибка: Папка lib не найдена в текущей директории.');
    return;
  }

  final sink = outputFile.openWrite();

  try {
    // Рекурсивно обходим все файлы в папке lib
    await for (final entity in libDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        // Пропускаем сам файл скрипта, чтобы он не дублировал себя в отчете
        if (entity.path.endsWith('combine.dart')) continue;

        // Получаем относительный путь для красивого заголовка
        final relativePath = entity.path.replaceFirst('$projectRoot/', '');

        sink.write('\n\n=== FILE: $relativePath ===\n\n');

        try {
          final content = await entity.readAsString();
          sink.write(content);
        } catch (e) {
          sink.write('[Ошибка чтения файла: $e]');
        }
      }
    }
    print('Готово! Все файлы объединены в: ${outputFile.path}');
  } finally {
    await sink.close();
  }
}

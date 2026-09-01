import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportService {
  static final ReportService _instance = ReportService._internal();
  factory ReportService() => _instance;
  ReportService._internal();

  pw.Font? _font;

  Future<void> _loadFont() async {
    if (_font != null) return;
    try {
      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      _font = pw.Font.ttf(fontData);
      print('✅ Шрифт Roboto загружен');
    } catch (e) {
      print('⚠️ Ошибка загрузки шрифта: $e');
      _font = null;
    }
  }

  Future<void> generateAndShareReport({
    required String projectName,
    required String ip,
    required int port,
    required int slaveId,
    required Map<String, Map<String, dynamic>> systemData,
    required Map<String, String> systemNames, // ✅ НОВЫЙ ПАРАМЕТР
    required DateTime reportTime,
  }) async {
    print('📄 Генерация отчета...');
    print('📊 Количество систем: ${systemData.length}');

    if (systemData.isEmpty) {
      print('❌ Нет данных для отчета');
      return;
    }

    await _loadFont();

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return _buildFirstPage(
            projectName: projectName,
            ip: ip,
            port: port,
            slaveId: slaveId,
            systemData: systemData,
            systemNames: systemNames,
            reportTime: reportTime,
          );
        },
      ),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return _buildSecondPage(
            projectName: projectName,
            systemData: systemData,
            systemNames: systemNames,
          );
        },
      ),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return _buildThirdPage(
            projectName: projectName,
            systemData: systemData,
            systemNames: systemNames,
          );
        },
      ),
    );

    final dateStr =
        '${reportTime.year}-${reportTime.month.toString().padLeft(2, '0')}-${reportTime.day.toString().padLeft(2, '0')}_${reportTime.hour.toString().padLeft(2, '0')}-${reportTime.minute.toString().padLeft(2, '0')}';

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Отчет_ИТП_$dateStr.pdf',
    );

    print('✅ Отчет отправлен');
  }

  // ==================== СТРАНИЦА 1 ====================
  pw.Widget _buildFirstPage({
    required String projectName,
    required String ip,
    required int port,
    required int slaveId,
    required Map<String, Map<String, dynamic>> systemData,
    required Map<String, String> systemNames,
    required DateTime reportTime,
  }) {
    final children = <pw.Widget>[];

    // ===== ЗАГОЛОВОК =====
    children.add(
      pw.Container(
        padding: const pw.EdgeInsets.all(20),
        color: PdfColors.blue,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'ОТЧЕТ ПО ИТП',
              style: pw.TextStyle(
                fontSize: 28,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                font: _font,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              projectName,
              style: pw.TextStyle(
                fontSize: 18,
                color: PdfColors.white,
                font: _font,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Дата формирования: ${_formatDateTime(reportTime)}',
              style: pw.TextStyle(
                fontSize: 12,
                color: PdfColors.white,
                font: _font,
              ),
            ),
          ],
        ),
      ),
    );

    children.add(pw.SizedBox(height: 16));

    // ===== ИНФОРМАЦИЯ О ПОДКЛЮЧЕНИИ =====
    children.add(
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(8),
          color: PdfColors.grey100,
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'ИНФОРМАЦИЯ О ПОДКЛЮЧЕНИИ',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue,
                font: _font,
              ),
            ),
            pw.SizedBox(height: 8),
            _buildInfoRow('IP адрес', ip),
            _buildInfoRow('Порт', port.toString()),
            _buildInfoRow('Slave ID', slaveId.toString()),
          ],
        ),
      ),
    );

    children.add(pw.SizedBox(height: 16));

    // ===== ПАРАМЕТРЫ СИСТЕМ =====
    children.add(
      pw.Text(
        'ПАРАМЕТРЫ СИСТЕМ',
        style: pw.TextStyle(
          fontSize: 16,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.blue,
          font: _font,
        ),
      ),
    );
    children.add(pw.Divider(color: PdfColors.blue, height: 2));
    children.add(pw.SizedBox(height: 8));

    // ✅ Только первая система на первой странице
    if (systemData.isNotEmpty) {
      final firstSystem = systemData.entries.first;
      final systemId = firstSystem.key;
      final systemName = systemNames[systemId] ?? systemId; // ✅ Берем название
      children.addAll(
        _buildSystemBlock(systemName, firstSystem.value, maxItems: 25),
      );
    }

    if (systemData.length > 1) {
      children.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12),
          child: pw.Text(
            '... продолжение на следующей странице',
            style: pw.TextStyle(
              fontSize: 12,
              color: PdfColors.grey,
              font: _font,
            ),
          ),
        ),
      );
    }

    children.add(pw.SizedBox(height: 16));

    children.add(
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Text(
          'Страница 1/3',
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey, font: _font),
          textAlign: pw.TextAlign.center,
        ),
      ),
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: children,
    );
  }

  // ==================== СТРАНИЦА 2 ====================
  pw.Widget _buildSecondPage({
    required String projectName,
    required Map<String, Map<String, dynamic>> systemData,
    required Map<String, String> systemNames,
  }) {
    final children = <pw.Widget>[];

    children.add(
      pw.Container(
        padding: const pw.EdgeInsets.all(16),
        color: PdfColors.blue,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'ПРОДОЛЖЕНИЕ ОТЧЕТА',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                font: _font,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              projectName,
              style: pw.TextStyle(
                fontSize: 14,
                color: PdfColors.white,
                font: _font,
              ),
            ),
          ],
        ),
      ),
    );

    children.add(pw.SizedBox(height: 16));

    // ===== ОСТАЛЬНЫЕ ПАРАМЕТРЫ =====
    int systemCount = 0;
    for (var entry in systemData.entries) {
      systemCount++;
      final systemId = entry.key;
      final systemName = systemNames[systemId] ?? systemId; // ✅ Берем название

      if (systemCount == 1) {
        final remainingParams = entry.value.entries.skip(25).toList();
        if (remainingParams.isNotEmpty) {
          final remainingData = Map.fromEntries(remainingParams);
          children.addAll(
            _buildSystemBlock(
              '$systemName (продолжение)',
              remainingData,
              maxItems: 999,
            ),
          );
        }
      } else {
        children.addAll(
          _buildSystemBlock(systemName, entry.value, maxItems: 999),
        );
      }
    }

    children.add(pw.SizedBox(height: 16));

    children.add(
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Text(
          'Страница 2/3',
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey, font: _font),
          textAlign: pw.TextAlign.center,
        ),
      ),
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: children,
    );
  }

  /// СТРАНИЦА 3: Третья система
  pw.Widget _buildThirdPage({
    required String projectName,
    required Map<String, Map<String, dynamic>> systemData,
    required Map<String, String> systemNames,
  }) {
    final children = <pw.Widget>[];

    // --- Заголовок ---
    children.add(
      pw.Container(
        padding: const pw.EdgeInsets.all(16),
        color: PdfColors.blue,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'ПРОДОЛЖЕНИЕ ОТЧЕТА',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                font: _font,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              projectName,
              style: pw.TextStyle(
                fontSize: 14,
                color: PdfColors.white,
                font: _font,
              ),
            ),
          ],
        ),
      ),
    );

    children.add(pw.SizedBox(height: 16));

    // --- Остальные параметры ---
    int systemCount = 0;
    for (var entry in systemData.entries) {
      systemCount++;
      final systemId = entry.key;
      final systemName = systemNames[systemId] ?? systemId;

      // Пропускаем первые две системы (они уже на страницах 1 и 2)
      if (systemCount <= 2) continue;

      // Показываем только третью систему (или больше, если их вдруг окажется > 3)
      final params = entry.value;
      children.addAll(_buildSystemBlock(systemName, params, maxItems: 999));
    }

    // Если по какой-то причине третьей системы нет — показываем сообщение
    if (systemData.length < 3) {
      children.add(
        pw.Padding(
          padding: const pw.EdgeInsets.all(20),
          child: pw.Text(
            'Нет данных для отображения',
            style: pw.TextStyle(
              fontSize: 14,
              color: PdfColors.grey,
              font: _font,
            ),
          ),
        ),
      );
    }

    children.add(pw.SizedBox(height: 16));

    // --- Подвал ---
    children.add(
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Text(
          'Страница 3/3 • Окончание отчета',
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey, font: _font),
          textAlign: pw.TextAlign.center,
        ),
      ),
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: children,
    );
  }

  // ==================== БЛОК СИСТЕМЫ ====================
  List<pw.Widget> _buildSystemBlock(
    String systemName,
    Map<String, dynamic> data, {
    int maxItems = 999,
  }) {
    final widgets = <pw.Widget>[];

    if (data.isEmpty) {
      widgets.add(
        pw.Text(
          'Система: $systemName - нет данных',
          style: pw.TextStyle(fontSize: 14, color: PdfColors.grey, font: _font),
        ),
      );
      return widgets;
    }

    widgets.add(pw.SizedBox(height: 12));
    widgets.add(
      pw.Text(
        'Система: $systemName (${data.length} параметров)',
        style: pw.TextStyle(
          fontSize: 16,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.blue,
          font: _font,
        ),
      ),
    );
    widgets.add(pw.SizedBox(height: 6));
    widgets.add(pw.Divider(color: PdfColors.grey300, height: 1));
    widgets.add(pw.SizedBox(height: 4));

    int count = 0;
    for (var entry in data.entries) {
      if (count >= maxItems) break;
      final name = entry.key;
      final value = entry.value;
      count++;

      String displayValue;
      String unit = '';

      if (value is Map<String, dynamic>) {
        displayValue = _formatValue(value);
        unit = value['unit'] ?? '';
      } else if (value is Map) {
        displayValue = _formatValue(value.cast<String, dynamic>());
        unit = value['unit'] ?? '';
      } else {
        displayValue = value.toString();
      }

      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 200,
                child: pw.Text(
                  name,
                  style: pw.TextStyle(fontSize: 11, font: _font),
                ),
              ),
              pw.Text(':', style: pw.TextStyle(fontSize: 11, font: _font)),
              pw.SizedBox(width: 8),
              pw.Text(
                displayValue,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  font: _font,
                ),
              ),
              if (unit.isNotEmpty && !_isBitValue(value)) ...[
                pw.SizedBox(width: 4),
                pw.Text(
                  unit,
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey,
                    font: _font,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    print('  ✅ Добавлено $count параметров в систему $systemName');

    return widgets;
  }

  // ==================== ФОРМАТИРОВАНИЕ ЗНАЧЕНИЯ ====================
  String _formatValue(Map<String, dynamic> value) {
    final raw = value['value'];
    final bit = value['bit'];
    final states = value['states'];

    if (bit != null && states != null && states is List && states.length == 2) {
      if (raw is int) {
        final isSet = (raw & (1 << bit)) != 0;
        return isSet ? states[1].toString() : states[0].toString();
      }
    }

    if (bit != null && raw is int) {
      final isSet = (raw & (1 << bit)) != 0;
      return isSet ? 'Включено' : 'Выключено';
    }

    if (raw == null) return '--';
    if (raw is double) {
      return raw.toStringAsFixed(1);
    }
    return raw.toString();
  }

  // ==================== ПРОВЕРКА БИТОВОГО ЗНАЧЕНИЯ ====================
  bool _isBitValue(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value.containsKey('bit') ||
          (value.containsKey('states') && value['states'] is List);
    }
    if (value is Map) {
      return value.containsKey('bit') ||
          (value.containsKey('states') && value['states'] is List);
    }
    return false;
  }

  // ==================== ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ====================

  pw.Widget _buildInfoRow(String label, String value) {
    return pw.Row(
      children: [
        pw.SizedBox(
          width: 100,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 12,
              color: PdfColors.grey,
              font: _font,
            ),
          ),
        ),
        pw.Text(': $value', style: pw.TextStyle(fontSize: 12, font: _font)),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

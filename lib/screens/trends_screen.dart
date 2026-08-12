import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../models/config_model.dart';
import '../services/modbus_manager.dart';
import '../services/modbus_service.dart';
import '../services/modbus_rtu_service.dart';
import '../models/trend_data.dart';
import '../services/logger_service.dart';

class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key});

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  List<TrendSeries> _series = [];
  Timer? _timer;
  bool _isCollecting = false;
  bool _connected = false;
  String _connectionType = 'none'; // 'tcp', 'rtu', 'none'

  @override
  void initState() {
    super.initState();
    _loadSensors();
    _checkConnection();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ✅ Определяем тип подключения по активным сервисам
  String _getConnectionType() {
    try {
      final rtuService = Provider.of<ModbusRtuService>(context, listen: false);
      if (rtuService.connected) {
        return 'rtu';
      }
    } catch (e) {
      // RTU сервис не зарегистрирован
    }

    try {
      final modbus = Provider.of<ModbusService>(context, listen: false);
      if (modbus.connected) {
        return 'tcp';
      }
    } catch (e) {
      // TCP сервис не зарегистрирован
    }

    return 'none';
  }

  void _checkConnection() {
    final modbusManager = ModbusManager(context);

    setState(() {
      _connected = modbusManager.connected;
      _connectionType = _getConnectionType();
    });
  }

  void _loadSensors() {
    final config = Provider.of<ConfigModel>(context, listen: false);
    final sensors = <TrendSeries>[];

    for (var systemEntry in config.systems.entries) {
      final system = systemEntry.value;

      for (var submenuEntry in system.submenus.entries) {
        final submenu = submenuEntry.value;

        if (submenu.type != 'sensors') {
          continue;
        }

        if (submenu.items != null) {
          for (var item in submenu.items!) {
            if ((item.type == 'float' || item.type == 'int') &&
                item.bit == null) {
              sensors.add(
                TrendSeries(
                  name: item.name,
                  unit: item.unit ?? '',
                  points: [],
                  isActive: false,
                ),
              );
            }
          }
        }

        if (submenu.groups != null) {
          for (var group in submenu.groups!) {
            for (var item in group.items) {
              if ((item.type == 'float' || item.type == 'int') &&
                  item.bit == null) {
                sensors.add(
                  TrendSeries(
                    name: item.name,
                    unit: item.unit ?? '',
                    points: [],
                    isActive: false,
                  ),
                );
              }
            }
          }
        }
      }
    }

    setState(() {
      _series = sensors;
    });

    LoggerService().log('📊 Загружено ${sensors.length} датчиков для тренда');
  }

  void _toggleCollection() {
    if (_isCollecting) {
      _timer?.cancel();
      setState(() {
        _isCollecting = false;
      });
      LoggerService().log('⏹️ Сбор данных остановлен');
    } else {
      final activeCount = _series.where((s) => s.isActive).length;
      if (activeCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Выберите хотя бы один датчик'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final modbusManager = ModbusManager(context);
      if (!modbusManager.connected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нет подключения к оборудованию'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _collectData();
      });

      setState(() {
        _isCollecting = true;
      });
      LoggerService().log('▶️ Сбор данных запущен (${activeCount} датчиков)');
    }
  }

  Future<void> _collectData() async {
    final modbusManager = ModbusManager(context);

    if (!modbusManager.connected) {
      _timer?.cancel();
      setState(() {
        _isCollecting = false;
        _connected = false;
        _connectionType = 'none';
      });
      LoggerService().log(
        '⚠️ Сбор остановлен: нет подключения',
        level: LogLevel.warning,
      );
      return;
    }

    final now = DateTime.now();
    final newSeries = <TrendSeries>[];

    for (var series in _series) {
      if (!series.isActive) {
        newSeries.add(series);
        continue;
      }

      try {
        final value = await _readSensorValue(series.name, modbusManager);

        if (value != null && value.isFinite) {
          final newPoints = List<TrendPoint>.from(series.points);
          newPoints.add(TrendPoint(timestamp: now, value: value));

          if (newPoints.length > TrendSeries.maxPoints) {
            newPoints.removeAt(0);
          }

          newSeries.add(series.copyWith(points: newPoints));
        } else {
          newSeries.add(series);
        }
      } catch (e) {
        LoggerService().log(
          '❌ Ошибка чтения ${series.name}: $e',
          level: LogLevel.error,
        );
        newSeries.add(series);
      }
    }

    setState(() {
      _series = newSeries;
    });
  }

  Future<double?> _readSensorValue(
    String sensorName,
    ModbusManager modbusManager,
  ) async {
    final config = Provider.of<ConfigModel>(context, listen: false);

    for (var systemEntry in config.systems.entries) {
      final system = systemEntry.value;

      for (var submenuEntry in system.submenus.entries) {
        final submenu = submenuEntry.value;

        if (submenu.items != null) {
          for (var item in submenu.items!) {
            if (item.name == sensorName) {
              final result = await modbusManager.readParameterValue(item);
              if (result != null) {
                final doubleValue = result is double
                    ? result
                    : (result as num).toDouble();
                return doubleValue.isFinite ? doubleValue : null;
              }
              return null;
            }
          }
        }

        if (submenu.groups != null) {
          for (var group in submenu.groups!) {
            for (var item in group.items) {
              if (item.name == sensorName) {
                final result = await modbusManager.readParameterValue(item);
                if (result != null) {
                  final doubleValue = result is double
                      ? result
                      : (result as num).toDouble();
                  return doubleValue.isFinite ? doubleValue : null;
                }
                return null;
              }
            }
          }
        }
      }
    }

    return null;
  }

  void _clearChart() {
    setState(() {
      _series = _series.map((s) => s.copyWith(points: [])).toList();
    });
    LoggerService().log('🗑️ График очищен');
  }

  void _toggleSensor(int index) {
    setState(() {
      _series[index] = _series[index].copyWith(
        isActive: !_series[index].isActive,
        points: [],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeCount = _series.where((s) => s.isActive).length;

    // ✅ Периодически проверяем подключение и тип
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final modbusManager = ModbusManager(context);
      final connectionType = _getConnectionType();
      if (_connected != modbusManager.connected ||
          _connectionType != connectionType) {
        setState(() {
          _connected = modbusManager.connected;
          _connectionType = connectionType;
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Тренды'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _timer?.cancel();
            Navigator.pop(context);
          },
        ),
        actions: [
          if (activeCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$activeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: _clearChart,
            tooltip: 'Очистить график',
          ),
          IconButton(
            icon: Icon(
              _isCollecting ? Icons.stop : Icons.play_arrow,
              color: _isCollecting ? Colors.green : Colors.white,
            ),
            onPressed: _toggleCollection,
            tooltip: _isCollecting ? 'Остановить' : 'Запустить',
          ),
        ],
      ),
      body: Column(
        children: [
          // ✅ Статус подключения с определением типа
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: _connected ? Colors.green[50] : Colors.red[50],
            child: Row(
              children: [
                // ✅ Иконка в зависимости от типа подключения
                Icon(
                  _connected
                      ? (_connectionType == 'rtu' ? Icons.usb : Icons.wifi)
                      : Icons.wifi_off,
                  color: _connected ? Colors.green : Colors.red,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  _connected
                      ? (_connectionType == 'rtu' ? 'RTU (USB)' : 'TCP/IP')
                      : 'Нет подключения',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _connected ? Colors.green : Colors.red,
                  ),
                ),
                if (_connected) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _connectionType == 'rtu' ? 'USB' : 'WiFi',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  _isCollecting ? '▶️ Сбор данных...' : '⏹️ Остановлен',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),

          // График
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              child: ClipRect(child: _buildChart(isDark)),
            ),
          ),

          // Список датчиков
          Expanded(
            flex: 1,
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              child: _series.isEmpty
                  ? const Center(child: Text('Нет доступных датчиков'))
                  : ListView.builder(
                      itemCount: _series.length,
                      itemBuilder: (context, index) {
                        final series = _series[index];
                        final lastValue = series.points.isNotEmpty
                            ? series.points.last.value
                            : null;

                        return Material(
                          color: Colors.transparent,
                          child: CheckboxListTile(
                            title: Text(
                              series.name,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            subtitle: Text(
                              series.unit,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                            value: series.isActive,
                            onChanged: (_) => _toggleSensor(index),
                            secondary: Container(
                              width: 50,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: series.isActive
                                    ? Colors.blue.withOpacity(0.1)
                                    : Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                lastValue != null && lastValue.isFinite
                                    ? lastValue.toStringAsFixed(1)
                                    : '--',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: series.isActive
                                      ? Colors.blue
                                      : Colors.grey,
                                ),
                              ),
                            ),
                            tileColor: Colors.transparent,
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== ГРАФИК ====================
  Widget _buildChart(bool isDark) {
    final activeSeries = _series
        .where((s) => s.isActive && s.points.isNotEmpty)
        .toList();

    if (activeSeries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart,
              size: 48,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _series.where((s) => s.isActive).isEmpty
                  ? 'Выберите датчики'
                  : 'Ожидание данных...',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    bool hasValidData = false;
    for (var s in activeSeries) {
      for (var p in s.points) {
        if (p.value.isFinite) {
          hasValidData = true;
          break;
        }
      }
      if (hasValidData) break;
    }

    if (!hasValidData) {
      return Center(
        child: Text(
          'Нет корректных данных',
          style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
        ),
      );
    }

    return CustomPaint(
      painter: TrendPainter(series: activeSeries, isDark: isDark),
      size: Size.infinite,
    );
  }
}

// ==================== КАСТОМНЫЙ РИСОВАТЕЛЬ ГРАФИКА ====================
class TrendPainter extends CustomPainter {
  final List<TrendSeries> series;
  final bool isDark;

  TrendPainter({required this.series, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final padding = 30.0;
    final graphWidth = size.width - padding * 2;
    final graphHeight = size.height - padding * 2;

    if (graphWidth <= 0 || graphHeight <= 0) return;

    double maxValue = -double.infinity;
    double minValue = double.infinity;
    int maxPoints = 0;

    for (var s in series) {
      if (s.points.length > maxPoints) maxPoints = s.points.length;
      for (var p in s.points) {
        if (p.value.isFinite) {
          if (p.value > maxValue) maxValue = p.value;
          if (p.value < minValue) minValue = p.value;
        }
      }
    }

    if (maxPoints == 0 || maxValue == -double.infinity) return;

    final range = maxValue - minValue;
    if (range < 0.1) {
      maxValue += 0.5;
      minValue -= 0.5;
    }
    final yRange = maxValue - minValue;

    if (yRange <= 0) return;

    final gridPaint = Paint()
      ..color = (isDark ? Colors.grey[700] : Colors.grey[300])!
      ..strokeWidth = 0.5;

    for (double i = 0; i <= 4; i++) {
      final y = padding + (graphHeight / 4) * i;
      canvas.drawLine(
        Offset(padding, y),
        Offset(size.width - padding, y),
        gridPaint,
      );
    }

    final List<Color> colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.brown,
    ];

    for (int sIndex = 0; sIndex < series.length; sIndex++) {
      final s = series[sIndex];
      final validPoints = s.points.where((p) => p.value.isFinite).toList();
      if (validPoints.isEmpty) continue;

      final color = colors[sIndex % colors.length];
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      final path = Path();

      for (int i = 0; i < validPoints.length; i++) {
        final x = padding + (i / (maxPoints - 1)) * graphWidth;
        final y =
            padding +
            graphHeight -
            ((validPoints[i].value - minValue) / yRange) * graphHeight;

        if (x.isNaN || y.isNaN) continue;

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }

        final pointPaint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;

        canvas.drawCircle(Offset(x, y), 3, pointPaint);
      }

      canvas.drawPath(path, paint);

      final lastPoint = validPoints.last;
      final lastX =
          padding + ((validPoints.length - 1) / (maxPoints - 1)) * graphWidth;
      final lastY =
          padding +
          graphHeight -
          ((lastPoint.value - minValue) / yRange) * graphHeight;

      if (lastX.isFinite && lastY.isFinite) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${s.name}: ${lastPoint.value.toStringAsFixed(1)}${s.unit}',
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(
            (lastX - textPainter.width / 2).clamp(
              0,
              size.width - textPainter.width,
            ),
            (lastY - textPainter.height - 6).clamp(
              0,
              size.height - textPainter.height,
            ),
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

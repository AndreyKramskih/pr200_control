// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/config_model.dart';
import 'providers/theme_provider.dart';
import 'services/modbus_service.dart';
import 'services/modbus_rtu_service.dart';
import 'services/config_service.dart';
import 'services/config_manager.dart';
import 'screens/main_menu_screen.dart';
import 'screens/system_screen.dart';
import 'screens/connection_screen.dart';
import 'screens/submenu_screens.dart';
import 'screens/load_config_screen.dart';
import 'services/logger_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ConfigModel? _config;
  late ModbusService _modbusService;
  late ModbusRtuService _modbusRtuService;
  final ThemeProvider _themeProvider = ThemeProvider();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _modbusService = ModbusService();
    _modbusRtuService = ModbusRtuService();
    _loadConfig();
    _initLogger();
  }

  Future<void> _initLogger() async {
    await LoggerService().init();
    LoggerService().log('🚀 Приложение запущено');
  }

  Future<void> _loadConfig() async {
    final configService = ConfigService();

    try {
      final activeConfigName = await ConfigManager.getActiveConfig();
      ConfigModel? config;

      if (activeConfigName != null) {
        LoggerService().log('📂 Загрузка активного конфига: $activeConfigName');
        config = await ConfigManager.loadConfig(activeConfigName);
        if (config != null) {
          LoggerService().log('✅ Активный конфиг загружен: $activeConfigName');
        } else {
          LoggerService().log(
            '⚠️ Активный конфиг не найден, загружаем стандартный',
            level: LogLevel.warning,
          );
        }
      }

      if (config == null) {
        LoggerService().log('📂 Загрузка стандартного конфига');
        config = await configService.loadConfig();
      }

      if (mounted) {
        setState(() {
          _config = config;
          _isLoading = false;
        });
      }

      // Автоподключение по TCP (только для TCP, RTU подключается вручную)
      await _autoConnectTCP();
    } catch (e) {
      LoggerService().log(
        '❌ Ошибка загрузки конфига: $e',
        level: LogLevel.error,
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Только TCP автоподключение
  Future<void> _autoConnectTCP() async {
    if (_config == null) return;

    try {
      final success = await _modbusService.connect(
        _config!.modbusServer.ip,
        port: _config!.modbusServer.port,
        slaveId: _config!.modbusServer.slaveId,
        timeout: _config!.modbusServer.timeout,
      );

      if (success) {
        LoggerService().log('✅ TCP автоподключение успешно');
      } else {
        LoggerService().log(
          '⚠️ TCP автоподключение не удалось: ${_modbusService.lastError}',
          level: LogLevel.warning,
        );
      }
    } catch (e) {
      LoggerService().log(
        '⚠️ Автоподключение не удалось: $e',
        level: LogLevel.warning,
      );
    }
  }

  Future<void> _reloadConfig() async {
    setState(() {
      _isLoading = true;
    });
    await _loadConfig();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    if (_config == null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Ошибка загрузки конфигурации',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _reloadConfig,
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        Provider<ConfigModel>.value(value: _config!),
        ChangeNotifierProvider<ModbusService>.value(value: _modbusService),
        ChangeNotifierProvider<ModbusRtuService>.value(
          value: _modbusRtuService,
        ),
        ChangeNotifierProvider<ThemeProvider>.value(value: _themeProvider),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'PR200 Управление',
            theme: _buildLightTheme(),
            darkTheme: _buildDarkTheme(),
            themeMode: themeProvider.themeMode,
            debugShowCheckedModeBanner: false,
            initialRoute: '/',
            routes: {
              '/': (context) => const MainMenuScreen(),
              '/connection': (context) => const ConnectionScreen(),
              '/load_config': (context) => const LoadConfigScreen(),
              '/system': (context) {
                final args =
                    ModalRoute.of(context)?.settings.arguments as String?;
                if (args == null) {
                  return const Scaffold(
                    body: Center(child: Text('Ошибка: ID системы не указан')),
                  );
                }
                return SystemScreen(systemId: args);
              },
              '/submenu': (context) {
                final args =
                    ModalRoute.of(context)?.settings.arguments
                        as Map<String, String>?;
                if (args == null ||
                    !args.containsKey('systemId') ||
                    !args.containsKey('submenuId')) {
                  return const Scaffold(
                    body: Center(child: Text('Ошибка: параметры не указаны')),
                  );
                }
                return SubmenuScreen(
                  systemId: args['systemId']!,
                  submenuId: args['submenuId']!,
                );
              },
            },
          );
        },
      ),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        elevation: 4,
        centerTitle: false,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[400]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[400]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(color: Colors.black87),
        hintStyle: TextStyle(color: Colors.grey[600]),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.black87),
        bodyMedium: TextStyle(color: Colors.black87),
        titleLarge: TextStyle(color: Colors.black87),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarTheme(
        elevation: 4,
        centerTitle: false,
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.grey[850],
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[600]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[600]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[800],
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: TextStyle(color: Colors.grey[500]),
        prefixIconColor: Colors.white70,
        suffixIconColor: Colors.white70,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white),
        titleLarge: TextStyle(color: Colors.white),
      ),
    );
  }
}

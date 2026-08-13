// lib/screens/pin_screen.dart
import 'package:flutter/material.dart';
import '../services/pin_service.dart';

class PinScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  final bool isSettingPin;

  const PinScreen({
    super.key,
    required this.onSuccess,
    this.isSettingPin = false,
  });

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final PinService _pinService = PinService();

  bool _isLoading = false;
  String _error = '';
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    _checkPinStatus();
  }

  Future<void> _checkPinStatus() async {
    final isSet = await _pinService.isPinSet();
    if (!isSet && !widget.isSettingPin) {
      widget.onSuccess();
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      if (widget.isSettingPin) {
        final pin = _pinController.text.trim();
        final confirm = _confirmController.text.trim();

        if (pin.isEmpty) {
          setState(() => _error = 'Введите PIN-код');
          return;
        }
        if (pin != confirm) {
          setState(() => _error = 'PIN-коды не совпадают');
          return;
        }

        await _pinService.setPin(pin);
        widget.onSuccess();
      } else {
        final pin = _pinController.text.trim();
        if (pin.isEmpty) {
          setState(() => _error = 'Введите PIN-код');
          return;
        }

        final isValid = await _pinService.verifyPin(pin);
        if (isValid) {
          widget.onSuccess();
        } else {
          if (_pinService.isLocked) {
            final remaining = _pinService.lockoutUntil!.difference(
              DateTime.now(),
            );
            setState(() {
              _error =
                  '🔒 Устройство заблокировано на ${remaining.inMinutes} минут';
            });
          } else {
            setState(() {
              _error =
                  '❌ Неверный PIN-код (осталось ${_pinService.remainingAttempts} попыток)';
            });
          }
        }
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // ✅ Запрещаем изменение размера при появлении клавиатуры
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(
          widget.isSettingPin ? 'Установка PIN-кода' : 'Введите PIN-код',
        ),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        leading: widget.isSettingPin
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(24),
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.isSettingPin ? Icons.lock_outline : Icons.lock,
                size: 64,
                color: Colors.blue[700],
              ),
              const SizedBox(height: 24),
              if (widget.isSettingPin) ...[
                const Text(
                  'Установите PIN-код для защиты',
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'PIN-код потребуется при входе в приложение',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ] else ...[
                const Text(
                  'Введите PIN-код для доступа',
                  style: TextStyle(fontSize: 18),
                ),
                if (_pinService.isLocked)
                  Text(
                    '🔒 Блокировка: ${(_pinService.lockoutUntil!.difference(DateTime.now()).inMinutes)} мин',
                    style: const TextStyle(color: Colors.red),
                  ),
              ],
              const SizedBox(height: 24),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      TextField(
                        controller: _pinController,
                        obscureText: _obscureText,
                        keyboardType: TextInputType.number,
                        maxLength: 8,
                        // ✅ Убираем автоматическую фокусировку
                        autofocus: false,
                        decoration: InputDecoration(
                          labelText: 'PIN-код',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureText
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () =>
                                setState(() => _obscureText = !_obscureText),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          errorText: _error.isNotEmpty && !widget.isSettingPin
                              ? _error
                              : null,
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                      if (widget.isSettingPin) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _confirmController,
                          obscureText: _obscureText,
                          keyboardType: TextInputType.number,
                          maxLength: 8,
                          autofocus: false,
                          decoration: InputDecoration(
                            labelText: 'Подтвердите PIN-код',
                            prefixIcon: const Icon(Icons.lock),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            errorText: _error.isNotEmpty ? _error : null,
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  widget.isSettingPin ? 'Установить' : 'Войти',
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // ✅ Добавляем отступ вниз для безопасной области
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../models/config_model.dart';

class ParameterWidget extends StatefulWidget {
  final ItemConfig item;
  final dynamic value;
  final Function(dynamic) onChanged;
  final Function(dynamic) onSave;
  final Future<dynamic> Function() onLoad;

  const ParameterWidget({
    super.key,
    required this.item,
    required this.value,
    required this.onChanged,
    required this.onSave,
    required this.onLoad,
  });

  @override
  State<ParameterWidget> createState() => _ParameterWidgetState();
}

class _ParameterWidgetState extends State<ParameterWidget> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.value != null && widget.value is double) {
      _controller.text = widget.value.toStringAsFixed(1); // 1 знак
    } else {
      _controller.text =
          widget.value?.toString() ??
          widget.item.defaultValue?.toString() ??
          '0';
    }
  }

  @override
  void didUpdateWidget(ParameterWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _controller.text = widget.value?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.item.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  widget.item.unit ?? '',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _controller,
                    keyboardType: widget.item.type == 'float'
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.number,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      constraints: const BoxConstraints(minHeight: 40),
                    ),
                    onChanged: (value) {
                      final newValue = widget.item.type == 'float'
                          ? double.tryParse(value)
                          : int.tryParse(value);
                      if (newValue != null) {
                        widget.onChanged(newValue);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.blue),
                  onPressed: _isLoading ? null : _loadValue,
                  tooltip: 'Обновить',
                ),
                IconButton(
                  icon: const Icon(Icons.save, color: Colors.green),
                  onPressed: _isLoading ? null : _saveValue,
                  tooltip: 'Сохранить',
                ),
              ],
            ),
            if (widget.item.min != null && widget.item.max != null)
              Text(
                'Диапазон: ${widget.item.min} - ${widget.item.max} ${widget.item.unit ?? ''}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadValue() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final value = await widget.onLoad();
      if (value != null && mounted) {
        _controller.text = value.toString();
        widget.onChanged(value);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка чтения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveValue() async {
    final valueStr = _controller.text.trim();
    if (valueStr.isEmpty) return;

    final newValue = widget.item.type == 'float'
        ? double.tryParse(valueStr)
        : int.tryParse(valueStr);

    if (newValue == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Введите корректное число'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Проверка диапазона
    if (widget.item.min != null && widget.item.max != null) {
      final numValue = double.tryParse(newValue.toString());
      if (numValue != null) {
        if (numValue < widget.item.min! || numValue > widget.item.max!) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Значение должно быть от ${widget.item.min} до ${widget.item.max}',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await widget.onSave(newValue);
      if (mounted) {
        _controller.text = newValue.toString();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

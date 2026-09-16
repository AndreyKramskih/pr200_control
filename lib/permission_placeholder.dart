// Фейковый класс-заглушка, чтобы компилятор Windows не ругался на отсутствие методов
class Permission {
  static const storage = _MockPermission();
}

class _MockPermission {
  const _MockPermission();
  dynamic request() async => this;
  bool get isGranted => true;
}

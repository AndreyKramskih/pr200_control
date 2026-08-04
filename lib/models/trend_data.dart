class TrendPoint {
  final DateTime timestamp;
  final double value;

  TrendPoint({required this.timestamp, required this.value});
}

class TrendSeries {
  final String name;
  final String unit;
  final List<TrendPoint> points;
  final bool isActive;

  TrendSeries({
    required this.name,
    required this.unit,
    this.points = const [],
    this.isActive = true,
  });

  TrendSeries copyWith({
    String? name,
    String? unit,
    List<TrendPoint>? points,
    bool? isActive,
  }) {
    return TrendSeries(
      name: name ?? this.name,
      unit: unit ?? this.unit,
      points: points ?? this.points,
      isActive: isActive ?? this.isActive,
    );
  }

  // Максимальное количество точек на графике (например, 60 = 1 минута)
  static const int maxPoints = 60;
}

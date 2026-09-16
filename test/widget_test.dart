import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pr200_control/main.dart';

void main() {
  testWidgets('MyApp shows loading state on startup', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

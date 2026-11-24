import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan3d/main.dart';

void main() {
  testWidgets('home screen shows the title and the start button', (tester) async {
    await tester.pumpWidget(const Scan3dApp());

    expect(find.text('Scan3D'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start scanning'), findsOneWidget);
  });
}

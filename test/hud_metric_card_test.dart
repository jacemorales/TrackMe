import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackme_client/widgets/hud_metric_card.dart';

void main() {
  testWidgets('HUDMetricCard renders label and value correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HUDMetricCard(
            icon: Icons.speed,
            label: 'Distance Left',
            value: '614.0 km',
          ),
        ),
      ),
    );

    expect(find.text('DISTANCE LEFT'), findsOneWidget);
    expect(find.text('614.0 km'), findsOneWidget);
    expect(find.byIcon(Icons.speed), findsOneWidget);
  });
}

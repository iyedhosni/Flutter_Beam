// Beam Notifications App Widget Test
//
// This test verifies that the Beam WebView app initializes correctly
// and shows the expected UI elements.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:test_notif/main.dart';

void main() {
  testWidgets('Beam app loads correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const BeamWebApp());

    // Wait for the app to initialize
    await tester.pumpAndSettle();

    // Verify that our app shows the expected title
    expect(find.text('Beam Store'), findsOneWidget);

    // Verify that the notification button is present
    expect(find.byIcon(Icons.notifications), findsWidgets);

    // Verify that the refresh button is present
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('Test notification works', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const BeamWebApp());

    // Wait for the app to initialize
    await tester.pumpAndSettle();

    // Find and tap the notification test button
    final notificationButton = find.byIcon(Icons.notifications);
    expect(notificationButton, findsWidgets);

    // Tap the notification button
    await tester.tap(notificationButton.first);
    await tester.pump();

    // The test passes if no exceptions are thrown
    // (Actual notification testing requires device/emulator)
  });
}

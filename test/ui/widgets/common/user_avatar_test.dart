import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:go_hard_app/ui/widgets/common/user_avatar.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: child))),
    );
  }

  NetworkImage? networkBackground(WidgetTester tester) {
    final avatars = tester.widgetList<CircleAvatar>(find.byType(CircleAvatar));
    if (avatars.isEmpty) return null;
    return avatars.first.backgroundImage as NetworkImage?;
  }

  testWidgets('renders a NetworkImage for a relative server photo path', (
    tester,
  ) async {
    await pump(
      tester,
      const UserAvatar(
        photoUrl: '/uploads/profiles/user_7_20240101.jpg',
        fallbackText: 'Bob',
      ),
    );

    final image = networkBackground(tester);
    expect(image, isNotNull);
    expect(image!.url, endsWith('/uploads/profiles/user_7_20240101.jpg'));
    expect(image.url, startsWith('http'));
    expect(find.text('B'), findsNothing);
  });

  testWidgets('passes an absolute photo URL through unchanged', (tester) async {
    await pump(
      tester,
      const UserAvatar(
        photoUrl: 'https://cdn.example.com/p.png',
        fallbackText: 'Bob',
      ),
    );

    expect(networkBackground(tester)!.url, 'https://cdn.example.com/p.png');
  });

  testWidgets('falls back to the first letter when there is no photo', (
    tester,
  ) async {
    await pump(tester, const UserAvatar(photoUrl: null, fallbackText: 'bob'));

    expect(find.byType(CircleAvatar), findsNothing);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets(
    'falls back to a person icon when there is no photo and no text',
    (tester) async {
      await pump(tester, const UserAvatar(photoUrl: '', fallbackText: '   '));

      expect(find.byType(CircleAvatar), findsNothing);
      expect(find.byIcon(Icons.person), findsOneWidget);
    },
  );

  testWidgets('a replaced photo URL clears a prior load-failure state', (
    tester,
  ) async {
    await pump(
      tester,
      const UserAvatar(photoUrl: '/uploads/a.jpg', fallbackText: 'Bob'),
    );

    // Simulate the first image failing to load: the widget swaps to the
    // letter fallback.
    tester
        .widget<CircleAvatar>(find.byType(CircleAvatar))
        .onBackgroundImageError
        ?.call(Object(), StackTrace.empty);
    await tester.pump();
    expect(find.text('B'), findsOneWidget);
    expect(find.byType(CircleAvatar), findsNothing);

    // A new URL must get a fresh attempt, not stay stuck on the fallback.
    await pump(
      tester,
      const UserAvatar(photoUrl: '/uploads/b.jpg', fallbackText: 'Bob'),
    );
    expect(networkBackground(tester)!.url, endsWith('/uploads/b.jpg'));
    expect(find.text('B'), findsNothing);
  });
}

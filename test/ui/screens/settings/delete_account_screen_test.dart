import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/providers/account_deletion_provider.dart';
import 'package:go_hard_app/ui/screens/settings/delete_account_screen.dart';

@GenerateMocks([AccountDeletionProvider])
import 'delete_account_screen_test.mocks.dart';

void main() {
  late MockAccountDeletionProvider mockProvider;

  setUp(() {
    mockProvider = MockAccountDeletionProvider();
    when(mockProvider.isDeleting).thenReturn(false);
    when(mockProvider.errorMessage).thenReturn(null);
  });

  Widget host() => MaterialApp(
    home: ChangeNotifierProvider<AccountDeletionProvider>.value(
      value: mockProvider,
      child: const DeleteAccountScreen(),
    ),
  );

  testWidgets('shows the explanation, password field, and delete button', (
    tester,
  ) async {
    await tester.pumpWidget(host());

    expect(find.text('This cannot be undone'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.widgetWithText(ElevatedButton, 'Delete Account'),
      findsOneWidget,
    );
  });

  testWidgets('tapping Delete with an empty password never calls the '
      'provider and shows a hint instead', (tester) async {
    await tester.pumpWidget(host());

    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
    await tester.pump();

    verifyNever(mockProvider.deleteAccount(any));
    expect(find.text('Enter your password to continue'), findsOneWidget);
  });

  testWidgets('tapping Delete with a password shows the destructive '
      'confirmation sheet before calling the provider', (tester) async {
    await tester.pumpWidget(host());
    await tester.enterText(find.byType(TextField), 'my-password');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
    await tester.pumpAndSettle();

    // The confirmation sheet is shown; the provider has NOT been called yet.
    expect(find.text('Delete your account?'), findsOneWidget);
    verifyNever(mockProvider.deleteAccount(any));
  });

  testWidgets('cancelling the confirmation sheet never calls the provider', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.enterText(find.byType(TextField), 'my-password');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keep My Account'));
    await tester.pumpAndSettle();

    verifyNever(mockProvider.deleteAccount(any));
  });

  testWidgets('confirming the sheet calls deleteAccount with the entered '
      'password', (tester) async {
    when(mockProvider.deleteAccount(any)).thenAnswer((_) async => true);
    await tester.pumpWidget(host());
    await tester.enterText(find.byType(TextField), 'my-password');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete Account').last);
    await tester.pumpAndSettle();

    verify(mockProvider.deleteAccount('my-password')).called(1);
  });

  testWidgets('while deleting, the button is disabled and shows a spinner', (
    tester,
  ) async {
    when(mockProvider.isDeleting).thenReturn(true);
    await tester.pumpWidget(host());

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a reported error is shown to the user', (tester) async {
    when(mockProvider.errorMessage).thenReturn('Incorrect password');
    when(mockProvider.deleteAccount(any)).thenAnswer((_) async => false);
    await tester.pumpWidget(host());
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Account').last);
    await tester.pumpAndSettle();

    expect(find.text('Incorrect password'), findsOneWidget);
  });
}

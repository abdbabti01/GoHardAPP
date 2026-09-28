import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/core/utils/unit_converter.dart';

/// Task 4: the ONLY lifted-weight conversion boundary later tasks (Log Sets,
/// analytics) call through. These tests lock the exact constant and rounding
/// behaviour so a future change can't silently drift the conversion.
void main() {
  test('Imperial input 135 lb -> 61.23496995 kg', () {
    expect(
      UnitConverter.liftedInputToKg(135, 'Imperial'),
      closeTo(61.23496995, 1e-9),
    );
  });

  test('Metric input is already kg', () {
    expect(UnitConverter.liftedInputToKg(60, 'Metric'), 60);
  });

  test('61.23496995 kg displays as 135 lb for Imperial', () {
    expect(
      UnitConverter.liftedKgToDisplay(61.23496995, 'Imperial'),
      closeTo(135, 1e-9),
    );
    expect(UnitConverter.formatLifted(61.23496995, 'Imperial'), '135 lb');
  });

  test('100 kg displays 100 kg / 220.5 lb', () {
    expect(UnitConverter.formatLifted(100, 'Metric'), '100 kg');
    expect(UnitConverter.formatLifted(100, 'Imperial'), '220.5 lb');
  });

  test('140 lb input stores ~63.5029 kg', () {
    expect(
      UnitConverter.liftedInputToKg(140, 'Imperial'),
      closeTo(63.5029318, 1e-6),
    );
  });

  test('null/unknown preference behaves as Metric', () {
    expect(UnitConverter.liftedUnitLabel(null), 'kg');
    expect(UnitConverter.liftedInputToKg(60, 'bogus'), 60);
  });

  test('lb -> kg -> lb round trip is exact to 1e-9', () {
    for (final lb in [45.0, 135.0, 102.5, 0.0]) {
      final kg = UnitConverter.liftedInputToKg(lb, 'Imperial');
      expect(
        UnitConverter.liftedKgToDisplay(kg, 'Imperial'),
        closeTo(lb, 1e-9),
      );
    }
  });
}

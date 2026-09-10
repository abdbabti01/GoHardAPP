import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/core/utils/image_format.dart';

void main() {
  group('detectImageFormatFromBytes', () {
    test('JPEG signature', () {
      expect(
        detectImageFormatFromBytes([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]),
        DetectedImageFormat.jpeg,
      );
    });

    test('PNG signature', () {
      expect(
        detectImageFormatFromBytes([
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
          0, 0, 0, 0,
        ]),
        DetectedImageFormat.png,
      );
    });

    test('HEIC (ISO-BMFF ftyp with heic brand) is detected, not treated as '
        'supported', () {
      final bytes = <int>[
        0x00, 0x00, 0x00, 0x18, // box size
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x68, 0x65, 0x69, 0x63, // 'heic'
        0x00, 0x00, 0x00, 0x00,
      ];
      final fmt = detectImageFormatFromBytes(bytes);
      expect(fmt, DetectedImageFormat.heic);
      expect(fmt.isServerSupported, isFalse);
    });

    test('mif1 brand (common iPhone HEIF) is detected as heic-family', () {
      final bytes = <int>[
        0x00, 0x00, 0x00, 0x18,
        0x66, 0x74, 0x79, 0x70,
        0x6D, 0x69, 0x66, 0x31, // 'mif1'
        0x00, 0x00, 0x00, 0x00,
      ];
      expect(detectImageFormatFromBytes(bytes), DetectedImageFormat.heic);
    });

    test('WebP (RIFF/WEBP) is detected and unsupported', () {
      final bytes = <int>[
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x00, 0x00, 0x00, 0x00,
        0x57, 0x45, 0x42, 0x50, // WEBP
      ];
      final fmt = detectImageFormatFromBytes(bytes);
      expect(fmt, DetectedImageFormat.webp);
      expect(fmt.isServerSupported, isFalse);
    });

    test('random / truncated bytes are unknown', () {
      expect(
        detectImageFormatFromBytes([1, 2, 3]),
        DetectedImageFormat.unknown,
      );
      expect(
        detectImageFormatFromBytes([9, 9, 9, 9, 9, 9, 9, 9]),
        DetectedImageFormat.unknown,
      );
    });

    test('only JPEG and PNG report isServerSupported', () {
      expect(DetectedImageFormat.jpeg.isServerSupported, isTrue);
      expect(DetectedImageFormat.png.isServerSupported, isTrue);
      for (final f in [
        DetectedImageFormat.gif,
        DetectedImageFormat.webp,
        DetectedImageFormat.heic,
        DetectedImageFormat.bmp,
        DetectedImageFormat.unknown,
      ]) {
        expect(f.isServerSupported, isFalse, reason: '$f');
      }
    });
  });

  group('detectImageFormat (file)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('img_fmt_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reads the head of a real JPEG file', () async {
      final f = File('${dir.path}/a.jpg')..writeAsBytesSync(
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(200, 0)]),
      );
      expect(await detectImageFormat(f), DetectedImageFormat.jpeg);
    });

    test('a .jpg extension over HEIC bytes is still reported HEIC', () async {
      final f = File('${dir.path}/lies.jpg')..writeAsBytesSync(
        Uint8List.fromList([
          0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, //
          0x68, 0x65, 0x69, 0x63, 0, 0, 0, 0,
        ]),
      );
      expect(await detectImageFormat(f), DetectedImageFormat.heic);
    });

    test('a missing file is unknown, never throws', () async {
      expect(
        await detectImageFormat(File('${dir.path}/nope.png')),
        DetectedImageFormat.unknown,
      );
    });
  });
}

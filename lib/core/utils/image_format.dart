import 'dart:io';
import 'dart:typed_data';

/// Image container formats we can tell apart from a file's leading bytes.
enum DetectedImageFormat {
  jpeg,
  png,
  gif,
  webp,
  heic,
  bmp,
  unknown;

  /// The deployed profile-photo API validates by content signature and only
  /// stores JPEG or PNG (see `PROFILE_PHOTO_STORAGE.md`). Everything else -
  /// including an iPhone HEIC that `image_picker` did not transcode - is
  /// rejected server-side with a 400, so the client checks first and shows a
  /// clear message instead.
  bool get isServerSupported =>
      this == DetectedImageFormat.jpeg || this == DetectedImageFormat.png;

  /// Short human label for an "unsupported format" message.
  String get label {
    switch (this) {
      case DetectedImageFormat.jpeg:
        return 'JPEG';
      case DetectedImageFormat.png:
        return 'PNG';
      case DetectedImageFormat.gif:
        return 'GIF';
      case DetectedImageFormat.webp:
        return 'WebP';
      case DetectedImageFormat.heic:
        return 'HEIC/HEIF';
      case DetectedImageFormat.bmp:
        return 'BMP';
      case DetectedImageFormat.unknown:
        return 'an unrecognised format';
    }
  }
}

/// Sniff [bytes] (a file's first few dozen bytes are enough) and classify the
/// image container. Never throws; unrecognised input is
/// [DetectedImageFormat.unknown].
///
/// This deliberately does NOT trust a file extension or a picker-reported MIME
/// type - `image_picker` on iOS can hand back a `.jpg` path whose bytes are
/// still HEIC.
DetectedImageFormat detectImageFormatFromBytes(List<int> bytes) {
  final b = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  if (b.length < 4) return DetectedImageFormat.unknown;

  // JPEG: FF D8 FF
  if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return DetectedImageFormat.jpeg;
  }

  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47 &&
      b[4] == 0x0D &&
      b[5] == 0x0A &&
      b[6] == 0x1A &&
      b[7] == 0x0A) {
    return DetectedImageFormat.png;
  }

  // GIF: "GIF87a" / "GIF89a"
  if (b.length >= 6 &&
      b[0] == 0x47 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x38 &&
      (b[4] == 0x37 || b[4] == 0x39) &&
      b[5] == 0x61) {
    return DetectedImageFormat.gif;
  }

  // BMP: "BM"
  if (b[0] == 0x42 && b[1] == 0x4D) return DetectedImageFormat.bmp;

  // ISO-BMFF (`....ftyp<brand>`) - covers HEIC/HEIF and the WebP-in-RIFF
  // check below. Bytes 4-7 are the "ftyp" box type.
  if (b.length >= 12 &&
      b[4] == 0x66 &&
      b[5] == 0x74 &&
      b[6] == 0x79 &&
      b[7] == 0x70) {
    final brand = String.fromCharCodes(b.sublist(8, 12)).toLowerCase();
    const heifBrands = {
      'heic',
      'heix',
      'hevc',
      'hevx',
      'heim',
      'heis',
      'hevm',
      'hevs',
      'mif1',
      'msf1',
    };
    if (heifBrands.contains(brand)) return DetectedImageFormat.heic;
  }

  // WebP: "RIFF"????"WEBP"
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return DetectedImageFormat.webp;
  }

  return DetectedImageFormat.unknown;
}

/// Read the first [headBytes] bytes of [file] and classify its image format.
/// A missing/unreadable file is [DetectedImageFormat.unknown] - never an
/// exception.
Future<DetectedImageFormat> detectImageFormat(
  File file, {
  int headBytes = 64,
}) async {
  try {
    final raf = await file.open();
    try {
      final length = await raf.length();
      final toRead = length < headBytes ? length : headBytes;
      final head = await raf.read(toRead);
      return detectImageFormatFromBytes(head);
    } finally {
      await raf.close();
    }
  } catch (_) {
    return DetectedImageFormat.unknown;
  }
}

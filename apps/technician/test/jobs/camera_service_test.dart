import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'package:fixcare_technician/features/jobs/presentation/photo_capture.dart';

/// Records every ladder step and returns a scripted output size per call.
class _FakeCompressStep {
  _FakeCompressStep(this.sizes);

  /// Output length for the n-th call.
  final List<int> sizes;
  final List<({int inputLength, int quality, int? minWidth, int? minHeight})> calls = [];

  Future<List<int>> call(List<int> bytes, {required int quality, int? minWidth, int? minHeight}) async {
    final size = sizes[calls.length];
    calls.add((inputLength: bytes.length, quality: quality, minWidth: minWidth, minHeight: minHeight));
    return List<int>.filled(size, 1);
  }
}

const _kb = 1024;

void main() {
  group('compressToBudget', () {
    final original = List<int>.filled(3000 * _kb, 9);

    test('first fit: returns the q80 result at the plugin-default size when it is already under budget', () async {
      final fake = _FakeCompressStep([400 * _kb]);

      final out = await compressToBudget(original, compress: fake.call);

      expect(out, hasLength(400 * _kb));
      expect(fake.calls, hasLength(1));
      expect(fake.calls.single.quality, 80);
      expect(fake.calls.single.minWidth, isNull, reason: 'null = the plugin default size');
      expect(fake.calls.single.minHeight, isNull);
    });

    test('walks quality 80/60/45/30, then downscales 1280@q60 — returns the first result within budget', () async {
      final fake = _FakeCompressStep([900 * _kb, 800 * _kb, 700 * _kb, 600 * _kb, 450 * _kb]);

      final out = await compressToBudget(original, compress: fake.call);

      expect(out, hasLength(450 * _kb));
      expect(
        fake.calls.map((c) => (c.quality, c.minWidth, c.minHeight)).toList(),
        [(80, null, null), (60, null, null), (45, null, null), (30, null, null), (60, 1280, 1280)],
      );
      // Every step compresses the ORIGINAL (never re-compresses a lossy output).
      expect(fake.calls.every((c) => c.inputLength == original.length), isTrue);
    });

    test('escalates to the last step (1024@q50) when 1280 is still over budget', () async {
      final fake = _FakeCompressStep([900 * _kb, 800 * _kb, 700 * _kb, 600 * _kb, 550 * _kb, 480 * _kb]);

      final out = await compressToBudget(original, compress: fake.call);

      expect(out, hasLength(480 * _kb));
      expect(fake.calls, hasLength(6));
      expect((fake.calls.last.quality, fake.calls.last.minWidth, fake.calls.last.minHeight), (50, 1024, 1024));
    });

    test('nothing fits: returns the SMALLEST result produced (not the last)', () async {
      final fake = _FakeCompressStep([900 * _kb, 700 * _kb, 650 * _kb, 600 * _kb, 520 * _kb, 530 * _kb]);

      final out = await compressToBudget(original, compress: fake.call);

      expect(fake.calls, hasLength(6));
      expect(out, hasLength(520 * _kb));
    });

    test('maxBytes is honoured (defaults to kPhotoMaxBytes)', () async {
      final fake = _FakeCompressStep([kPhotoMaxBytes + 1, kPhotoMaxBytes]);

      final out = await compressToBudget(original, compress: fake.call);

      expect(out, hasLength(kPhotoMaxBytes));
      expect(fake.calls, hasLength(2));
    });
  });

  group('ImagePickerCameraService.capture (happy path)', () {
    test('compresses, stamps capturedAt right after the shot (before compress + location), geotags from the fix',
        () async {
      final raw = Uint8List.fromList(List<int>.filled(4096, 5));
      final before = DateTime.now().toUtc();
      DateTime? locationDoneAt;

      final svc = ImagePickerCameraService(
        pickImage: ({required ImageSource source}) async => XFile.fromData(raw),
        compress: (bytes) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return bytes.sublist(0, 100);
        },
        readLocation: () async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          locationDoneAt = DateTime.now().toUtc();
          return Position(
            latitude: 22.3,
            longitude: 73.2,
            timestamp: DateTime.now(),
            accuracy: 5,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );
        },
      );

      final photo = await svc.capture();

      expect(photo, isNotNull);
      expect(photo!.bytes, hasLength(100), reason: 'the compressed bytes are what gets uploaded');
      final capturedAt = DateTime.parse(photo.capturedAt);
      expect(capturedAt.isUtc, isTrue);
      expect(capturedAt.isBefore(before), isFalse);
      // Taken before the compress (50ms) + location (200ms) delays elapsed.
      expect(locationDoneAt!.difference(capturedAt), greaterThanOrEqualTo(const Duration(milliseconds: 200)));
      expect(photo.lat, 22.3);
      expect(photo.lng, 73.2);
    });
  });

  group('camera-only source scan', () {
    test('no gallery / file / multi / video picker anywhere under lib/ (comment lines skipped)', () {
      const banned = [
        'ImageSource.gallery',
        'pickMultiImage',
        'pickMedia',
        'pickMultipleMedia',
        'pickVideo',
        'file_picker',
        'FilePicker',
      ];
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      // Sanity: the scan really reads the app's sources (not an empty dir).
      expect(files.any((f) => f.path.endsWith('photo_capture.dart')), isTrue);

      final hits = <String>[];
      var sawCameraSource = false;
      for (final f in files) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue; // `//` and `///` comment lines
          if (line.contains('ImageSource.camera')) sawCameraSource = true;
          for (final b in banned) {
            if (line.contains(b)) hits.add('${f.path}:${i + 1}: $b');
          }
        }
      }

      expect(hits, isEmpty, reason: 'camera-only evidence (fraud vector): ${hits.join('\n')}');
      expect(sawCameraSource, isTrue, reason: 'the scanner must see the real camera call site');
    });
  });
}

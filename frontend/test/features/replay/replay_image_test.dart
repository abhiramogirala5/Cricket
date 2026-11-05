import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/features/replay/replay_image.dart';

void main() {
  group('lumaToRgba', () {
    test('turns each grey value into an opaque grey pixel', () {
      final Uint8List rgba = lumaToRgba(Uint8List.fromList(<int>[0, 128, 255]));
      expect(rgba, <int>[0, 0, 0, 255, 128, 128, 128, 255, 255, 255, 255, 255]);
    });

    test('an empty picture gives no bytes', () {
      expect(lumaToRgba(Uint8List(0)), isEmpty);
    });

    test('the result is four times as long as the input', () {
      expect(lumaToRgba(Uint8List(25)).length, 100);
    });
  });
}

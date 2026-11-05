import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/live/replay_codec.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';

const int width = 40;
const int height = 24;

/// A small film: a faintly noisy gradient wall and a bright square that moves to the right.
List<LumaFrame> makeFilm(int count, {int firstMs = 1000, int stepMs = 33}) {
  final math.Random random = math.Random(5);
  final List<LumaFrame> film = <LumaFrame>[];
  for (int i = 0; i < count; i++) {
    final Uint8List pixels = Uint8List(width * height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int value = _pixel(x, y, i) + random.nextInt(5) - 2;
        pixels[y * width + x] = value < 0 ? 0 : (value > 255 ? 255 : value);
      }
    }
    film.add(LumaFrame(width: width, height: height, timestampMs: firstMs + i * stepMs, pixels: pixels));
  }
  return film;
}

int _pixel(int x, int y, int frame) {
  final int left = 2 + 2 * frame;
  if (x >= left && x < left + 6 && y >= 8 && y < 14) {
    return 250;
  }
  return 20 + (x * 3 + y * 5) % 200;
}

Uint8List flat(int value) => Uint8List.fromList(List<int>.filled(width * height, value));

LumaFrame flatFrame(int value, int timestampMs) {
  return LumaFrame(width: width, height: height, timestampMs: timestampMs, pixels: flat(value));
}

int worstDifference(Uint8List a, Uint8List b) {
  int worst = 0;
  for (int i = 0; i < a.length; i++) {
    final int difference = (a[i] - b[i]).abs();
    if (difference > worst) {
      worst = difference;
    }
  }
  return worst;
}

void main() {
  group('ReplayCodec', () {
    test('writes a pack that reads back with the same size, count and times', () {
      final List<LumaFrame> film = makeFilm(30);

      final ReplayReader reader = ReplayReader.parse(ReplayCodec.encode(film));

      expect(reader.width, width);
      expect(reader.height, height);
      expect(reader.frameCount, 30);
      expect(reader.keyInterval, ReplayCodec.defaultKeyInterval);
      expect(reader.startTimestampMs, 1000);
      for (int i = 0; i < 30; i++) {
        expect(reader.timestampOf(i), 1000 + 33 * i);
      }
      expect(reader.durationMs, 33 * 29);
      expect(reader.meta, isNull);
    });

    test('every decoded pixel is within the promised error of the original', () {
      final List<LumaFrame> film = makeFilm(30);
      final ReplayReader reader = ReplayReader.parse(ReplayCodec.encode(film));

      for (int i = 0; i < film.length; i++) {
        expect(
          worstDifference(reader.frame(i), film[i].pixels),
          lessThanOrEqualTo(ReplayCodec.maxError),
          reason: 'picture $i',
        );
      }
    });

    test('the error does not add up over many pictures', () {
      // 100 pictures of a slowly brightening wall: every step is smaller than the dead zone.
      final List<LumaFrame> film = <LumaFrame>[
        for (int i = 0; i < 100; i++) flatFrame(50 + i ~/ 3, i * 33),
      ];
      final ReplayReader reader = ReplayReader.parse(ReplayCodec.encode(film, keyInterval: 100));

      expect(worstDifference(reader.frame(99), film[99].pixels), lessThanOrEqualTo(ReplayCodec.maxError));
      expect(worstDifference(reader.frame(50), film[50].pixels), lessThanOrEqualTo(ReplayCodec.maxError));
    });

    test('handles the biggest possible jumps between black and white', () {
      final List<LumaFrame> film = <LumaFrame>[
        flatFrame(0, 0),
        flatFrame(255, 33),
        flatFrame(0, 66),
        flatFrame(255, 99),
        flatFrame(0, 132),
      ];

      for (final int interval in <int>[1, 2, 5]) {
        final ReplayReader reader = ReplayReader.parse(ReplayCodec.encode(film, keyInterval: interval));

        for (int i = 0; i < film.length; i++) {
          expect(
            worstDifference(reader.frame(i), film[i].pixels),
            lessThanOrEqualTo(ReplayCodec.maxError),
            reason: 'picture $i, key interval $interval',
          );
        }
      }
    });

    test('jumping to a picture gives the same result as playing up to it', () {
      final List<LumaFrame> film = makeFilm(30);
      final Uint8List pack = ReplayCodec.encode(film);
      final ReplayReader sequential = ReplayReader.parse(pack);
      final List<Uint8List> expected = <Uint8List>[
        for (int i = 0; i < film.length; i++) Uint8List.fromList(sequential.frame(i)),
      ];
      final ReplayReader jumping = ReplayReader.parse(pack);

      for (final int index in <int>[25, 3, 13, 12, 11, 29, 0, 24, 24, 5, 6, 7, 20, 12]) {
        expect(jumping.frame(index), expected[index], reason: 'picture $index');
      }
    });

    test('a key interval of one makes every picture independent', () {
      final List<LumaFrame> film = makeFilm(6);
      final ReplayReader reader = ReplayReader.parse(ReplayCodec.encode(film, keyInterval: 1));

      expect(reader.keyInterval, 1);
      expect(worstDifference(reader.frame(4), film[4].pixels), lessThanOrEqualTo(ReplayCodec.maxError));
      expect(worstDifference(reader.frame(2), film[2].pixels), lessThanOrEqualTo(ReplayCodec.maxError));
    });

    test('a still scene packs to a fraction of the raw size', () {
      final List<LumaFrame> film = <LumaFrame>[
        for (int i = 0; i < 40; i++)
          LumaFrame(
            width: 80,
            height: 60,
            timestampMs: i * 33,
            pixels: Uint8List.fromList(<int>[
              for (int y = 0; y < 60; y++)
                for (int x = 0; x < 80; x++) 60 + (x + y) % 40,
            ]),
          ),
      ];

      final Uint8List pack = ReplayCodec.encode(film);

      expect(pack.length, lessThan(40 * 80 * 60 ~/ 3));
    });

    test('indexAt finds the last picture at or before a time', () {
      final ReplayReader reader = ReplayReader.parse(ReplayCodec.encode(makeFilm(10)));

      expect(reader.indexAt(0), 0);
      expect(reader.indexAt(999), 0);
      expect(reader.indexAt(1000), 0);
      expect(reader.indexAt(1032), 0);
      expect(reader.indexAt(1033), 1);
      expect(reader.indexAt(1100), 3);
      expect(reader.indexAt(1000 + 33 * 9), 9);
      expect(reader.indexAt(999999), 9);
    });

    test('a picture outside the pack is a range error', () {
      final ReplayReader reader = ReplayReader.parse(ReplayCodec.encode(makeFilm(3)));

      expect(() => reader.frame(-1), throwsRangeError);
      expect(() => reader.frame(3), throwsRangeError);
    });

    test('refuses what it cannot pack', () {
      expect(() => ReplayCodec.encode(const <LumaFrame>[]), throwsArgumentError);
      expect(() => ReplayCodec.encode(makeFilm(2), keyInterval: 0), throwsArgumentError);
      expect(() => ReplayCodec.encode(makeFilm(2), keyInterval: 256), throwsArgumentError);
      expect(
        () => ReplayCodec.encode(<LumaFrame>[
          flatFrame(1, 0),
          LumaFrame(width: 8, height: 8, timestampMs: 33, pixels: Uint8List(64)),
        ]),
        throwsArgumentError,
      );
      final List<LumaFrame> tooMany = <LumaFrame>[
        for (int i = 0; i <= ReplayCodec.maxFrames; i++)
          LumaFrame(width: 8, height: 8, timestampMs: i, pixels: Uint8List(64)),
      ];
      expect(() => ReplayCodec.encode(tooMany), throwsArgumentError);
    });

    test('packs the most pictures it allows', () {
      final List<LumaFrame> film = <LumaFrame>[
        for (int i = 0; i < ReplayCodec.maxFrames; i++)
          LumaFrame(width: 8, height: 8, timestampMs: i * 10, pixels: Uint8List(64)),
      ];

      final ReplayReader reader = ReplayReader.parse(ReplayCodec.encode(film));

      expect(reader.frameCount, ReplayCodec.maxFrames);
      expect(reader.timestampOf(ReplayCodec.maxFrames - 1), (ReplayCodec.maxFrames - 1) * 10);
    });
  });

  group('ReplayReader with damaged files', () {
    late Uint8List pack;

    setUp(() {
      pack = ReplayCodec.encode(makeFilm(20));
    });

    test('refuses anything that is not a pack', () {
      expect(() => ReplayReader.parse(Uint8List(0)), throwsA(isA<ReplayFormatException>()));
      expect(() => ReplayReader.parse(Uint8List(5)), throwsA(isA<ReplayFormatException>()));
      expect(() => ReplayReader.parse(Uint8List(200)), throwsA(isA<ReplayFormatException>()));
      expect(
        () => ReplayReader.parse(Uint8List.fromList(List<int>.generate(100, (int i) => i))),
        throwsA(isA<ReplayFormatException>()),
      );
    });

    test('refuses a pack from a different version of the codec', () {
      final Uint8List other = Uint8List.fromList(pack)..[11] = ReplayCodec.quantStep + 1;

      expect(() => ReplayReader.parse(other), throwsA(isA<ReplayFormatException>()));
    });

    test('refuses a header with a zero size, count or key interval', () {
      for (final int position in <int>[4, 6, 8, 10]) {
        final Uint8List broken = Uint8List.fromList(pack);
        broken[position] = 0;
        broken[position == 10 ? position : position + 1] = 0;

        expect(
          () => ReplayReader.parse(broken),
          throwsA(isA<ReplayFormatException>()),
          reason: 'byte $position zero',
        );
      }
    });

    test('refuses a pack that was cut short, in the table or in the pictures', () {
      expect(() => ReplayReader.parse(pack.sublist(0, 40)), throwsA(isA<ReplayFormatException>()));
      expect(
        () => ReplayReader.parse(pack.sublist(0, pack.length - 10)),
        throwsA(isA<ReplayFormatException>()),
      );
    });
  });

  group('ReplayCodec metadata', () {
    final Map<String, Object?> meta = <String, Object?>{
      'version': 1,
      'name': 'delivery',
      'speed': 112.5,
      'flags': <Object?>[true, false, null],
      'nested': <String, Object?>{'a': 1, 'b': <Object?>[0.25, 'x']},
    };

    test('rides along with the pictures', () {
      final Uint8List pack = ReplayCodec.encode(makeFilm(10));

      final Uint8List withMeta = ReplayCodec.attachMeta(pack, meta);

      expect(withMeta.length, greaterThan(pack.length));
      final ReplayReader reader = ReplayReader.parse(withMeta);
      expect(reader.meta, meta);
      expect(reader.frameCount, 10);
      final ReplayReader plain = ReplayReader.parse(pack);
      for (int i = 0; i < 10; i++) {
        expect(reader.frame(i), plain.frame(i));
      }
    });

    test('a later document replaces an earlier one', () {
      final Uint8List pack = ReplayCodec.encode(makeFilm(10));
      final Map<String, Object?> second = <String, Object?>{'version': 1, 'name': 'second'};

      final Uint8List twice = ReplayCodec.attachMeta(ReplayCodec.attachMeta(pack, meta), second);

      expect(ReplayReader.parse(twice).meta, second);
      expect(twice, ReplayCodec.attachMeta(pack, second));
    });

    test('a pack without a document has none', () {
      expect(ReplayReader.parse(ReplayCodec.encode(makeFilm(3))).meta, isNull);
    });

    test('a damaged document is ignored and the pictures still play', () {
      final Uint8List pack = ReplayCodec.encode(makeFilm(10));
      final Uint8List withMeta = ReplayCodec.attachMeta(pack, meta);
      final Uint8List damaged = Uint8List.fromList(withMeta);
      for (int i = pack.length + 2; i < withMeta.length - 8; i++) {
        damaged[i] = damaged[i] ^ 0x5A;
      }

      final ReplayReader reader = ReplayReader.parse(damaged);

      expect(reader.meta, isNull);
      expect(reader.frameCount, 10);
      expect(worstDifference(reader.frame(5), makeFilm(10)[5].pixels), lessThanOrEqualTo(ReplayCodec.maxError));
    });

    test('a footer that claims an impossible length is no document', () {
      final Uint8List pack = ReplayCodec.encode(makeFilm(10));
      final Uint8List forged = Uint8List(pack.length + 8)..setRange(0, pack.length, pack);
      ByteData.sublistView(forged).setUint32(pack.length, 0xFFFFFFF0, Endian.little);
      forged.setRange(forged.length - 4, forged.length, <int>[0x47, 0x55, 0x4D, 0x31]);

      final ReplayReader reader = ReplayReader.parse(forged);

      expect(reader.meta, isNull);
      expect(reader.frameCount, 10);
    });
  });
}

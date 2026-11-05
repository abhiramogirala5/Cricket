import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:gully_umpire/cv/vision/luma_frame.dart';

/// Why a replay file could not be read.
final class ReplayFormatException implements Exception {
  const ReplayFormatException(this.message);

  final String message;

  @override
  String toString() => 'ReplayFormatException: $message';
}

/// The compact file in which the pictures of one delivery are kept (the "replay pack").
///
/// A delivery is a second or two of small greyscale pictures. Instead of a general video codec
/// (which would need a native plugin and cannot be cut into deliveries while the camera runs) the
/// pack uses a small closed-loop predictive codec:
///
/// * a **key picture** every [keyInterval] pictures is coded row by row, each pixel as a small
///   step from its left neighbour;
/// * every other picture is coded as the step from the previous (already decoded) picture, with a
///   dead zone, so still background (and sensor noise) becomes long runs of zero;
/// * each picture is then compressed with gzip.
///
/// Because the encoder predicts from what the *decoder* will have, errors never add up: every pixel
/// is within [maxError] brightness levels of the original. A table at the start of the file gives
/// the time and position of every picture, so the replay can jump to any moment by decoding from
/// the nearest key picture.
///
/// File layout (little endian):
/// ```
/// 0   4  magic "GUR1"
/// 4   2  width            6   2  height
/// 8   2  picture count   10   1  key interval   11  1  quantiser step
/// 12  4  time of the first picture (ms, informational)
/// 16  12 x count: time since the first picture (i32), payload offset (u32), compressed size (u32)
/// ... payload: the gzip data of each picture
/// ... optional trailer (see [attachMeta]): gzip of a JSON document, its length (u32), "GUM1"
/// ```
abstract final class ReplayCodec {
  static const int _magic0 = 0x47; // G
  static const int _magic1 = 0x55; // U
  static const int _magic2 = 0x52; // R
  static const int _magic3 = 0x31; // 1
  static const int _headerBytes = 16;
  static const int _entryBytes = 12;
  static const List<int> _metaMagic = <int>[0x47, 0x55, 0x4D, 0x31]; // GUM1
  static const int _metaFooterBytes = 8;

  /// Brightness step of the quantiser.
  static const int quantStep = 8;

  /// Biggest difference between a decoded and the original pixel.
  static const int maxError = quantStep ~/ 2;

  /// Pictures between two key pictures.
  static const int defaultKeyInterval = 12;

  /// Most pictures one pack holds (the count is stored in 16 bits).
  static const int maxFrames = 600;

  /// Packs [frames] (same size, oldest first) into one file.
  ///
  /// Throws an [ArgumentError] for an empty list, different sizes or too many pictures.
  static Uint8List encode(List<LumaFrame> frames, {int keyInterval = defaultKeyInterval}) {
    if (frames.isEmpty) {
      throw ArgumentError.value(frames, 'frames', 'needs at least one picture');
    }
    if (frames.length > maxFrames) {
      throw ArgumentError.value(frames.length, 'frames', 'too many pictures for one pack');
    }
    if (keyInterval < 1 || keyInterval > 255) {
      throw ArgumentError.value(keyInterval, 'keyInterval', 'must be 1..255');
    }
    final int width = frames.first.width;
    final int height = frames.first.height;
    if (width > 65535 || height > 65535) {
      throw ArgumentError('Pictures this large cannot be packed');
    }
    for (final LumaFrame frame in frames) {
      if (frame.width != width || frame.height != height) {
        throw ArgumentError('All pictures must have the same size');
      }
    }

    final List<Uint8List> compressed = <Uint8List>[];
    Uint8List previous = Uint8List(width * height);
    for (int i = 0; i < frames.length; i++) {
      final Uint8List residuals = Uint8List(width * height);
      final Uint8List decoded = Uint8List(width * height);
      if (i % keyInterval == 0) {
        _encodeKey(frames[i].pixels, width, height, residuals, decoded);
      } else {
        _encodeDelta(frames[i].pixels, previous, residuals, decoded);
      }
      previous = decoded;
      compressed.add(Uint8List.fromList(gzip.encode(residuals)));
    }

    int payload = 0;
    for (final Uint8List part in compressed) {
      payload += part.length;
    }
    final int tableBytes = frames.length * _entryBytes;
    final Uint8List file = Uint8List(_headerBytes + tableBytes + payload);
    final ByteData data = ByteData.sublistView(file);
    file[0] = _magic0;
    file[1] = _magic1;
    file[2] = _magic2;
    file[3] = _magic3;
    data.setUint16(4, width, Endian.little);
    data.setUint16(6, height, Endian.little);
    data.setUint16(8, frames.length, Endian.little);
    data.setUint8(10, keyInterval);
    data.setUint8(11, quantStep);
    data.setInt32(12, frames.first.timestampMs, Endian.little);
    int offset = 0;
    int cursor = _headerBytes;
    for (int i = 0; i < frames.length; i++) {
      data.setInt32(cursor, frames[i].timestampMs - frames.first.timestampMs, Endian.little);
      data.setUint32(cursor + 4, offset, Endian.little);
      data.setUint32(cursor + 8, compressed[i].length, Endian.little);
      cursor += _entryBytes;
      offset += compressed[i].length;
    }
    final int payloadStart = _headerBytes + tableBytes;
    int write = payloadStart;
    for (final Uint8List part in compressed) {
      file.setRange(write, write + part.length, part);
      write += part.length;
    }
    return file;
  }

  /// Returns a copy of [pack] that carries [meta] (what the app worked out about the delivery) after
  /// the pictures, so one file holds everything the replay needs. An earlier document is replaced.
  ///
  /// [meta] must be JSON-encodable.
  static Uint8List attachMeta(Uint8List pack, Map<String, Object?> meta) {
    final int? existing = _trailerStart(pack, _headerBytes);
    final Uint8List base = existing == null ? pack : Uint8List.sublistView(pack, 0, existing);
    final Uint8List document = Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(meta))));
    final Uint8List out = Uint8List(base.length + document.length + _metaFooterBytes);
    out.setRange(0, base.length, base);
    out.setRange(base.length, base.length + document.length, document);
    final ByteData data = ByteData.sublistView(out);
    data.setUint32(base.length + document.length, document.length, Endian.little);
    out.setRange(out.length - 4, out.length, _metaMagic);
    return out;
  }

  /// Where the metadata trailer of [bytes] starts, or null when there is none (or it cannot fit
  /// after [minStart]).
  static int? _trailerStart(Uint8List bytes, int minStart) {
    if (bytes.length < minStart + _metaFooterBytes) {
      return null;
    }
    for (int i = 0; i < 4; i++) {
      if (bytes[bytes.length - 4 + i] != _metaMagic[i]) {
        return null;
      }
    }
    final int length = ByteData.sublistView(bytes).getUint32(bytes.length - _metaFooterBytes, Endian.little);
    final int start = bytes.length - _metaFooterBytes - length;
    return start >= minStart ? start : null;
  }

  static int _quantise(int residual) {
    // Dead zone of +-(quantStep / 2): small differences (noise) become zero.
    const int half = quantStep ~/ 2;
    final int magnitude = residual < 0 ? -residual : residual;
    int steps = (magnitude + half - 1) ~/ quantStep;
    if (steps > 32) {
      steps = 32;
    }
    return residual < 0 ? -steps : steps;
  }

  static int _clampPixel(int value) => value < 0 ? 0 : (value > 255 ? 255 : value);

  static void _encodeKey(Uint8List source, int width, int height, Uint8List residuals, Uint8List decoded) {
    for (int y = 0; y < height; y++) {
      int left = 128;
      final int row = y * width;
      for (int x = 0; x < width; x++) {
        final int steps = _quantise(source[row + x] - left);
        residuals[row + x] = steps & 0xFF;
        left = _clampPixel(left + steps * quantStep);
        decoded[row + x] = left;
      }
    }
  }

  static void _encodeDelta(Uint8List source, Uint8List previous, Uint8List residuals, Uint8List decoded) {
    for (int i = 0; i < source.length; i++) {
      final int steps = _quantise(source[i] - previous[i]);
      residuals[i] = steps & 0xFF;
      decoded[i] = _clampPixel(previous[i] + steps * quantStep);
    }
  }
}

/// Reads a replay pack picture by picture.
///
/// Playing forward decodes one picture per step; jumping decodes from the nearest key picture
/// (at most `keyInterval - 1` extra pictures). The last decoded picture is cached.
final class ReplayReader {
  ReplayReader._(
    this._bytes,
    this.width,
    this.height,
    this.keyInterval,
    this.startTimestampMs,
    this._times,
    this._offsets,
    this._sizes,
    this._payloadStart,
    this._metaStart,
    this._metaLength,
  );

  /// Parses [bytes]. Throws a [ReplayFormatException] when it is not a replay pack or is damaged.
  factory ReplayReader.parse(Uint8List bytes) {
    const int header = ReplayCodec._headerBytes;
    if (bytes.length < header) {
      throw const ReplayFormatException('The file is too short');
    }
    if (bytes[0] != ReplayCodec._magic0 ||
        bytes[1] != ReplayCodec._magic1 ||
        bytes[2] != ReplayCodec._magic2 ||
        bytes[3] != ReplayCodec._magic3) {
      throw const ReplayFormatException('This is not a replay file');
    }
    final ByteData data = ByteData.sublistView(bytes);
    final int width = data.getUint16(4, Endian.little);
    final int height = data.getUint16(6, Endian.little);
    final int count = data.getUint16(8, Endian.little);
    final int keyInterval = data.getUint8(10);
    final int step = data.getUint8(11);
    final int start = data.getInt32(12, Endian.little);
    if (width == 0 || height == 0 || count == 0 || keyInterval == 0) {
      throw const ReplayFormatException('The replay header is damaged');
    }
    if (step != ReplayCodec.quantStep) {
      throw const ReplayFormatException('This replay was made by a different version');
    }
    final int tableBytes = count * ReplayCodec._entryBytes;
    final int payloadStart = header + tableBytes;
    if (bytes.length < payloadStart) {
      throw const ReplayFormatException('The replay table is cut short');
    }
    final List<int> times = <int>[];
    final List<int> offsets = <int>[];
    final List<int> sizes = <int>[];
    int cursor = header;
    int payloadEnd = payloadStart;
    for (int i = 0; i < count; i++) {
      times.add(data.getInt32(cursor, Endian.little));
      final int offset = data.getUint32(cursor + 4, Endian.little);
      final int size = data.getUint32(cursor + 8, Endian.little);
      final int end = payloadStart + offset + size;
      if (end > bytes.length) {
        throw const ReplayFormatException('The replay data is cut short');
      }
      if (end > payloadEnd) {
        payloadEnd = end;
      }
      offsets.add(offset);
      sizes.add(size);
      cursor += ReplayCodec._entryBytes;
    }
    int metaStart = -1;
    int metaLength = 0;
    final int? trailer = ReplayCodec._trailerStart(bytes, payloadEnd);
    if (trailer != null) {
      metaStart = trailer;
      metaLength = bytes.length - ReplayCodec._metaFooterBytes - trailer;
    }
    return ReplayReader._(
      bytes,
      width,
      height,
      keyInterval,
      start,
      times,
      offsets,
      sizes,
      payloadStart,
      metaStart,
      metaLength,
    );
  }

  final Uint8List _bytes;
  final int width;
  final int height;
  final int keyInterval;

  /// Capture time of the first picture (ms).
  final int startTimestampMs;

  final List<int> _times;
  final List<int> _offsets;
  final List<int> _sizes;
  final int _payloadStart;
  final int _metaStart;
  final int _metaLength;

  int _cachedIndex = -1;
  Uint8List? _cached;

  /// What [ReplayCodec.attachMeta] stored with the pictures, or null when there is nothing (or it is
  /// damaged: the pictures can still be played).
  Map<String, Object?>? get meta {
    if (_metaStart < 0) {
      return null;
    }
    try {
      final List<int> raw = gzip.decode(Uint8List.sublistView(_bytes, _metaStart, _metaStart + _metaLength));
      final Object? decoded = jsonDecode(utf8.decode(raw));
      return decoded is Map<String, Object?> ? decoded : null;
    } on Object {
      return null;
    }
  }

  /// Number of pictures.
  int get frameCount => _times.length;

  /// Capture time (ms) of picture [index].
  int timestampOf(int index) => startTimestampMs + _times[index];

  /// Length of the replay in milliseconds.
  int get durationMs => _times.last - _times.first;

  /// Index of the last picture taken at or before [timestampMs] (0 when it is before the first).
  int indexAt(int timestampMs) {
    final int relative = timestampMs - startTimestampMs;
    int low = 0;
    int high = _times.length - 1;
    int found = 0;
    while (low <= high) {
      final int mid = (low + high) >> 1;
      if (_times[mid] <= relative) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }

  /// The decoded greyscale picture [index] (`width * height` bytes). Do not change the result:
  /// it may be reused by the next call.
  Uint8List frame(int index) {
    if (index < 0 || index >= frameCount) {
      throw RangeError.index(index, _times, 'index');
    }
    if (index == _cachedIndex && _cached != null) {
      return _cached!;
    }
    int from = index - (index % keyInterval);
    if (_cached != null && _cachedIndex >= from && _cachedIndex < index) {
      from = _cachedIndex + 1;
    }
    Uint8List? previous = (from > 0 && from == _cachedIndex + 1) ? _cached : null;
    for (int i = from; i <= index; i++) {
      previous = _decode(i, previous);
    }
    _cachedIndex = index;
    _cached = previous;
    return previous!;
  }

  Uint8List _decode(int index, Uint8List? previous) {
    final int start = _payloadStart + _offsets[index];
    final List<int> raw = gzip.decode(Uint8List.sublistView(_bytes, start, start + _sizes[index]));
    final int count = width * height;
    if (raw.length != count) {
      throw const ReplayFormatException('A replay picture has the wrong size');
    }
    final Uint8List decoded = Uint8List(count);
    final bool isKey = index % keyInterval == 0;
    if (isKey) {
      for (int y = 0; y < height; y++) {
        int left = 128;
        final int row = y * width;
        for (int x = 0; x < width; x++) {
          left = _clamp(left + _signed(raw[row + x]) * ReplayCodec.quantStep);
          decoded[row + x] = left;
        }
      }
    } else {
      final Uint8List base = previous ?? Uint8List(count);
      for (int i = 0; i < count; i++) {
        decoded[i] = _clamp(base[i] + _signed(raw[i]) * ReplayCodec.quantStep);
      }
    }
    return decoded;
  }

  static int _signed(int byte) => byte > 127 ? byte - 256 : byte;

  static int _clamp(int value) => value < 0 ? 0 : (value > 255 ? 255 : value);
}

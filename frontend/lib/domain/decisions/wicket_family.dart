/// The kind of physical object being used as the wicket.
///
/// Wire values match `wicket_detections.wicket_family` (docs/API_CONTRACT.md §5.3).
enum WicketFamily {
  traditionalStumps('TRADITIONAL_STUMPS'),
  chair('CHAIR'),
  brickStack('BRICK_STACK'),
  bottleStack('BOTTLE_STACK'),
  coneStack('CONE_STACK'),
  bucket('BUCKET'),
  bagOrObject('BAG_OR_OBJECT'),
  wallTarget('WALL_TARGET'),
  unknownPhysicalObject('UNKNOWN_PHYSICAL_OBJECT');

  const WicketFamily(this.wire);

  /// UPPER_SNAKE_CASE value used in JSON and in the database.
  final String wire;

  /// Parses a wire value; throws [FormatException] for anything unknown.
  static WicketFamily fromWire(Object? raw) {
    for (final WicketFamily value in WicketFamily.values) {
      if (value.wire == raw) {
        return value;
      }
    }
    throw FormatException('Unknown WicketFamily: $raw');
  }

  /// Short, friendly text for chips and banners.
  String get label {
    switch (this) {
      case WicketFamily.traditionalStumps:
        return 'Stumps';
      case WicketFamily.chair:
        return 'Chair';
      case WicketFamily.brickStack:
        return 'Brick stack';
      case WicketFamily.bottleStack:
        return 'Bottle stack';
      case WicketFamily.coneStack:
        return 'Cone stack';
      case WicketFamily.bucket:
        return 'Bucket';
      case WicketFamily.bagOrObject:
        return 'Bag or object';
      case WicketFamily.wallTarget:
        return 'Wall target';
      case WicketFamily.unknownPhysicalObject:
        return 'Unknown object';
    }
  }
}

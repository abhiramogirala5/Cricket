import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/live/replay_meta.dart';
import 'package:gully_umpire/cv/pipelines/pose_sample.dart';
import 'package:gully_umpire/features/replay/replay_geometry.dart';

import '../../support/replay_fixtures.dart';

void main() {
  group('nearestPose', () {
    final List<PoseSample> poses = <PoseSample>[poseAt(0), poseAt(100), poseAt(200)];

    test('takes the pose measured closest in time', () {
      expect(nearestPose(poses, 140)?.timestampMs, 100);
      expect(nearestPose(poses, 160)?.timestampMs, 200);
      expect(nearestPose(poses, -50)?.timestampMs, 0);
      expect(nearestPose(poses, 900)?.timestampMs, 200);
    });

    test('on a tie the earlier pose wins', () {
      expect(nearestPose(poses, 150)?.timestampMs, 100);
    });

    test('is null when nothing was measured', () {
      expect(nearestPose(const <PoseSample>[], 10), isNull);
    });
  });

  group('batterLinesAt', () {
    test('puts the waist and shoulder lines at their share of the batter height', () {
      final ReplayMeta meta = makeMeta(poses: <PoseSample>[poseAt(0)]);
      final BatterLines? lines = batterLinesAt(meta, 20);
      expect(lines, isNotNull);
      // The batter is 0.6 tall (0.9 - 0.3): waist 0.55 of that, shoulder 0.82 of that.
      expect(lines!.centerX, 0.5);
      expect(lines.groundY, 0.9);
      expect(lines.headY, 0.3);
      expect(lines.waistY, closeTo(0.9 - 0.55 * 0.6, 1e-12));
      expect(lines.shoulderY, closeTo(0.9 - 0.82 * 0.6, 1e-12));
      expect(lines.waistY, greaterThan(lines.shoulderY));
      expect(lines.shoulderY, greaterThan(lines.headY));
    });

    test('uses the ratios stored with the replay', () {
      final ReplayMeta meta = makeMeta(
        poses: <PoseSample>[poseAt(0)],
        waistRatio: 0.5,
        shoulderRatio: 0.8,
      );
      final BatterLines lines = batterLinesAt(meta, 0)!;
      expect(lines.waistY, closeTo(0.9 - 0.5 * 0.6, 1e-12));
      expect(lines.shoulderY, closeTo(0.9 - 0.8 * 0.6, 1e-12));
    });

    test('is null when the batter was never measured or has no height', () {
      expect(batterLinesAt(makeMeta(poses: const <PoseSample>[]), 0), isNull);
      expect(
        batterLinesAt(makeMeta(poses: <PoseSample>[poseAt(0, groundY: 0.5, topY: 0.5)]), 0),
        isNull,
      );
    });
  });

  group('trailUpTo', () {
    final ReplayMeta meta = makeMeta(
      track: <ReplayBallPoint>[ballPoint(0), ballPoint(40), ballPoint(80), ballPoint(120)],
    );

    test('includes every point up to and including the time', () {
      expect(trailUpTo(meta, 80).map((ReplayBallPoint p) => p.timestampMs), <int>[0, 40, 80]);
      expect(trailUpTo(meta, 79).map((ReplayBallPoint p) => p.timestampMs), <int>[0, 40]);
      expect(trailUpTo(meta, 1000), hasLength(4));
    });

    test('is empty before the first point', () {
      expect(trailUpTo(meta, -1), isEmpty);
    });
  });

  group('replayBallAt', () {
    final ReplayMeta meta = makeMeta(
      track: <ReplayBallPoint>[
        ballPoint(0, x: 0.2, y: 0.2, d: 0.01, c: 0.8),
        ballPoint(40, x: 0.4, y: 0.6, d: 0.03, c: 0.6),
        ballPoint(200, x: 0.5, y: 0.9, d: 0.04, c: 0.9),
      ],
    );

    test('returns a tracked point exactly', () {
      expect(replayBallAt(meta, 40)?.y, 0.6);
      expect(replayBallAt(meta, 0)?.x, 0.2);
    });

    test('goes between two close points', () {
      final ReplayBallPoint? middle = replayBallAt(meta, 20);
      expect(middle, isNotNull);
      expect(middle!.timestampMs, 20);
      expect(middle.x, closeTo(0.3, 1e-12));
      expect(middle.y, closeTo(0.4, 1e-12));
      expect(middle.diameter, closeTo(0.02, 1e-12));
      expect(middle.confidence, 0.6, reason: 'never more sure than the weaker neighbour');
    });

    test('never invents a path across a long gap', () {
      // 40 -> 200 is 160 ms apart, more than the 120 ms limit.
      expect(replayBallAt(meta, 100), isNull);
      expect(replayBallAt(meta, 100, maxGapMs: 200), isNotNull);
    });

    test('is not shown before the first point', () {
      expect(replayBallAt(meta, -5), isNull);
    });

    test('stays at the last point only for a moment', () {
      expect(replayBallAt(meta, 250)?.timestampMs, 200);
      expect(replayBallAt(meta, 261), isNull);
    });

    test('an empty track shows nothing', () {
      expect(replayBallAt(makeMeta(track: const <ReplayBallPoint>[]), 10), isNull);
    });
  });

  group('trackPointNear', () {
    final ReplayMeta meta = makeMeta(
      track: <ReplayBallPoint>[ballPoint(0), ballPoint(40), ballPoint(200)],
    );

    test('finds the closest tracked point', () {
      expect(trackPointNear(meta, 35)?.timestampMs, 40);
      expect(trackPointNear(meta, 190)?.timestampMs, 200);
      expect(trackPointNear(meta, -100)?.timestampMs, 0);
    });

    test('is null without a time or without a track', () {
      expect(trackPointNear(meta, null), isNull);
      expect(trackPointNear(makeMeta(track: const <ReplayBallPoint>[]), 10), isNull);
    });
  });

  group('text', () {
    test('metresLabel uses two decimals', () {
      expect(metresLabel(1.05), '1.05 m');
      expect(metresLabel(1), '1.00 m');
    });

    test('ballHeightText shows the height and the margin', () {
      expect(
        ballHeightText(makeMeta(ballHeightM: 1.1, heightUncertaintyM: 0.3)),
        'about 1.10 m, give or take 0.30 m',
      );
      expect(ballHeightText(makeMeta(ballHeightM: 1.1)), 'about 1.10 m');
      expect(ballHeightText(makeMeta(ballHeightM: 1.1, heightUncertaintyM: 0)), 'about 1.10 m');
    });

    test('ballHeightText never shows a negative height and is null when not worked out', () {
      expect(ballHeightText(makeMeta(ballHeightM: -0.1)), 'about 0.00 m');
      expect(ballHeightText(makeMeta()), isNull);
      expect(ballHeightText(makeMeta(ballHeightM: double.nan)), isNull);
    });

    test('bounceText says what is known', () {
      expect(bounceText(makeMeta()), 'Not sure whether it bounced');
      expect(bounceText(makeMeta(bounced: true)), 'Bounced before the batter');
      expect(bounceText(makeMeta(bounced: false)), 'Reached the batter without bouncing');
    });
  });

  group('headingLineOf', () {
    // A ball moving at (0.5, -0.4) picture units a second, a picture every 33 ms: eight points up
    // to 231 ms, which is where it reaches the batter.
    List<ReplayBallPoint> straight({int count = 8, int step = 33}) {
      return <ReplayBallPoint>[
        for (int i = 0; i < count; i++)
          ballPoint(i * step, x: 0.30 + 0.5 * i * step / 1000, y: 0.60 - 0.4 * i * step / 1000),
      ];
    }

    test('follows the straight path up to the batter and points the way it was going', () {
      final HeadingLine? line = headingLineOf(makeMeta(track: straight(), arrivalMs: 231));

      expect(line, isNotNull);
      expect(line!.cutMs, 231);
      expect(line.from.x, closeTo(0.4155, 1e-9));
      expect(line.from.y, closeTo(0.5076, 1e-9));
      expect(line.direction.x, closeTo(0.5 / 0.6403124, 1e-6));
      expect(line.direction.y, closeTo(-0.4 / 0.6403124, 1e-6));
      expect(line.direction.length, closeTo(1, 1e-9));
    });

    test('is cut at the path change when one was seen, whatever the ball did afterwards', () {
      final List<ReplayBallPoint> track = <ReplayBallPoint>[
        ...straight(count: 5),
        // After 132 ms the ball is knocked sideways.
        ballPoint(165, x: 0.60, y: 0.55),
        ballPoint(198, x: 0.70, y: 0.55),
        ballPoint(231, x: 0.80, y: 0.55),
      ];

      final HeadingLine line = headingLineOf(makeMeta(track: track, arrivalMs: 231, contactMs: 132))!;

      expect(line.cutMs, 132);
      expect(line.direction.x, closeTo(0.5 / 0.6403124, 1e-6));
      expect(line.direction.y, closeTo(-0.4 / 0.6403124, 1e-6));
    });

    test('after a bounce only the path after it is followed', () {
      final List<ReplayBallPoint> track = <ReplayBallPoint>[
        for (int t = 0; t <= 99; t += 33) ballPoint(t, x: 0.5, y: 0.2 + 0.003 * t),
        for (int t = 132; t <= 231; t += 33) ballPoint(t, x: 0.5, y: 0.497 - 0.002 * (t - 99)),
      ];

      final HeadingLine line =
          headingLineOf(makeMeta(track: track, arrivalMs: 231, bounced: true, bounceMs: 99))!;

      expect(line.direction.x, closeTo(0, 1e-9));
      expect(line.direction.y, closeTo(-1, 1e-9));
      expect(line.from.y, closeTo(0.233, 1e-9));
    });

    test('gives no line without a moment to cut at', () {
      expect(headingLineOf(makeMeta(track: straight())), isNull);
    });

    test('gives no line from too few points or too short a stretch of time', () {
      expect(headingLineOf(makeMeta(track: straight(count: 3), arrivalMs: 66)), isNull);
      expect(headingLineOf(makeMeta(track: straight(count: 4, step: 20), arrivalMs: 60)), isNull);
    });

    test('gives no line for a path that is not straight', () {
      final List<ReplayBallPoint> zigzag = <ReplayBallPoint>[
        for (int i = 0; i < 8; i++)
          ballPoint(i * 33, x: 0.5 + (i.isEven ? 0.1 : -0.1), y: 0.6 - 0.05 * i),
      ];

      expect(headingLineOf(makeMeta(track: zigzag, arrivalMs: 231)), isNull);
    });

    test('gives no line for a ball that hardly moves in the picture', () {
      final List<ReplayBallPoint> still = <ReplayBallPoint>[
        for (int i = 0; i < 8; i++) ballPoint(i * 33, x: 0.5, y: 0.5),
      ];

      expect(headingLineOf(makeMeta(track: still, arrivalMs: 231)), isNull);
    });
  });

  group('HeadingLine.endAt', () {
    test('ends the given length from the start', () {
      const HeadingLine line =
          HeadingLine(from: Point2D(0.5, 0.5), direction: Point2D(0, -1), cutMs: 0);

      final Point2D end = line.endAt(0.3);

      expect(end.x, closeTo(0.5, 1e-12));
      expect(end.y, closeTo(0.2, 1e-12));
    });

    test('is stopped at the edge of the picture', () {
      const HeadingLine up = HeadingLine(from: Point2D(0.5, 0.5), direction: Point2D(0, -1), cutMs: 0);
      expect(up.endAt(2).y, closeTo(0, 1e-12));

      const double side = 0.7071067811865476;
      const HeadingLine diagonal =
          HeadingLine(from: Point2D(0.9, 0.5), direction: Point2D(side, side), cutMs: 0);
      final Point2D end = diagonal.endAt(2);
      expect(end.x, closeTo(1, 1e-9));
      expect(end.y, closeTo(0.6, 1e-9));
    });
  });

  group('pathChangeText', () {
    test('is null when no change was seen', () {
      expect(pathChangeText(makeMeta(arrivalMs: 700)), isNull);
    });

    test('says when the change came, compared with the ball reaching the batter', () {
      expect(
        pathChangeText(makeMeta(arrivalMs: 700, contactMs: 700)),
        'The path changed suddenly as the ball reached the batter (bat, pad or glove)',
      );
      expect(
        pathChangeText(makeMeta(arrivalMs: 700, contactMs: 640)),
        'The path changed suddenly 60 ms before the ball reached the batter (bat, pad or glove)',
      );
      expect(
        pathChangeText(makeMeta(arrivalMs: 700, contactMs: 760)),
        'The path changed suddenly 60 ms after the ball reached the batter (bat, pad or glove)',
      );
      expect(
        pathChangeText(makeMeta(contactMs: 640)),
        'The path changed suddenly (bat, pad or glove)',
      );
    });
  });
}

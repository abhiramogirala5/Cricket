import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/domain/aggregates/match_list_item.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/features/matches/match_presentation.dart';

// Local (not UTC) times, so the date labels do not depend on the machine's time zone.
final DateTime _created = DateTime(2026, 10, 8, 12);
final DateTime _started = DateTime(2026, 10, 9, 18, 30);

MatchListItem _item(
  String id,
  MatchStatus status, {
  String? name,
  DateTime? startedAt,
  List<Innings> innings = const <Innings>[],
}) {
  return MatchListItem(
    match: CricketMatch(
      id: id,
      teamAId: 'team-a',
      teamBId: 'team-b',
      matchName: name,
      startedAt: startedAt,
      status: status,
      createdAt: _created,
      updatedAt: _created,
    ),
    teamAName: 'Reds',
    teamBName: 'Blues',
    innings: innings,
  );
}

Innings _innings(String battingTeamId, {int runs = 0, int wickets = 0, int balls = 0}) {
  return Innings(
    id: 'innings-$battingTeamId',
    matchId: 'match-1',
    inningsNumber: battingTeamId == 'team-a' ? 1 : 2,
    battingTeamId: battingTeamId,
    bowlingTeamId: battingTeamId == 'team-a' ? 'team-b' : 'team-a',
    totalRuns: runs,
    wickets: wickets,
    legalBalls: balls,
    startedAt: _created,
  );
}

void main() {
  final List<MatchListItem> mixed = <MatchListItem>[
    _item('draft', MatchStatus.draft),
    _item('live', MatchStatus.live),
    _item('done', MatchStatus.completed),
    _item('quit', MatchStatus.abandoned),
    _item('ready', MatchStatus.ready),
  ];

  List<String> ids(List<MatchListItem> items) =>
      items.map<String>((MatchListItem item) => item.match.id).toList();

  group('MatchListItem', () {
    test('uses the match name, trimmed, as the title', () {
      expect(_item('m', MatchStatus.live, name: '  Sunday finals ').title, 'Sunday finals');
    });

    test('falls back to the two team names when there is no usable name', () {
      expect(_item('m', MatchStatus.live).title, 'Reds vs Blues');
      expect(_item('m', MatchStatus.live, name: '   ').title, 'Reds vs Blues');
    });

    test('isOpen is false only for finished matches', () {
      expect(_item('m', MatchStatus.draft).isOpen, isTrue);
      expect(_item('m', MatchStatus.live).isOpen, isTrue);
      expect(_item('m', MatchStatus.completed).isOpen, isFalse);
      expect(_item('m', MatchStatus.abandoned).isOpen, isFalse);
    });
  });

  group('filterMatches', () {
    test('all keeps everything in order', () {
      expect(ids(filterMatches(mixed, MatchFilter.all)),
          <String>['draft', 'live', 'done', 'quit', 'ready']);
    });

    test('in progress keeps every match that can still be scored', () {
      expect(ids(filterMatches(mixed, MatchFilter.inProgress)),
          <String>['draft', 'live', 'ready']);
    });

    test('finished keeps completed and abandoned matches', () {
      expect(ids(filterMatches(mixed, MatchFilter.finished)), <String>['done', 'quit']);
    });

    test('an empty list stays empty', () {
      for (final MatchFilter filter in MatchFilter.values) {
        expect(filterMatches(const <MatchListItem>[], filter), isEmpty);
      }
    });

    test('filters have the labels shown on the chips', () {
      expect(MatchFilter.values.map<String>((MatchFilter f) => f.label),
          <String>['All', 'In progress', 'Finished']);
    });
  });

  group('resumableMatch', () {
    test('is null when there are no matches', () {
      expect(resumableMatch(const <MatchListItem>[]), isNull);
    });

    test('is null when every match is finished', () {
      expect(
        resumableMatch(<MatchListItem>[
          _item('a', MatchStatus.completed),
          _item('b', MatchStatus.abandoned),
        ]),
        isNull,
      );
    });

    test('prefers a live match over a newer unfinished one', () {
      final MatchListItem? result = resumableMatch(<MatchListItem>[
        _item('newest-ready', MatchStatus.ready),
        _item('older-live', MatchStatus.live),
        _item('oldest-live', MatchStatus.live),
      ]);
      expect(result?.match.id, 'older-live');
    });

    test('otherwise offers the newest unfinished match', () {
      final MatchListItem? result = resumableMatch(<MatchListItem>[
        _item('done', MatchStatus.completed),
        _item('newest-draft', MatchStatus.draft),
        _item('older-ready', MatchStatus.ready),
      ]);
      expect(result?.match.id, 'newest-draft');
    });
  });

  group('score lines', () {
    test('inningsScoreLine writes runs, wickets and overs', () {
      final Innings innings = _innings('team-a', runs: 54, wickets: 3, balls: 26);
      expect(inningsScoreLine('Reds', innings), 'Reds 54/3 (4.2 ov)');
    });

    test('a fresh innings reads 0/0 (0.0 ov)', () {
      expect(inningsScoreLine('Blues', _innings('team-b')), 'Blues 0/0 (0.0 ov)');
    });

    test('scoreLines has one line per innings, named after the batting team', () {
      final MatchListItem item = _item(
        'm',
        MatchStatus.live,
        innings: <Innings>[
          _innings('team-a', runs: 30, wickets: 2, balls: 12),
          _innings('team-b', runs: 8, wickets: 0, balls: 7),
        ],
      );
      expect(scoreLines(item), <String>['Reds 30/2 (2.0 ov)', 'Blues 8/0 (1.1 ov)']);
    });

    test('scoreLines is empty before the first innings', () {
      expect(scoreLines(_item('m', MatchStatus.ready)), isEmpty);
    });
  });

  group('matchDateLabel', () {
    test('shows when the match started', () {
      final CricketMatch match = _item('m', MatchStatus.live, startedAt: _started).match;
      expect(matchDateLabel(match), '9 Oct 2026');
    });

    test('falls back to when it was created', () {
      expect(matchDateLabel(_item('m', MatchStatus.draft).match), '8 Oct 2026');
    });
  });

  group('statusColors', () {
    test('live is white on pitch green', () {
      final ({Color foreground, Color background}) colors = statusColors(MatchStatus.live);
      expect(colors.foreground, Colors.white);
      expect(colors.background, AppColors.pitchGreen);
    });

    test('matches that have not started share the amber chip', () {
      for (final MatchStatus status in <MatchStatus>[
        MatchStatus.draft,
        MatchStatus.scanning,
        MatchStatus.ready,
      ]) {
        final ({Color foreground, Color background}) colors = statusColors(status);
        expect(colors.foreground, AppColors.creaseAmberInk, reason: status.wire);
        expect(colors.background, AppColors.creaseAmberTint, reason: status.wire);
      }
    });

    test('completed and abandoned look different from each other', () {
      expect(statusColors(MatchStatus.completed).background, AppColors.grassTint);
      expect(statusColors(MatchStatus.abandoned).background, AppColors.outline);
    });
  });
}

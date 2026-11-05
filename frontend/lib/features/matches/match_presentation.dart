import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/core/utils/formatters.dart';
import 'package:gully_umpire/domain/aggregates/match_list_item.dart';
import 'package:gully_umpire/domain/models/models.dart';

/// Which matches the list shows.
enum MatchFilter {
  all('All'),
  inProgress('In progress'),
  finished('Finished');

  const MatchFilter(this.label);

  final String label;
}

List<MatchListItem> filterMatches(List<MatchListItem> items, MatchFilter filter) {
  switch (filter) {
    case MatchFilter.all:
      return items;
    case MatchFilter.inProgress:
      return items.where((MatchListItem item) => item.isOpen).toList(growable: false);
    case MatchFilter.finished:
      return items.where((MatchListItem item) => !item.isOpen).toList(growable: false);
  }
}

/// The match to offer on the home page: one being played, otherwise the newest unfinished one.
/// [items] must be newest first.
MatchListItem? resumableMatch(List<MatchListItem> items) {
  MatchListItem? firstOpen;
  for (final MatchListItem item in items) {
    if (!item.isOpen) {
      continue;
    }
    if (item.match.status == MatchStatus.live) {
      return item;
    }
    firstOpen ??= item;
  }
  return firstOpen;
}

/// `Gully Kings 54/3 (4.2 ov)`.
String inningsScoreLine(String teamName, Innings innings) =>
    '$teamName ${innings.totalRuns}/${innings.wickets} (${formatOvers(innings.legalBalls)} ov)';

/// One line per innings that has started. Empty before the first ball.
List<String> scoreLines(MatchListItem item) {
  return <String>[
    for (final Innings innings in item.innings)
      inningsScoreLine(item.teamName(innings.battingTeamId), innings),
  ];
}

/// The date shown on a match: when it started, or when it was created.
String matchDateLabel(CricketMatch match) => formatDate(match.startedAt ?? match.createdAt);

({Color foreground, Color background}) statusColors(MatchStatus status) {
  switch (status) {
    case MatchStatus.live:
      return (foreground: Colors.white, background: AppColors.pitchGreen);
    case MatchStatus.draft:
    case MatchStatus.scanning:
    case MatchStatus.ready:
      return (foreground: AppColors.creaseAmberInk, background: AppColors.creaseAmberTint);
    case MatchStatus.completed:
      return (foreground: AppColors.pitchGreenDark, background: AppColors.grassTint);
    case MatchStatus.abandoned:
      return (foreground: AppColors.inkMuted, background: AppColors.outline);
  }
}

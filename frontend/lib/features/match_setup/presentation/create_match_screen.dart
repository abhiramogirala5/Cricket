import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gully_umpire/app/router/routes.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/config/app_config.dart';
import 'package:gully_umpire/core/di/core_providers.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/core/widgets/friendly_error.dart';
import 'package:gully_umpire/core/widgets/message_banner.dart';
import 'package:gully_umpire/core/widgets/screen_body.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/setup/match_setup.dart';
import 'package:gully_umpire/features/match_setup/presentation/rules_editor.dart';
import 'package:gully_umpire/features/match_setup/presentation/team_editor.dart';
import 'package:gully_umpire/features/match_setup/team_draft.dart';

/// The "new match" form: teams and players, overs, optional name and place, optional rules.
class CreateMatchScreen extends ConsumerStatefulWidget {
  const CreateMatchScreen({super.key});

  @override
  ConsumerState<CreateMatchScreen> createState() => _CreateMatchScreenState();
}

class _CreateMatchScreenState extends ConsumerState<CreateMatchScreen> {
  static const List<int> _quickOvers = <int>[2, 5, 6, 10, 20];

  final TeamDraft _teamA = TeamDraft();
  final TeamDraft _teamB = TeamDraft();
  final TextEditingController _matchName = TextEditingController();
  final TextEditingController _place = TextEditingController();
  int _overs = 6;
  MatchRules _rules = const MatchRules(matchId: '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _teamA.dispose();
    _teamB.dispose();
    _matchName.dispose();
    _place.dispose();
    super.dispose();
  }

  void _redraw() => setState(() => _error = null);

  void _setOvers(int value) {
    final int clamped = value
        .clamp(CricketMatch.minOvers, CricketMatch.maxOvers)
        .toInt();
    setState(() => _overs = clamped);
  }

  NewMatchInput _buildInput() => NewMatchInput(
        teamA: _teamA.toInput(),
        teamB: _teamB.toInput(),
        matchName: _matchName.text,
        locationName: _place.text,
        oversPerInnings: _overs,
        rules: _rules,
      );

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    final NewMatchInput input = _buildInput();
    final String? problem = validateNewMatch(input);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final MatchBundle bundle = await ref.read(matchRepositoryProvider).createMatch(input);
      if (!mounted) {
        return;
      }
      context.pushReplacement(Routes.match(bundle.match.id));
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = friendlyError(error);
      });
    }
  }

  List<String> _savedTeamNames(List<Team> teams, TeamDraft other) {
    final String otherName = other.trimmedName.toLowerCase();
    return <String>[
      for (final Team team in teams)
        if (team.name.trim().toLowerCase() != otherName) team.name,
    ].take(6).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final AppConfig config = ref.watch(appConfigProvider);
    final List<Player> savedPlayers =
        ref.watch(playersProvider).valueOrNull ?? const <Player>[];
    final List<Team> savedTeams = ref.watch(teamsProvider).valueOrNull ?? const <Team>[];
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('New match')),
      body: ScreenBody(
        children: <Widget>[
          TextField(
            controller: _matchName,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Match name (optional)',
              hintText: 'Sunday friendly',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _place,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Place (optional)',
              hintText: 'Lane 4 ground',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Overs per innings',
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      IconButton.filledTonal(
                        tooltip: 'Fewer overs',
                        onPressed: _overs > CricketMatch.minOvers
                            ? () => _setOvers(_overs - 1)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      SizedBox(
                        width: 96,
                        child: Text(
                          '$_overs',
                          textAlign: TextAlign.center,
                          style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'More overs',
                        onPressed: _overs < CricketMatch.maxOvers
                            ? () => _setOvers(_overs + 1)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      children: <Widget>[
                        for (final int value in _quickOvers)
                          ChoiceChip(
                            label: Text('$value'),
                            selected: _overs == value,
                            onSelected: (_) => _setOvers(value),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TeamEditor(
            title: 'Team 1',
            draft: _teamA,
            savedPlayers: savedPlayers,
            unavailablePlayerIds: _teamB.savedIds,
            savedTeamNames: _savedTeamNames(savedTeams, _teamB),
            onChanged: _redraw,
          ),
          const SizedBox(height: AppSpacing.lg),
          TeamEditor(
            title: 'Team 2',
            draft: _teamB,
            savedPlayers: savedPlayers,
            unavailablePlayerIds: _teamA.savedIds,
            savedTeamNames: _savedTeamNames(savedTeams, _teamA),
            onChanged: _redraw,
          ),
          const SizedBox(height: AppSpacing.lg),
          RulesEditor(
            rules: _rules,
            showEdgeReview: config.enableEdgeReview,
            showLbwReview: config.enableLbwReview,
            onChanged: (MatchRules value) => setState(() => _rules = value),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_error != null) ...<Widget>[
            MessageBanner(message: _error!, kind: BannerKind.error),
            const SizedBox(height: AppSpacing.md),
          ],
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text('Create match'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'You can score the match as soon as it is created.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}

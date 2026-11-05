import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/features/players/presentation/players_screen.dart';

import '../../support/model_fixtures.dart';

Player _player({BattingHand hand = BattingHand.unknown, int? height}) => Player(
      id: 'p',
      displayName: 'Asha',
      battingHand: hand,
      declaredHeightCm: height,
      createdAt: t0,
      updatedAt: t0,
    );

void main() {
  group('playerSubtitle', () {
    test('says when nothing is set', () {
      expect(playerSubtitle(_player()), 'Details not set');
    });

    test('shows hand and height together', () {
      expect(
        playerSubtitle(_player(hand: BattingHand.left, height: 168)),
        'Left-handed · 168 cm',
      );
    });

    test('shows whichever one is set', () {
      expect(playerSubtitle(_player(hand: BattingHand.right)), 'Right-handed');
      expect(playerSubtitle(_player(height: 170)), '170 cm');
    });
  });
}

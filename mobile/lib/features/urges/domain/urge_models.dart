import '../../onboarding/domain/onboarding_models.dart';

/// Same members as the backend's urge outcome.
enum UrgeOutcome {
  passed,
  gambled,

  /// Left unresolved: the app was closed, or a new urge was started before this one ended.
  abandoned,
}

abstract final class UrgePause {
  static const options = [10, 20, 30, 60];
  static const defaultMinutes = 20;
  static const extensionMinutes = 10;

  /// An unresolved urge older than this is no longer treated as in progress.
  static const staleAfter = Duration(hours: 12);

  static Duration remaining({required DateTime startedAt, required int minutes, required DateTime now}) {
    final left = startedAt.add(Duration(minutes: minutes)).difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// "09:05" — minutes and seconds, rounded up so the display never shows 00:00 early.
  static String format(Duration d) {
    final seconds = (d.inMilliseconds / 1000).ceil();
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

const intensityLabels = {1: 'Mild', 3: 'Strong', 5: 'Very strong'};

/// What to read during the pause. Practical and kind; never lectures or shames.
abstract final class UrgeGuidance {
  static const opening = "That's okay. Urges rise and fall, and most pass within a few minutes if you give them time.";

  static const breathing = 'Breathe in slowly for 4, hold for 4, and breathe out for 6. Repeat a few times.';

  static const grounding = [
    'Name 5 things you can see.',
    'Notice 4 things you can feel, like your feet on the floor.',
    'Listen for 3 sounds around you.',
    'Find 2 things you can smell.',
    'Notice 1 thing you can taste.',
  ];

  static List<String> tipsFor(TriggerType trigger) => switch (trigger) {
        TriggerType.stress => [
            'Gambling can feel like a break from stress, but it usually adds more.',
            'Step outside or walk for ten minutes before deciding anything.',
          ],
        TriggerType.boredom => [
            'Boredom urges fade fastest when your hands are busy.',
            'Message someone, cook something or put on a show for the length of this pause.',
          ],
        TriggerType.payday => [
            'Pay the things that matter first: rent, food, transport, the people who rely on you.',
            'Moving money out of easy reach for a few days takes the pressure off.',
          ],
        TriggerType.tryingToRecoverLosses => [
            'Trying to win it back is how a loss usually gets bigger.',
            "The money that's gone is gone. The money you still have is yours to keep.",
          ],
        TriggerType.alcohol => [
            'Urges feel stronger after a drink, and decisions feel easier than they are.',
            'Put the phone in another room until the morning if you can.',
          ],
        TriggerType.friendsGambling => [
            "It's fine to sit this one out. You don't owe anyone an explanation.",
            'Suggest something else to do together, or step away for a while.',
          ],
        TriggerType.loneliness => [
            'Reaching out to one person, even with a short message, can ease this.',
            "Feeling lonely is hard. It doesn't need a bet to make it better.",
          ],
        TriggerType.excitement => [
            'The rush is real, and so is what it costs afterwards.',
            'Look for something that gets your heart going without the money: a run, music, a game with friends.',
          ],
        TriggerType.financialPressure => [
            'When money is tight a big win can seem like the answer. It rarely is.',
            'A financial counsellor can help you make a plan for what you owe.',
          ],
        TriggerType.other => [
            'Notice what was happening just before this urge. That alone helps.',
            'Give it the full pause before deciding anything.',
          ],
      };

  static const passed = 'You gave the urge time and it passed. That gets a little easier each time you do it.';

  static const gambled =
      "Thank you for being honest. One time doesn't undo the progress you've made. Logging what you spent keeps the picture clear.";
}

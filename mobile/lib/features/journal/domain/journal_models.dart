// Same members as the backend's journal enums.

enum JournalOutcome {
  noUrge('No urge'),
  resisted('Got through it'),
  gambled('Gambled');

  const JournalOutcome(this.label);
  final String label;
}

/// What helped (or what the user tried) when an urge came up.
enum CopingStrategy {
  walked('Went for a walk or moved'),
  talkedToSomeone('Talked to someone'),
  breathing('Breathing or grounding'),
  distraction('Did something else'),
  blockedSites('Blocking kept me out'),
  leftPhone('Put the phone away'),
  rememberedGoal('Thought about my goal'),
  other('Something else');

  const CopingStrategy(this.label);
  final String label;
}

abstract final class MoodScale {
  static const labels = {1: 'Very low', 2: 'Low', 3: 'Okay', 4: 'Good', 5: 'Very good'};
}

const maxJournalNoteLength = 2000;

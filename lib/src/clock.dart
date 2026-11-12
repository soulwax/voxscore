import 'dart:math' as math;

/// Musical quantization grid for section transitions and stingers.
enum MusicQuantization {
  immediate,
  nextBeat,
  nextBar,
  nextPhrase,
}

/// Deterministic BPM and bar/beat timeline clock for interactive music synchronization.
final class MusicalClock {
  double bpm;
  int beatsPerBar;
  int barsPerPhrase;
  double elapsedSeconds = 0.0;

  int _lastWholeBeat = -1;
  int _lastBar = -1;

  MusicalClock({
    this.bpm = 120.0,
    this.beatsPerBar = 4,
    this.barsPerPhrase = 4,
    this.elapsedSeconds = 0.0,
  });

  double get beatDurationSeconds => 60.0 / math.max(1.0, bpm);
  double get barDurationSeconds => beatDurationSeconds * math.max(1, beatsPerBar);
  double get phraseDurationSeconds => barDurationSeconds * math.max(1, barsPerPhrase);

  double get totalBeats => elapsedSeconds / beatDurationSeconds;
  int get currentWholeBeat => (totalBeats + 1e-9).floor();
  int get currentBar => (totalBeats + 1e-9) ~/ math.max(1, beatsPerBar);
  int get beatInBar => currentWholeBeat % math.max(1, beatsPerBar);
  double get beatPhase => totalBeats - totalBeats.floorToDouble();

  /// Computes the wall-clock [elapsedSeconds] of the next [quantization] boundary.
  double nextBoundarySeconds(MusicQuantization quantization) {
    switch (quantization) {
      case MusicQuantization.immediate:
        return elapsedSeconds;
      case MusicQuantization.nextBeat:
        final nextBeatIdx = ((totalBeats + 1e-9).floor() + 1);
        return nextBeatIdx * beatDurationSeconds;
      case MusicQuantization.nextBar:
        final totalBars = totalBeats / math.max(1, beatsPerBar);
        final nextBarIdx = ((totalBars + 1e-9).floor() + 1);
        return nextBarIdx * barDurationSeconds;
      case MusicQuantization.nextPhrase:
        final phraseBeats = math.max(1, beatsPerBar) * math.max(1, barsPerPhrase);
        final totalPhrases = totalBeats / phraseBeats;
        final nextPhraseIdx = ((totalPhrases + 1e-9).floor() + 1);
        return nextPhraseIdx * phraseDurationSeconds;
    }
  }

  /// Advances clock by [dt] seconds and reports whether beat or bar boundaries crossed.
  ({bool beatCrossed, bool barCrossed}) advance(double dt) {
    if (dt <= 0.0) return (beatCrossed: false, barCrossed: false);
    if (_lastWholeBeat < 0) _lastWholeBeat = currentWholeBeat;
    if (_lastBar < 0) _lastBar = currentBar;

    elapsedSeconds += dt;
    final b = currentWholeBeat;
    final bar = currentBar;
    final beatCrossed = b > _lastWholeBeat;
    final barCrossed = bar > _lastBar;
    _lastWholeBeat = b;
    _lastBar = bar;
    return (beatCrossed: beatCrossed, barCrossed: barCrossed);
  }

  void reset([double startSeconds = 0.0]) {
    elapsedSeconds = startSeconds;
    _lastWholeBeat = currentWholeBeat;
    _lastBar = currentBar;
  }
}

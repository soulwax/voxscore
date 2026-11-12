import 'dart:collection';
import 'dart:math' as math;

import 'clock.dart';

/// Vertical musical layer activated within an intensity band with smooth fade envelopes.
final class MusicStemLayer {
  final String id;
  final double minIntensity;
  final double maxIntensity;
  final double fadeInSeconds;
  final double fadeOutSeconds;
  final double maxGain;
  bool muted;
  bool solo;

  MusicStemLayer({
    required this.id,
    this.minIntensity = 0.0,
    this.maxIntensity = 1.0,
    this.fadeInSeconds = 0.75,
    this.fadeOutSeconds = 1.0,
    this.maxGain = 1.0,
    this.muted = false,
    this.solo = false,
  });

  double targetGainFor(double intensity, {required bool anySoloActive}) {
    if (muted) return 0.0;
    if (anySoloActive && !solo) return 0.0;
    final x = intensity.clamp(0.0, 1.0);
    if (x + 1e-9 < minIntensity || x - 1e-9 > maxIntensity) return 0.0;
    return maxGain;
  }
}

/// Musical loopable arrangement block owning BPM, meter, and vertical stem layers.
final class MusicSectionDef {
  final String id;
  final String name;
  final double bpm;
  final int beatsPerBar;
  final int barsPerLoop;
  final List<MusicStemLayer> stems;
  final double crossfadeSeconds;

  MusicSectionDef({
    required this.id,
    required this.name,
    this.bpm = 120.0,
    this.beatsPerBar = 4,
    this.barsPerLoop = 8,
    List<MusicStemLayer>? stems,
    this.crossfadeSeconds = 0.6,
  }) : stems = stems ?? [];
}

/// Beat-quantized one-shot orchestral/synth stinger that ducks stem gain smoothly.
final class MusicStingerCue {
  final String id;
  final MusicQuantization quantization;
  final double durationSeconds;
  final double duckAmount;
  final double attackSeconds;
  final double releaseSeconds;

  const MusicStingerCue({
    required this.id,
    this.quantization = MusicQuantization.nextBeat,
    this.durationSeconds = 1.5,
    this.duckAmount = 0.45,
    this.attackSeconds = 0.05,
    this.releaseSeconds = 0.35,
  });
}

final class _ScheduledTransition {
  final String targetSectionId;
  final double executeAtSeconds;
  final MusicQuantization quantization;

  _ScheduledTransition({
    required this.targetSectionId,
    required this.executeAtSeconds,
    required this.quantization,
  });
}

final class _QueuedStinger {
  final MusicStingerCue cue;
  final double triggerAtSeconds;
  bool triggered = false;
  double ageSinceTrigger = 0.0;

  _QueuedStinger({required this.cue, required this.triggerAtSeconds});

  bool get isExpired => triggered && ageSinceTrigger >= cue.durationSeconds;

  double duckMultiplier() {
    if (!triggered || isExpired) return 1.0;
    final att = math.max(1e-4, cue.attackSeconds);
    final rel = math.max(1e-4, cue.releaseSeconds);
    var env = 1.0;
    if (ageSinceTrigger < att) {
      env = ageSinceTrigger / att;
    } else if (ageSinceTrigger > cue.durationSeconds - rel) {
      env = ((cue.durationSeconds - ageSinceTrigger) / rel).clamp(0.0, 1.0);
    }
    return (1.0 - cue.duckAmount.clamp(0.0, 0.95) * env).toDouble();
  }
}

/// Per-frame evaluated mix snapshot driving scene audio stems and stingers.
final class ScoreMixSnapshot {
  final String? activeSectionId;
  final String? pendingSectionId;
  final int currentBar;
  final int beatInBar;
  final double intensity;
  final double musicDuckMultiplier;
  final Map<String, double> stemGains;
  final List<String> firedStingersThisStep;

  const ScoreMixSnapshot({
    required this.activeSectionId,
    required this.pendingSectionId,
    required this.currentBar,
    required this.beatInBar,
    required this.intensity,
    required this.musicDuckMultiplier,
    required this.stemGains,
    required this.firedStingersThisStep,
  });
}

/// Interactive adaptive score state machine synchronizing vertical stems, horizontal
/// quantized transitions, and stinger ducking on [MusicalClock].
final class InteractiveScoreConductor {
  final MusicalClock clock;
  final Map<String, MusicSectionDef> _sections = {};
  final Map<String, MusicStingerCue> _stingers = {};
  final Map<String, double> _stemGains = {};
  final List<_QueuedStinger> _activeStingers = [];

  String? _activeSectionId;
  _ScheduledTransition? _pendingTransition;

  double intensity;
  double targetIntensity;
  double intensitySmoothingPerSecond;

  void Function(int beatIndex)? onBeat;
  void Function(int barIndex)? onBar;
  void Function(String? previousSectionId, String nextSectionId)? onSectionChanged;
  void Function(MusicStingerCue stinger)? onStingerTriggered;

  InteractiveScoreConductor({
    MusicalClock? clock,
    double initialIntensity = 0.2,
    this.intensitySmoothingPerSecond = 2.5,
  })  : clock = clock ?? MusicalClock(),
        intensity = initialIntensity.clamp(0.0, 1.0).toDouble(),
        targetIntensity = initialIntensity.clamp(0.0, 1.0).toDouble();

  String? get activeSectionId => _activeSectionId;
  String? get pendingSectionId => _pendingTransition?.targetSectionId;
  MusicSectionDef? get activeSection =>
      _activeSectionId == null ? null : _sections[_activeSectionId!];

  Map<String, double> get currentStemGains => UnmodifiableMapView(_stemGains);

  void registerSection(MusicSectionDef section) {
    _sections[section.id] = section;
    for (final s in section.stems) {
      _stemGains.putIfAbsent(s.id, () => 0.0);
    }
  }

  void registerStinger(MusicStingerCue stinger) {
    _stingers[stinger.id] = stinger;
  }

  void setIntensity(double value, {bool immediate = false}) {
    targetIntensity = value.clamp(0.0, 1.0).toDouble();
    if (immediate) intensity = targetIntensity;
  }

  /// Starts [sectionId] immediately and aligns [clock] BPM/meter.
  bool startSection(String sectionId) {
    final sec = _sections[sectionId];
    if (sec == null) return false;
    final prev = _activeSectionId;
    _activeSectionId = sectionId;
    _pendingTransition = null;
    clock
      ..bpm = sec.bpm
      ..beatsPerBar = sec.beatsPerBar;
    if (prev == null) clock.reset(0.0);
    onSectionChanged?.call(prev, sectionId);
    return true;
  }

  /// Requests transition to [sectionId] on [quantization] boundary.
  bool requestSection(
    String sectionId, {
    MusicQuantization quantization = MusicQuantization.nextBar,
  }) {
    if (!_sections.containsKey(sectionId)) return false;
    if (_activeSectionId == null || quantization == MusicQuantization.immediate) {
      return startSection(sectionId);
    }
    if (_activeSectionId == sectionId && _pendingTransition == null) return true;
    _pendingTransition = _ScheduledTransition(
      targetSectionId: sectionId,
      executeAtSeconds: clock.nextBoundarySeconds(quantization),
      quantization: quantization,
    );
    return true;
  }

  /// Enqueues [stingerId] to trigger on its quantization grid boundary.
  bool queueStinger(String stingerId) {
    final cue = _stingers[stingerId];
    if (cue == null) return false;
    _activeStingers.add(
      _QueuedStinger(
        cue: cue,
        triggerAtSeconds: clock.nextBoundarySeconds(cue.quantization),
      ),
    );
    return true;
  }

  /// Advances musical clock, fires quantized cues, ramps stem gains & returns mix snapshot.
  ScoreMixSnapshot step(double dt) {
    final stepDt = math.max(0.0, dt);
    final events = clock.advance(stepDt);

    if ((intensity - targetIntensity).abs() > 1e-5) {
      final alpha = 1.0 - math.exp(-math.max(0.1, intensitySmoothingPerSecond) * stepDt);
      intensity = (intensity + (targetIntensity - intensity) * alpha)
          .clamp(0.0, 1.0)
          .toDouble();
    } else {
      intensity = targetIntensity;
    }

    if (events.beatCrossed) onBeat?.call(clock.currentWholeBeat);
    if (events.barCrossed) onBar?.call(clock.currentBar);

    final pending = _pendingTransition;
    if (pending != null && clock.elapsedSeconds + 1e-7 >= pending.executeAtSeconds) {
      startSection(pending.targetSectionId);
    }

    final firedThisStep = <String>[];
    var duckMult = 1.0;
    for (final st in _activeStingers) {
      if (!st.triggered && clock.elapsedSeconds + 1e-7 >= st.triggerAtSeconds) {
        st.triggered = true;
        st.ageSinceTrigger = (clock.elapsedSeconds - st.triggerAtSeconds).clamp(0.0, st.cue.durationSeconds);
        firedThisStep.add(st.cue.id);
        onStingerTriggered?.call(st.cue);
      } else if (st.triggered) {
        st.ageSinceTrigger += stepDt;
      }
      final m = st.duckMultiplier();
      if (m < duckMult) duckMult = m;
    }
    _activeStingers.removeWhere((s) => s.isExpired);

    // Compute per-stem target gain & apply fade envelopes
    final sec = activeSection;
    final activeStems = <String, MusicStemLayer>{
      if (sec != null)
        for (final s in sec.stems) s.id: s,
    };
    final anySolo = sec?.stems.any((s) => s.solo) ?? false;

    for (final stemId in _stemGains.keys.toList()) {
      final stem = activeStems[stemId];
      final desiredRaw =
          stem?.targetGainFor(intensity, anySoloActive: anySolo) ?? 0.0;
      final curr = _stemGains[stemId] ?? 0.0;
      if (desiredRaw > curr) {
        final fadeIn = math.max(1e-3, stem?.fadeInSeconds ?? 0.75);
        _stemGains[stemId] = math.min(desiredRaw, curr + stepDt / fadeIn);
      } else if (desiredRaw < curr) {
        final fadeOut = math.max(1e-3, stem?.fadeOutSeconds ?? 1.0);
        _stemGains[stemId] = math.max(desiredRaw, curr - stepDt / fadeOut);
      }
    }

    final outputGains = <String, double>{
      for (final entry in _stemGains.entries) entry.key: entry.value * duckMult,
    };

    return ScoreMixSnapshot(
      activeSectionId: _activeSectionId,
      pendingSectionId: _pendingTransition?.targetSectionId,
      currentBar: clock.currentBar,
      beatInBar: clock.beatInBar,
      intensity: intensity,
      musicDuckMultiplier: duckMult,
      stemGains: UnmodifiableMapView(outputGains),
      firedStingersThisStep: List.unmodifiable(firedThisStep),
    );
  }
}

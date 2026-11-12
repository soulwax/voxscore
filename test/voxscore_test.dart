import 'package:test/test.dart';
import 'package:voxscore/voxscore.dart';

void main() {
  test('MusicalClock tracks BPM beats, bars & exact nextBeat/nextBar boundaries', () {
    final clock = MusicalClock(bpm: 120.0, beatsPerBar: 4, barsPerPhrase: 2);
    expect(clock.beatDurationSeconds, closeTo(0.5, 1e-6));
    expect(clock.barDurationSeconds, closeTo(2.0, 1e-6));
    expect(clock.nextBoundarySeconds(MusicQuantization.nextBeat), closeTo(0.5, 1e-6));
    expect(clock.nextBoundarySeconds(MusicQuantization.nextBar), closeTo(2.0, 1e-6));

    clock.advance(0.6);
    expect(clock.currentWholeBeat, 1);
    expect(clock.beatInBar, 1);
    expect(clock.nextBoundarySeconds(MusicQuantization.nextBeat), closeTo(1.0, 1e-6));
    expect(clock.nextBoundarySeconds(MusicQuantization.nextBar), closeTo(2.0, 1e-6));
    expect(clock.nextBoundarySeconds(MusicQuantization.nextPhrase), closeTo(4.0, 1e-6));
  });

  test('InteractiveScoreConductor smoothly crossfades vertical stems by intensity band', () {
    final conductor = InteractiveScoreConductor(
      initialIntensity: 0.1,
      intensitySmoothingPerSecond: 10.0,
    )..registerSection(
        MusicSectionDef(
          id: 'explore',
          name: 'Exploration',
          bpm: 120.0,
          stems: [
            MusicStemLayer(id: 'pad', minIntensity: 0.0, fadeInSeconds: 0.2),
            MusicStemLayer(id: 'drums', minIntensity: 0.5, fadeInSeconds: 0.25, fadeOutSeconds: 0.25),
            MusicStemLayer(id: 'brass', minIntensity: 0.8, fadeInSeconds: 0.25),
          ],
        ),
      );
    conductor.startSection('explore');

    for (var i = 0; i < 10; i++) {
      conductor.step(0.05);
    }
    expect(conductor.currentStemGains['pad'], closeTo(1.0, 0.05));
    expect(conductor.currentStemGains['drums'], closeTo(0.0, 1e-6));
    expect(conductor.currentStemGains['brass'], closeTo(0.0, 1e-6));

    conductor.setIntensity(0.95);
    for (var i = 0; i < 16; i++) {
      conductor.step(0.05);
    }
    expect(conductor.currentStemGains['drums'], greaterThan(0.8));
    expect(conductor.currentStemGains['brass'], greaterThan(0.8));
  });

  test('InteractiveScoreConductor quantizes section switches to bar and fires ducking stingers on beat', () {
    final conductor = InteractiveScoreConductor(initialIntensity: 0.5);
    conductor
      ..registerSection(
        MusicSectionDef(
          id: 'stealth',
          name: 'Stealth',
          bpm: 120.0,
          stems: [MusicStemLayer(id: 'bass', fadeInSeconds: 0.1, fadeOutSeconds: 0.1)],
        ),
      )
      ..registerSection(
        MusicSectionDef(
          id: 'boss',
          name: 'Boss Combat',
          bpm: 150.0,
          stems: [MusicStemLayer(id: 'choir', fadeInSeconds: 0.1)],
        ),
      )
      ..registerStinger(
        const MusicStingerCue(
          id: 'stinger_alert',
          quantization: MusicQuantization.nextBeat,
          durationSeconds: 1.0,
          duckAmount: 0.5,
          attackSeconds: 0.02,
          releaseSeconds: 0.2,
        ),
      );

    conductor.startSection('stealth');
    conductor.step(0.2); // inside beat 0 (< 0.5s), bar 0 (< 2.0s)
    conductor.requestSection('boss', quantization: MusicQuantization.nextBar);
    conductor.queueStinger('stinger_alert');

    // Before next beat at 0.5s: neither stinger nor boss triggered
    final snapBeforeBeat = conductor.step(0.2); // t = 0.4s
    expect(snapBeforeBeat.activeSectionId, 'stealth');
    expect(snapBeforeBeat.firedStingersThisStep, isEmpty);

    // Crosses beat 1 at 0.5s -> stinger fires & ducks music stems; boss still waiting until bar 1 (2.0s)
    final snapAtBeat = conductor.step(0.2); // t = 0.6s
    expect(snapAtBeat.firedStingersThisStep, ['stinger_alert']);
    expect(snapAtBeat.musicDuckMultiplier, lessThan(0.6));
    expect(snapAtBeat.activeSectionId, 'stealth');
    expect(snapAtBeat.pendingSectionId, 'boss');

    // Step across bar 1 at 2.0s -> boss transitions smoothly and stinger finishes & restores ducking
    for (var i = 0; i < 16; i++) {
      conductor.step(0.1);
    }
    final snapFinal = conductor.step(0.05);
    expect(snapFinal.activeSectionId, 'boss');
    expect(snapFinal.pendingSectionId, isNull);
    expect(conductor.clock.bpm, 150.0);
    expect(snapFinal.musicDuckMultiplier, closeTo(1.0, 1e-6));
  });
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/song.dart';
import '../models/stem_track.dart';
import '../models/setlist.dart';
import 'pitch_shifter.dart';

class AudioEngine extends ChangeNotifier {
  Setlist? _currentSetlist;
  int _currentSongIndex = 0;
  
  bool _isPlaying = false;
  bool _isSplitModeActive = true; // True = Modo Show (L: Click/Guia | R: P.A.)
  int _pitchOffset = 0;           // -6 a +6 semitons

  double _currentPositionSeconds = 0.0;
  double _totalDurationSeconds = 288.0; // 04:48
  int _currentBar = 1;
  int _currentBeat = 1;
  Timer? _playbackTicker;

  AudioEngine() {
    _initializeMockData();
  }

  // Getters
  Setlist? get currentSetlist => _currentSetlist;
  int get currentSongIndex => _currentSongIndex;
  Song? get currentSong {
    if (_currentSetlist == null || _currentSetlist!.songs.isEmpty) return null;
    return _currentSetlist!.songs[_currentSongIndex];
  }
  bool get isPlaying => _isPlaying;
  bool get isSplitModeActive => _isSplitModeActive;
  int get pitchOffset => _pitchOffset;
  double get currentPositionSeconds => _currentPositionSeconds;
  double get totalDurationSeconds => _totalDurationSeconds;
  int get currentBar => _currentBar;
  int get currentBeat => _currentBeat;

  String get currentKey {
    final song = currentSong;
    if (song == null) return 'C';
    return PitchShifterService.transposeNote(song.originalKey, _pitchOffset);
  }

  // Controles de Reprodução
  void togglePlay() {
    _isPlaying = !_isPlaying;
    if (_isPlaying) {
      WakelockPlus.enable(); // Não deixar a tela do celular apagar no palco
      _startTicker();
    } else {
      WakelockPlus.disable();
      _playbackTicker?.cancel();
    }
    notifyListeners();
  }

  void stop() {
    _isPlaying = false;
    _currentPositionSeconds = 0.0;
    _currentBar = 1;
    _currentBeat = 1;
    _playbackTicker?.cancel();
    WakelockPlus.disable();
    notifyListeners();
  }

  void nextSong() {
    if (_currentSetlist != null && _currentSongIndex < _currentSetlist!.songs.length - 1) {
      _currentSongIndex++;
      _pitchOffset = 0;
      stop();
    }
  }

  void previousSong() {
    if (_currentSongIndex > 0) {
      _currentSongIndex--;
      _pitchOffset = 0;
      stop();
    }
  }

  void selectSong(int index) {
    if (_currentSetlist != null && index >= 0 && index < _currentSetlist!.songs.length) {
      _currentSongIndex = index;
      _pitchOffset = 0;
      stop();
    }
  }

  // Transposição de Tom (Pitch Shift)
  void setPitchOffset(int semitones) {
    _pitchOffset = semitones.clamp(-6, 6);
    notifyListeners();
  }

  void incrementPitch() {
    if (_pitchOffset < 6) {
      _pitchOffset++;
      notifyListeners();
    }
  }

  void decrementPitch() {
    if (_pitchOffset > -6) {
      _pitchOffset--;
      notifyListeners();
    }
  }

  void resetPitch() {
    _pitchOffset = 0;
    notifyListeners();
  }

  // Controle de Mixer de Pistas (Stems)
  void setStemVolume(String stemId, double volume) {
    final song = currentSong;
    if (song == null) return;

    final stem = song.stems.firstWhere((s) => s.id == stemId);
    stem.volume = volume.clamp(0.0, 1.0);
    notifyListeners();
  }

  void toggleMute(String stemId) {
    final song = currentSong;
    if (song == null) return;

    final stem = song.stems.firstWhere((s) => s.id == stemId);
    stem.isMuted = !stem.isMuted;
    notifyListeners();
  }

  void toggleSolo(String stemId) {
    final song = currentSong;
    if (song == null) return;

    final stem = song.stems.firstWhere((s) => s.id == stemId);
    stem.isSolo = !stem.isSolo;
    notifyListeners();
  }

  void toggleSplitMode() {
    _isSplitModeActive = !_isSplitModeActive;
    notifyListeners();
  }

  void seekTo(double seconds) {
    _currentPositionSeconds = seconds.clamp(0.0, _totalDurationSeconds);
    notifyListeners();
  }

  // Timer de simulação do compasso e andamento
  void _startTicker() {
    _playbackTicker?.cancel();
    _playbackTicker = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!_isPlaying) return;
      _currentPositionSeconds += 0.2;
      if (_currentPositionSeconds >= _totalDurationSeconds) {
        stop();
        return;
      }

      // Calcula compasso baseado no BPM
      final song = currentSong;
      final bpm = song?.bpm ?? 120;
      final beatsPerSecond = bpm / 60.0;
      final totalBeats = (_currentPositionSeconds * beatsPerSecond).toInt();
      _currentBar = (totalBeats / 4).toInt() + 1;
      _currentBeat = (totalBeats % 4) + 1;

      notifyListeners();
    });
  }

  void _initializeMockData() {
    _currentSetlist = Setlist(
      id: 'setlist-1',
      title: 'Culto / Show de Domingo',
      date: DateTime.now(),
      isOfflineReady: true,
      songs: [
        Song(
          id: 'song-1',
          title: 'Vitorioso És',
          artist: 'Gabriel Guedes',
          originalKey: 'B',
          bpm: 130,
          isMultiTrack: true,
          stems: [
            StemTrack(id: 's1-click', name: 'CLICK', isCue: true, volume: 0.95),
            StemTrack(id: 's1-guia', name: 'GUIA', isCue: true, volume: 0.8),
            StemTrack(id: 's1-pad', name: 'PAD / AMBIENCE', isCue: false, volume: 0.85),
            StemTrack(id: 's1-keys', name: 'TECLADOS', isCue: false, volume: 0.75),
            StemTrack(id: 's1-guitars', name: 'GUITARRAS', isCue: false, volume: 0.7),
          ],
        ),
        Song(
          id: 'song-2',
          title: 'Bondade de Deus',
          artist: 'Isaías Saad',
          originalKey: 'Ab',
          bpm: 70,
          isMultiTrack: false, // Faixa única L/R
          stems: [
            StemTrack(id: 's2-click', name: 'CLICK (L)', isCue: true, volume: 0.95),
            StemTrack(id: 's2-pa', name: 'PLAYBACK (R)', isCue: false, volume: 0.85),
          ],
        ),
        Song(
          id: 'song-3',
          title: 'Ousado Amor',
          artist: 'Isaias Saad',
          originalKey: 'G',
          bpm: 68,
          timeSignature: '6/8',
          isMultiTrack: true,
          sections: [
            const SongSection(name: 'Intro', startSeconds: 0, startBar: 1),
            const SongSection(name: 'Verso 1', startSeconds: 28, startBar: 9),
            const SongSection(name: 'Refrão', startSeconds: 65, startBar: 17),
            const SongSection(name: 'Verso 2', startSeconds: 110, startBar: 29),
            const SongSection(name: 'Ponte', startSeconds: 160, startBar: 41),
            const SongSection(name: 'Final', startSeconds: 220, startBar: 55),
          ],
          chordsText: '''
INTRO: [ 6/8 ]
Em7   D   C9   (2x)

VERSO 1
Em7                D                 C9
Antes de eu falar, Tu cantavas sobre mim
Em7               D             C9
Tu tens sido tão, tão bom pra mim
Em7                D                 C9
Antes de eu respirar, sopraste Tua vida em mim
Em7               D             C9
Tu tens sido tão, tão bom pra mim

REFRÃO
Em7            D                   C9         G
Oh, impressionante, infinito e ousado amor de Deus
Em7           D                 C9        G
Oh, que deixa as noventa e nove só pra me buscar
Em7             D                C9            G
Não posso comprá-lo, nem merecê-lo, mesmo assim se entregou
Em7            D                   C9         G
Oh, impressionante, infinito e ousado amor de Deus
''',
          stems: [
            StemTrack(id: 's3-click', name: 'CLICK', isCue: true, volume: 0.95),
            StemTrack(id: 's3-guia', name: 'GUIA', isCue: true, volume: 0.80),
            StemTrack(id: 's3-pad', name: 'PAD / ATMO', isCue: false, volume: 0.85),
            StemTrack(id: 's3-keys', name: 'TECLADOS', isCue: false, volume: 0.70),
            StemTrack(id: 's3-guitars', name: 'GUITARRAS', isCue: false, volume: 0.65),
            StemTrack(id: 's3-vox', name: 'VOZES FX', isCue: false, volume: 0.60),
          ],
        ),
      ],
    );
    _currentSongIndex = 2; // Começa na música 3 (Ousado Amor)
  }

  @override
  void dispose() {
    _playbackTicker?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }
}

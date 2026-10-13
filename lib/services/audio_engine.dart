import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/song.dart';
import '../models/stem_track.dart';
import '../models/setlist.dart';
import 'pitch_shifter.dart';

class AudioEngine extends ChangeNotifier {
  // ACERVO GERAL (Todas as músicas já cadastradas pela banda)
  final List<Song> _masterLibrary = [];

  // PLAYLIST ATUAL (Músicas selecionadas para a semana/show)
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
  List<Song> get masterLibrary => List.unmodifiable(_masterLibrary);
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

  // ==========================================
  // GESTÃO DO ACERVO & PLAYLISTS
  // ==========================================

  /// Salva uma música no Acervo Geral
  void addSongToLibrary(Song song) {
    if (!_masterLibrary.any((s) => s.id == song.id)) {
      _masterLibrary.add(song);
      notifyListeners();
    }
  }

  /// Adiciona uma música do Acervo para a Playlist da semana
  void addSongToCurrentSetlist(Song song) {
    if (_currentSetlist != null) {
      _currentSetlist!.songs.add(song);
      notifyListeners();
    }
  }

  /// Adiciona múltiplas músicas selecionadas do Acervo
  void addMultipleSongsToSetlist(List<Song> songs) {
    if (_currentSetlist != null) {
      _currentSetlist!.songs.addAll(songs);
      notifyListeners();
    }
  }

  /// Remove uma música da playlist da semana (sem apagar do acervo geral)
  void removeSongFromSetlist(int index) {
    if (_currentSetlist != null && index >= 0 && index < _currentSetlist!.songs.length) {
      _currentSetlist!.songs.removeAt(index);
      if (_currentSongIndex >= _currentSetlist!.songs.length) {
        _currentSongIndex = (_currentSetlist!.songs.length - 1).clamp(0, 999);
      }
      notifyListeners();
    }
  }

  // Controles de Reprodução
  void togglePlay() {
    _isPlaying = !_isPlaying;
    if (_isPlaying) {
      WakelockPlus.enable();
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

  void _startTicker() {
    _playbackTicker?.cancel();
    _playbackTicker = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!_isPlaying) return;
      _currentPositionSeconds += 0.2;
      if (_currentPositionSeconds >= _totalDurationSeconds) {
        stop();
        return;
      }

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
    // 1. Cria músicas do Acervo Geral (Master Library)
    final songVitorioso = Song(
      id: 'lib-1',
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
    );

    final songBondade = Song(
      id: 'lib-2',
      title: 'Bondade de Deus',
      artist: 'Isaías Saad',
      originalKey: 'Ab',
      bpm: 70,
      isMultiTrack: false,
      stems: [
        StemTrack(id: 's2-click', name: 'CLICK (L)', isCue: true, volume: 0.95),
        StemTrack(id: 's2-pa', name: 'PLAYBACK (R)', isCue: false, volume: 0.85),
      ],
    );

    final songOusado = Song(
      id: 'lib-3',
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

REFRÃO
Em7            D                   C9         G
Oh, impressionante, infinito e ousado amor de Deus
Em7           D                 C9        G
Oh, que deixa as noventa e nove só pra me buscar
''',
      stems: [
        StemTrack(id: 's3-click', name: 'CLICK', isCue: true, volume: 0.95),
        StemTrack(id: 's3-guia', name: 'GUIA', isCue: true, volume: 0.80),
        StemTrack(id: 's3-pad', name: 'PAD / ATMO', isCue: false, volume: 0.85),
        StemTrack(id: 's3-keys', name: 'TECLADOS', isCue: false, volume: 0.70),
        StemTrack(id: 's3-guitars', name: 'GUITARRAS', isCue: false, volume: 0.65),
      ],
    );

    final songRuja = Song(
      id: 'lib-4',
      title: 'Ruja o Leão',
      artist: 'Talita Catanzaro',
      originalKey: 'Em',
      bpm: 74,
      isMultiTrack: true,
      stems: [
        StemTrack(id: 's4-click', name: 'CLICK', isCue: true, volume: 0.95),
        StemTrack(id: 's4-guia', name: 'GUIA', isCue: true, volume: 0.80),
        StemTrack(id: 's4-pad', name: 'PAD', isCue: false, volume: 0.85),
      ],
    );

    final songGraca = Song(
      id: 'lib-5',
      title: 'Graça Sem Fim',
      artist: 'Morada',
      originalKey: 'D',
      bpm: 72,
      isMultiTrack: true,
      stems: [
        StemTrack(id: 's5-click', name: 'CLICK', isCue: true, volume: 0.95),
        StemTrack(id: 's5-pad', name: 'PAD', isCue: false, volume: 0.85),
      ],
    );

    final songEleVive = Song(
      id: 'lib-6',
      title: 'Porque Ele Vive',
      artist: 'Harpa Cristã',
      originalKey: 'G',
      bpm: 76,
      isMultiTrack: false,
      stems: [
        StemTrack(id: 's6-click', name: 'CLICK (L)', isCue: true, volume: 0.95),
        StemTrack(id: 's6-pa', name: 'TRACK (R)', isCue: false, volume: 0.85),
      ],
    );

    _masterLibrary.addAll([
      songVitorioso,
      songBondade,
      songOusado,
      songRuja,
      songGraca,
      songEleVive,
    ]);

    // 2. Setlist inicial com algumas músicas selecionadas do acervo
    _currentSetlist = Setlist(
      id: 'setlist-1',
      title: 'Culto de Domingo',
      date: DateTime.now(),
      isOfflineReady: true,
      songs: [
        songVitorioso,
        songBondade,
        songOusado,
        songRuja,
      ],
    );
    _currentSongIndex = 2; // Ousado Amor
  }

  @override
  void dispose() {
    _playbackTicker?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }
}

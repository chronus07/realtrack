import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/song.dart';
import '../models/stem_track.dart';
import '../models/setlist.dart';
import 'pitch_shifter.dart';
import 'supabase_service.dart';

class AudioEngine extends ChangeNotifier {
  // ACERVO GERAL (Inicia 100% limpo, sem músicas de teste)
  final List<Song> _masterLibrary = [];

  // GESTÃO DE MÚLTIPLAS PLAYLISTS
  final List<Setlist> _allSetlists = [];
  Setlist? _currentSetlist;
  int _currentSongIndex = 0;
  
  bool _isPlaying = false;
  bool _isSplitModeActive = true; // True = Modo Show (L: Click/Guia | R: P.A.)
  int _pitchOffset = 0;           // -6 a +6 semitons

  double _currentPositionSeconds = 0.0;
  double _totalDurationSeconds = 240.0;
  int _currentBar = 1;
  int _currentBeat = 1;
  Timer? _playbackTicker;

  AudioEngine() {
    _initializeCleanState();
  }

  // Getters
  List<Song> get masterLibrary => List.unmodifiable(_masterLibrary);
  List<Setlist> get allSetlists => List.unmodifiable(_allSetlists);
  Setlist? get currentSetlist => _currentSetlist;
  int get currentSongIndex => _currentSongIndex;
  Song? get currentSong {
    if (_currentSetlist == null || _currentSetlist!.songs.isEmpty) return null;
    if (_currentSongIndex >= _currentSetlist!.songs.length) return null;
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

  // GESTÃO DO ACERVO
  void setLibrary(List<Song> songs) {
    _masterLibrary.clear();
    _masterLibrary.addAll(songs);
    notifyListeners();
  }

  void addSongToLibrary(Song song) {
    if (!_masterLibrary.any((s) => s.id == song.id)) {
      _masterLibrary.add(song);
      notifyListeners();
    }
  }

  void removeSongFromLibrary(String songId) {
    _masterLibrary.removeWhere((s) => s.id == songId);
    for (final setlist in _allSetlists) {
      setlist.songs.removeWhere((s) => s.id == songId);
    }
    if (_currentSetlist != null && _currentSongIndex >= _currentSetlist!.songs.length) {
      _currentSongIndex = (_currentSetlist!.songs.length - 1).clamp(0, 999);
    }
    notifyListeners();
  }

  // GESTÃO DE MÚLTIPLAS PLAYLISTS
  void setAllSetlists(List<Setlist> list, {String? selectId}) {
    if (list.isEmpty) {
      if (_allSetlists.isEmpty) {
        _initializeCleanState();
      }
      return;
    }
    _allSetlists.clear();
    _allSetlists.addAll(list);

    if (selectId != null) {
      _currentSetlist = _allSetlists.firstWhere(
        (s) => s.id == selectId,
        orElse: () => _allSetlists.first,
      );
    } else if (_currentSetlist != null) {
      _currentSetlist = _allSetlists.firstWhere(
        (s) => s.id == _currentSetlist!.id,
        orElse: () => _allSetlists.first,
      );
    } else {
      _currentSetlist = _allSetlists.first;
    }
    _currentSongIndex = 0;
    _pitchOffset = (_currentSetlist != null && _currentSetlist!.songs.isNotEmpty)
        ? _currentSetlist!.songs[0].pitchOffsetSemitones
        : 0;
    notifyListeners();
  }

  void selectSetlist(String id) {
    final found = _allSetlists.firstWhere((s) => s.id == id, orElse: () => _allSetlists.first);
    _currentSetlist = found;
    _currentSongIndex = 0;
    _pitchOffset = found.songs.isNotEmpty ? found.songs[0].pitchOffsetSemitones : 0;
    _isPlaying = false;
    _playbackTicker?.cancel();
    notifyListeners();
  }

  Setlist createNewSetlist(String title, {String? customId}) {
    final cleanTitle = title.trim().isEmpty ? 'Nova Playlist' : title.trim();
    final newSetlist = Setlist(
      id: customId ?? SupabaseService.generateUuid(),
      title: cleanTitle,
      date: DateTime.now(),
      isOfflineReady: true,
      songs: [],
    );
    _allSetlists.insert(0, newSetlist);
    _currentSetlist = newSetlist;
    _currentSongIndex = 0;
    _pitchOffset = 0;
    notifyListeners();
    return newSetlist;
  }

  void updateSetlistTitle(String id, String newTitle) {
    final cleanTitle = newTitle.trim().isEmpty ? 'Playlist' : newTitle.trim();
    for (final s in _allSetlists) {
      if (s.id == id) {
        s.title = cleanTitle;
      }
    }
    if (_currentSetlist?.id == id) {
      _currentSetlist!.title = cleanTitle;
    }
    notifyListeners();
  }

  void deleteSetlist(String id) {
    _allSetlists.removeWhere((s) => s.id == id);
    if (_allSetlists.isEmpty) {
      _initializeCleanState();
    } else if (_currentSetlist?.id == id) {
      _currentSetlist = _allSetlists.first;
      _currentSongIndex = 0;
      _pitchOffset = _currentSetlist!.songs.isNotEmpty ? _currentSetlist!.songs[0].pitchOffsetSemitones : 0;
    }
    notifyListeners();
  }

  void addSongToSetlist(String setlistId, Song song) {
    final target = _allSetlists.firstWhere((s) => s.id == setlistId, orElse: () => _currentSetlist!);
    if (!target.songs.any((s) => s.id == song.id)) {
      target.songs.add(song);
      notifyListeners();
    }
  }

  void addSongToCurrentSetlist(Song song) {
    if (_currentSetlist != null) {
      if (!_currentSetlist!.songs.any((s) => s.id == song.id)) {
        _currentSetlist!.songs.add(song);
        notifyListeners();
      }
    }
  }

  void addMultipleSongsToSetlist(List<Song> songs) {
    if (_currentSetlist != null) {
      for (final song in songs) {
        if (!_currentSetlist!.songs.any((s) => s.id == song.id)) {
          _currentSetlist!.songs.add(song);
        }
      }
      notifyListeners();
    }
  }

  void removeSongFromSetlist(int index) {
    if (_currentSetlist != null && index >= 0 && index < _currentSetlist!.songs.length) {
      _currentSetlist!.songs.removeAt(index);
      if (_currentSongIndex >= _currentSetlist!.songs.length) {
        _currentSongIndex = (_currentSetlist!.songs.length - 1).clamp(0, 999);
      }
      notifyListeners();
    }
  }

  void setCurrentSetlist(Setlist setlist) {
    final idx = _allSetlists.indexWhere((s) => s.id == setlist.id);
    if (idx != -1) {
      _allSetlists[idx] = setlist;
    } else {
      _allSetlists.add(setlist);
    }
    _currentSetlist = setlist;
    _currentSongIndex = 0;
    _pitchOffset = (setlist.songs.isNotEmpty) ? setlist.songs[0].pitchOffsetSemitones : 0;
    notifyListeners();
  }

  void reorderSetlistSong(int oldIndex, int newIndex) {
    if (_currentSetlist == null) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final song = _currentSetlist!.songs.removeAt(oldIndex);
    _currentSetlist!.songs.insert(newIndex, song);
    notifyListeners();
  }

  void updateSongPitchOffset(int songIndex, int offset) {
    if (_currentSetlist == null || songIndex < 0 || songIndex >= _currentSetlist!.songs.length) return;
    final song = _currentSetlist!.songs[songIndex];
    song.pitchOffsetSemitones = offset.clamp(-6, 6);
    song.currentKey = PitchShifterService.transposeNote(song.originalKey, song.pitchOffsetSemitones);
    if (songIndex == _currentSongIndex) {
      _pitchOffset = song.pitchOffsetSemitones;
    }
    notifyListeners();
  }

  // Controles de Reprodução
  void togglePlay() {
    if (currentSong == null) return;
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
      final song = _currentSetlist!.songs[index];
      _pitchOffset = song.pitchOffsetSemitones;
      stop();
    }
  }

  void setPitchOffset(int semitones) {
    _pitchOffset = semitones.clamp(-6, 6);
    final song = currentSong;
    if (song != null) {
      song.pitchOffsetSemitones = _pitchOffset;
      song.currentKey = PitchShifterService.transposeNote(song.originalKey, _pitchOffset);
    }
    notifyListeners();
  }

  void incrementPitch() {
    if (_pitchOffset < 6) {
      setPitchOffset(_pitchOffset + 1);
    }
  }

  void decrementPitch() {
    if (_pitchOffset > -6) {
      setPitchOffset(_pitchOffset - 1);
    }
  }

  void resetPitch() {
    setPitchOffset(0);
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

  // Inicializa o sistema 100% limpo sem dados mockados
  void _initializeCleanState() {
    _masterLibrary.clear();
    final defaultSetlist = Setlist(
      id: '00000000-0000-0000-0000-000000000001',
      title: 'Culto Principal',
      date: DateTime.now(),
      isOfflineReady: true,
      songs: [],
    );
    _allSetlists.clear();
    _allSetlists.add(defaultSetlist);
    _currentSetlist = defaultSetlist;
    _currentSongIndex = 0;
  }

  @override
  void dispose() {
    _playbackTicker?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }
}

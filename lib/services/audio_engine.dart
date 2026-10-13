import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import '../config/app_config.dart';
import '../models/song.dart';
import '../models/stem_track.dart';
import '../models/setlist.dart';
import 'audio_cache_service.dart';
import 'pitch_shifter.dart';
import 'supabase_service.dart';

class AudioEngine extends ChangeNotifier {
  // ACERVO GERAL (Sincronizado com o Supabase)
  final List<Song> _masterLibrary = [];

  // GESTÃO DE MÚLTIPLAS PLAYLISTS
  final List<Setlist> _allSetlists = [];
  Setlist? _currentSetlist;
  int _currentSongIndex = 0;

  // PLAYERS DE ÁUDIO REAL PARA AS PISTAS
  final Map<String, AudioPlayer> _stemPlayers = {};
  String? _masterStemId;
  bool _isLoadingAudio = false;
  bool get isLoadingAudio => _isLoadingAudio;

  bool _isPlaying = false;
  bool _isSplitModeActive = true; // True = Modo Palco/Cabo Y (L: Click/Guia | R: P.A.)
  int _pitchOffset = 0;           // -6 a +6 semitons

  double _currentPositionSeconds = 0.0;
  double _totalDurationSeconds = 240.0;
  int _currentBar = 1;
  int _currentBeat = 1;
  int _lastNotifiedMillis = 0;

  Timer? _playbackTicker;
  Timer? _driftCheckTimer;
  Timer? _cloudSyncTimer;
  RealtimeChannel? _realtimeChannel;
  bool _isSyncingCloud = false;

  final Map<String, int> _lastStemSeekTimes = {};

  AudioEngine() {
    _initializeCleanState();
    startCloudAutoSync();
    syncFromCloudSilently();
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
  bool get isSyncingCloud => _isSyncingCloud;

  String get currentKey {
    final song = currentSong;
    if (song == null) return 'C';
    return PitchShifterService.transposeNote(song.originalKey, _pitchOffset);
  }

  // ==========================================
  // SINCRONIZAÇÃO EM TEMPO REAL ENTRE DISPOSITIVOS
  // ==========================================

  void startCloudAutoSync() {
    _setupRealtimeSubscription();
    _cloudSyncTimer?.cancel();
    _cloudSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      syncFromCloudSilently();
    });
  }

  void _setupRealtimeSubscription() {
    if (!AppConfig.isConfigured) return;
    try {
      _realtimeChannel = SupabaseService.client.channel('realtracks_live_sync');
      _realtimeChannel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'setlists',
        callback: (payload) {
          debugPrint('📡 [Realtime] Atualização em setlists: ${payload.eventType}');
          syncFromCloudSilently();
        },
      );
      _realtimeChannel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'setlist_songs',
        callback: (payload) {
          debugPrint('📡 [Realtime] Atualização em setlist_songs: ${payload.eventType}');
          syncFromCloudSilently();
        },
      );
      _realtimeChannel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'songs',
        callback: (payload) {
          debugPrint('📡 [Realtime] Atualização no acervo songs: ${payload.eventType}');
          syncFromCloudSilently();
        },
      );
      _realtimeChannel!.subscribe();
    } catch (e) {
      debugPrint('Erro ao conectar Supabase Realtime: $e');
    }
  }

  Future<void> syncFromCloudSilently() async {
    if (!AppConfig.isConfigured || _isSyncingCloud) return;
    _isSyncingCloud = true;

    try {
      // 1. Atualiza Acervo Geral
      final cloudSongs = await SupabaseService.fetchAllLibrarySongs();
      if (cloudSongs.isNotEmpty) {
        _masterLibrary.clear();
        _masterLibrary.addAll(cloudSongs);
      }

      // 2. Atualiza Playlists
      final cloudSetlists = await SupabaseService.fetchAllSetlists();
      if (cloudSetlists.isNotEmpty) {
        final currentId = _currentSetlist?.id;
        _allSetlists.clear();
        _allSetlists.addAll(cloudSetlists);

        if (currentId != null) {
          final matched = _allSetlists.firstWhere(
            (s) => s.id == currentId,
            orElse: () => _allSetlists.first,
          );
          _currentSetlist = matched;
          if (_currentSongIndex >= _currentSetlist!.songs.length) {
            _currentSongIndex = (_currentSetlist!.songs.length - 1).clamp(0, 999);
          }
        } else {
          _currentSetlist = _allSetlists.first;
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Silently sync error: $e');
    } finally {
      _isSyncingCloud = false;
    }
  }

  // ==========================================
  // GESTÃO DO ACERVO GERAL
  // ==========================================

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

  Future<void> removeSongFromLibrary(String songId) async {
    _masterLibrary.removeWhere((s) => s.id == songId);
    for (final setlist in _allSetlists) {
      setlist.songs.removeWhere((s) => s.id == songId);
    }
    if (_currentSetlist != null && _currentSongIndex >= _currentSetlist!.songs.length) {
      _currentSongIndex = (_currentSetlist!.songs.length - 1).clamp(0, 999);
    }
    notifyListeners();
    await SupabaseService.deleteSongFromLibrary(songId);
  }

  // ==========================================
  // GESTÃO DE MÚLTIPLAS PLAYLISTS
  // ==========================================

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
    _driftCheckTimer?.cancel();
    _disposeStemPlayers();
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

    SupabaseService.saveSetlistToCloud(newSetlist);
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

    SupabaseService.updateSetlistTitleOnCloud(id, cleanTitle);
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

    SupabaseService.deleteSetlistFromCloud(id);
  }

  void addSongToSetlist(String setlistId, Song song) {
    final target = _allSetlists.firstWhere((s) => s.id == setlistId, orElse: () => _currentSetlist!);
    if (!target.songs.any((s) => s.id == song.id)) {
      target.songs.add(song);
      notifyListeners();
      SupabaseService.saveSetlistToCloud(target);
    }
  }

  void addSongToCurrentSetlist(Song song) {
    if (_currentSetlist != null) {
      if (!_currentSetlist!.songs.any((s) => s.id == song.id)) {
        _currentSetlist!.songs.add(song);
        notifyListeners();
        SupabaseService.saveSetlistToCloud(_currentSetlist!);
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
      SupabaseService.saveSetlistToCloud(_currentSetlist!);
    }
  }

  void removeSongFromSetlist(int index) {
    if (_currentSetlist != null && index >= 0 && index < _currentSetlist!.songs.length) {
      _currentSetlist!.songs.removeAt(index);
      if (_currentSongIndex >= _currentSetlist!.songs.length) {
        _currentSongIndex = (_currentSetlist!.songs.length - 1).clamp(0, 999);
      }
      notifyListeners();
      SupabaseService.saveSetlistToCloud(_currentSetlist!);
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
    SupabaseService.saveSetlistToCloud(_currentSetlist!);
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
    SupabaseService.saveSetlistToCloud(_currentSetlist!);
  }

  // ==========================================
  // REPRODUÇÃO MULTITRACKS COM SINCRONISMO DE ALTA PRECISÃO
  // ==========================================

  void _disposeStemPlayers() {
    _driftCheckTimer?.cancel();
    _playbackTicker?.cancel();
    for (final player in _stemPlayers.values) {
      try {
        player.stop();
        player.dispose();
      } catch (_) {}
    }
    _stemPlayers.clear();
    _masterStemId = null;
    _lastStemSeekTimes.clear();
  }

  void togglePlay() {
    if (currentSong == null) return;
    if (_isPlaying) {
      _pausePlayback();
    } else {
      _startPlayback();
    }
  }

  Future<void> _startPlayback() async {
    final song = currentSong;
    if (song == null) return;

    _isLoadingAudio = true;
    _isPlaying = true;
    notifyListeners();

    try {
      WakelockPlus.enable();

      // 1. Inicializa os players se ainda não existirem
      if (_stemPlayers.isEmpty) {
        final anySolo = song.stems.any((s) => s.isSolo);

        // Identifica faixa master (preferência por Click ou Guia)
        final masterStem = song.stems.firstWhere(
          (s) => s.name.toUpperCase().contains('CLICK') || s.name.toUpperCase().contains('GUIA'),
          orElse: () => song.stems.first,
        );
        _masterStemId = masterStem.id;

        // Inicializa todas as faixas com tratamento individual para nenhuma travar as outras
        final List<Future<void>> initTasks = [];

        for (final stem in song.stems) {
          if (stem.filePath == null || stem.filePath!.isEmpty) continue;

          initTasks.add(() async {
            try {
              final player = AudioPlayer();

              try {
                await player.setReleaseMode(ReleaseMode.stop);
              } catch (_) {}

              Source source;
              final localPath = await AudioCacheService.getLocalPathIfExists(stem.filePath!);
              if (localPath != null && !kIsWeb) {
                source = DeviceFileSource(localPath);
              } else {
                final url = SupabaseService.getAudioUrl(stem.filePath!);
                source = UrlSource(url);
              }

              await player.setSource(source);

              final effVol = stem.getEffectiveVolume(anySolo);
              await player.setVolume(effVol);

              if (!kIsWeb) {
                try {
                  await player.setBalance(stem.pan);
                } catch (_) {}
              }

              _stemPlayers[stem.id] = player;

              // Apenas o master escuta position para evitar sobrecarga de rebuilds
              if (stem.id == _masterStemId) {
                player.onDurationChanged.listen((dur) {
                  if (dur.inMilliseconds > 0) {
                    _totalDurationSeconds = dur.inMilliseconds / 1000.0;
                    notifyListeners();
                  }
                });

                player.onPositionChanged.listen((pos) {
                  final millis = pos.inMilliseconds;
                  _currentPositionSeconds = millis / 1000.0;

                  final bpm = song.bpm;
                  final beatsPerSecond = bpm / 60.0;
                  final totalBeats = (_currentPositionSeconds * beatsPerSecond).toInt();
                  final bar = (totalBeats / 4).toInt() + 1;
                  final beat = (totalBeats % 4) + 1;

                  // Throttling: notifica a cada 250ms ou quando mudar o compasso/tempo
                  if (bar != _currentBar || beat != _currentBeat || (millis - _lastNotifiedMillis).abs() >= 250) {
                    _currentBar = bar;
                    _currentBeat = beat;
                    _lastNotifiedMillis = millis;
                    notifyListeners();
                  }
                });

                player.onPlayerComplete.listen((_) {
                  stop();
                });
              }
            } catch (stemErr) {
              debugPrint('Aviso: Pista ${stem.name} não pôde ser inicializada: $stemErr');
            }
          }());
        }

        await Future.wait(initTasks);
      }

      if (_stemPlayers.isEmpty) {
        // Fallback simulador se não houver áudios válidos
        _startTicker();
      } else {
        // Se a posição for maior que 0, posiciona todas
        final seekPos = Duration(milliseconds: (_currentPositionSeconds * 1000).toInt());
        if (_currentPositionSeconds > 0) {
          final seekFutures = _stemPlayers.values.map((p) async {
            try {
              await p.seek(seekPos);
            } catch (_) {}
          });
          await Future.wait(seekFutures);
        }

        // DISPARO SIMULTÂNEO VIA FUTURE.WAIT
        final resumeFutures = _stemPlayers.values.map((p) async {
          try {
            await p.resume();
          } catch (e) {
            debugPrint('Erro ao iniciar player: $e');
          }
        });
        await Future.wait(resumeFutures);

        // Inicia o monitor de alinhamento suave (a cada 3.0s, sem travamentos)
        _startDriftCompensation();

        // Download suave em cache no mobile em segundo plano
        AudioCacheService.prefetchSong(song);
      }
    } catch (e) {
      debugPrint('Erro ao iniciar áudio: $e');
      _startTicker();
    } finally {
      _isLoadingAudio = false;
      notifyListeners();
    }
  }

  /// Watchdog de drift suave: a cada 3.0s verifica se alguma pista divergiu mais de 250ms
  void _startDriftCompensation() {
    _driftCheckTimer?.cancel();
    _driftCheckTimer = Timer.periodic(const Duration(milliseconds: 3000), (_) async {
      if (!_isPlaying || _stemPlayers.isEmpty) return;

      final now = DateTime.now().millisecondsSinceEpoch;

      for (final entry in _stemPlayers.entries) {
        if (entry.key == _masterStemId) continue;

        // Evita reajustar a mesma pista com intervalo menor que 5 segundos
        final lastSeek = _lastStemSeekTimes[entry.key] ?? 0;
        if (now - lastSeek < 5000) continue;

        final player = entry.value;

        try {
          final pos = await player.getCurrentPosition();
          if (pos != null) {
            final trackSec = pos.inMilliseconds / 1000.0;
            final diff = (trackSec - _currentPositionSeconds).abs();
            // Apenas reajusta se a defasagem for perceptível (> 250ms)
            if (diff > 0.250) {
              _lastStemSeekTimes[entry.key] = now;
              await player.seek(Duration(milliseconds: (_currentPositionSeconds * 1000).toInt()));
            }
          }
        } catch (_) {}
      }
    });
  }

  Future<void> _pausePlayback() async {
    _isPlaying = false;
    _driftCheckTimer?.cancel();
    _playbackTicker?.cancel();
    WakelockPlus.disable();

    final pauseFutures = _stemPlayers.values.map((p) async {
      try {
        await p.pause();
      } catch (_) {}
    });
    await Future.wait(pauseFutures);
    notifyListeners();
  }

  void stop() {
    _isPlaying = false;
    _driftCheckTimer?.cancel();
    _playbackTicker?.cancel();
    _currentPositionSeconds = 0.0;
    _currentBar = 1;
    _currentBeat = 1;
    WakelockPlus.disable();

    // Mantém players em estado Pausado na posição zero (evita IllegalStateException no Android)
    for (final player in _stemPlayers.values) {
      try {
        player.pause();
        player.seek(Duration.zero);
      } catch (_) {}
    }
    notifyListeners();
  }

  void nextSong() {
    if (_currentSetlist != null && _currentSongIndex < _currentSetlist!.songs.length - 1) {
      _disposeStemPlayers();
      _currentSongIndex++;
      _pitchOffset = 0;
      stop();
    }
  }

  void previousSong() {
    if (_currentSongIndex > 0) {
      _disposeStemPlayers();
      _currentSongIndex--;
      _pitchOffset = 0;
      stop();
    }
  }

  void selectSong(int index) {
    if (_currentSetlist != null && index >= 0 && index < _currentSetlist!.songs.length) {
      _disposeStemPlayers();
      _currentSongIndex = index;
      final song = _currentSetlist!.songs[index];
      _pitchOffset = song.pitchOffsetSemitones;
      stop();
    }
  }

  // ==========================================
  // CONTROLE DE PITCH (TRANSPOSIÇÃO DE TOM)
  // ==========================================

  void setPitchOffset(int semitones) {
    _pitchOffset = semitones.clamp(-6, 6);
    final song = currentSong;
    if (song != null) {
      song.pitchOffsetSemitones = _pitchOffset;
      song.currentKey = PitchShifterService.transposeNote(song.originalKey, _pitchOffset);
      if (_currentSetlist != null) {
        SupabaseService.saveSetlistToCloud(_currentSetlist!);
      }
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

  // ==========================================
  // CONTROLE DE VOLUME, MUTE, SOLO E PAN
  // ==========================================

  void setStemVolume(String stemId, double volume) {
    final song = currentSong;
    if (song == null) return;
    final stem = song.stems.firstWhere((s) => s.id == stemId, orElse: () => song.stems.first);
    stem.volume = volume.clamp(0.0, 1.0);
    final anySolo = song.stems.any((s) => s.isSolo);
    final effVol = stem.getEffectiveVolume(anySolo);
    _stemPlayers[stemId]?.setVolume(effVol);
    notifyListeners();
  }

  /// CONTROLE DE PAN INDIVIDUAL (-1.0 = L | 0.0 = Centro | 1.0 = R)
  void setStemPan(String stemId, double pan) {
    final song = currentSong;
    if (song == null) return;
    final stem = song.stems.firstWhere((s) => s.id == stemId, orElse: () => song.stems.first);
    stem.setPan(pan);

    if (!kIsWeb) {
      try {
        _stemPlayers[stemId]?.setBalance(stem.pan);
      } catch (e) {
        debugPrint('Erro ao ajustar pan da faixa: $e');
      }
    }
    notifyListeners();
  }

  /// PRESET CABO Y (PALCO): Click e Guia em L (-1.0) | Demais faixas da banda em R (+1.0)
  void applySplitModeRouting() {
    _isSplitModeActive = true;
    final song = currentSong;
    if (song == null) return;

    for (final stem in song.stems) {
      stem.setPan(stem.isCue ? -1.0 : 1.0);
      if (!kIsWeb) {
        try {
          _stemPlayers[stem.id]?.setBalance(stem.pan);
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  /// PRESET ESTÉREO (ENSAIO/FONE): Todas as faixas no Centro (0.0)
  void applyStereoCenterRouting() {
    _isSplitModeActive = false;
    final song = currentSong;
    if (song == null) return;

    for (final stem in song.stems) {
      stem.setPan(0.0);
      if (!kIsWeb) {
        try {
          _stemPlayers[stem.id]?.setBalance(0.0);
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  void toggleSplitMode() {
    if (_isSplitModeActive) {
      applyStereoCenterRouting();
    } else {
      applySplitModeRouting();
    }
  }

  void toggleMute(String stemId) {
    final song = currentSong;
    if (song == null) return;
    final stem = song.stems.firstWhere((s) => s.id == stemId, orElse: () => song.stems.first);
    stem.isMuted = !stem.isMuted;
    final anySolo = song.stems.any((s) => s.isSolo);
    final effVol = stem.getEffectiveVolume(anySolo);
    _stemPlayers[stemId]?.setVolume(effVol);
    notifyListeners();
  }

  void toggleSolo(String stemId) {
    final song = currentSong;
    if (song == null) return;
    final stem = song.stems.firstWhere((s) => s.id == stemId, orElse: () => song.stems.first);
    stem.isSolo = !stem.isSolo;
    final anySolo = song.stems.any((s) => s.isSolo);
    for (final st in song.stems) {
      final effVol = st.getEffectiveVolume(anySolo);
      _stemPlayers[st.id]?.setVolume(effVol);
    }
    notifyListeners();
  }

  void seekTo(double seconds) {
    _currentPositionSeconds = seconds.clamp(0.0, _totalDurationSeconds);
    final target = Duration(milliseconds: (_currentPositionSeconds * 1000).toInt());
    for (final player in _stemPlayers.values) {
      try {
        player.seek(target);
      } catch (_) {}
    }
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

  void _initializeCleanState() {
    _disposeStemPlayers();
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
    _realtimeChannel?.unsubscribe();
    _cloudSyncTimer?.cancel();
    _driftCheckTimer?.cancel();
    _disposeStemPlayers();
    _playbackTicker?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }
}

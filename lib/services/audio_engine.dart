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
  int _lastPositionUpdateMillis = 0;

  Timer? _playbackTicker;
  Timer? _driftCheckTimer;
  Timer? _cloudSyncTimer;
  RealtimeChannel? _realtimeChannel;
  bool _isSyncingCloud = false;

  final Map<String, int> _lastStemSeekTimes = {};

  AudioEngine() {
    _initAudioGlobal();
    _initializeCleanState();
    startCloudAutoSync();
    syncFromCloudSilently();
  }

  void _initAudioGlobal() {
    try {
      AudioPlayer.global.setAudioContext(
        AudioContextConfig(
          focus: AudioContextConfigFocus.mixWithOthers,
          stayAwake: true,
        ).build(),
      );
    } catch (e) {
      debugPrint('AudioEngine global audio context error: $e');
    }
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
  bool get hasActiveSolo => currentSong?.stems.any((s) => s.isSolo) ?? false;
  bool get hasActiveMute => currentSong?.stems.any((s) => s.isMuted) ?? false;

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

  bool _hasSetlistsChanged(List<Setlist> incoming) {
    if (_allSetlists.length != incoming.length) return true;
    for (int i = 0; i < _allSetlists.length; i++) {
      final oldSetlist = _allSetlists[i];
      final newSetlist = incoming[i];
      if (oldSetlist.id != newSetlist.id || oldSetlist.title != newSetlist.title) return true;
      if (oldSetlist.songs.length != newSetlist.songs.length) return true;
      for (int j = 0; j < oldSetlist.songs.length; j++) {
        final songA = oldSetlist.songs[j];
        final songB = newSetlist.songs[j];
        if (songA.id != songB.id || songA.title != songB.title) return true;
        if (songA.stems.length != songB.stems.length) return true;
      }
    }
    return false;
  }

  void _mergeSetlistsPreservingRuntimeState(List<Setlist> incomingList, {String? selectId}) {
    // 1. Memoriza a música ativa e seu índice atual
    final currentActiveSongId = currentSong?.id;
    final oldSongIndex = _currentSongIndex;
    final targetSetlistId = selectId ?? _currentSetlist?.id;

    // 2. Coleta o estado de runtime de TODAS as pistas existentes (volume, pan, canal, mute, solo)
    final Map<String, StemTrack> existingStems = {};
    final Map<String, int> existingPitchOffsets = {};

    for (final setlist in _allSetlists) {
      for (final song in setlist.songs) {
        existingPitchOffsets[song.id] = song.pitchOffsetSemitones;
        for (final stem in song.stems) {
          existingStems[stem.id] = stem;
          existingStems['${song.id}_${stem.name.toLowerCase()}'] = stem;
        }
      }
    }

    // 3. Aplica os estados nas músicas e pistas recém-chegadas da nuvem
    for (final setlist in incomingList) {
      for (final song in setlist.songs) {
        if (existingPitchOffsets.containsKey(song.id)) {
          song.pitchOffsetSemitones = existingPitchOffsets[song.id]!;
          song.currentKey = PitchShifterService.transposeNote(song.originalKey, song.pitchOffsetSemitones);
        }
        for (final stem in song.stems) {
          final existing = existingStems[stem.id] ?? existingStems['${song.id}_${stem.name.toLowerCase()}'];
          if (existing != null) {
            stem.volume = existing.volume;
            stem.pan = existing.pan;
            stem.outputChannel = existing.outputChannel;
            stem.isMuted = existing.isMuted;
            stem.isSolo = existing.isSolo;
          }
        }
      }
    }

    // 4. Substitui a lista de setlists de forma limpa
    _allSetlists.clear();
    _allSetlists.addAll(incomingList);

    // 5. Restaura a playlist atual
    if (targetSetlistId != null) {
      _currentSetlist = _allSetlists.firstWhere(
        (s) => s.id == targetSetlistId,
        orElse: () => _allSetlists.first,
      );
    } else if (_allSetlists.isNotEmpty) {
      _currentSetlist = _allSetlists.first;
    }

    // 6. Restaura a posição da música na playlist sem reiniciar para zero
    if (_currentSetlist != null && _currentSetlist!.songs.isNotEmpty) {
      if (currentActiveSongId != null) {
        final foundIdx = _currentSetlist!.songs.indexWhere((s) => s.id == currentActiveSongId);
        if (foundIdx != -1) {
          _currentSongIndex = foundIdx;
        } else {
          _currentSongIndex = oldSongIndex.clamp(0, _currentSetlist!.songs.length - 1);
        }
      } else {
        _currentSongIndex = oldSongIndex.clamp(0, _currentSetlist!.songs.length - 1);
      }
      _pitchOffset = _currentSetlist!.songs[_currentSongIndex].pitchOffsetSemitones;
    } else {
      _currentSongIndex = 0;
      _pitchOffset = 0;
    }

    // 7. Se as pistas estiverem no mixer/reproduzindo, garante consistência de áudio
    if (_stemPlayers.isNotEmpty) {
      _applyAllStemsAudioSettings();
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

      // 2. Atualiza Playlists preservando 100% dos Solos, Mutes e Volumes locais
      final cloudSetlists = await SupabaseService.fetchAllSetlists();
      if (cloudSetlists.isNotEmpty) {
        if (_hasSetlistsChanged(cloudSetlists)) {
          _mergeSetlistsPreservingRuntimeState(cloudSetlists);
          notifyListeners();
        }
      }
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
    _mergeSetlistsPreservingRuntimeState(list, selectId: selectId);
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
        // Identifica pista master (preferência: CLICK com arquivo, senão GUIA com arquivo, senão primeira com arquivo)
        final masterStem = song.stems.firstWhere(
          (s) => s.name.toUpperCase().contains('CLICK') && (s.filePath?.isNotEmpty ?? false),
          orElse: () => song.stems.firstWhere(
            (s) => s.name.toUpperCase().contains('GUIA') && (s.filePath?.isNotEmpty ?? false),
            orElse: () => song.stems.firstWhere(
              (s) => s.filePath?.isNotEmpty ?? false,
              orElse: () => song.stems.first,
            ),
          ),
        );
        _masterStemId = masterStem.id;

        // Inicializa todas as faixas com tratamento individual para nenhuma travar as outras
        final List<Future<void>> initTasks = [];

        for (final stem in song.stems) {
          if (stem.filePath == null || stem.filePath!.isEmpty) continue;

          initTasks.add(() async {
            try {
              final player = AudioPlayer();

              // Configura contexto sem roubo de foco de áudio por pista (fundamental no Android)
              try {
                await player.setAudioContext(
                  AudioContextConfig(
                    focus: AudioContextConfigFocus.mixWithOthers,
                    stayAwake: true,
                  ).build(),
                );
              } catch (_) {}

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

              // Timeout de segurança para evitar travamento se uma pista demorar
              await player.setSource(source).timeout(const Duration(seconds: 15));

              final effVol = stem.getEffectiveVolume(hasActiveSolo);
              await player.setVolume(effVol);

              try {
                await player.setBalance(stem.pan);
              } catch (_) {}

              _stemPlayers[stem.id] = player;

              // Duração da música: atualiza conforme as faixas carregam
              player.onDurationChanged.listen((dur) {
                if (dur.inMilliseconds > 0) {
                  final durSec = dur.inMilliseconds / 1000.0;
                  if (durSec > _totalDurationSeconds || _totalDurationSeconds == 240.0) {
                    _totalDurationSeconds = durSec;
                    notifyListeners();
                  }
                }
              });

              // Apenas o master escuta position para evitar sobrecarga de rebuilds
              if (stem.id == _masterStemId) {
                player.onPositionChanged.listen((pos) {
                  final millis = pos.inMilliseconds;
                  _lastPositionUpdateMillis = DateTime.now().millisecondsSinceEpoch;
                  _currentPositionSeconds = millis / 1000.0;
                  _updateMusicalGrid();

                  if ((millis - _lastNotifiedMillis).abs() >= 250) {
                    _lastNotifiedMillis = millis;
                    notifyListeners();
                  }
                });

                player.onPlayerComplete.listen((_) {
                  // Só encerra se a música realmente tiver chegado ao final
                  if (_currentPositionSeconds >= (_totalDurationSeconds - 2.0)) {
                    stop();
                  }
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
        _startPlaybackClock();
      } else {
        // Se a posição for maior que 0, posiciona todas as pistas
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

        // CRUCIAL: Após início no hardware do Android/iOS, reaplica volume e balanço (PAN)
        // em todas as pistas para garantir que o roteamento L/R do Cabo Y não seja resetado pelo SO!
        await _applyAllStemsAudioSettings();

        // Inicia relógio de reprodução com watchdog de avanço
        _startPlaybackClock();

        // Inicia o monitor de alinhamento suave (a cada 3.0s, sem travamentos)
        _startDriftCompensation();

        // Download suave em cache no mobile em segundo plano
        AudioCacheService.prefetchSong(song);
      }
    } catch (e) {
      debugPrint('Erro ao iniciar áudio: $e');
      _startPlaybackClock();
    } finally {
      _isLoadingAudio = false;
      notifyListeners();
    }
  }

  void _updateMusicalGrid() {
    final song = currentSong;
    final bpm = song?.bpm ?? 120;
    final beatsPerSecond = bpm / 60.0;
    final totalBeats = (_currentPositionSeconds * beatsPerSecond).toInt();
    _currentBar = (totalBeats / 4).toInt() + 1;
    _currentBeat = (totalBeats % 4) + 1;
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
    _lastPositionUpdateMillis = 0;
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
  // CONTROLE DE VOLUME, MUTE, SOLO E PAN (UNIFICADO E PROTEGIDO)
  // ==========================================

  /// Aplica volume e balanço (PAN) com proteção nativa Android/iOS
  Future<void> _applyStemAudioSettings(StemTrack stem) async {
    final player = _stemPlayers[stem.id];
    if (player == null) return;

    final anySolo = hasActiveSolo;
    final effVol = stem.getEffectiveVolume(anySolo);

    try {
      // 1. Aplica o volume efetivo considerando Solo e Mute
      await player.setVolume(effVol);

      // 2. CRUCIAL NO ANDROID E IOS:
      // O MediaPlayer do Android reseta o balanço (L/R) para (v, v) sempre que setVolume é chamado.
      // Reaplicar setBalance imediatamente após setVolume garante que o PAN (Cabo Y ou customizado)
      // seja rigorosamente mantido no hardware!
      try {
        await player.setBalance(stem.pan);
      } catch (_) {}
    } catch (e) {
      debugPrint('Erro ao aplicar configurações de áudio na pista ${stem.name}: $e');
    }
  }

  /// Aplica configurações de volume e balanço em todas as faixas ativas
  Future<void> _applyAllStemsAudioSettings() async {
    final song = currentSong;
    if (song == null) return;

    final anySolo = hasActiveSolo;

    for (final stem in song.stems) {
      final player = _stemPlayers[stem.id];
      if (player == null) continue;

      final effVol = stem.getEffectiveVolume(anySolo);
      try {
        await player.setVolume(effVol);
        try {
          await player.setBalance(stem.pan);
        } catch (_) {}
      } catch (e) {
        debugPrint('Erro ao aplicar volume/pan em ${stem.name}: $e');
      }
    }
  }

  void setStemVolume(String stemId, double volume) {
    final song = currentSong;
    if (song == null) return;
    final index = song.stems.indexWhere((s) => s.id == stemId);
    if (index == -1) return;
    final stem = song.stems[index];
    stem.volume = volume.clamp(0.0, 1.0);
    _applyStemAudioSettings(stem);
    notifyListeners();
  }

  /// CONTROLE DE PAN INDIVIDUAL (-1.0 = L | 0.0 = Centro | 1.0 = R)
  void setStemPan(String stemId, double pan) {
    final song = currentSong;
    if (song == null) return;
    final index = song.stems.indexWhere((s) => s.id == stemId);
    if (index == -1) return;
    final stem = song.stems[index];
    stem.setPan(pan);
    _applyStemAudioSettings(stem);
    notifyListeners();
  }

  /// PRESET CABO Y (PALCO): Click e Guia em L (-1.0) | Demais faixas da banda em R (+1.0)
  void applySplitModeRouting() {
    _isSplitModeActive = true;
    final song = currentSong;
    if (song == null) return;

    for (final stem in song.stems) {
      stem.setPan(stem.isCue ? -1.0 : 1.0);
    }
    _applyAllStemsAudioSettings();
    notifyListeners();
  }

  /// PRESET ESTÉREO (ENSAIO/FONE): Todas as faixas no Centro (0.0)
  void applyStereoCenterRouting() {
    _isSplitModeActive = false;
    final song = currentSong;
    if (song == null) return;

    for (final stem in song.stems) {
      stem.setPan(0.0);
    }
    _applyAllStemsAudioSettings();
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
    final index = song.stems.indexWhere((s) => s.id == stemId);
    if (index == -1) return;
    final stem = song.stems[index];
    stem.isMuted = !stem.isMuted;
    _applyAllStemsAudioSettings();
    notifyListeners();
  }

  void toggleSolo(String stemId) {
    final song = currentSong;
    if (song == null) return;
    final index = song.stems.indexWhere((s) => s.id == stemId);
    if (index == -1) return;
    final stem = song.stems[index];
    stem.isSolo = !stem.isSolo;
    _applyAllStemsAudioSettings();
    notifyListeners();
  }

  void clearAllSolos() {
    final song = currentSong;
    if (song == null) return;
    for (final stem in song.stems) {
      stem.isSolo = false;
    }
    _applyAllStemsAudioSettings();
    notifyListeners();
  }

  void clearAllMutes() {
    final song = currentSong;
    if (song == null) return;
    for (final stem in song.stems) {
      stem.isMuted = false;
    }
    _applyAllStemsAudioSettings();
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

  /// Relógio de reprodução com watchdog de avanço para garantir sincronismo
  void _startPlaybackClock() {
    _playbackTicker?.cancel();
    _playbackTicker = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!_isPlaying) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      // Se não há players nativos ou se o player nativo não emitiu posição recente (> 1000ms)
      if (_stemPlayers.isEmpty || (now - _lastPositionUpdateMillis > 1000)) {
        _currentPositionSeconds += 0.2;
        if (_currentPositionSeconds >= _totalDurationSeconds) {
          stop();
          return;
        }
        _updateMusicalGrid();
        notifyListeners();
      }
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

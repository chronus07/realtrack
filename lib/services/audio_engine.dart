import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:http/http.dart' as http;
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

  // REPRODUÇÃO MULTITRACKS COM SOLOUD (ENGINE C++ SAMPLE-ACCURATE)
  final Map<String, AudioSource> _stemSources = {};
  final Map<String, SoundHandle> _stemHandles = {};
  final Map<String, String> _stemLoadErrors = {};
  String? _masterStemId;
  bool _isLoadingAudio = false;
  String _loadingStatus = 'Carregando áudio...';
  double _loadingProgress = 0.0;

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
  Timer? _cloudSyncTimer;
  RealtimeChannel? _realtimeChannel;
  bool _isSyncingCloud = false;

  AudioEngine() {
    _initAudioGlobal();
    _initializeCleanState();
    startCloudAutoSync();
    syncFromCloudSilently();
  }

  Future<void> _initAudioGlobal() async {
    try {
      if (!SoLoud.instance.isInitialized) {
        await SoLoud.instance.init();
      }
      try {
        SoLoud.instance.setMaxActiveVoiceCount(128);
      } catch (_) {}
      debugPrint('AudioEngine: SoLoud engine inicializado com sucesso (128 vozes ativas).');
    } catch (e) {
      debugPrint('AudioEngine SoLoud init error: $e');
    }
  }

  // Getters
  bool get isLoadingAudio => _isLoadingAudio;
  String get loadingStatus => _loadingStatus;
  double get loadingProgress => _loadingProgress;
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
  int get loadedStemsCount => _stemSources.length;
  int get totalStemsCount => currentSong?.stems.length ?? 0;
  bool isStemLoaded(String stemId) => _stemSources.containsKey(stemId);
  String? getStemError(String stemId) => _stemLoadErrors[stemId];

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
    if (_stemHandles.isNotEmpty) {
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

  void addLocalSongToLibrary(Song song) => addSongToLibrary(song);

  Future<void> updateLibrarySongKeyAndBpm(String songId, {String? key, int? bpm}) async {
    final idx = _masterLibrary.indexWhere((s) => s.id == songId);
    if (idx != -1) {
      final old = _masterLibrary[idx];
      final newKey = key ?? old.originalKey;
      final newBpm = bpm ?? old.bpm;
      final updated = Song(
        id: old.id,
        title: old.title,
        artist: old.artist,
        originalKey: newKey,
        currentKey: newKey,
        pitchOffsetSemitones: old.pitchOffsetSemitones,
        bpm: newBpm,
        timeSignature: old.timeSignature,
        isMultiTrack: old.isMultiTrack,
        stems: old.stems,
        sections: old.sections,
        chordsText: old.chordsText,
        isDownloaded: old.isDownloaded,
      );
      _masterLibrary[idx] = updated;

      for (final setlist in _allSetlists) {
        for (int i = 0; i < setlist.songs.length; i++) {
          if (setlist.songs[i].id == songId) {
            final sOld = setlist.songs[i];
            setlist.songs[i] = Song(
              id: sOld.id,
              title: sOld.title,
              artist: sOld.artist,
              originalKey: newKey,
              currentKey: sOld.pitchOffsetSemitones == 0 ? newKey : sOld.currentKey,
              pitchOffsetSemitones: sOld.pitchOffsetSemitones,
              bpm: newBpm,
              timeSignature: sOld.timeSignature,
              isMultiTrack: sOld.isMultiTrack,
              stems: sOld.stems,
              sections: sOld.sections,
              chordsText: sOld.chordsText,
              isDownloaded: sOld.isDownloaded,
            );
          }
        }
      }
      notifyListeners();
      await SupabaseService.updateSongKeyAndBpm(songId, key: key, bpm: bpm);
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
    await AudioCacheService.cleanOrphanedCache(_allSetlists, _masterLibrary);
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
    if (found.songs.isNotEmpty && (!found.songs[0].isMultiTrack || found.songs[0].stems.length <= 1)) {
      for (final stem in found.songs[0].stems) {
        stem.setPan(0.0);
      }
    }
    _pitchOffset = found.songs.isNotEmpty ? found.songs[0].pitchOffsetSemitones : 0;
    _totalDurationSeconds = 0.0;
    _currentPositionSeconds = 0.0;
    _isPlaying = false;
    _playbackTicker?.cancel();
    _disposeStemPlayers();
    _applyPitchOffsetToAudio();
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
    AudioCacheService.cleanOrphanedCache(_allSetlists, _masterLibrary);
  }

  void addSongToSetlist(String setlistId, Song song) {
    final target = _allSetlists.firstWhere((s) => s.id == setlistId, orElse: () => _currentSetlist!);
    if (!target.songs.any((s) => s.id == song.id)) {
      target.songs.add(song.clone());
      notifyListeners();
      SupabaseService.saveSetlistToCloud(target);
    }
  }

  void addSongToCurrentSetlist(Song song) {
    if (_currentSetlist != null) {
      if (!_currentSetlist!.songs.any((s) => s.id == song.id)) {
        _currentSetlist!.songs.add(song.clone());
        notifyListeners();
        SupabaseService.saveSetlistToCloud(_currentSetlist!);
      }
    }
  }

  void addMultipleSongsToSetlist(List<Song> songs) {
    if (_currentSetlist != null) {
      for (final song in songs) {
        if (!_currentSetlist!.songs.any((s) => s.id == song.id)) {
          _currentSetlist!.songs.add(song.clone());
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
      AudioCacheService.cleanOrphanedCache(_allSetlists, _masterLibrary);
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
    _applyPitchOffsetToAudio();
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
      _applyPitchOffsetToAudio();
    }
    notifyListeners();
    SupabaseService.saveSetlistToCloud(_currentSetlist!);
  }

  // ==========================================
  // REPRODUÇÃO MULTITRACKS COM SINCRONISMO DE ALTA PRECISÃO
  // ==========================================

  void _disposeStemPlayers() {
    _playbackTicker?.cancel();
    try {
      SoLoud.instance.stopAll();
    } catch (_) {}
    _stemHandles.clear();

    for (final source in _stemSources.values) {
      try {
        if (!kIsWeb && source.filters.pitchShiftFilter.isActive) {
          source.filters.pitchShiftFilter.deactivate();
        }
      } catch (_) {}
      try {
        SoLoud.instance.disposeSource(source);
      } catch (_) {}
    }
    _stemSources.clear();
    _masterStemId = null;
    _totalDurationSeconds = 0.0;
    _currentPositionSeconds = 0.0;

    if (_pitchOffset == 0) {
      try {
        if (SoLoud.instance.filters.pitchShiftFilter.isActive) {
          SoLoud.instance.filters.pitchShiftFilter.deactivate();
        }
      } catch (_) {}
    }

    // Libera a memória RAM do navegador de todos os bytes temporários
    AudioCacheService.clearAllWebBytes();
  }

  Future<void> togglePlay() async {
    if (currentSong == null) return;
    if (_isPlaying) {
      await _pausePlayback();
    } else {
      if (_stemHandles.isNotEmpty) {
        await _resumePlayback();
      } else {
        await _startPlayback();
      }
    }
  }

  Future<void> _resumePlayback() async {
    if (_stemHandles.isEmpty || _stemSources.isEmpty) {
      await _startPlayback();
      return;
    }

    _isPlaying = true;
    _isLoadingAudio = false;
    WakelockPlus.enable();

    await _applyAllStemsAudioSettings();
    _applyPitchOffsetToAudio();

    // Retoma todas as vozes simultaneamente no motor C++ SoLoud já afinadas
    for (final handle in _stemHandles.values) {
      try {
        SoLoud.instance.setPause(handle, false);
      } catch (_) {}
    }

    _startPlaybackClock();
    notifyListeners();
  }

  Future<void> retryFailedStems() async {
    final song = currentSong;
    if (song == null) return;
    _disposeStemPlayers();
    await _startPlayback();
  }

  Future<void> downloadCurrentSongToDevice({void Function(int done, int total, double pct)? onProgress}) async {
    final song = currentSong;
    if (song == null) return;
    _isLoadingAudio = true;
    _loadingStatus = kIsWeb
        ? 'Carregando faixas de "${song.title}" na memória...'
        : 'Baixando faixas de "${song.title}" para o aparelho...';
    _loadingProgress = 0.05;
    notifyListeners();

    try {
      await AudioCacheService.downloadSong(
        song,
        onProgress: (done, total, pct) {
          _loadingStatus = kIsWeb
              ? 'Carregando na memória: $done/$total faixas (${(pct * 100).toInt()}%)...'
              : 'Salvando no aparelho: $done/$total faixas (${(pct * 100).toInt()}%)...';
          _loadingProgress = pct;
          onProgress?.call(done, total, pct);
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('Erro no download da música: $e');
    } finally {
      _isLoadingAudio = false;
      notifyListeners();
    }
  }

  Future<void> _startPlayback() async {
    final song = currentSong;
    if (song == null) return;
    if (_isLoadingAudio) return;

    _isLoadingAudio = true;
    _isPlaying = true;
    _loadingProgress = 0.0;
    _loadingStatus = 'Preparando faixas no motor de áudio SoLoud...';
    notifyListeners();

    try {
      WakelockPlus.enable();

      // Regra Single Track: quando for faixa única, o pan deve ser 100% Centro (C / 0.0)
      final bool isSingleTrack = !song.isMultiTrack || song.stems.length <= 1;
      if (isSingleTrack) {
        for (final stem in song.stems) {
          stem.setPan(0.0);
        }
      }

      // Reinicia o cálculo de duração total para a música atual
      _totalDurationSeconds = 0.0;

      if (!SoLoud.instance.isInitialized) {
        await SoLoud.instance.init();
      }
      try {
        SoLoud.instance.setMaxActiveVoiceCount(128);
      } catch (_) {}

      // Limpa fontes e memória web que pertencem a músicas antigas para evitar vazamento de memória
      if (kIsWeb) {
        AudioCacheService.clearWebCacheExcept(song);
      }
      final validStemIds = song.stems.map((s) => s.id).toSet();
      _stemSources.removeWhere((id, source) {
        if (!validStemIds.contains(id)) {
          try {
            SoLoud.instance.disposeSource(source);
          } catch (_) {}
          return true;
        }
        return false;
      });

      // Calcula a duração a partir das fontes que já estão em memória para esta música
      for (final stem in song.stems) {
        final existingSrc = _stemSources[stem.id];
        if (existingSrc != null) {
          try {
            final len = SoLoud.instance.getLength(existingSrc);
            final lenSec = len.inMilliseconds / 1000.0;
            if (lenSec > _totalDurationSeconds) {
              _totalDurationSeconds = lenSec;
            }
          } catch (_) {}
        }
      }

      // Identifica a faixa master (Click ou Guia) para ser a referência de clock
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

      // Pistas que ainda precisam ser carregadas na memória do SoLoud
      final stemsToLoad = song.stems.where(
        (s) => (s.filePath != null && s.filePath!.isNotEmpty) && !_stemSources.containsKey(s.id),
      ).toList();

      if (stemsToLoad.isNotEmpty) {
        // Pré-cacheia apenas no armazenamento local em plataformas nativas (Android / iOS / Desktop)
        // No navegador Web, cada faixa é transmitida diretamente para o SoLoud no loop abaixo,
        // economizando 50% do tempo de carregamento e eliminando picos de memória RAM no Safari.
        if (!kIsWeb) {
          final isCached = await AudioCacheService.isSongFullyCached(song);
          if (!isCached) {
            _loadingStatus = 'Garantindo cache local para sincronismo zero-latência...';
            _loadingProgress = 0.05;
            notifyListeners();

            await AudioCacheService.downloadSong(
              song,
              onProgress: (done, total, pct) {
                _loadingStatus = 'Salvando no aparelho: $done/$total (${(pct * 100).toInt()}%)...';
                _loadingProgress = pct;
                notifyListeners();
              },
            );
          }
        }

        // Carrega pistas sequencialmente (1 a 1) para evitar picos de memória e I/O
        _stemLoadErrors.clear();
        for (int i = 0; i < stemsToLoad.length; i++) {
          final stem = stemsToLoad[i];
          final filePath = stem.filePath!;
          final ext = filePath.contains('.') ? filePath.split('.').last.toLowerCase() : 'mp3';
          final isIsoContainer = ext == 'm4a' || ext == 'mp4' || ext == 'aac';
          final uniqueRefName = '${stem.id}.$ext';

          _loadingStatus = 'Carregando ${i + 1}/${stemsToLoad.length}: ${stem.name}...';
          _loadingProgress = (i + 1) / stemsToLoad.length;
          notifyListeners();

          AudioSource? source;
          String? lastError;

          // REGRA DE ARQUITETURA DE ÁUDIO REALTRACKS:
          // Usa LoadMode.memory (RAM) em todas as plataformas (Android, iOS, Web, Desktop).
          // Em RAM, a reprodução de 8 a 12 stems simultâneos é 100% instantânea, livre de I/O na memória flash,
          // eliminando completamente travamentos, estalos ou gargalos no Android.
          // Se houver restrição de RAM em aparelho antigo, o fallback para LoadMode.disk é acionado automaticamente.
          final preferredMode = LoadMode.memory;

          for (int attempt = 1; attempt <= 2 && source == null; attempt++) {
            try {
              if (kIsWeb) {
                var webBytes = AudioCacheService.getWebBytes(filePath);
                if (webBytes == null) {
                  final url = SupabaseService.getAudioUrl(filePath);
                  final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 120));
                  if (res.statusCode == 200 && res.bodyBytes.lengthInBytes > 1024) {
                    webBytes = res.bodyBytes;
                  }
                }

                if (webBytes != null) {
                  try {
                    source = await SoLoud.instance.loadMem(
                      uniqueRefName,
                      webBytes,
                      mode: LoadMode.memory,
                    );
                  } finally {
                    AudioCacheService.evictWebBytes(filePath);
                  }
                } else {
                  lastError = 'Download Web retornou vazio';
                }
              } else {
                // Android / iOS / Desktop nativo
                var localPath = await AudioCacheService.getLocalPathIfExists(filePath);
                if (localPath == null) {
                  try {
                    localPath = await AudioCacheService.getOrDownloadAudio(filePath);
                  } catch (dlErr) {
                    lastError = 'Download local: $dlErr';
                  }
                }

                if (localPath != null && !localPath.startsWith('http://') && !localPath.startsWith('https://')) {
                  try {
                    source = await SoLoud.instance.loadFile(localPath, mode: preferredMode);
                  } catch (loadErr) {
                    debugPrint('preferredMode (memory) falhou para ${stem.name}, usando fallback LoadMode.disk: $loadErr');
                    try {
                      source = await SoLoud.instance.loadFile(localPath, mode: LoadMode.disk);
                    } catch (memErr) {
                      lastError = 'Falha ao carregar arquivo local: $memErr';
                    }
                  }
                } else {
                  // Fallback pela URL usando LoadMode.memory seguro
                  final url = SupabaseService.getAudioUrl(filePath);
                  try {
                    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 120));
                    if (res.statusCode == 200 && res.bodyBytes.lengthInBytes > 1024) {
                      source = await SoLoud.instance.loadMem(
                        uniqueRefName,
                        res.bodyBytes,
                        mode: LoadMode.memory,
                      );
                    }
                  } catch (netErr) {
                    lastError = 'Fallback URL falhou: $netErr';
                  }
                }
              }

              if (source != null) {
                _stemSources[stem.id] = source;
                try {
                  final len = SoLoud.instance.getLength(source);
                  final lenSec = len.inMilliseconds / 1000.0;
                  if (lenSec > _totalDurationSeconds) {
                    _totalDurationSeconds = lenSec;
                  }
                } catch (_) {}
              }
            } catch (err) {
              lastError = err.toString();
              debugPrint('Tentativa $attempt pista ${stem.name} ($filePath) falhou: $err');
              if (attempt < 2) {
                await Future.delayed(const Duration(milliseconds: 300));
              }
            }
          }

          if (source == null) {
            _stemLoadErrors[stem.id] = lastError ?? 'Erro de decodificação';
            debugPrint('❌ Falha na pista ${stem.name}: ${_stemLoadErrors[stem.id]}');
          }

          // Intervalo de 30ms para o Garbage Collector desalocar objetos temporários
          await Future.delayed(const Duration(milliseconds: 30));
        }
      }

      if (_totalDurationSeconds <= 0.0) {
        _totalDurationSeconds = 240.0;
      }

      if (_stemSources.isEmpty) {
        _startPlaybackClock();
      } else {
        // Interrompe e limpa quaisquer handles anteriores antes de novo disparo
        for (final oldHandle in _stemHandles.values) {
          try {
            SoLoud.instance.stop(oldHandle);
          } catch (_) {}
        }
        _stemHandles.clear();

        for (final stem in song.stems) {
          final source = _stemSources[stem.id];
          if (source == null) continue;

          final effVol = stem.getEffectiveVolume(hasActiveSolo);
          final handle = SoLoud.instance.play(
            source,
            volume: effVol,
            pan: stem.pan,
            paused: true,
          );

          if (handle.isError) {
            _stemLoadErrors[stem.id] = 'Voz SoLoud esgotada ou inválida';
            debugPrint('❌ Handle de voz inválido para ${stem.name}');
            continue;
          }

          try {
            // PROTEÇÃO CONTRA VOICE STEALING:
            // Garante que o mixer SoLoud nunca corte ou silencie esta faixa em sessões com muitas vozes
            SoLoud.instance.setProtectVoice(handle, true);
            // SINCRONISMO CONTÍNUO: Mantém o ponteiro e clock da faixa avançando mesmo se mutada ou com volume 0
            SoLoud.instance.setInaudibleBehavior(handle, true, false);
          } catch (_) {}

          if (_currentPositionSeconds > 0.08) {
            try {
              SoLoud.instance.seek(
                handle,
                Duration(milliseconds: (_currentPositionSeconds * 1000).toInt()),
              );
            } catch (_) {}
          }

          _stemHandles[stem.id] = handle;
        }

        // Aplica o tom em todas as faixas ANTES de despausar, garantindo sincronismo sample-accurate
        _applyPitchOffsetToAudio();

        // Dispara todas as faixas simultaneamente no motor de áudio C++ já afinadas
        for (final handle in _stemHandles.values) {
          try {
            SoLoud.instance.setPause(handle, false);
          } catch (_) {}
        }

        _startPlaybackClock();
      }
    } catch (e) {
      debugPrint('Erro ao iniciar áudio com SoLoud: $e');
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

  Future<void> _pausePlayback() async {
    _isPlaying = false;
    _playbackTicker?.cancel();
    WakelockPlus.disable();

    for (final handle in _stemHandles.values) {
      try {
        SoLoud.instance.setPause(handle, true);
      } catch (_) {}
    }
    notifyListeners();
  }

  void stop() {
    _isPlaying = false;
    _playbackTicker?.cancel();
    _currentPositionSeconds = 0.0;
    _currentBar = 1;
    _currentBeat = 1;
    _lastPositionUpdateMillis = 0;
    WakelockPlus.disable();

    try {
      SoLoud.instance.stopAll();
    } catch (_) {}
    _stemHandles.clear();

    notifyListeners();
  }

  void nextSong() {
    if (_currentSetlist != null && _currentSongIndex < _currentSetlist!.songs.length - 1) {
      _disposeStemPlayers();
      _currentSongIndex++;
      final song = _currentSetlist!.songs[_currentSongIndex];
      if (!song.isMultiTrack || song.stems.length <= 1) {
        for (final stem in song.stems) {
          stem.setPan(0.0);
        }
      }
      _pitchOffset = song.pitchOffsetSemitones;
      _totalDurationSeconds = 0.0;
      _currentPositionSeconds = 0.0;
      stop();
      _applyPitchOffsetToAudio();
      notifyListeners();
    }
  }

  void previousSong() {
    if (_currentSongIndex > 0) {
      _disposeStemPlayers();
      _currentSongIndex--;
      final song = _currentSetlist != null && _currentSongIndex < _currentSetlist!.songs.length
          ? _currentSetlist!.songs[_currentSongIndex]
          : null;
      if (song != null && (!song.isMultiTrack || song.stems.length <= 1)) {
        for (final stem in song.stems) {
          stem.setPan(0.0);
        }
      }
      _pitchOffset = song?.pitchOffsetSemitones ?? 0;
      _totalDurationSeconds = 0.0;
      _currentPositionSeconds = 0.0;
      stop();
      _applyPitchOffsetToAudio();
      notifyListeners();
    }
  }

  void selectSong(int index) {
    if (_currentSetlist != null && index >= 0 && index < _currentSetlist!.songs.length) {
      _disposeStemPlayers();
      _currentSongIndex = index;
      final song = _currentSetlist!.songs[index];
      if (!song.isMultiTrack || song.stems.length <= 1) {
        for (final stem in song.stems) {
          stem.setPan(0.0);
        }
      }
      _pitchOffset = song.pitchOffsetSemitones;
      _totalDurationSeconds = 0.0;
      _currentPositionSeconds = 0.0;
      stop();
      _applyPitchOffsetToAudio();
      notifyListeners();
    }
  }

  /// Salva e atualiza as Cifras de uma música no Acervo (memória e Supabase)
  Future<void> updateSongChords(String songId, String newChords) async {
    // 1. Atualiza no masterLibrary
    for (int i = 0; i < _masterLibrary.length; i++) {
      if (_masterLibrary[i].id == songId) {
        _masterLibrary[i] = _masterLibrary[i].clone(chordsText: newChords);
      }
    }

    // 2. Atualiza em todas as playlists em memória
    for (var setlist in _allSetlists) {
      for (int i = 0; i < setlist.songs.length; i++) {
        if (setlist.songs[i].id == songId) {
          setlist.songs[i] = setlist.songs[i].clone(chordsText: newChords);
        }
      }
    }

    // 3. Atualiza na playlist atual
    if (_currentSetlist != null) {
      for (int i = 0; i < _currentSetlist!.songs.length; i++) {
        if (_currentSetlist!.songs[i].id == songId) {
          _currentSetlist!.songs[i] = _currentSetlist!.songs[i].clone(chordsText: newChords);
        }
      }
    }

    notifyListeners();

    // 4. Salva no banco de dados na nuvem (Supabase)
    await SupabaseService.updateSongChords(songId, newChords);
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
    }

    _applyPitchOffsetToAudio();
    notifyListeners();
  }

  void _applyPitchOffsetToAudio() {
    try {
      if (!SoLoud.instance.isInitialized) return;

      final song = currentSong;
      final factor = pow(2.0, _pitchOffset / 12.0).toDouble();
      final bool isMulti = song != null && song.isMultiTrack && song.stems.length > 1;

      // 1. Tom original (0 semitons): desativa todos os filtros para áudio 100% puro e sem processamento DSP
      if (_pitchOffset == 0) {
        try {
          if (SoLoud.instance.filters.pitchShiftFilter.isActive) {
            SoLoud.instance.filters.pitchShiftFilter.deactivate();
          }
        } catch (_) {}

        for (final source in _stemSources.values) {
          try {
            if (!kIsWeb && source.filters.pitchShiftFilter.isActive) {
              source.filters.pitchShiftFilter.deactivate();
            }
          } catch (_) {}
        }
        return;
      }

      // 2. Transposição ativa (_pitchOffset != 0):
      if (!kIsWeb && isMulti) {
        // MULTITRACK EM PLATAFORMAS NATIVAS (Android, iOS, macOS, Windows):
        // Aplica o pitch shift em TODAS as faixas para garantir 100% DE SINCRONISMO (mesma latência de buffer FFT).
        // - Nas faixas de CUE (Click e Guia): fator = 1.0 (neutro: tom 100% original, sem alteração de tom).
        // - Nas faixas musicais da banda: fator = transposição calculada.
        // Desta forma, o Click e a Guia NUNCA sofrem alteração de tom e NUNCA dessincronizam da banda!
        bool anyStemFiltered = false;

        for (final stem in song.stems) {
          final source = _stemSources[stem.id];
          if (source == null) continue;

          final bool isCueTrack = stem.isCue ||
              stem.name.toLowerCase().contains('click') ||
              stem.name.toLowerCase().contains('metronomo') ||
              stem.name.toLowerCase().contains('metronome') ||
              stem.name.toLowerCase().contains('guia') ||
              stem.name.toLowerCase().contains('guide') ||
              stem.name.toLowerCase().contains('count');

          final handle = _stemHandles[stem.id];
          // Click e Guia usam fator 1.0 (tom original, mas com o mesmo buffer delay para sincronismo perfeito)
          final double stemFactor = isCueTrack ? 1.0 : factor;

          try {
            if (!source.filters.pitchShiftFilter.isActive) {
              source.filters.pitchShiftFilter.activate();
            }
            if (handle != null) {
              source.filters.pitchShiftFilter.shift(soundHandle: handle).value = stemFactor;
            } else {
              source.filters.pitchShiftFilter.shift().value = stemFactor;
            }
            anyStemFiltered = true;
          } catch (e) {
            debugPrint('Aviso ao aplicar pitchShiftFilter no stem ${stem.name}: $e');
          }
        }

        if (anyStemFiltered) {
          // Desativa o filtro Master global para não afetar o Click e a Guia
          try {
            if (SoLoud.instance.filters.pitchShiftFilter.isActive) {
              SoLoud.instance.filters.pitchShiftFilter.deactivate();
            }
          } catch (_) {}
          return;
        }
      }

      // 3. Fallback (Single Track ou Web): usa o filtro no mixer Master global do SoLoud
      try {
        if (!SoLoud.instance.filters.pitchShiftFilter.isActive) {
          SoLoud.instance.filters.pitchShiftFilter.activate();
        }
        SoLoud.instance.filters.pitchShiftFilter.shift.value = factor;
      } catch (e) {
        debugPrint('Aviso ao aplicar pitchShiftFilter master: $e');
      }
    } catch (e) {
      debugPrint('Aviso ao aplicar pitchShiftFilter no SoLoud: $e');
    }
  }

  void setTargetKey(String newKey) {
    final song = currentSong;
    if (song == null) return;
    final semitones = PitchShifterService.getSemitonesBetween(song.originalKey, newKey);
    setPitchOffset(semitones);
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

  /// Salva e fixa o tom ajustado especificamente nesta Playlist (Setlist)
  /// Mantendo 100% o tom original no Acervo Geral
  Future<bool> saveCurrentSongKeyToPlaylist([Setlist? targetSetlist]) async {
    final song = currentSong;
    if (song == null) return false;
    final setlist = targetSetlist ?? _currentSetlist;
    if (setlist == null) return false;

    // 1. Atualiza na playlist localmente
    final idx = setlist.songs.indexWhere((s) => s.id == song.id);
    if (idx != -1) {
      setlist.songs[idx].pitchOffsetSemitones = _pitchOffset;
      setlist.songs[idx].currentKey = song.currentKey;
    } else {
      setlist.songs.add(song.clone(
        currentKey: song.currentKey,
        pitchOffsetSemitones: _pitchOffset,
      ));
    }

    // 2. Salva e persiste na nuvem Supabase (colunas custom_key e pitch_offset da playlist)
    await SupabaseService.saveSetlistToCloud(setlist);

    // 3. Garante que no Acervo Geral da banda a música permaneça com seu tom original
    final libIdx = _masterLibrary.indexWhere((s) => s.id == song.id);
    if (libIdx != -1) {
      _masterLibrary[libIdx].pitchOffsetSemitones = 0;
      _masterLibrary[libIdx].currentKey = _masterLibrary[libIdx].originalKey;
    }

    notifyListeners();
    return true;
  }

  void playLibrarySongInMixer(Song librarySong) {
    _disposeStemPlayers();
    stop();

    _totalDurationSeconds = 0.0;
    _currentPositionSeconds = 0.0;
    _pitchOffset = 0;

    final bool isSingle = !librarySong.isMultiTrack || librarySong.stems.length <= 1;
    if (isSingle) {
      for (final stem in librarySong.stems) {
        stem.setPan(0.0);
      }
    }

    // Se já estiver na playlist atual, apenas seleciona
    if (_currentSetlist != null) {
      final existingIndex = _currentSetlist!.songs.indexWhere((s) => s.id == librarySong.id);
      if (existingIndex != -1) {
        _currentSongIndex = existingIndex;
        final existingSong = _currentSetlist!.songs[existingIndex];
        if (isSingle) {
          for (final stem in existingSong.stems) {
            stem.setPan(0.0);
          }
        }
        _pitchOffset = existingSong.pitchOffsetSemitones;
        _applyPitchOffsetToAudio();
        notifyListeners();
        return;
      }
    }

    // Se não estiver na playlist, cria preview no tom original
    final cloned = librarySong.clone(
      currentKey: librarySong.originalKey,
      pitchOffsetSemitones: 0,
    );
    if (isSingle) {
      for (final stem in cloned.stems) {
        stem.setPan(0.0);
      }
    }

    if (_currentSetlist == null) {
      _currentSetlist = Setlist(
        id: 'temp-acervo',
        title: 'Acervo Geral',
        date: DateTime.now(),
        songs: [cloned],
        isOfflineReady: true,
      );
      _currentSongIndex = 0;
    } else {
      _currentSetlist!.songs.add(cloned);
      _currentSongIndex = _currentSetlist!.songs.length - 1;
    }
    _applyPitchOffsetToAudio();
    notifyListeners();
  }

  // ==========================================
  // CONTROLE DE VOLUME, MUTE, SOLO E PAN (UNIFICADO E PROTEGIDO)
  // ==========================================

  /// Aplica volume e balanço (PAN) diretamente no mixer SoLoud C++
  Future<void> _applyStemAudioSettings(StemTrack stem) async {
    final handle = _stemHandles[stem.id];
    if (handle == null) return;

    final anySolo = hasActiveSolo;
    final effVol = stem.getEffectiveVolume(anySolo);

    try {
      SoLoud.instance.setVolume(handle, effVol);
      SoLoud.instance.setPan(handle, stem.pan);
    } catch (e) {
      debugPrint('Erro ao aplicar volume/pan na pista ${stem.name} no SoLoud: $e');
    }
  }

  /// Aplica configurações de volume e balanço em todas as faixas ativas
  Future<void> _applyAllStemsAudioSettings() async {
    final song = currentSong;
    if (song == null) return;

    final anySolo = hasActiveSolo;

    for (final stem in song.stems) {
      final handle = _stemHandles[stem.id];
      if (handle == null) continue;

      final effVol = stem.getEffectiveVolume(anySolo);
      try {
        SoLoud.instance.setVolume(handle, effVol);
        SoLoud.instance.setPan(handle, stem.pan);
      } catch (e) {
        debugPrint('Erro ao aplicar volume/pan em ${stem.name} no SoLoud: $e');
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

    if (!song.isMultiTrack || song.stems.length <= 1) {
      // Single track permanece sempre no Centro (0.0 / C)
      for (final stem in song.stems) {
        stem.setPan(0.0);
      }
    } else {
      for (final stem in song.stems) {
        stem.setPan(stem.isCue ? -1.0 : 1.0);
      }
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

  Future<void> seekTo(double seconds) async {
    _currentPositionSeconds = seconds.clamp(0.0, _totalDurationSeconds);
    _updateMusicalGrid();
    notifyListeners();

    if (_stemHandles.isEmpty) return;

    final target = Duration(milliseconds: (_currentPositionSeconds * 1000).toInt());
    for (final handle in _stemHandles.values) {
      try {
        SoLoud.instance.seek(handle, target);
      } catch (_) {}
    }
  }

  /// Relógio de alta precisão conectado diretamente à posição do mixer SoLoud C++
  void _startPlaybackClock() {
    _playbackTicker?.cancel();
    _playbackTicker = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isPlaying) return;

      if (_masterStemId != null && _stemHandles.containsKey(_masterStemId)) {
        try {
          final handle = _stemHandles[_masterStemId]!;
          final pos = SoLoud.instance.getPosition(handle);
          final posSec = pos.inMilliseconds / 1000.0;
          if (posSec >= 0) {
            _currentPositionSeconds = posSec;
            _lastPositionUpdateMillis = DateTime.now().millisecondsSinceEpoch;
            _updateMusicalGrid();

            if ((pos.inMilliseconds - _lastNotifiedMillis).abs() >= 200) {
              _lastNotifiedMillis = pos.inMilliseconds;
              notifyListeners();
            }

            if (_currentPositionSeconds >= (_totalDurationSeconds - 0.5) && _totalDurationSeconds > 5.0) {
              stop();
            }
            return;
          }
        } catch (_) {}
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastPositionUpdateMillis > 500) {
        _currentPositionSeconds += 0.1;
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
    _disposeStemPlayers();
    _playbackTicker?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }
}

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import '../models/setlist.dart';
import 'supabase_service.dart';

class AudioCacheService {
  static final Map<String, double> _downloadProgress = {};
  static final Set<String> _activeDownloads = {};
  static final Map<String, String> _cachedPaths = {};
  static bool _isPrefetching = false;

  static double getProgress(String storagePath) => _downloadProgress[storagePath] ?? 0.0;
  static bool isDownloading(String storagePath) => _activeDownloads.contains(storagePath);

  /// Retorna o diretório base de cache de áudio permanente no aparelho
  static Future<Directory> _getCacheDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${docsDir.path}/realtracks_audio');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// Gera um caminho local determinístico e seguro para o arquivo de áudio
  static Future<File> _getLocalFile(String storagePath) async {
    final dir = await _getCacheDirectory();
    final safeName = storagePath.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return File('${dir.path}/$safeName');
  }

  /// Verifica se o arquivo de áudio já foi baixado para o aparelho e está íntegro
  static Future<String?> getLocalPathIfExists(String storagePath) async {
    if (kIsWeb) return null;

    if (_cachedPaths.containsKey(storagePath)) {
      final p = _cachedPaths[storagePath]!;
      if (File(p).existsSync()) {
        return p;
      }
      _cachedPaths.remove(storagePath);
    }

    try {
      final file = await _getLocalFile(storagePath);
      if (await file.exists() && await file.length() > 1024) {
        _cachedPaths[storagePath] = file.path;
        return file.path;
      }
    } catch (e) {
      debugPrint('Erro ao verificar cache local: $e');
    }
    return null;
  }

  /// Verifica se todas as pistas de uma música estão salvas localmente no aparelho
  static Future<bool> isSongFullyCached(Song song) async {
    if (kIsWeb) return true;
    for (final stem in song.stems) {
      if (stem.filePath != null && stem.filePath!.isNotEmpty) {
        final local = await getLocalPathIfExists(stem.filePath!);
        if (local == null) return false;
      }
    }
    return true;
  }

  /// Verifica se todas as músicas de uma playlist estão baixadas
  static Future<bool> isSetlistFullyCached(Setlist setlist) async {
    if (kIsWeb) return true;
    for (final song in setlist.songs) {
      final cached = await isSongFullyCached(song);
      if (!cached) return false;
    }
    return true;
  }

  /// Retorna o caminho do arquivo local (baixando de forma confiável e síncrona na primeira vez)
  static Future<String> getOrDownloadAudio(
    String storagePath, {
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      return SupabaseService.getAudioUrl(storagePath);
    }

    // 1. Já existe no armazenamento local permanente?
    final existingPath = await getLocalPathIfExists(storagePath);
    if (existingPath != null) {
      return existingPath;
    }

    // 2. Se já estiver sendo baixado por outra rotina, aguarda concluir
    if (_activeDownloads.contains(storagePath)) {
      int waitCycles = 0;
      while (_activeDownloads.contains(storagePath) && waitCycles < 120) {
        await Future.delayed(const Duration(milliseconds: 200));
        waitCycles++;
        final path = await getLocalPathIfExists(storagePath);
        if (path != null) return path;
      }
    }

    _activeDownloads.add(storagePath);
    _downloadProgress[storagePath] = 0.01;

    final url = SupabaseService.getAudioUrl(storagePath);
    http.Client? client;

    try {
      final file = await _getLocalFile(storagePath);
      final tempFile = File('${file.path}.tmp');

      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }

      client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode == 200) {
        final totalBytes = response.contentLength ?? 0;
        int receivedBytes = 0;

        final sink = tempFile.openWrite();
        await response.stream.forEach((chunk) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            final prog = (receivedBytes / totalBytes).clamp(0.0, 1.0);
            _downloadProgress[storagePath] = prog;
            onProgress?.call(prog);
          }
        });

        await sink.flush();
        await sink.close();

        if (await tempFile.exists() && await tempFile.length() > 512) {
          if (await file.exists()) {
            try {
              await file.delete();
            } catch (_) {}
          }
          try {
            await tempFile.rename(file.path);
          } catch (_) {
            // Em alguns dispositivos Android, rename entre volumes falha; usa copy + delete
            await tempFile.copy(file.path);
            try {
              await tempFile.delete();
            } catch (_) {}
          }

          if (await file.exists() && await file.length() > 512) {
            _cachedPaths[storagePath] = file.path;
            _downloadProgress[storagePath] = 1.0;
            debugPrint('✅ Faixa salva no cache permanentemente: ${file.path}');
            return file.path;
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao baixar áudio $storagePath: $e');
    } finally {
      client?.close();
      _activeDownloads.remove(storagePath);
    }

    // Fallback: URL direta de streaming caso a rede caia durante o download
    return SupabaseService.getAudioUrl(storagePath);
  }

  /// Baixa todas as pistas de uma música com concorrência segura (2 por vez para não sobrecarregar a I/O do celular)
  static Future<void> downloadSong(
    Song song, {
    void Function(int done, int total, double progress)? onProgress,
  }) async {
    if (kIsWeb) return;

    final stemsToDownload = song.stems.where(
      (s) => s.filePath != null && s.filePath!.isNotEmpty,
    ).toList();

    if (stemsToDownload.isEmpty) return;

    int completed = 0;
    final total = stemsToDownload.length;

    // Baixa de 2 em 2 para garantir gravação estável na memória flash do celular
    for (int i = 0; i < stemsToDownload.length; i += 2) {
      final chunk = stemsToDownload.sublist(i, (i + 2 > total) ? total : i + 2);
      await Future.wait(chunk.map((stem) async {
        final local = await getLocalPathIfExists(stem.filePath!);
        if (local == null) {
          await getOrDownloadAudio(stem.filePath!);
        }
        completed++;
        onProgress?.call(completed, total, completed / total);
      }));
    }
  }

  /// Baixa a playlist inteira em segundo plano
  static Future<void> cacheSetlist(
    Setlist setlist, {
    void Function(int currentSong, int totalSongs, String songTitle)? onProgress,
  }) async {
    if (kIsWeb) return;
    final songs = setlist.songs;
    for (int i = 0; i < songs.length; i++) {
      final song = songs[i];
      onProgress?.call(i + 1, songs.length, song.title);
      await downloadSong(song);
    }
  }

  /// Baixa suavemente as faixas de uma música em background
  static Future<void> prefetchSong(Song song) async {
    if (kIsWeb || _isPrefetching) return;
    _isPrefetching = true;
    try {
      await downloadSong(song);
    } catch (e) {
      debugPrint('Erro durante download de faixas: $e');
    } finally {
      _isPrefetching = false;
    }
  }

  /// Limpa arquivos órfãos sem apagar músicas do acervo nem das playlists
  static Future<void> cleanOrphanedCache(List<Setlist> activeSetlists, [List<Song>? librarySongs]) async {
    if (kIsWeb) return;
    try {
      final dir = await _getCacheDirectory();
      if (!await dir.exists()) return;

      final Set<String> validFileNames = {};
      for (final setlist in activeSetlists) {
        for (final song in setlist.songs) {
          for (final stem in song.stems) {
            if (stem.filePath != null && stem.filePath!.isNotEmpty) {
              final safeName = stem.filePath!.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
              validFileNames.add(safeName);
            }
          }
        }
      }

      if (librarySongs != null) {
        for (final song in librarySongs) {
          for (final stem in song.stems) {
            if (stem.filePath != null && stem.filePath!.isNotEmpty) {
              final safeName = stem.filePath!.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
              validFileNames.add(safeName);
            }
          }
        }
      }

      final entities = dir.listSync();
      int deletedCount = 0;
      for (final entity in entities) {
        if (entity is File) {
          final fileName = entity.uri.pathSegments.last;
          if (!validFileNames.contains(fileName) && !fileName.endsWith('.tmp')) {
            try {
              entity.deleteSync();
              deletedCount++;
              debugPrint('🧹 Cache limpo: removido áudio não utilizado: $fileName');
            } catch (_) {}
          }
        }
      }
      if (deletedCount > 0) {
        debugPrint('🧹 Total de $deletedCount arquivo(s) de áudio excluído(s) do aparelho.');
      }
    } catch (e) {
      debugPrint('Erro ao limpar cache órfão: $e');
    }
  }

  /// Limpa 100% de todo o cache local de áudio quando solicitado pelo usuário
  static Future<void> clearAllCache() async {
    if (kIsWeb) return;
    try {
      _cachedPaths.clear();
      final dir = await _getCacheDirectory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Erro ao limpar todo o cache: $e');
    }
  }
}

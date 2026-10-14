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
  static bool _isPrefetching = false;

  static double getProgress(String storagePath) => _downloadProgress[storagePath] ?? 0.0;
  static bool isDownloading(String storagePath) => _activeDownloads.contains(storagePath);

  /// Retorna o diretório base de cache de áudio no aparelho
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
    try {
      final file = await _getLocalFile(storagePath);
      if (await file.exists() && await file.length() > 1024) {
        return file.path;
      }
    } catch (e) {
      debugPrint('Erro ao verificar cache local: $e');
    }
    return null;
  }

  /// Verifica se todas as pistas de uma música estão 100% salvas no aparelho
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

  /// Retorna o arquivo local se existir, ou baixa da nuvem de forma segura
  static Future<String> getOrDownloadAudio(
    String storagePath, {
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      return SupabaseService.getAudioUrl(storagePath);
    }

    http.Client? client;
    try {
      final file = await _getLocalFile(storagePath);
      if (await file.exists() && await file.length() > 1024) {
        return file.path;
      }

      if (_activeDownloads.contains(storagePath)) {
        return SupabaseService.getAudioUrl(storagePath);
      }

      _activeDownloads.add(storagePath);
      _downloadProgress[storagePath] = 0.01;

      final url = SupabaseService.getAudioUrl(storagePath);
      client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode == 200) {
        final totalBytes = response.contentLength ?? 0;
        int receivedBytes = 0;
        final tempFile = File('${file.path}.tmp');

        final sink = tempFile.openWrite();
        await response.stream.listen(
          (chunk) {
            sink.add(chunk);
            receivedBytes += chunk.length;
            if (totalBytes > 0) {
              final prog = receivedBytes / totalBytes;
              _downloadProgress[storagePath] = prog;
              onProgress?.call(prog);
            }
          },
          onDone: () async {
            await sink.flush();
            await sink.close();
            if (await tempFile.exists()) {
              await tempFile.rename(file.path);
            }
          },
          onError: (e) {
            sink.close();
          },
          cancelOnError: true,
        ).asFuture();

        _activeDownloads.remove(storagePath);
        _downloadProgress[storagePath] = 1.0;

        if (await file.exists() && await file.length() > 1024) {
          return file.path;
        }
      }
    } catch (e) {
      debugPrint('Erro no download em cache da faixa $storagePath: $e');
    } finally {
      client?.close();
      _activeDownloads.remove(storagePath);
    }

    // Fallback: URL direta de streaming
    return SupabaseService.getAudioUrl(storagePath);
  }

  /// Baixa todas as pistas de uma música com concorrência otimizada
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

    // Baixa de 3 em 3 faixas para máxima velocidade sem engasgar o celular
    for (int i = 0; i < stemsToDownload.length; i += 3) {
      final chunk = stemsToDownload.sublist(i, (i + 3 > total) ? total : i + 3);
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

  /// Remove do celular qualquer arquivo de áudio que NÃO pertença a nenhuma playlist ativa.
  /// (Conforme regra do usuário: enquanto a playlist existir o cache é mantido; se a playlist for excluída, o cache é apagado)
  static Future<void> cleanOrphanedCache(List<Setlist> activeSetlists) async {
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

      final entities = dir.listSync();
      int deletedCount = 0;
      for (final entity in entities) {
        if (entity is File) {
          final fileName = entity.uri.pathSegments.last;
          if (!validFileNames.contains(fileName) && !fileName.endsWith('.tmp')) {
            try {
              entity.deleteSync();
              deletedCount++;
              debugPrint('🧹 Cache limpo: removido áudio de playlist excluída: $fileName');
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

  /// Limpa 100% de todo o cache local de áudio
  static Future<void> clearAllCache() async {
    if (kIsWeb) return;
    try {
      final dir = await _getCacheDirectory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Erro ao limpar todo o cache: $e');
    }
  }
}

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
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

  /// Retorna o arquivo local se existir, ou baixa da nuvem de forma segura
  static Future<String> getOrDownloadAudio(
    String storagePath, {
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      return SupabaseService.getAudioUrl(storagePath);
    }

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
      final client = http.Client();
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
      _activeDownloads.remove(storagePath);
    }

    // Fallback: URL direta de streaming
    return SupabaseService.getAudioUrl(storagePath);
  }

  /// Baixa todas as pistas de uma música uma por uma em segundo plano sem saturar a rede
  static Future<void> prefetchSong(Song song) async {
    if (kIsWeb || _isPrefetching) return;
    _isPrefetching = true;
    try {
      for (final stem in song.stems) {
        if (stem.filePath != null && stem.filePath!.isNotEmpty) {
          final local = await getLocalPathIfExists(stem.filePath!);
          if (local == null) {
            await getOrDownloadAudio(stem.filePath!);
            // Intervalo suave de 400ms entre downloads para não travar conexões 4G/Wi-Fi
            await Future.delayed(const Duration(milliseconds: 400));
          }
        }
      }
    } catch (e) {
      debugPrint('Erro durante prefetch sequencial: $e');
    } finally {
      _isPrefetching = false;
    }
  }
}

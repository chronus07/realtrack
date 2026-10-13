import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/song.dart';
import '../models/setlist.dart';
import '../models/stem_track.dart';

class UploadStemItem {
  final PlatformFile file;
  String name;
  bool isCue; // true = Click/Guia (L), false = Banda (R)

  UploadStemItem({
    required this.file,
    required this.name,
    required this.isCue,
  });
}

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  /// Inicializa o Supabase no início do aplicativo
  static Future<void> initialize() async {
    if (AppConfig.isConfigured) {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
    }
  }

  /// Busca todo o Acervo Geral de Músicas da banda no Supabase
  static Future<List<Song>> fetchAllLibrarySongs() async {
    if (!AppConfig.isConfigured) return [];

    try {
      final response = await client
          .from('songs')
          .select('*, song_stems(*)')
          .order('title', ascending: true);

      final List<Song> songs = [];
      for (var row in response) {
        final stemsRaw = row['song_stems'] as List? ?? [];
        final List<StemTrack> stems = stemsRaw.map<StemTrack>((st) {
          return StemTrack(
            id: st['id'] ?? '',
            name: st['name'] ?? '',
            isCue: st['is_cue'] ?? false,
            filePath: st['storage_path'],
          );
        }).toList();

        songs.add(
          Song(
            id: row['id'],
            title: row['title'],
            artist: row['artist'] ?? '',
            originalKey: row['original_key'] ?? 'G',
            bpm: row['bpm'] ?? 120,
            timeSignature: row['time_signature'] ?? '4/4',
            isMultiTrack: row['is_multitrack'] ?? true,
            chordsText: row['chords_text'] ?? '',
            stems: stems,
          ),
        );
      }
      return songs;
    } catch (e) {
      debugPrint('Erro ao buscar acervo no Supabase: $e');
      return [];
    }
  }

  /// Faz o upload de uma nova música e de seus áudios (stems) para o Supabase
  static Future<Song?> uploadNewSong({
    required String title,
    required String artist,
    required String originalKey,
    required int bpm,
    required String timeSignature,
    required bool isMultiTrack,
    required String chordsText,
    required List<UploadStemItem> stemsToUpload,
    Function(double progress, String status)? onProgress,
  }) async {
    if (!AppConfig.isConfigured) {
      throw Exception('Supabase não configurado');
    }

    try {
      onProgress?.call(0.1, 'Salvando metadados da música no acervo...');

      // 1. Inserir a música na tabela `songs`
      final songInsertResponse = await client.from('songs').insert({
        'title': title,
        'artist': artist,
        'original_key': originalKey,
        'bpm': bpm,
        'time_signature': timeSignature,
        'is_multitrack': isMultiTrack,
        'chords_text': chordsText,
      }).select().single();

      final String songId = songInsertResponse['id'];
      final List<StemTrack> createdStems = [];

      // 2. Upload de cada arquivo de áudio para o bucket `audio-tracks`
      for (int i = 0; i < stemsToUpload.length; i++) {
        final item = stemsToUpload[i];
        final file = item.file;
        final double stepProgress = 0.2 + (0.7 * (i / stemsToUpload.length));
        
        onProgress?.call(stepProgress, 'Enviando faixa ${i + 1}/${stemsToUpload.length}: ${item.name}...');

        final String storagePath = 'songs/$songId/${file.name}';

        if (file.bytes != null) {
          await client.storage.from(AppConfig.audioBucketName).uploadBinary(
                storagePath,
                file.bytes!,
                fileOptions: const FileOptions(upsert: true),
              );
        } else if (file.path != null) {
          final ioFile = File(file.path!);
          await client.storage.from(AppConfig.audioBucketName).upload(
                storagePath,
                ioFile,
                fileOptions: const FileOptions(upsert: true),
              );
        }

        // 3. Registra a pista na tabela `song_stems`
        final stemInsertResponse = await client.from('song_stems').insert({
          'song_id': songId,
          'name': item.name,
          'is_cue': item.isCue,
          'storage_path': storagePath,
          'file_size_bytes': file.size,
        }).select().single();

        createdStems.add(
          StemTrack(
            id: stemInsertResponse['id'],
            name: item.name,
            isCue: item.isCue,
            filePath: storagePath,
          ),
        );
      }

      onProgress?.call(1.0, 'Música cadastrada com sucesso no acervo!');

      return Song(
        id: songId,
        title: title,
        artist: artist,
        originalKey: originalKey,
        bpm: bpm,
        timeSignature: timeSignature,
        isMultiTrack: isMultiTrack,
        chordsText: chordsText,
        stems: createdStems,
      );
    } catch (e) {
      debugPrint('Erro ao fazer upload da música: $e');
      rethrow;
    }
  }

  /// Remove uma música do Acervo Geral
  static Future<bool> deleteSongFromLibrary(String songId) async {
    if (!AppConfig.isConfigured) return false;
    try {
      await client.from('songs').delete().eq('id', songId);
      return true;
    } catch (e) {
      debugPrint('Erro ao excluir música: $e');
      return false;
    }
  }

  /// Baixa uma pista de áudio da nuvem para o armazenamento do celular (Modo Offline)
  static Future<File> downloadStemOffline(String storagePath, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final localPath = '${dir.path}/tracks/$filename';
    final file = File(localPath);

    if (await file.exists()) {
      return file;
    }

    await file.parent.create(recursive: true);
    final audioUrl = client.storage.from(AppConfig.audioBucketName).getPublicUrl(storagePath);
    final response = await http.get(Uri.parse(audioUrl));

    await file.writeAsBytes(response.bodyBytes);
    return file;
  }
}

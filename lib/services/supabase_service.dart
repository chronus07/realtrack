import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/song.dart';
import '../models/setlist.dart';
import '../models/stem_track.dart';

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

  /// Busca as setlists da banda na nuvem
  static Future<List<Setlist>> getBandSetlists(String bandId) async {
    if (!AppConfig.isConfigured) return [];

    final response = await client
        .from('setlists')
        .select('*, setlist_songs(*, songs(*, song_stems(*)))')
        .eq('band_id', bandId)
        .order('event_date', ascending: false);

    final List<Setlist> list = [];
    for (var item in response) {
      final songsRaw = item['setlist_songs'] as List? ?? [];
      final List<Song> songs = [];

      for (var sRaw in songsRaw) {
        final songData = sRaw['songs'];
        if (songData == null) continue;

        final stemsRaw = songData['song_stems'] as List? ?? [];
        final List<StemTrack> stems = stemsRaw.map<StemTrack>((st) {
          return StemTrack(
            id: st['id'],
            name: st['name'],
            isCue: st['is_cue'] ?? false,
            filePath: st['storage_path'],
          );
        }).toList();

        songs.add(
          Song(
            id: songData['id'],
            title: songData['title'],
            artist: songData['artist'],
            originalKey: songData['original_key'],
            currentKey: sRaw['custom_key'] ?? songData['original_key'],
            pitchOffsetSemitones: sRaw['pitch_offset'] ?? 0,
            bpm: songData['bpm'],
            timeSignature: songData['time_signature'] ?? '4/4',
            isMultiTrack: songData['is_multitrack'] ?? true,
            chordsText: songData['chords_text'] ?? '',
            stems: stems,
          ),
        );
      }

      list.add(
        Setlist(
          id: item['id'],
          title: item['title'],
          date: DateTime.parse(item['event_date']),
          songs: songs,
        ),
      );
    }
    return list;
  }

  /// Baixa uma pista de áudio da nuvem para o armazenamento do celular (Modo Offline)
  static Future<File> downloadStemOffline(String storagePath, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final localPath = '${dir.path}/tracks/$filename';
    final file = File(localPath);

    if (await file.exists()) {
      return file; // Já está baixado!
    }

    await file.parent.create(recursive: true);

    // Obtém a URL pública do Cloudflare / Supabase Storage
    final audioUrl = client.storage.from(AppConfig.audioBucketName).getPublicUrl(storagePath);
    final response = await http.get(Uri.parse(audioUrl));

    await file.writeAsBytes(response.bodyBytes);
    return file;
  }

  /// Sincronização em tempo real (Notifica quando o líder mudar tom ou repertório)
  static RealtimeChannel listenToSetlistChanges(String setlistId, VoidCallback onUpdate) {
    return client
        .channel('public:setlist_songs:$setlistId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'setlist_songs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'setlist_id',
            value: setlistId,
          ),
          callback: (payload) {
            onUpdate();
          },
        )
        .subscribe();
  }
}

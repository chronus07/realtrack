import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class CloudImporterService {
  static String get serviceUrl => AppConfig.cloudImporterUrl.replaceAll(RegExp(r'/+$'), '');

  static set serviceUrl(String url) {
    AppConfig.cloudImporterUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
  }

  /// Verifica se o serviço na nuvem está online e pronto
  static Future<bool> isServiceOnline([String? customUrl]) async {
    final target = (customUrl != null && customUrl.isNotEmpty)
        ? customUrl.replaceAll(RegExp(r'/+$'), '')
        : serviceUrl;

    if (target.isEmpty) return false;

    try {
      final res = await http.get(Uri.parse('$target/health')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['status'] == 'online';
      }
    } catch (_) {}
    return false;
  }

  /// Resolve o link do YouTube ou Spotify e extrai os metadados
  static Future<Map<String, dynamic>> resolveLink(String rawUrl) async {
    final target = serviceUrl;
    if (target.isEmpty) {
      throw Exception('A URL do serviço na nuvem (Cloud Importer) não está configurada.');
    }

    try {
      final response = await http
          .post(
            Uri.parse('$target/api/resolve'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'url': rawUrl.trim()}),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        final errData = jsonDecode(response.body);
        throw Exception(errData['error'] ?? 'Erro ${response.statusCode} ao resolver link.');
      }
    } catch (e) {
      debugPrint('Erro ao resolver link no Cloud Importer: $e');
      rethrow;
    }
  }

  /// Dispara o download em nuvem do áudio, conversão em MP3 e upload no Supabase
  static Future<Map<String, dynamic>> importSong({
    required String youtubeUrl,
    required String title,
    required String artist,
    required String key,
    required int bpm,
    required String timeSignature,
  }) async {
    final target = serviceUrl;
    if (target.isEmpty) {
      throw Exception('A URL do serviço na nuvem não está configurada.');
    }

    try {
      final payload = {
        'youtubeUrl': youtubeUrl,
        'title': title,
        'artist': artist,
        'key': key,
        'bpm': bpm,
        'timeSignature': timeSignature,
        'supabaseUrl': AppConfig.supabaseUrl,
        'supabaseKey': AppConfig.supabaseAnonKey,
      };

      final response = await http
          .post(
            Uri.parse('$target/api/import'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 180)); // Tempo amplo para download + conversão + upload

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        final errData = jsonDecode(response.body);
        throw Exception(errData['error'] ?? 'Falha na importação na nuvem (HTTP ${response.statusCode})');
      }
    } catch (e) {
      debugPrint('Erro ao importar música via Cloud Importer: $e');
      rethrow;
    }
  }
}

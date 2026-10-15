import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';
import 'supabase_service.dart';

class AppUpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final String changelog;
  final bool hasUpdate;

  AppUpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    required this.changelog,
    required this.hasUpdate,
  });
}

class UpdateService {
  static const String currentVersion = '1.0.20';
  static const String defaultDownloadUrl =
      'https://github.com/chronus07/realtrack/releases/download/latest/app-release.apk';

  /// Verifica se há uma versão mais recente
  static Future<AppUpdateInfo?> checkForUpdate() async {
    // Na Web, o usuário atualiza a página simplesmente dando F5. Desabilita verificação e download de APK.
    if (kIsWeb) return null;

    try {
      // 1. Tenta buscar da tabela app_config no Supabase
      if (AppConfig.isConfigured) {
        try {
          final client = SupabaseService.client;
          final res = await client.from('app_config').select('*');
          if (res.isNotEmpty) {
            String latestVersion = currentVersion;
            String downloadUrl = defaultDownloadUrl;
            String changelog = 'Melhorias de sincronização do acervo e novidades no app.';

            for (var row in res) {
              if (row['key'] == 'latest_version') latestVersion = row['value'];
              if (row['key'] == 'apk_download_url') downloadUrl = row['value'];
              if (row['key'] == 'release_notes') changelog = row['value'];
            }

            final bool hasUpdate = _isVersionNewer(latestVersion, currentVersion);
            return AppUpdateInfo(
              latestVersion: latestVersion,
              downloadUrl: downloadUrl,
              changelog: changelog,
              hasUpdate: hasUpdate,
            );
          }
        } catch (_) {
          // Continua para o fallback do GitHub Releases
        }
      }

      // 2. Fallback: Checa a API de Releases do GitHub
      final ghRes = await http.get(
        Uri.parse('https://api.github.com/repos/chronus07/realtrack/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (ghRes.statusCode == 200) {
        final data = jsonDecode(ghRes.body);
        final tagName = data['tag_name'] ?? '1.0.1';
        final cleanTag = tagName.replaceAll(RegExp(r'[^0-9.]'), '');
        final body = data['body'] ?? 'Novas melhorias e correções.';
        final hasUpdate = _isVersionNewer(cleanTag, currentVersion);

        return AppUpdateInfo(
          latestVersion: cleanTag,
          downloadUrl: defaultDownloadUrl,
          changelog: body,
          hasUpdate: hasUpdate,
        );
      }
    } catch (e) {
      debugPrint('Erro ao verificar atualizações: $e');
    }
    return null;
  }

  static bool _isVersionNewer(String latest, String current) {
    try {
      final latestParts = latest.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

      for (int i = 0; i < latestParts.length && i < currentParts.length; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return latestParts.length > currentParts.length;
    } catch (_) {
      return latest != current;
    }
  }

  /// Exibe o diálogo de atualização para o usuário
  static void showUpdateDialog(BuildContext context, AppUpdateInfo info) {
    if (kIsWeb) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.system_update, color: AppTheme.primary, size: 28),
            SizedBox(width: 10),
            Text('Nova Versão Disponível!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Versão instalada: v$currentVersion ➔ Nova versão: v${info.latestVersion}',
              style: const TextStyle(fontSize: 12, color: AppTheme.amberCue, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Novidades:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              info.changelog,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            const Text(
              'Ao clicar em Atualizar, o download iniciará automaticamente e seus repertórios serão mantidos.',
              style: TextStyle(fontSize: 10, color: Colors.white38),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mais Tarde', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Atualizar Agora', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final uri = Uri.parse(info.downloadUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
    );
  }
}

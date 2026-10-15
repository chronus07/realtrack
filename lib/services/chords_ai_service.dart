import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/song.dart';
import 'worship_catalog.dart';

class ChordsAiService {
  static String? _userApiKey;

  /// Retorna a chave ativa (definida pelo usuário ou estática no AppConfig)
  static String get activeApiKey =>
      (_userApiKey != null && _userApiKey!.isNotEmpty)
          ? _userApiKey!
          : AppConfig.geminiApiKey;

  /// Permite ao usuário configurar uma chave Gemini customizada
  static void setUserApiKey(String key) {
    _userApiKey = key.trim();
  }

  /// Retorna as cifras com inteligência de cache (Acervo) e IA
  /// 1. Cache do Acervo (0 tokens)
  /// 2. Catálogo worship integrado (0 tokens)
  /// 3. Google Gemini Flash API
  static Future<String?> getOrFetchChords(
    Song song, {
    bool forceRegenerate = false,
  }) async {
    // 1. Verifica se já está salva no Acervo
    if (!forceRegenerate && song.chordsText.trim().isNotEmpty) {
      debugPrint('ChordsAiService: Cifra carregada do Acervo local/Supabase para "${song.title}" (0 tokens).');
      return song.chordsText;
    }

    // 2. Verifica se existe no catálogo de worship embutido
    final builtIn = WorshipCatalog.getBuiltInChords(song.title);
    if (!forceRegenerate && builtIn != null && builtIn.trim().isNotEmpty) {
      debugPrint('ChordsAiService: Cifra encontrada no catálogo integrado para "${song.title}" (0 tokens).');
      return builtIn;
    }

    // 3. Tenta gerar via Gemini API
    final apiKey = activeApiKey;
    if (apiKey.isEmpty) {
      // Se não houver chave de API configurada e tivermos a cifra de catálogo (mesmo se foi solicitado regerar), usa o catálogo
      if (builtIn != null && builtIn.trim().isNotEmpty) {
        return builtIn;
      }
      return null;
    }

    try {
      debugPrint('ChordsAiService: Solicitando cifra ao Gemini para "${song.title}" (${song.artist})...');

      final prompt = '''
Você é um músico profissional especialista em cifras de louvor e adoração para bandas e igrejas.
Gere a cifra completa com acordes alinhados em cima da letra para a música:
Título: "${song.title}"
Artista/Ministério: "${song.artist}"
Tom desejado: ${song.originalKey}

Instruções rigorosas de formatação:
1. Use seções claras entre colchetes, por exemplo: [Intro], [Verso 1], [Pré-Refrão], [Refrão], [Ponte], [Final].
2. Posicione os acordes exatamente acima das sílabas onde ocorrem as mudanças de harmonia.
3. Não utilize notação tipo ChordPro (como [G]palavra), utilize o formato tradicional brasileiro de cifras onde a linha de acordes fica acima da linha de letra.
4. Não adicione saudações, introduções, explicações ou blocos com crases (```), responda apenas o texto puro da cifra.
''';

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey',
      );

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.2,
            'maxOutputTokens': 2048,
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          final parts = content['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            String text = parts[0]['text'] ?? '';
            // Limpa crases de blocos de código se o modelo tiver retornado
            text = text.replaceAll('```markdown', '').replaceAll('```text', '').replaceAll('```', '').trim();
            debugPrint('ChordsAiService: Cifra gerada com sucesso via Gemini!');
            return text;
          }
        }
      } else {
        debugPrint('ChordsAiService: Erro na chamada Gemini API (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('ChordsAiService: Falha ao chamar Gemini: $e');
    }

    // Se a chamada de IA falhar, fallback para o catálogo se disponível
    if (builtIn != null && builtIn.trim().isNotEmpty) {
      return builtIn;
    }

    return null;
  }
}

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../models/stem_track.dart';

class AudioDetectionResult {
  final int? bpm;
  final String? key;
  final String? timeSignature;
  final String? detectedTitle;
  final String? detectedArtist;
  final double confidence; // 0.0 a 1.0
  final String source;     // Descrição de como foi detectado

  const AudioDetectionResult({
    this.bpm,
    this.key,
    this.timeSignature,
    this.detectedTitle,
    this.detectedArtist,
    this.confidence = 0.0,
    this.source = 'Automático',
  });

  bool get hasBpm => bpm != null && bpm! > 0;
  bool get hasKey => key != null && key!.isNotEmpty;
  bool get hasAny => hasBpm || hasKey;

  @override
  String toString() => 'AudioDetectionResult(bpm: $bpm, key: $key, timeSignature: $timeSignature, source: $source, confidence: ${(confidence * 100).toInt()}%)';
}

class BpmKeyDetector {
  static const List<String> standardKeys = [
    'C', 'C#', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'
  ];

  // ==========================================
  // 1. DETECÇÃO COMPLETA MULTI-ESTRATÉGIA
  // ==========================================

  /// Analisa um conjunto de nomes de arquivos, metadados ou caminhos e retorna Tom e BPM
  static Future<AudioDetectionResult> detectFromStemsAndMetadata({
    required List<String> fileNames,
    List<String>? filePaths,
    List<Uint8List>? fileBytesList,
    String? songTitle,
    String? chordsText,
  }) async {
    int? detectedBpm;
    String? detectedKey;
    String? detectedTimeSig;
    String? detectedTitle;
    String? detectedArtist;
    String source = '';
    double confidence = 0.0;

    // A. Análise do Click Track (se houver áudio e arquivo WAV/PCM ou identificação de Click)
    for (int i = 0; i < fileNames.length; i++) {
      final name = fileNames[i];
      final lower = name.toLowerCase();
      if (lower.contains('click') || lower.contains('metronomo') || lower.contains('guia')) {
        // Tenta ler BPM direto no nome do Click
        final bpmInClick = _extractBpmFromString(name);
        if (bpmInClick != null) {
          detectedBpm = bpmInClick;
          source = 'Pista de Click ($name)';
          confidence = 0.95;
          break;
        }

        // Tenta análise de transientes PCM se for WAV
        if (fileBytesList != null && i < fileBytesList.length && fileBytesList[i].length > 44) {
          final pcmBpm = _detectBpmFromWavBytes(fileBytesList[i]);
          if (pcmBpm != null) {
            detectedBpm = pcmBpm;
            source = 'Análise de Transientes de Áudio (Click)';
            confidence = 0.98;
            break;
          }
        } else if (filePaths != null && i < filePaths.length && filePaths[i].isNotEmpty) {
          final pcmBpm = await _detectBpmFromWavFile(filePaths[i]);
          if (pcmBpm != null) {
            detectedBpm = pcmBpm;
            source = 'Análise de Áudio Local (Click)';
            confidence = 0.98;
            break;
          }
        }
      }
    }

    // B. Leitura de Metadados Binários (ID3v2 TBPM / TKEY / MP4 tmpo)
    if (fileBytesList != null) {
      for (final bytes in fileBytesList) {
        if (bytes.length > 32) {
          final meta = _parseAudioHeaderMetadata(bytes);
          if (meta.hasBpm && detectedBpm == null) {
            detectedBpm = meta.bpm;
            source = 'Metadados ID3 do Áudio';
            confidence = math.max(confidence, 0.90);
          }
          if (meta.hasKey && detectedKey == null) {
            detectedKey = meta.key;
            source = 'Metadados ID3 do Áudio';
            confidence = math.max(confidence, 0.90);
          }
        }
      }
    }

    // C. Varredura Inteligente nos Nomes dos Arquivos
    for (final name in fileNames) {
      if (detectedBpm == null) {
        final b = _extractBpmFromString(name);
        if (b != null) {
          detectedBpm = b;
          source = 'Nomenclatura da Faixa ($name)';
          confidence = math.max(confidence, 0.85);
        }
      }

      if (detectedKey == null) {
        final k = _extractKeyFromString(name);
        if (k != null) {
          detectedKey = k;
          source = 'Nomenclatura da Faixa ($name)';
          confidence = math.max(confidence, 0.85);
        }
      }

      if (detectedTimeSig == null) {
        final ts = _extractTimeSignatureFromString(name);
        if (ts != null) {
          detectedTimeSig = ts;
        }
      }
    }

    // D. Varredura no Título da Música / Pasta
    if (songTitle != null && songTitle.isNotEmpty) {
      if (detectedBpm == null) {
        final b = _extractBpmFromString(songTitle);
        if (b != null) {
          detectedBpm = b;
          source = 'Título da Música';
          confidence = math.max(confidence, 0.80);
        }
      }

      if (detectedKey == null) {
        final k = _extractKeyFromString(songTitle);
        if (k != null) {
          detectedKey = k;
          source = 'Título da Música';
          confidence = math.max(confidence, 0.80);
        }
      }

      // Tenta extrair artista se estiver no formato "Artista - Música" ou "Música - Artista"
      final parts = songTitle.split(RegExp(r'\s+[-–—]\s+'));
      if (parts.length >= 2) {
        detectedTitle = _cleanTitle(parts[0]);
        detectedArtist = _cleanTitle(parts[1]);
      }
    }

    // E. Análise Harmônica das Cifras (se houver chordsText)
    if (detectedKey == null && chordsText != null && chordsText.trim().isNotEmpty) {
      final chordKey = _detectKeyFromChordsText(chordsText);
      if (chordKey != null) {
        detectedKey = chordKey;
        source = 'Análise Harmônica das Cifras';
        confidence = math.max(confidence, 0.88);
      }
    }

    return AudioDetectionResult(
      bpm: detectedBpm,
      key: _normalizeKey(detectedKey),
      timeSignature: detectedTimeSig ?? '4/4',
      detectedTitle: detectedTitle,
      detectedArtist: detectedArtist,
      confidence: confidence,
      source: source.isNotEmpty ? source : 'Padrão Inteligente',
    );
  }

  // ==========================================
  // 2. PARSERS DE EXPRESSÃO REGULAR (REGEX)
  // ==========================================

  /// Extrai BPM numérico de strings como "Song - G - 72bpm", "Click_130", "BPM 68", "(95 BPM)"
  static int? _extractBpmFromString(String text) {
    final clean = text.replaceAll('_', ' ').replaceAll('-', ' ');

    // 1. Padrão explícito: "72bpm", "72 bpm", "bpm 72", "bpm: 72"
    final explicitRegex = RegExp(r'\b(?:bpm[\s:]*)?([5-9]\d|1\d\d|2[0-1]\d)(?:[\s]*bpm)?\b', caseSensitive: false);
    for (final match in explicitRegex.allMatches(clean)) {
      final str = match.group(0)?.toLowerCase() ?? '';
      if (str.contains('bpm')) {
        final numPart = RegExp(r'\d+').firstMatch(str)?.group(0);
        if (numPart != null) {
          final val = int.tryParse(numPart);
          if (val != null && val >= 45 && val <= 240) return val;
        }
      }
    }

    // 2. Padrão Click: "Click 130", "130 Click"
    final clickRegex = RegExp(r'click[^\d]*(\d{2,3})|(\d{2,3})[^\d]*click', caseSensitive: false);
    final clickMatch = clickRegex.firstMatch(clean);
    if (clickMatch != null) {
      final g = clickMatch.group(1) ?? clickMatch.group(2);
      if (g != null) {
        final val = int.tryParse(g);
        if (val != null && val >= 45 && val <= 240) return val;
      }
    }

    // 3. Padrão entre parênteses ou colchetes: "(74)" ou "[74]"
    final bracketRegex = RegExp(r'[(\[]\s*(\d{2,3})\s*[)\]]');
    final bracketMatch = bracketRegex.firstMatch(clean);
    if (bracketMatch != null) {
      final val = int.tryParse(bracketMatch.group(1) ?? '');
      if (val != null && val >= 50 && val <= 220) return val;
    }

    return null;
  }

  /// Extrai Tom musical como "G", "Ab", "F#m", "Tom D", "Key: Bb", "Dó Maior"
  static String? _extractKeyFromString(String text) {
    // 1. Padrão explícito com prefixo "tom", "tom:", "key", "key:"
    final explicitKeyRegex = RegExp(r'\b(?:tom|key)[\s_\-:]*([A-Ga-g][#b]?(?:m|maj|min)?)\b', caseSensitive: false);
    final explicitMatch = explicitKeyRegex.firstMatch(text);
    if (explicitMatch != null) {
      final k = explicitMatch.group(1);
      if (k != null) return k;
    }

    // 2. Padrão isolado entre delimitadores (ex: " - Bb - ", "(G)", "[F#m]", "_D_")
    final isolatedKeyRegex = RegExp(r'(?:^|[_\-\s(\[])([A-Ga-g][#b]?[mM]?)(?:[_\-\s)\]]|$|\.)');
    for (final match in isolatedKeyRegex.allMatches(text)) {
      final cand = match.group(1);
      if (cand != null) {
        // Evita falsos positivos como letra "A" isolada que seja apenas artigo
        if (cand.toUpperCase() == 'A' && !text.contains('Key') && !text.contains('Tom') && !text.contains('- A -')) {
          continue;
        }
        if (_isValidKey(cand)) {
          return cand;
        }
      }
    }

    return null;
  }

  /// Extrai fórmula de compasso ("4/4", "6/8", "3/4", "12/8")
  static String? _extractTimeSignatureFromString(String text) {
    final sigRegex = RegExp(r'\b(4/4|6/8|3/4|2/4|12/8|2/2)\b');
    final match = sigRegex.firstMatch(text);
    return match?.group(1);
  }

  static String _cleanTitle(String raw) {
    String t = raw.replaceAll(RegExp(r'\.(m4a|wav|mp3|aac|flac)$', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\b(?:bpm|tom|key)[\s_\-:]*\w+\b', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\b\d{2,3}\s*bpm\b', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    return t;
  }

  // ==========================================
  // 3. ANÁLISE DE TRANSISTENTES DE CLICK (WAV PCM)
  // ==========================================

  static int? _detectBpmFromWavBytes(Uint8List bytes) {
    try {
      if (bytes.length < 44) return null;

      // Verifica se é cabeçalho RIFF WAVE
      final riff = String.fromCharCodes(bytes.sublist(0, 4));
      final wave = String.fromCharCodes(bytes.sublist(8, 12));
      if (riff != 'RIFF' || wave != 'WAVE') return null;

      final byteData = ByteData.sublistView(bytes);
      final channels = byteData.getUint16(22, Endian.little);
      final sampleRate = byteData.getUint32(24, Endian.little);
      final bitsPerSample = byteData.getUint16(34, Endian.little);

      if (channels < 1 || sampleRate < 8000 || bitsPerSample != 16) return null;

      // Procura bloco 'data'
      int dataOffset = 36;
      while (dataOffset < bytes.length - 8) {
        final chunkId = String.fromCharCodes(bytes.sublist(dataOffset, dataOffset + 4));
        final chunkSize = byteData.getUint32(dataOffset + 4, Endian.little);
        if (chunkId == 'data') {
          dataOffset += 8;
          break;
        }
        dataOffset += 8 + chunkSize;
      }

      if (dataOffset >= bytes.length) return null;

      // Analisa até 12 segundos de áudio para encontrar picos de metrônomo
      final maxSamples = math.min((bytes.length - dataOffset) ~/ 2, sampleRate * channels * 12);
      final List<int> peakSampleIndices = [];
      const threshold = 12000; // ~37% do volume máximo em 16-bit PCM (32767)
      final minSamplesBetweenBeats = (sampleRate * 0.25).toInt(); // Max 240 BPM

      int lastPeakIndex = -minSamplesBetweenBeats;

      for (int i = 0; i < maxSamples; i += channels) {
        final byteIdx = dataOffset + (i * 2);
        if (byteIdx + 1 >= bytes.length) break;

        final sample = byteData.getInt16(byteIdx, Endian.little).abs();
        final currentSampleIndex = i ~/ channels;

        if (sample > threshold && (currentSampleIndex - lastPeakIndex) > minSamplesBetweenBeats) {
          peakSampleIndices.add(currentSampleIndex);
          lastPeakIndex = currentSampleIndex;
        }
      }

      if (peakSampleIndices.length < 4) return null;

      // Calcula a distância entre os picos sucessivos
      final List<double> intervalsInSeconds = [];
      for (int i = 1; i < peakSampleIndices.length; i++) {
        final diffSamples = peakSampleIndices[i] - peakSampleIndices[i - 1];
        final sec = diffSamples / sampleRate;
        // Intervalos válidos de BPM musical (entre 45 BPM e 220 BPM -> 0.27s a 1.33s)
        if (sec >= 0.26 && sec <= 1.4) {
          intervalsInSeconds.add(sec);
        }
      }

      if (intervalsInSeconds.length < 3) return null;

      // Mediana dos intervalos para ignorar viradas ou ruídos
      intervalsInSeconds.sort();
      final medianInterval = intervalsInSeconds[intervalsInSeconds.length ~/ 2];

      final calculatedBpm = (60.0 / medianInterval).round();
      if (calculatedBpm >= 45 && calculatedBpm <= 220) {
        return calculatedBpm;
      }
    } catch (e) {
      debugPrint('Erro ao calcular BPM via WAV: $e');
    }
    return null;
  }

  static Future<int?> _detectBpmFromWavFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      // Lê os primeiros 256KB para capturar o cabeçalho e os primeiros cliques
      final raf = await file.open(mode: FileMode.read);
      final headerBytes = await raf.read(256 * 1024);
      await raf.close();
      return _detectBpmFromWavBytes(headerBytes);
    } catch (_) {
      return null;
    }
  }

  // ==========================================
  // 4. PARSER DE METADADOS ID3V2 E MP4/M4A
  // ==========================================

  static AudioDetectionResult _parseAudioHeaderMetadata(Uint8List bytes) {
    int? bpm;
    String? key;

    try {
      // 1. Verifica tag ID3v2 (primeiros 3 bytes = "ID3")
      if (bytes.length > 10 && bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
        final textData = String.fromCharCodes(bytes.sublist(0, math.min(bytes.length, 4096)));
        
        // TBPM frame
        final bpmMatch = RegExp(r'TBPM[^\w]*(\d{2,3})', caseSensitive: false).firstMatch(textData);
        if (bpmMatch != null) {
          bpm = int.tryParse(bpmMatch.group(1) ?? '');
        }

        // TKEY frame
        final keyMatch = RegExp(r'TKEY[^\w]*([A-Ga-g][#b]?[mM]?)', caseSensitive: false).firstMatch(textData);
        if (keyMatch != null) {
          key = keyMatch.group(1);
        }
      }

      // 2. Verifica MP4/M4A (atom "tmpo" para BPM)
      if (bytes.length > 64) {
        final textData = String.fromCharCodes(bytes.sublist(0, math.min(bytes.length, 4096)));
        final tmpoIdx = textData.indexOf('tmpo');
        if (tmpoIdx != -1 && tmpoIdx + 8 < bytes.length) {
          final byteData = ByteData.sublistView(bytes);
          final rawBpm = byteData.getUint16(tmpoIdx + 4, Endian.big);
          if (rawBpm >= 45 && rawBpm <= 240) {
            bpm = rawBpm;
          }
        }
      }
    } catch (_) {}

    return AudioDetectionResult(
      bpm: bpm,
      key: _normalizeKey(key),
      source: 'Metadados Internos do Arquivo',
    );
  }

  // ==========================================
  // 5. ANÁLISE HARMÔNICA DE CIFRAS (CHORDS)
  // ==========================================

  static String? _detectKeyFromChordsText(String chordsText) {
    try {
      // Extrai acordes como G, D/F#, Em7, C9, Bb, etc.
      final chordRegex = RegExp(r'\b([A-G][#b]?(?:m|maj|min|dim|aug|sus\d?)?\d?(?:/[A-G][#b]?)?)\b');
      final matches = chordRegex.allMatches(chordsText);
      if (matches.isEmpty) return null;

      final Map<String, int> rootCount = {};
      String? firstChordRoot;

      for (final m in matches) {
        final fullChord = m.group(1) ?? '';
        final rootMatch = RegExp(r'^([A-G][#b]?)').firstMatch(fullChord);
        if (rootMatch != null) {
          final root = rootMatch.group(1)!;
          rootCount[root] = (rootCount[root] ?? 0) + 1;
          firstChordRoot ??= root;
        }
      }

      if (rootCount.isEmpty) return null;

      // O primeiro acorde ou o acorde mais frequente em 90% das músicas de adoração indica o Tom
      String mostFrequent = rootCount.entries.first.key;
      int maxFreq = 0;
      for (final e in rootCount.entries) {
        if (e.value > maxFreq) {
          maxFreq = e.value;
          mostFrequent = e.key;
        }
      }

      // Se o primeiro acorde tiver relevância expressiva, ele tem altíssima chance de ser a tônica
      if (firstChordRoot != null && (rootCount[firstChordRoot] ?? 0) >= (maxFreq * 0.6)) {
        return firstChordRoot;
      }

      return mostFrequent;
    } catch (_) {
      return null;
    }
  }

  // ==========================================
  // 6. UTILITÁRIOS E NORMALIZAÇÃO
  // ==========================================

  static bool _isValidKey(String k) {
    final clean = k.trim().replaceAll('m', '').replaceAll('M', '');
    return standardKeys.any((sk) => sk.toUpperCase() == clean.toUpperCase());
  }

  static String? _normalizeKey(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    var k = raw.trim();
    // Ex: "g" -> "G", "bb" -> "Bb", "c#" -> "C#"
    if (k.length == 1) {
      k = k.toUpperCase();
    } else if (k.length >= 2) {
      final first = k[0].toUpperCase();
      final rest = k.substring(1);
      k = '$first$rest';
    }

    // Normaliza variações menores
    if (k.endsWith('m') || k.endsWith('min')) {
      final base = k.replaceAll('min', '').replaceAll('m', '');
      return base; // RealTracks trabalha com o Tom Maior equivalente ou transposição padrão
    }

    return standardKeys.firstWhere(
      (sk) => sk.toUpperCase() == k.toUpperCase(),
      orElse: () => k,
    );
  }

  /// Executa auto-detecção em uma música existente do Acervo e atualiza Tom e BPM
  static Future<AudioDetectionResult> autoDetectForExistingSong(Song song) async {
    final fileNames = song.stems.map((s) => s.name).toList();
    final filePaths = song.stems.map((s) => s.filePath ?? '').toList();

    return detectFromStemsAndMetadata(
      fileNames: fileNames,
      filePaths: filePaths,
      songTitle: song.title,
      chordsText: song.chordsText,
    );
  }
}

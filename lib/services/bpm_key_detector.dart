import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../models/stem_track.dart';
import 'worship_catalog.dart';

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

  String get summary {
    final parts = <String>[];
    if (hasKey) parts.add('Tom: $key');
    if (hasBpm) parts.add('$bpm BPM');
    if (timeSignature != null && timeSignature!.isNotEmpty) parts.add(timeSignature!);
    return parts.isEmpty ? 'Nenhum padrão identificado' : parts.join(' • ');
  }

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
    List<Uint8List?>? fileBytesList,
    String? songTitle,
    String? chordsText,
  }) async {
    // ----------------------------------------------------
    // PILAR 1: CONSULTA INSTANTÂNEA NO CATÁLOGO DE LOUVOR
    // ----------------------------------------------------
    if (songTitle != null && songTitle.trim().isNotEmpty) {
      final catalogMatch = WorshipCatalog.lookup(songTitle);
      if (catalogMatch != null) {
        return AudioDetectionResult(
          bpm: catalogMatch.bpm,
          key: catalogMatch.key,
          timeSignature: catalogMatch.timeSignature,
          detectedTitle: catalogMatch.title,
          detectedArtist: catalogMatch.artist,
          confidence: 0.99,
          source: 'Catálogo de Louvor (${catalogMatch.artist})',
        );
      }
    }

    // Verifica se algum dos arquivos ou pastas traz o nome de uma música do catálogo
    for (final name in fileNames) {
      final catalogMatch = WorshipCatalog.lookup(name);
      if (catalogMatch != null) {
        return AudioDetectionResult(
          bpm: catalogMatch.bpm,
          key: catalogMatch.key,
          timeSignature: catalogMatch.timeSignature,
          detectedTitle: catalogMatch.title,
          detectedArtist: catalogMatch.artist,
          confidence: 0.98,
          source: 'Catálogo de Louvor (${catalogMatch.artist})',
        );
      }
    }

    if (filePaths != null) {
      for (final p in filePaths) {
        final catalogMatch = WorshipCatalog.lookup(p);
        if (catalogMatch != null) {
          return AudioDetectionResult(
            bpm: catalogMatch.bpm,
            key: catalogMatch.key,
            timeSignature: catalogMatch.timeSignature,
            detectedTitle: catalogMatch.title,
            detectedArtist: catalogMatch.artist,
            confidence: 0.98,
            source: 'Catálogo de Louvor (${catalogMatch.artist})',
          );
        }
      }
    }

    // ----------------------------------------------------
    // PILAR 2: ANÁLISE DE TRANSISTENTES DE CLICK (.WAV E .M4A)
    // ----------------------------------------------------
    int? detectedBpm;
    String? detectedKey;
    String? detectedTimeSig;
    String? detectedTitle;
    String? detectedArtist;
    String source = '';
    double confidence = 0.0;

    for (int i = 0; i < fileNames.length; i++) {
      final name = fileNames[i];
      final lower = name.toLowerCase();
      if (lower.contains('click') ||
          lower.contains('metronomo') ||
          lower.contains('metronome') ||
          lower.contains('guia') ||
          lower.contains('guide') ||
          lower.contains('cue') ||
          lower.contains('count') ||
          lower.contains('tempo')) {
        // A. Tenta ler BPM direto no nome do Click (ex: Click_125.m4a)
        final bpmInClick = _extractBpmFromString(name);
        if (bpmInClick != null) {
          detectedBpm = bpmInClick;
          source = 'Pista de Click ($name)';
          confidence = 0.95;
          break;
        }

        // B. Análise PCM em arquivos .WAV
        if (fileBytesList != null && i < fileBytesList.length && fileBytesList[i] != null && fileBytesList[i]!.length > 44) {
          final pcmBpm = _detectBpmFromWavBytes(fileBytesList[i]!);
          if (pcmBpm != null) {
            detectedBpm = pcmBpm;
            source = 'Análise de Transientes de Áudio (Click)';
            confidence = 0.98;
            break;
          }

          // C. Análise de quadros AAC em arquivos .M4A
          final m4aBpm = _detectBpmFromM4aBytes(fileBytesList[i]!);
          if (m4aBpm != null) {
            detectedBpm = m4aBpm;
            source = 'Análise de Metrônomo AAC (Click)';
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

          final m4aBpm = await _detectBpmFromM4aFile(filePaths[i]);
          if (m4aBpm != null) {
            detectedBpm = m4aBpm;
            source = 'Análise de Metrônomo AAC Local (Click)';
            confidence = 0.98;
            break;
          }
        }
      }
    }

    // ----------------------------------------------------
    // PILAR 3: METADADOS BINÁRIOS (ID3v2 TBPM / TKEY / MP4 tmpo)
    // ----------------------------------------------------
    if (fileBytesList != null) {
      for (final bytes in fileBytesList) {
        if (bytes != null && bytes.length > 32) {
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

    // ----------------------------------------------------
    // PILAR 4: VARREDURA NOS NOMES DAS PISTAS
    // ----------------------------------------------------
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

    // ----------------------------------------------------
    // PILAR 5: VARREDURA NO TÍTULO DIGITADO
    // ----------------------------------------------------
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

      final parts = songTitle.split(RegExp(r'\s+[-–—]\s+'));
      if (parts.length >= 2) {
        detectedTitle = _cleanTitle(parts[0]);
        detectedArtist = _cleanTitle(parts[1]);
      }
    }

    // ----------------------------------------------------
    // PILAR 6: ANÁLISE HARMÔNICA DE CIFRAS
    // ----------------------------------------------------
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

  static int? _extractBpmFromString(String text) {
    final clean = text.replaceAll('_', ' ').replaceAll('-', ' ');

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

    final clickRegex = RegExp(r'click[^\d]*(\d{2,3})|(\d{2,3})[^\d]*click', caseSensitive: false);
    final clickMatch = clickRegex.firstMatch(clean);
    if (clickMatch != null) {
      final g = clickMatch.group(1) ?? clickMatch.group(2);
      if (g != null) {
        final val = int.tryParse(g);
        if (val != null && val >= 45 && val <= 240) return val;
      }
    }

    final bracketRegex = RegExp(r'[(\[]\s*(\d{2,3})\s*[)\]]');
    final bracketMatch = bracketRegex.firstMatch(clean);
    if (bracketMatch != null) {
      final val = int.tryParse(bracketMatch.group(1) ?? '');
      if (val != null && val >= 50 && val <= 220) return val;
    }

    return null;
  }

  static String? _extractKeyFromString(String text) {
    final explicitKeyRegex = RegExp(r'\b(?:tom|key)[\s_\-:]*([A-Ga-g][#b]?(?:m|maj|min)?)\b', caseSensitive: false);
    final explicitMatch = explicitKeyRegex.firstMatch(text);
    if (explicitMatch != null) {
      final k = explicitMatch.group(1);
      if (k != null) return k;
    }

    final isolatedKeyRegex = RegExp(r'(?:^|[_\-\s(\[])([A-Ga-g][#b]?[mM]?)(?:[_\-\s)\]]|$|\.)');
    for (final match in isolatedKeyRegex.allMatches(text)) {
      final cand = match.group(1);
      if (cand != null) {
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

      final riff = String.fromCharCodes(bytes.sublist(0, 4));
      final wave = String.fromCharCodes(bytes.sublist(8, 12));
      if (riff != 'RIFF' || wave != 'WAVE') return null;

      final byteData = ByteData.sublistView(bytes);
      final channels = byteData.getUint16(22, Endian.little);
      final sampleRate = byteData.getUint32(24, Endian.little);
      final bitsPerSample = byteData.getUint16(34, Endian.little);

      if (channels < 1 || sampleRate < 8000 || bitsPerSample != 16) return null;

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

      final maxSamples = math.min((bytes.length - dataOffset) ~/ 2, sampleRate * channels * 12);
      final List<int> peakSampleIndices = [];
      const threshold = 12000;
      final minSamplesBetweenBeats = (sampleRate * 0.25).toInt();

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

      final List<double> intervalsInSeconds = [];
      for (int i = 1; i < peakSampleIndices.length; i++) {
        final diffSamples = peakSampleIndices[i] - peakSampleIndices[i - 1];
        final sec = diffSamples / sampleRate;
        if (sec >= 0.26 && sec <= 1.4) {
          intervalsInSeconds.add(sec);
        }
      }

      if (intervalsInSeconds.length < 3) return null;

      intervalsInSeconds.sort();
      final medianInterval = intervalsInSeconds[intervalsInSeconds.length ~/ 2];

      final calculatedBpm = (60.0 / medianInterval).round();
      if (calculatedBpm >= 45 && calculatedBpm <= 220) {
        return calculatedBpm;
      }
    } catch (_) {}
    return null;
  }

  static Future<int?> _detectBpmFromWavFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final raf = await file.open(mode: FileMode.read);
      final headerBytes = await raf.read(256 * 1024);
      await raf.close();
      return _detectBpmFromWavBytes(headerBytes);
    } catch (_) {
      return null;
    }
  }

  // ==========================================
  // 4. ANÁLISE DE QUADROS AAC EM ARQUIVOS .M4A
  // ==========================================

  static int? _detectBpmFromM4aBytes(Uint8List bytes) {
    try {
      if (bytes.length < 100) return null;

      // Procura o átomo 'stsz' (Sample Size Atom) que contém o tamanho de cada quadro AAC (1024 amostras = ~23ms)
      int stszOffset = -1;
      for (int i = 0; i < bytes.length - 24; i++) {
        if (bytes[i] == 0x73 &&
            bytes[i + 1] == 0x74 &&
            bytes[i + 2] == 0x73 &&
            bytes[i + 3] == 0x7A) {
          stszOffset = i;
          break;
        }
      }

      if (stszOffset == -1) return null;

      final byteData = ByteData.sublistView(bytes);
      final uniformSize = byteData.getUint32(stszOffset + 8, Endian.big);
      final sampleCount = byteData.getUint32(stszOffset + 12, Endian.big);

      if (uniformSize != 0 || sampleCount < 10) return null;

      // Tenta extrair a taxa de amostragem (timescale) do átomo 'mdhd', padrão 44.1kHz
      int sampleRate = 44100;
      for (int i = 0; i < bytes.length - 28; i++) {
        if (bytes[i] == 0x6D && bytes[i + 1] == 0x64 && bytes[i + 2] == 0x68 && bytes[i + 3] == 0x64) {
          final version = bytes[i + 4];
          final tsOffset = version == 1 ? i + 24 : i + 16;
          if (tsOffset + 4 <= bytes.length) {
            final ts = byteData.getUint32(tsOffset, Endian.big);
            if (ts >= 8000 && ts <= 96000) {
              sampleRate = ts;
              break;
            }
          }
        }
      }

      final List<int> frameSizes = [];
      int offset = stszOffset + 16;
      final maxSamples = math.min(sampleCount, 2500); // Primeiros ~60 segundos

      for (int i = 0; i < maxSamples; i++) {
        if (offset + 4 > bytes.length) break;
        frameSizes.add(byteData.getUint32(offset, Endian.big));
        offset += 4;
      }

      if (frameSizes.length < 40) return null;

      final sortedSizes = List<int>.from(frameSizes)..sort();
      final medianSize = sortedSizes[sortedSizes.length ~/ 2];
      final spikeThreshold = math.max((medianSize * 2.0).toInt(), 60);

      final List<int> clickFrameIndices = [];
      const minFramesBetweenClicks = 11; // ~255ms (máximo 235 BPM)
      int lastClickFrame = -minFramesBetweenClicks;

      for (int i = 0; i < frameSizes.length; i++) {
        final sz = frameSizes[i];
        if (sz >= spikeThreshold && (i - lastClickFrame) >= minFramesBetweenClicks) {
          clickFrameIndices.add(i);
          lastClickFrame = i;
        }
      }

      if (clickFrameIndices.length < 4) return null;

      final List<double> intervalsInSeconds = [];
      final secondsPerAacFrame = 1024.0 / sampleRate;

      for (int i = 1; i < clickFrameIndices.length; i++) {
        final diffFrames = clickFrameIndices[i] - clickFrameIndices[i - 1];
        final sec = diffFrames * secondsPerAacFrame;
        if (sec >= 0.25 && sec <= 1.5) {
          intervalsInSeconds.add(sec);
        }
      }

      if (intervalsInSeconds.length < 3) return null;

      intervalsInSeconds.sort();
      final medianInterval = intervalsInSeconds[intervalsInSeconds.length ~/ 2];
      final bpm = (60.0 / medianInterval).round();

      if (bpm >= 45 && bpm <= 230) {
        return bpm;
      }
    } catch (_) {}
    return null;
  }

  static Future<int?> _detectBpmFromM4aFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final len = await file.length();
      if (len < 100) return null;

      final raf = await file.open(mode: FileMode.read);

      // 1. Tenta nos primeiros 512KB (se o arquivo tiver moov no início / faststart)
      final headSize = math.min(512 * 1024, len);
      final headBytes = await raf.read(headSize);
      int? bpm = _detectBpmFromM4aBytes(headBytes);
      if (bpm != null) {
        await raf.close();
        return bpm;
      }

      // 2. Se moov estiver no final do arquivo (padrão em exports de DAWs e FFmpeg sem faststart)
      if (len > headSize) {
        final tailReadSize = math.min(1024 * 1024, len);
        await raf.setPosition(len - tailReadSize);
        final tailBytes = await raf.read(tailReadSize);
        bpm = _detectBpmFromM4aBytes(tailBytes);
        if (bpm != null) {
          await raf.close();
          return bpm;
        }
      }

      await raf.close();
      return null;
    } catch (_) {
      return null;
    }
  }

  // ==========================================
  // 5. PARSER DE METADADOS ID3V2 E MP4/M4A
  // ==========================================

  static AudioDetectionResult _parseAudioHeaderMetadata(Uint8List bytes) {
    int? bpm;
    String? key;

    try {
      if (bytes.length > 10 && bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
        final textData = String.fromCharCodes(bytes.sublist(0, math.min(bytes.length, 4096)));
        
        final bpmMatch = RegExp(r'TBPM[^\w]*(\d{2,3})', caseSensitive: false).firstMatch(textData);
        if (bpmMatch != null) {
          bpm = int.tryParse(bpmMatch.group(1) ?? '');
        }

        final keyMatch = RegExp(r'TKEY[^\w]*([A-Ga-g][#b]?[mM]?)', caseSensitive: false).firstMatch(textData);
        if (keyMatch != null) {
          key = keyMatch.group(1);
        }
      }

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
  // 6. ANÁLISE HARMÔNICA DE CIFRAS (CHORDS)
  // ==========================================

  static String? _detectKeyFromChordsText(String chordsText) {
    try {
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

      String mostFrequent = rootCount.entries.first.key;
      int maxFreq = 0;
      for (final e in rootCount.entries) {
        if (e.value > maxFreq) {
          maxFreq = e.value;
          mostFrequent = e.key;
        }
      }

      if (firstChordRoot != null && (rootCount[firstChordRoot] ?? 0) >= (maxFreq * 0.6)) {
        return firstChordRoot;
      }

      return mostFrequent;
    } catch (_) {
      return null;
    }
  }

  // ==========================================
  // 7. UTILITÁRIOS E NORMALIZAÇÃO
  // ==========================================

  static bool _isValidKey(String k) {
    final clean = k.trim().replaceAll('m', '').replaceAll('M', '');
    return standardKeys.any((sk) => sk.toUpperCase() == clean.toUpperCase());
  }

  static String? _normalizeKey(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    var k = raw.trim();
    if (k.length == 1) {
      k = k.toUpperCase();
    } else if (k.length >= 2) {
      final first = k[0].toUpperCase();
      final rest = k.substring(1);
      k = '$first$rest';
    }

    if (k.endsWith('m') || k.endsWith('min')) {
      final base = k.replaceAll('min', '').replaceAll('m', '');
      return base;
    }

    return standardKeys.firstWhere(
      (sk) => sk.toUpperCase() == k.toUpperCase(),
      orElse: () => k,
    );
  }

  /// Executa auto-detecção em uma música existente do Acervo e atualiza Tom e BPM
  static Future<AudioDetectionResult> autoDetectForExistingSong(Song song) async {
    // 1. Tenta catálogo primeiro
    final catalogMatch = WorshipCatalog.lookup(song.title);
    if (catalogMatch != null) {
      return AudioDetectionResult(
        bpm: catalogMatch.bpm,
        key: catalogMatch.key,
        timeSignature: catalogMatch.timeSignature,
        detectedTitle: catalogMatch.title,
        detectedArtist: catalogMatch.artist,
        confidence: 0.99,
        source: 'Catálogo de Louvor (${catalogMatch.artist})',
      );
    }

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

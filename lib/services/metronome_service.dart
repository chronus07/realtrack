import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

enum MetronomeTimbre {
  digitalClave,
  acousticRimshot,
  classicBeep,
  woodblock,
}

enum MetronomeSubdivision {
  quarter, // 1/4 (Semínima)
  eighth, // 1/8 (Colcheia)
  triplet, // Tercina (3 notas por tempo)
  sixteenth, // 1/16 (Semicolcheia)
}

class MetronomeService extends ChangeNotifier {
  bool _isPlaying = false;
  int _bpm = 120;
  String _timeSignature = '4/4';
  int _beatsPerBar = 4;
  int _currentBeat = 1;
  int _currentSubdivisionIndex = 0;
  double _pan = 0.0; // -1.0 (L), 0.0 (C), 1.0 (R)
  double _volume = 0.85;
  bool _isMuted = false;
  MetronomeTimbre _timbre = MetronomeTimbre.digitalClave;
  MetronomeSubdivision _subdivision = MetronomeSubdivision.quarter;

  // Handles de áudio no SoLoud
  AudioSource? _hiSource;
  AudioSource? _loSource;
  AudioSource? _subSource;
  bool _isAudioReady = false;

  // Timer de alta precisão livre de drift cumulativo
  Timer? _timer;
  DateTime? _startTime;
  int _tickIndex = 0;

  // TAP Tempo
  final List<DateTime> _tapTimestamps = [];

  // Getters
  bool get isPlaying => _isPlaying;
  int get bpm => _bpm;
  String get timeSignature => _timeSignature;
  int get beatsPerBar => _beatsPerBar;
  int get currentBeat => _currentBeat;
  int get currentSubdivisionIndex => _currentSubdivisionIndex;
  double get pan => _pan;
  double get volume => _volume;
  bool get isMuted => _isMuted;
  MetronomeTimbre get timbre => _timbre;
  MetronomeSubdivision get subdivision => _subdivision;
  bool get isAudioReady => _isAudioReady;

  MetronomeService() {
    _updateBeatsPerBar();
    _initSounds();
  }

  void _updateBeatsPerBar() {
    final parts = _timeSignature.split('/');
    if (parts.isNotEmpty) {
      _beatsPerBar = int.tryParse(parts[0]) ?? 4;
    } else {
      _beatsPerBar = 4;
    }
  }

  // ==========================================
  // INICIALIZAÇÃO E GERAÇÃO SINTÉTICA DE ONDAS
  // ==========================================

  Future<void> _initSounds() async {
    try {
      if (!SoLoud.instance.isInitialized) {
        await SoLoud.instance.init();
        SoLoud.instance.setMaxActiveVoiceCount(128);
      }
      await _loadSourcesForTimbre(_timbre);
      _isAudioReady = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Aviso ao inicializar áudios do metrônomo: $e');
    }
  }

  Future<void> _loadSourcesForTimbre(MetronomeTimbre timbre) async {
    // Descarta fontes anteriores de forma segura
    if (_hiSource != null) {
      try {
        await SoLoud.instance.disposeSource(_hiSource!);
      } catch (_) {}
      _hiSource = null;
    }
    if (_loSource != null) {
      try {
        await SoLoud.instance.disposeSource(_loSource!);
      } catch (_) {}
      _loSource = null;
    }
    if (_subSource != null) {
      try {
        await SoLoud.instance.disposeSource(_subSource!);
      } catch (_) {}
      _subSource = null;
    }

    final hiBytes = _generateWavBytes(isAccent: true, timbre: timbre);
    final loBytes = _generateWavBytes(isAccent: false, timbre: timbre);
    final subBytes = _generateWavBytes(isAccent: false, isSubdivision: true, timbre: timbre);

    try {
      _hiSource = await SoLoud.instance.loadMem(
        'metro_${timbre.name}_hi.wav',
        hiBytes,
        mode: LoadMode.memory,
      );
      _loSource = await SoLoud.instance.loadMem(
        'metro_${timbre.name}_lo.wav',
        loBytes,
        mode: LoadMode.memory,
      );
      _subSource = await SoLoud.instance.loadMem(
        'metro_${timbre.name}_sub.wav',
        subBytes,
        mode: LoadMode.memory,
      );
    } catch (e) {
      debugPrint('Erro ao carregar fontes de áudio do metrônomo no SoLoud: $e');
    }
  }

  /// Gera áudio PCM 16-bit estritamente formatado em RIFF WAV mono
  Uint8List _generateWavBytes({
    required bool isAccent,
    bool isSubdivision = false,
    required MetronomeTimbre timbre,
    int sampleRate = 44100,
  }) {
    double freq = 2000.0;
    double secondaryFreq = 0.0;
    double noiseMix = 0.0;
    double durationSec = 0.040;
    double decayTau = 0.015;

    switch (timbre) {
      case MetronomeTimbre.digitalClave:
        if (isAccent) {
          freq = 2400.0;
          decayTau = 0.018;
          durationSec = 0.045;
        } else if (isSubdivision) {
          freq = 1800.0;
          decayTau = 0.010;
          durationSec = 0.025;
        } else {
          freq = 1400.0;
          decayTau = 0.015;
          durationSec = 0.038;
        }
        break;

      case MetronomeTimbre.acousticRimshot:
        if (isAccent) {
          freq = 1600.0;
          secondaryFreq = 850.0;
          noiseMix = 0.28;
          decayTau = 0.035;
          durationSec = 0.055;
        } else if (isSubdivision) {
          freq = 1300.0;
          secondaryFreq = 650.0;
          noiseMix = 0.15;
          decayTau = 0.018;
          durationSec = 0.030;
        } else {
          freq = 1000.0;
          secondaryFreq = 520.0;
          noiseMix = 0.22;
          decayTau = 0.030;
          durationSec = 0.045;
        }
        break;

      case MetronomeTimbre.classicBeep:
        if (isAccent) {
          freq = 1760.0; // A6
          decayTau = 0.035;
          durationSec = 0.045;
        } else if (isSubdivision) {
          freq = 1174.6; // D6
          decayTau = 0.018;
          durationSec = 0.025;
        } else {
          freq = 880.0; // A5
          decayTau = 0.030;
          durationSec = 0.040;
        }
        break;

      case MetronomeTimbre.woodblock:
        if (isAccent) {
          freq = 1250.0;
          secondaryFreq = 2500.0;
          decayTau = 0.025;
          durationSec = 0.050;
        } else if (isSubdivision) {
          freq = 1000.0;
          secondaryFreq = 2000.0;
          decayTau = 0.015;
          durationSec = 0.030;
        } else {
          freq = 800.0;
          secondaryFreq = 1600.0;
          decayTau = 0.025;
          durationSec = 0.050;
        }
        break;
    }

    final numSamples = (sampleRate * durationSec).toInt();
    final dataSize = numSamples * 2;
    final byteData = ByteData(44 + dataSize);

    // 1. RIFF Header
    byteData.setUint8(0, 0x52); // 'R'
    byteData.setUint8(1, 0x49); // 'I'
    byteData.setUint8(2, 0x46); // 'F'
    byteData.setUint8(3, 0x46); // 'F'
    byteData.setUint32(4, 36 + dataSize, Endian.little);
    byteData.setUint8(8, 0x57);  // 'W'
    byteData.setUint8(9, 0x41);  // 'A'
    byteData.setUint8(10, 0x56); // 'V'
    byteData.setUint8(11, 0x45); // 'E'

    // 2. fmt chunk
    byteData.setUint8(12, 0x66); // 'f'
    byteData.setUint8(13, 0x6D); // 'm'
    byteData.setUint8(14, 0x74); // 't'
    byteData.setUint8(15, 0x20); // ' '
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little); // PCM
    byteData.setUint16(22, 1, Endian.little); // Mono
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    byteData.setUint16(32, 2, Endian.little); // block align
    byteData.setUint16(34, 16, Endian.little); // bits per sample

    // 3. data chunk
    byteData.setUint8(36, 0x64); // 'd'
    byteData.setUint8(37, 0x61); // 'a'
    byteData.setUint8(38, 0x74); // 't'
    byteData.setUint8(39, 0x61); // 'a'
    byteData.setUint32(40, dataSize, Endian.little);

    final random = Random(1337);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final env = exp(-t / decayTau);

      double tone = sin(2 * pi * freq * t);
      if (secondaryFreq > 0) {
        tone = (tone * 0.7) + (sin(2 * pi * secondaryFreq * t) * 0.3);
      }
      if (noiseMix > 0) {
        final whiteNoise = (random.nextDouble() * 2.0 - 1.0);
        tone = (tone * (1.0 - noiseMix)) + (whiteNoise * noiseMix);
      }

      final sample = (tone * env).clamp(-1.0, 1.0);
      final intSample = (sample * 30000).toInt().clamp(-32767, 32767);
      byteData.setInt16(44 + i * 2, intSample, Endian.little);
    }

    return byteData.buffer.asUint8List();
  }

  // ==========================================
  // CONTROLES DE PARÂMETROS
  // ==========================================

  void setBpm(int newBpm) {
    final clamped = newBpm.clamp(30, 300);
    if (_bpm == clamped) return;
    _bpm = clamped;
    notifyListeners();

    if (_isPlaying) {
      _restartTimer();
    }
  }

  void adjustBpm(int delta) {
    setBpm(_bpm + delta);
  }

  void setPan(double newPan) {
    // -1.0 (L), 0.0 (C), 1.0 (R)
    _pan = newPan.clamp(-1.0, 1.0);
    notifyListeners();
  }

  void setVolume(double newVol) {
    _volume = newVol.clamp(0.0, 1.0);
    notifyListeners();
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    notifyListeners();
  }

  void setTimeSignature(String ts) {
    if (_timeSignature == ts) return;
    _timeSignature = ts;
    _updateBeatsPerBar();
    _currentBeat = 1;
    _currentSubdivisionIndex = 0;
    notifyListeners();

    if (_isPlaying) {
      _restartTimer();
    }
  }

  Future<void> setTimbre(MetronomeTimbre newTimbre) async {
    if (_timbre == newTimbre) return;
    _timbre = newTimbre;
    notifyListeners();
    await _loadSourcesForTimbre(newTimbre);
  }

  void setSubdivision(MetronomeSubdivision newSub) {
    if (_subdivision == newSub) return;
    _subdivision = newSub;
    _currentSubdivisionIndex = 0;
    notifyListeners();

    if (_isPlaying) {
      _restartTimer();
    }
  }

  // ==========================================
  // TAP TEMPO INTELIGENTE
  // ==========================================

  void tapTempo() {
    final now = DateTime.now();

    // Se a última batida foi há mais de 2,5 segundos, reinicia a contagem
    if (_tapTimestamps.isNotEmpty && now.difference(_tapTimestamps.last).inMilliseconds > 2500) {
      _tapTimestamps.clear();
    }

    _tapTimestamps.add(now);

    // Mantém no máximo os últimos 5 toques para resposta rápida e precisa
    if (_tapTimestamps.length > 5) {
      _tapTimestamps.removeAt(0);
    }

    if (_tapTimestamps.length >= 2) {
      double totalIntervalMs = 0;
      for (int i = 1; i < _tapTimestamps.length; i++) {
        totalIntervalMs += _tapTimestamps[i].difference(_tapTimestamps[i - 1]).inMilliseconds;
      }
      final avgIntervalMs = totalIntervalMs / (_tapTimestamps.length - 1);
      if (avgIntervalMs > 0) {
        final calcBpm = (60000.0 / avgIntervalMs).round().clamp(30, 300);
        setBpm(calcBpm);
      }
    }
  }

  // ==========================================
  // LOOP DO METRÔNOMO (ZERO DRIFT CUMULATIVO)
  // ==========================================

  void togglePlay() {
    if (_isPlaying) {
      stop();
    } else {
      start();
    }
  }

  Future<void> start() async {
    if (_isPlaying) return;

    if (!_isAudioReady) {
      await _initSounds();
    }

    _isPlaying = true;
    _currentBeat = 1;
    _currentSubdivisionIndex = 0;
    _tickIndex = 0;
    _startTime = DateTime.now();

    try {
      await WakelockPlus.enable();
    } catch (_) {}

    notifyListeners();
    _scheduleNextTick();
  }

  void stop() {
    if (!_isPlaying) return;

    _isPlaying = false;
    _timer?.cancel();
    _timer = null;
    _currentBeat = 1;
    _currentSubdivisionIndex = 0;

    try {
      WakelockPlus.disable();
    } catch (_) {}

    notifyListeners();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    _tickIndex = 0;
    _startTime = DateTime.now();
    _scheduleNextTick();
  }

  int _getSubdivisionFactor() {
    switch (_subdivision) {
      case MetronomeSubdivision.quarter:
        return 1;
      case MetronomeSubdivision.eighth:
        return 2;
      case MetronomeSubdivision.triplet:
        return 3;
      case MetronomeSubdivision.sixteenth:
        return 4;
    }
  }

  void _scheduleNextTick() {
    if (!_isPlaying) return;

    // Dispara a batida atual
    _executeTick();

    _tickIndex++;
    final subFactor = _getSubdivisionFactor();
    // Intervalo exato em microssegundos para cada pulso/subdivisão
    final intervalMicrosec = (60000000.0 / (_bpm * subFactor)).round();

    // Calcula o timestamp absoluto ideal do próximo tick a partir do startTime
    // Isso garante ZERO drift cumulativo após horas tocando!
    final nextTarget = _startTime!.add(Duration(microseconds: _tickIndex * intervalMicrosec));
    final now = DateTime.now();
    final delay = nextTarget.difference(now);

    final waitDuration = delay.isNegative ? Duration.zero : delay;
    _timer = Timer(waitDuration, _scheduleNextTick);
  }

  void _executeTick() {
    final subFactor = _getSubdivisionFactor();
    final isMainBeat = (_currentSubdivisionIndex == 0);
    final isAccent = isMainBeat && (_currentBeat == 1);

    // Toca o áudio correspondente com o PAN selecionado (L, C ou R)
    if (!_isMuted && _volume > 0.0) {
      AudioSource? sourceToPlay;
      if (isAccent) {
        sourceToPlay = _hiSource;
      } else if (isMainBeat) {
        sourceToPlay = _loSource;
      } else {
        sourceToPlay = _subSource ?? _loSource;
      }

      if (sourceToPlay != null) {
        try {
          SoLoud.instance.play(
            sourceToPlay,
            volume: isAccent ? _volume : (_volume * (isMainBeat ? 0.85 : 0.60)),
            pan: _pan,
          );
        } catch (e) {
          debugPrint('Falha ao disparar click do metrônomo: $e');
        }
      }
    }

    // Avança a contagem visual
    notifyListeners();

    _currentSubdivisionIndex++;
    if (_currentSubdivisionIndex >= subFactor) {
      _currentSubdivisionIndex = 0;
      _currentBeat++;
      if (_currentBeat > _beatsPerBar) {
        _currentBeat = 1;
      }
    }
  }

  /// Sincroniza BPM e fórmula de compasso com os dados da música ativa no Player
  void syncWithSong({required int songBpm, required String songTimeSignature}) {
    setBpm(songBpm);
    if (songTimeSignature.isNotEmpty) {
      setTimeSignature(songTimeSignature);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hiSource?.let((s) => SoLoud.instance.disposeSource(s));
    _loSource?.let((s) => SoLoud.instance.disposeSource(s));
    _subSource?.let((s) => SoLoud.instance.disposeSource(s));
    super.dispose();
  }
}

extension<T> on T {
  void let(void Function(T) op) => op(this);
}

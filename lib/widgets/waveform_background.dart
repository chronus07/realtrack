import 'dart:math' as math;
import 'package:flutter/material.dart';

class WaveformBackground extends StatefulWidget {
  final double progress;
  final Color trackColor;
  final bool isPlaying;
  final String stemName;
  final int beat;

  const WaveformBackground({
    super.key,
    required this.progress,
    required this.trackColor,
    required this.isPlaying,
    required this.stemName,
    required this.beat,
  });

  @override
  State<WaveformBackground> createState() => _WaveformBackgroundState();
}

class _WaveformBackgroundState extends State<WaveformBackground>
    with SingleTickerProviderStateMixin {
  AnimationController? _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.isPlaying) {
      _animController?.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant WaveformBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !oldWidget.isPlaying) {
      _animController?.repeat();
    } else if (!widget.isPlaying && oldWidget.isPlaying) {
      _animController?.stop();
    }
  }

  @override
  void dispose() {
    _animController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _animController ?? const AlwaysStoppedAnimation(0.0),
        builder: (context, _) {
          return CustomPaint(
            painter: _TrackWaveformPainter(
              progress: widget.progress.clamp(0.0, 1.0),
              trackColor: widget.trackColor,
              isPlaying: widget.isPlaying,
              stemName: widget.stemName,
              beat: widget.beat,
              animValue: _animController?.value ?? 0.0,
            ),
          );
        },
      ),
    );
  }
}

class _TrackWaveformPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final bool isPlaying;
  final String stemName;
  final int beat;
  final double animValue;

  _TrackWaveformPainter({
    required this.progress,
    required this.trackColor,
    required this.isPlaying,
    required this.stemName,
    required this.beat,
    required this.animValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final isClick = stemName.toUpperCase().contains('CLICK');
    final isDrums = stemName.toUpperCase().contains('BAT') || stemName.toUpperCase().contains('DRUM');
    final isBass = stemName.toUpperCase().contains('BAIXO') || stemName.toUpperCase().contains('BASS');

    final centerY = size.height * 0.48;
    final maxAmp = size.height * 0.36;
    final cursorX = (size.width * progress).clamp(0.0, size.width);

    // Número de colunas / fatias de onda ao longo da largura do card
    const barCount = 42;
    final barWidth = size.width / barCount;

    // 1. SILHUETA DO ESPECTRO DE FREQUÊNCIAS INFERIORES (Sub-Bass / Médios)
    final playedSpectrumPath = Path()..moveTo(0, size.height);
    final upcomingSpectrumPath = Path()..moveTo(cursorX, size.height);

    for (int i = 0; i <= barCount; i++) {
      final x = i * barWidth;
      final t = i / barCount;

      // Forma determinística e orgânica do espectro
      double hFactor;
      if (isClick) {
        hFactor = (i % 5 == 0) ? 0.75 : 0.12;
      } else if (isDrums) {
        hFactor = (i % 4 == 0) ? 0.82 : (0.18 + (math.sin(i * 0.8) * 0.22).abs());
      } else if (isBass) {
        hFactor = 0.35 + 0.35 * (math.sin(t * 8 + (isPlaying ? animValue * 2 * math.pi : 0)).abs());
      } else {
        final wave1 = math.sin(t * 12) * 0.25;
        final wave2 = math.cos(t * 6) * 0.18;
        hFactor = (0.32 + wave1.abs() + wave2.abs()).clamp(0.12, 0.88);
      }

      // Nuances ativas quando tocando
      if (isPlaying && x <= cursorX) {
        final liveWobble = math.sin((x / size.width) * 14 + animValue * 2 * math.pi) * 0.08;
        hFactor = (hFactor + liveWobble).clamp(0.1, 0.95);
      }

      final topY = size.height - (hFactor * size.height * 0.45);

      if (x <= cursorX) {
        playedSpectrumPath.lineTo(x, topY);
        if (x >= cursorX - barWidth) {
          upcomingSpectrumPath.lineTo(cursorX, topY);
        }
      } else {
        upcomingSpectrumPath.lineTo(x, topY);
      }
    }

    playedSpectrumPath.lineTo(cursorX, size.height);
    playedSpectrumPath.close();

    upcomingSpectrumPath.lineTo(size.width, size.height);
    upcomingSpectrumPath.close();

    // Pinta o espectro já tocado com gradiente elegante na cor da pista
    final playedSpectrumPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          trackColor.withOpacity(0.18),
          trackColor.withOpacity(0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, cursorX > 0 ? cursorX : 1, size.height));
    canvas.drawPath(playedSpectrumPath, playedSpectrumPaint);

    // Pinta o espectro futuro com silhueta cinza suave
    final upcomingSpectrumPaint = Paint()
      ..color = Colors.white.withOpacity(0.035)
      ..style = PaintingStyle.fill;
    canvas.drawPath(upcomingSpectrumPath, upcomingSpectrumPaint);

    // 2. FORMA DE ONDA PRINCIPAL CENTRALIZADA (WAVEFORM BARS)
    final playedWavePaint = Paint()
      ..color = trackColor.withOpacity(0.38)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final upcomingWavePaint = Paint()
      ..color = Colors.white.withOpacity(0.10)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < barCount; i++) {
      final x = i * barWidth + barWidth * 0.5;
      final t = i / barCount;

      double amp;
      if (isClick) {
        amp = (i % 5 == 0) ? maxAmp * 0.95 : maxAmp * 0.15;
      } else if (isDrums) {
        final kick = (i % 4 == 0) ? maxAmp * 0.9 : maxAmp * 0.35;
        amp = kick * (0.85 + 0.3 * math.sin(i * 1.5).abs());
      } else if (isBass) {
        amp = maxAmp * (0.35 + 0.45 * math.sin(t * 10).abs());
      } else {
        final envelope = math.sin(t * math.pi); // Mais alto no centro da música
        final transients = (math.sin(i * 0.8).abs() * 0.5 + math.cos(i * 1.6).abs() * 0.5);
        amp = maxAmp * (0.2 + 0.65 * envelope * transients).clamp(0.15, 0.95);
      }

      // Nuances dinâmicas de respiração durante o play
      if (isPlaying && x <= cursorX) {
        final wobble = math.sin((x / size.width) * 12 + animValue * 3 * math.pi) * 2.2;
        amp = (amp + wobble).clamp(2.0, maxAmp);
      }

      final p1 = Offset(x, centerY - amp);
      final p2 = Offset(x, centerY + amp);

      if (x <= cursorX) {
        canvas.drawLine(p1, p2, playedWavePaint);
      } else {
        canvas.drawLine(p1, p2, upcomingWavePaint);
      }
    }

    // 3. CURSOR DE REPRODUÇÃO (PLAYHEAD) COM BRILHO VERTICAL
    if (progress > 0.005 && progress < 0.995) {
      final cursorPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            trackColor.withOpacity(0.0),
            trackColor.withOpacity(0.85),
            trackColor.withOpacity(0.0),
          ],
        ).createShader(Rect.fromLTWH(cursorX - 1, 0, 2, size.height))
        ..strokeWidth = 1.5;

      canvas.drawLine(Offset(cursorX, 0), Offset(cursorX, size.height), cursorPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrackWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.beat != beat ||
        oldDelegate.animValue != animValue;
  }
}

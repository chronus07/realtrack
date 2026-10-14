import 'dart:math' as math;
import 'package:flutter/material.dart';

class VuMeterBar extends StatefulWidget {
  final double volume;
  final double pan; // -1.0 (L) a +1.0 (R)
  final bool isPlaying;
  final String stemName;
  final int beat;

  const VuMeterBar({
    super.key,
    required this.volume,
    required this.pan,
    required this.isPlaying,
    required this.stemName,
    required this.beat,
  });

  @override
  State<VuMeterBar> createState() => _VuMeterBarState();
}

class _VuMeterBarState extends State<VuMeterBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );

    if (widget.isPlaying && widget.volume > 0.0) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant VuMeterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && widget.volume > 0.0) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 15.0,
      height: 52.0,
      child: CustomPaint(
        painter: _VuMeterPainter(
          volume: widget.volume,
          pan: widget.pan,
          isPlaying: widget.isPlaying,
          stemName: widget.stemName,
          beat: widget.beat,
          animation: _controller,
        ),
      ),
    );
  }
}

class _VuMeterPainter extends CustomPainter {
  final double volume;
  final double pan;
  final bool isPlaying;
  final String stemName;
  final int beat;
  final Animation<double> animation;

  _VuMeterPainter({
    required this.volume,
    required this.pan,
    required this.isPlaying,
    required this.stemName,
    required this.beat,
    required this.animation,
  }) : super(repaint: animation);

  static final Paint _bgPaint = Paint()
    ..color = const Color(0xD9030712)
    ..style = PaintingStyle.fill;

  static final Paint _borderPaint = Paint()
    ..color = const Color(0x2EFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8;

  static final Paint _inactivePaint = Paint()
    ..color = const Color(0x14FFFFFF)
    ..style = PaintingStyle.fill;

  static final Paint _greenPaint = Paint()
    ..color = const Color(0xFF10B981)
    ..style = PaintingStyle.fill;

  static final Paint _yellowPaint = Paint()
    ..color = const Color(0xFFF59E0B)
    ..style = PaintingStyle.fill;

  static final Paint _redPaint = Paint()
    ..color = const Color(0xFFF43F5E)
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. Moldura externa
    final bgRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(4),
    );
    canvas.drawRRect(bgRRect, _bgPaint);
    canvas.drawRRect(bgRRect, _borderPaint);

    if (!isPlaying || volume <= 0.0) {
      _drawColumn(canvas, 1.8, 0);
      _drawColumn(canvas, 8.2, 0);
      return;
    }

    // 2. Dinâmica de oscilação do sinal de áudio
    final animVal = animation.value;
    final isClick = stemName.toUpperCase().contains('CLICK');
    final isDrums = stemName.toUpperCase().contains('BAT') || stemName.toUpperCase().contains('DRUM');

    double bounceFactor;
    if (isClick) {
      bounceFactor = 0.75 + 0.25 * (beat % 2 == 1 ? 1.0 : 0.6);
    } else if (isDrums) {
      bounceFactor = 0.60 + 0.40 * (math.sin(animVal * 2 * math.pi).abs());
    } else {
      final nameOffset = (stemName.codeUnits.fold<int>(0, (a, b) => a + b) % 10) / 10.0;
      bounceFactor = 0.65 + 0.35 * (math.sin((animVal + nameOffset) * 2 * math.pi).abs());
    }

    // Aplicação do PAN (L / R)
    final panL = pan <= 0 ? 1.0 : (1.0 - pan).clamp(0.05, 1.0);
    final panR = pan >= 0 ? 1.0 : (1.0 + pan).clamp(0.05, 1.0);

    final levelL = (volume * panL * bounceFactor).clamp(0.0, 1.0);
    final levelR = (volume * panR * bounceFactor).clamp(0.0, 1.0);

    final activeCountL = (levelL * 10).round();
    final activeCountR = (levelR * 10).round();

    _drawColumn(canvas, 1.8, activeCountL);
    _drawColumn(canvas, 8.2, activeCountR);
  }

  void _drawColumn(Canvas canvas, double startX, int activeCount) {
    const totalSegments = 10;
    const segWidth = 5.0;
    const segHeight = 3.2;
    const spacing = 1.4;
    const topOffset = 2.8;

    for (int idx = 0; idx < totalSegments; idx++) {
      // 0 no topo (Peak), 9 na base
      final segmentIndex = totalSegments - 1 - idx;
      final isActive = segmentIndex < activeCount;
      final y = topOffset + idx * (segHeight + spacing);

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(startX, y, segWidth, segHeight),
        const Radius.circular(1.5),
      );

      if (!isActive) {
        canvas.drawRRect(rrect, _inactivePaint);
      } else if (segmentIndex >= 9) {
        canvas.drawRRect(rrect, _redPaint);
      } else if (segmentIndex >= 7) {
        canvas.drawRRect(rrect, _yellowPaint);
      } else {
        canvas.drawRRect(rrect, _greenPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VuMeterPainter oldDelegate) {
    return oldDelegate.volume != volume ||
        oldDelegate.pan != pan ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.beat != beat;
  }
}

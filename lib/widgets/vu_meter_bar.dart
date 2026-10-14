import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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
  AnimationController? _controller;
  final math.Random _random = math.Random();
  double _rawLevelL = 0.0;
  double _rawLevelR = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    )..addListener(_tick);

    if (widget.isPlaying && widget.volume > 0.0) {
      _controller?.repeat();
    }
  }

  void _tick() {
    if (!mounted) return;
    if (!widget.isPlaying || widget.volume <= 0.0) {
      if (_rawLevelL > 0.0 || _rawLevelR > 0.0) {
        setState(() {
          _rawLevelL = math.max(0.0, _rawLevelL - 0.2);
          _rawLevelR = math.max(0.0, _rawLevelR - 0.2);
        });
      }
      return;
    }

    final isClick = widget.stemName.toUpperCase().contains('CLICK');
    final isDrums = widget.stemName.toUpperCase().contains('BAT') || widget.stemName.toUpperCase().contains('DRUM');

    // Oscilação dinâmica baseada no instrumento
    double bounceFactor;
    if (isClick) {
      bounceFactor = 0.75 + 0.25 * (widget.beat % 2 == 1 ? 1.0 : 0.6);
    } else if (isDrums) {
      bounceFactor = 0.65 + 0.35 * _random.nextDouble();
    } else {
      bounceFactor = 0.70 + 0.30 * _random.nextDouble();
    }

    // Aplicação do PAN (L / R)
    final panL = widget.pan <= 0 ? 1.0 : (1.0 - widget.pan).clamp(0.05, 1.0);
    final panR = widget.pan >= 0 ? 1.0 : (1.0 + widget.pan).clamp(0.05, 1.0);

    setState(() {
      _rawLevelL = (widget.volume * panL * bounceFactor).clamp(0.0, 1.0);
      _rawLevelR = (widget.volume * panR * bounceFactor).clamp(0.0, 1.0);
    });
  }

  @override
  void didUpdateWidget(covariant VuMeterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && widget.volume > 0.0) {
      if (!(_controller?.isAnimating ?? false)) {
        _controller?.repeat();
      }
    } else {
      if (_controller?.isAnimating ?? false) {
        _controller?.stop();
        setState(() {
          _rawLevelL = 0.0;
          _rawLevelR = 0.0;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Widget _buildLedColumn(double level) {
    const totalSegments = 10;
    final activeCount = (level * totalSegments).round();

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(totalSegments, (idx) {
        // Inverte o índice: 0 no topo (Peak), 9 na base
        final segmentIndex = totalSegments - 1 - idx;
        final isActive = segmentIndex < activeCount;

        Color segmentColor;
        if (segmentIndex >= 9) {
          segmentColor = AppTheme.roseMute; // Top Peak (Vermelho)
        } else if (segmentIndex >= 7) {
          segmentColor = AppTheme.amberCue; // Mid High (Amarelo)
        } else {
          segmentColor = AppTheme.emeraldSafe; // Normal (Verde)
        }

        return Container(
          width: 5,
          height: 3.2,
          margin: const EdgeInsets.symmetric(vertical: 0.8),
          decoration: BoxDecoration(
            color: isActive ? segmentColor : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(1.5),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: segmentColor.withOpacity(0.6),
                      blurRadius: 3,
                      spreadRadius: 0.2,
                    )
                  ]
                : null,
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 15,
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF030712).withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white12, width: 0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildLedColumn(_rawLevelL),
          const SizedBox(width: 1.5),
          _buildLedColumn(_rawLevelR),
        ],
      ),
    );
  }
}

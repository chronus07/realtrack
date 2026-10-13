import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_engine.dart';
import '../theme/app_theme.dart';

class TransportBar extends StatelessWidget {
  const TransportBar({super.key});

  String _formatDuration(double seconds) {
    final int min = seconds ~/ 60;
    final int sec = (seconds % 60).toInt();
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AudioEngine>();

    final currentPos = engine.currentPositionSeconds;
    final totalPos = engine.totalDurationSeconds;
    final isPlaying = engine.isPlaying;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Informações de tempo e compasso
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(currentPos),
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white70),
              ),
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isPlaying ? AppTheme.primary : Colors.white24,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'COMPASSO ${engine.currentBar} [${engine.currentBeat}]',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              Text(
                _formatDuration(totalPos),
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white70),
              ),
            ],
          ),

          // Barra de progresso linear
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: currentPos.clamp(0.0, totalPos > 0 ? totalPos : 1.0),
              min: 0.0,
              max: totalPos > 0 ? totalPos : 1.0,
              onChanged: (val) => engine.seekTo(val),
            ),
          ),

          // Botões de Transporte
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 26),
                color: Colors.white70,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: engine.previousSong,
              ),
              GestureDetector(
                onTap: engine.togglePlay,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.35),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: engine.isLoadingAudio
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                        )
                      : Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          size: 30,
                          color: Colors.black,
                        ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, size: 26),
                color: Colors.white70,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: engine.nextSong,
              ),
              IconButton(
                icon: const Icon(Icons.stop, size: 22),
                color: Colors.white54,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: engine.stop,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

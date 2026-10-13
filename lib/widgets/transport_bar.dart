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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
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
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isPlaying ? AppTheme.primary : Colors.white24,
                    ),
                  ),
                  const SizedBox(width: 6),
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
          const SizedBox(height: 6),

          // Barra de progresso linear
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            ),
            child: Slider(
              value: currentPos.clamp(0.0, totalPos),
              min: 0.0,
              max: totalPos,
              onChanged: (val) => engine.seekTo(val),
            ),
          ),
          const SizedBox(height: 8),

          // Botões de Transporte
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 28),
                color: Colors.white70,
                onPressed: engine.previousSong,
              ),
              GestureDetector(
                onTap: engine.togglePlay,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 32,
                    color: Colors.black,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, size: 28),
                color: Colors.white70,
                onPressed: engine.nextSong,
              ),
              IconButton(
                icon: const Icon(Icons.stop, size: 24),
                color: Colors.white54,
                onPressed: engine.stop,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

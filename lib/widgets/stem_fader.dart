import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stem_track.dart';
import '../services/audio_engine.dart';
import '../theme/app_theme.dart';

class StemFader extends StatelessWidget {
  final StemTrack stem;

  const StemFader({super.key, required this.stem});

  @override
  Widget build(BuildContext context) {
    final engine = context.read<AudioEngine>();

    final isCue = stem.isCue;
    final primaryTrackColor = isCue ? AppTheme.amberCue : AppTheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Track Name & Channel Info
          SizedBox(
            width: 85,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: primaryTrackColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        stem.name,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isCue ? FontWeight.w900 : FontWeight.bold,
                          color: isCue ? AppTheme.amberCue : Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(
                  isCue ? 'SAÍDA L (CUE)' : 'SAÍDA R (P.A.)',
                  style: const TextStyle(fontSize: 8, color: Colors.white38, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),

          // Slider de Volume
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: primaryTrackColor,
                thumbColor: primaryTrackColor,
              ),
              child: Slider(
                value: stem.volume,
                min: 0.0,
                max: 1.0,
                onChanged: (val) => engine.setStemVolume(stem.id, val),
              ),
            ),
          ),

          // Botões de Mute e Solo
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mute Button
              GestureDetector(
                onTap: () => engine.toggleMute(stem.id),
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: stem.isMuted ? AppTheme.roseMute : AppTheme.cardBorder,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'M',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: stem.isMuted ? Colors.white : Colors.white54,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Solo Button
              GestureDetector(
                onTap: () => engine.toggleSolo(stem.id),
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: stem.isSolo ? AppTheme.amberCue : AppTheme.cardBorder,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'S',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: stem.isSolo ? Colors.black : Colors.white54,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

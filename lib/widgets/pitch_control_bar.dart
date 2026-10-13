import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_engine.dart';
import '../services/pitch_shifter.dart';
import '../theme/app_theme.dart';

class PitchControlBar extends StatelessWidget {
  const PitchControlBar({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AudioEngine>();
    final song = engine.currentSong;
    if (song == null) return const SizedBox.shrink();

    final offset = engine.pitchOffset;
    final currentKey = engine.currentKey;
    final displayKey = PitchShifterService.getDisplayKey(currentKey);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF451A03).withOpacity(0.35),
        border: Border.all(color: AppTheme.amberCue.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Text('🎵', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              const Text(
                'Tom: ',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.amberCue,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  displayKey,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                offset == 0
                    ? '(Original)'
                    : offset > 0
                        ? '(+$offset st)'
                        : '($offset st)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: offset == 0
                      ? Colors.white54
                      : offset > 0
                          ? AppTheme.emeraldSafe
                          : AppTheme.roseMute,
                ),
              ),
            ],
          ),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 14),
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  padding: EdgeInsets.zero,
                  onPressed: engine.decrementPitch,
                ),
                TextButton(
                  onPressed: engine.resetPitch,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(26, 26),
                  ),
                  child: const Text('Reset', style: TextStyle(fontSize: 9, color: Colors.white60)),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 14),
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  padding: EdgeInsets.zero,
                  onPressed: engine.incrementPitch,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

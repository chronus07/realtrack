import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_engine.dart';
import '../theme/app_theme.dart';

class SectionMarkers extends StatelessWidget {
  const SectionMarkers({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AudioEngine>();
    final song = engine.currentSong;
    if (song == null || song.sections.isEmpty) return const SizedBox.shrink();

    final currentPos = engine.currentPositionSeconds;

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: song.sections.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final sec = song.sections[index];
          final isCurrentSection = (index < song.sections.length - 1)
              ? (currentPos >= sec.startSeconds && currentPos < song.sections[index + 1].startSeconds)
              : (currentPos >= sec.startSeconds);

          return GestureDetector(
            onTap: () => engine.seekTo(sec.startSeconds),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isCurrentSection ? AppTheme.primary : AppTheme.cardBorder,
                borderRadius: BorderRadius.circular(8),
                boxShadow: isCurrentSection
                    ? [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 6)]
                    : [],
              ),
              alignment: Alignment.center,
              child: Text(
                sec.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isCurrentSection ? Colors.black : Colors.white70,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

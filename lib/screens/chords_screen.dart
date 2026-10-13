import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_engine.dart';
import '../services/pitch_shifter.dart';
import '../theme/app_theme.dart';

class ChordsScreen extends StatelessWidget {
  final VoidCallback onOpenMixer;

  const ChordsScreen({super.key, required this.onOpenMixer});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AudioEngine>();
    final song = engine.currentSong;

    if (song == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Cifras', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: const Icon(Icons.music_note, size: 36, color: Colors.white24),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Nenhuma cifra ativa',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Selecione uma música na playlist para visualizar os acordes com transposição em tempo real.',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final transposedChords = PitchShifterService.transposeChordSheet(
      song.chordsText,
      engine.pitchOffset,
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              song.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Cifras sincronizadas com o playback',
              style: TextStyle(fontSize: 10, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.cardBorder,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: engine.decrementPitch,
                ),
                Text(
                  engine.currentKey,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.amberCue,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: engine.incrementPitch,
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      transposedChords.isEmpty
                          ? 'Nenhuma letra ou cifra cadastrada para esta música.'
                          : transposedChords,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.6,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            engine.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                            size: 36,
                            color: AppTheme.primary,
                          ),
                          onPressed: engine.togglePlay,
                        ),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              engine.isPlaying ? 'Tocando no palco' : 'Pausado',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Tom: ${engine.currentKey} • Compasso ${engine.currentBar}',
                              style: const TextStyle(fontSize: 10, color: Colors.white54),
                            ),
                          ],
                        ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: onOpenMixer,
                      icon: const Icon(Icons.tune, size: 16, color: AppTheme.primary),
                      label: const Text('Mixer', style: TextStyle(fontSize: 12, color: AppTheme.primary)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

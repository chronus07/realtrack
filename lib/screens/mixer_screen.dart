import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/pitch_control_bar.dart';
import '../widgets/section_markers.dart';
import '../widgets/stem_fader.dart';
import '../widgets/transport_bar.dart';

class MixerScreen extends StatelessWidget {
  const MixerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AudioEngine>();
    final song = engine.currentSong;

    if (song == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Mixer de Palco', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                  child: const Icon(Icons.tune, size: 36, color: Colors.white24),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Nenhuma música carregada no mixer',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Adicione músicas na playlist e selecione uma para controlar os faders, click e transposição de tom aqui.',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Música ${(engine.currentSongIndex + 1).toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text(
                  '${song.bpm} BPM • ${song.timeSignature}',
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
            Text(
              song.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: engine.toggleSplitMode,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: engine.isSplitModeActive
                      ? AppTheme.emeraldSafe.withOpacity(0.15)
                      : Colors.white10,
                  border: Border.all(
                    color: engine.isSplitModeActive ? AppTheme.emeraldSafe : Colors.white24,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: engine.isSplitModeActive ? AppTheme.emeraldSafe : Colors.white54,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      engine.isSplitModeActive ? 'Split L/R Ativo' : 'Estéreo Normal',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: engine.isSplitModeActive ? AppTheme.emeraldSafe : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              const PitchControlBar(),
              const SizedBox(height: 10),
              const SectionMarkers(),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: ListView.separated(
                    itemCount: song.stems.length,
                    separatorBuilder: (context, index) {
                      if (index < song.stems.length - 1 &&
                          song.stems[index].isCue &&
                          !song.stems[index + 1].isCue) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: const [
                              Expanded(child: Divider(color: AppTheme.cardBorder)),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  'PISTAS DA BANDA (P.A.)',
                                  style: TextStyle(fontSize: 8, color: AppTheme.primary, fontFamily: 'monospace'),
                                ),
                              ),
                              Expanded(child: Divider(color: AppTheme.cardBorder)),
                            ],
                          ),
                        );
                      }
                      return const SizedBox(height: 2);
                    },
                    itemBuilder: (context, index) {
                      return StemFader(stem: song.stems[index]);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const TransportBar(),
            ],
          ),
        ),
      ),
    );
  }
}

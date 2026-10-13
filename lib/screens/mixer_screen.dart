import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stem_track.dart';
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
                  'Selecione uma música na Playlist ou no Acervo para controlar faders, PAN, click e pitch shift aqui.',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Ordena pistas: Primeiro Click e Guia (CUE/L), depois instrumentos da banda (R)
    final sortedStems = List<StemTrack>.from(song.stems);
    sortedStems.sort((a, b) {
      if (a.isCue && !b.isCue) return -1;
      if (!a.isCue && b.isCue) return 1;
      return a.name.compareTo(b.name);
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Faixa ${(engine.currentSongIndex + 1).toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 9, color: AppTheme.primary, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${song.bpm} BPM • ${song.timeSignature} • ${song.stems.length} Pistas',
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              song.title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          // Botão seletor rápido de Cabo Y (Palco) vs Estéreo (Ensaio)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PopupMenuButton<String>(
              tooltip: 'Roteamento de Canais e PAN',
              icon: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: engine.isSplitModeActive
                      ? AppTheme.emeraldSafe.withOpacity(0.18)
                      : Colors.white10,
                  border: Border.all(
                    color: engine.isSplitModeActive ? AppTheme.emeraldSafe : Colors.white24,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.alt_route,
                      size: 14,
                      color: engine.isSplitModeActive ? AppTheme.emeraldSafe : Colors.white70,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      engine.isSplitModeActive ? 'Cabo Y (L/R)' : 'Estéreo (C)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: engine.isSplitModeActive ? AppTheme.emeraldSafe : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              onSelected: (val) {
                if (val == 'split') {
                  engine.applySplitModeRouting();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🎛️ Cabo Y ativado: Click/Guia em L e Banda em R!'),
                      backgroundColor: AppTheme.emeraldSafe,
                      duration: Duration(seconds: 2),
                    ),
                  );
                } else if (val == 'stereo') {
                  engine.applyStereoCenterRouting();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🎧 Estéreo normal ativado: Todas as pistas centralizadas!'),
                      backgroundColor: Colors.blueGrey,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'split',
                  child: Row(
                    children: [
                      Icon(Icons.headphones, color: AppTheme.emeraldSafe, size: 18),
                      SizedBox(width: 8),
                      Text('Cabo Y (L: Click/Guia | R: Banda)', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'stereo',
                  child: Row(
                    children: [
                      Icon(Icons.volume_up, color: Colors.white70, size: 18),
                      SizedBox(width: 8),
                      Text('Estéreo / Ensaio (Todas no Centro)', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            children: [
              // Barra de Pitch compacta
              const PitchControlBar(),

              // Marcadores de seção (se existirem)
              if (song.sections.isNotEmpty) ...[
                const SizedBox(height: 6),
                const SectionMarkers(),
              ],

              const SizedBox(height: 6),

              // Lista fluida e responsiva com todos os faders
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    itemCount: sortedStems.length,
                    separatorBuilder: (context, index) {
                      // Divisor elegante separando CUE de BANDA
                      if (index < sortedStems.length - 1 &&
                          sortedStems[index].isCue &&
                          !sortedStems[index + 1].isCue) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: const [
                              Expanded(child: Divider(color: AppTheme.cardBorder, height: 1)),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  'PISTAS DA BANDA (P.A.)',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary,
                                    letterSpacing: 1.0,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              Expanded(child: Divider(color: AppTheme.cardBorder, height: 1)),
                            ],
                          ),
                        );
                      }
                      return const SizedBox(height: 2);
                    },
                    itemBuilder: (context, index) {
                      return StemFader(stem: sortedStems[index]);
                    },
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // Barra de Transporte fixa e compacta
              const TransportBar(),
            ],
          ),
        ),
      ),
    );
  }
}

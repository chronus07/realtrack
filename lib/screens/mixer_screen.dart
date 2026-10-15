import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stem_track.dart';
import '../services/audio_cache_service.dart';
import '../services/audio_engine.dart';
import '../services/bpm_key_detector.dart';
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
                GestureDetector(
                  onTap: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.amberCue),
                            ),
                            const SizedBox(width: 8),
                            Text('⚡ Analisando faixas de "${song.title}"...'),
                          ],
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );

                    final result = await BpmKeyDetector.autoDetectForExistingSong(song);
                    if (result.hasAny && context.mounted) {
                      await engine.updateLibrarySongKeyAndBpm(
                        song.id,
                        key: result.key,
                        bpm: result.bpm,
                      );
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✅ Auto-detectado: Tom ${result.key ?? song.originalKey} • ${result.bpm ?? song.bpm} BPM (${result.source})'),
                          backgroundColor: AppTheme.emeraldSafe,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Não foi possível identificar metadados adicionais para esta música.'),
                          backgroundColor: AppTheme.amberCue,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  child: Row(
                    children: [
                      Text(
                        '${song.bpm} BPM • ${song.timeSignature} • ${song.stems.length} Pistas',
                        style: const TextStyle(fontSize: 10, color: Colors.white54),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.auto_awesome, size: 10, color: AppTheme.amberCue),
                    ],
                  ),
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
          // Botão Baixar Música / Status de Cache no Celular
          if (!kIsWeb)
            FutureBuilder<bool>(
              future: AudioCacheService.isSongFullyCached(song),
              builder: (context, snapshot) {
                final isCached = snapshot.data ?? false;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () async {
                      if (isCached) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✅ Todas as pistas de "${song.title}" já estão 100% salvas no celular.'),
                            backgroundColor: AppTheme.emeraldSafe,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      } else {
                        await engine.downloadCurrentSongToDevice();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✅ Pistas de "${song.title}" baixadas com sucesso no aparelho!'),
                              backgroundColor: AppTheme.emeraldSafe,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: isCached
                            ? AppTheme.emeraldSafe.withOpacity(0.18)
                            : AppTheme.amberCue.withOpacity(0.18),
                        border: Border.all(
                          color: isCached ? AppTheme.emeraldSafe : AppTheme.amberCue,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isCached ? Icons.offline_pin : Icons.download_for_offline,
                            size: 14,
                            color: isCached ? AppTheme.emeraldSafe : AppTheme.amberCue,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isCached ? 'No Aparelho' : 'Baixar Pistas',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isCached ? AppTheme.emeraldSafe : AppTheme.amberCue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

          // Botão seletor rápido de Cabo Y (Palco) vs Estéreo (Ensaio) - 1 Toque Direto
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                engine.toggleSplitMode();
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      engine.isSplitModeActive
                          ? '🎛️ Cabo Y Ativado: Click/Guia em L (-1.0) e Banda em R (+1.0)!'
                          : '🎧 Estéreo Normal: Todas as faixas no Centro (0.0)!',
                    ),
                    backgroundColor: engine.isSplitModeActive ? AppTheme.emeraldSafe : Colors.blueGrey,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                    const SizedBox(width: 5),
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

              // Banner visual quando o áudio está carregando / baixando para o aparelho
              if (engine.isLoadingAudio) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              engine.loadingStatus,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${(engine.loadingProgress * 100).toInt()}%',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                          ),
                        ],
                      ),
                      if (engine.loadingProgress > 0) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: engine.loadingProgress,
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              // Alerta caso alguma pista não tenha carregado no SoLoud
              if (!engine.isLoadingAudio && engine.isPlaying && engine.loadedStemsCount < song.stems.length) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.roseMute.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.roseMute.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 16, color: AppTheme.roseMute),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${engine.loadedStemsCount}/${song.stems.length} pistas ativas (${song.stems.length - engine.loadedStemsCount} pendentes)',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => engine.retryFailedStems(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.roseMute,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            'Recarregar',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Marcadores de seção (se existirem)
              if (song.sections.isNotEmpty) ...[
                const SizedBox(height: 6),
                const SectionMarkers(),
              ],

              // Banner visual quando Modo SOLO estiver ativo
              if (engine.hasActiveSolo) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.amberCue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.amberCue.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.headphones, size: 16, color: AppTheme.amberCue),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'SOLO ATIVO: Apenas pistas com [S] estão soando.',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.amberCue),
                        ),
                      ),
                      GestureDetector(
                        onTap: engine.clearAllSolos,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.amberCue,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            'Limpar Solos',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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

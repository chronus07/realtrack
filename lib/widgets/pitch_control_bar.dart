import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/setlist.dart';
import '../models/song.dart';
import '../services/audio_engine.dart';
import '../services/pitch_shifter.dart';
import '../theme/app_theme.dart';

class PitchControlBar extends StatelessWidget {
  const PitchControlBar({super.key});

  void _showKeySelectorModal(BuildContext context, AudioEngine engine, Song song) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Consumer<AudioEngine>(
          builder: (context, eng, _) {
            final curSong = eng.currentSong ?? song;
            final currentKey = curSong.currentKey;
            final offset = eng.pitchOffset;

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E24),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(top: BorderSide(color: AppTheme.amberCue, width: 2)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'TRANSPOSIÇÃO DE TOM (MIXER)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.amberCue,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                curSong.title,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Painel de Status de Tom
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Text('Tom Original (Acervo)', style: TextStyle(fontSize: 10, color: Colors.white54)),
                              const SizedBox(height: 4),
                              Text(
                                PitchShifterService.getDisplayKey(curSong.originalKey),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
                              ),
                            ],
                          ),
                          Container(width: 1, height: 28, color: Colors.white12),
                          Column(
                            children: [
                              const Text('Tom Atual no Mixer', style: TextStyle(fontSize: 10, color: AppTheme.amberCue)),
                              const SizedBox(height: 4),
                              Text(
                                '${PitchShifterService.getDisplayKey(currentKey)} ${offset != 0 ? (offset > 0 ? "+$offset" : "$offset") + " st" : ""}',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppTheme.amberCue),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'Selecione o Tom desejado:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
                    ),
                    const SizedBox(height: 8),

                    // Grid de 12 Tons
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: PitchShifterService.standardKeys.map((k) {
                        final isSelected = k == currentKey;
                        final isOriginal = k == curSong.originalKey;

                        return SizedBox(
                          width: (MediaQuery.of(context).size.width - 64) / 4,
                          child: InkWell(
                            onTap: () {
                              eng.setTargetKey(k);
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.amberCue
                                    : (isOriginal ? AppTheme.primary.withOpacity(0.15) : AppTheme.card),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.amberCue
                                      : (isOriginal ? AppTheme.primary : AppTheme.cardBorder),
                                  width: isSelected || isOriginal ? 1.5 : 1.0,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    k,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      color: isSelected ? Colors.black : Colors.white,
                                    ),
                                  ),
                                  if (isOriginal)
                                    Text(
                                      'Orig.',
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? Colors.black87 : AppTheme.primary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    // Stepper rápido (-1 st, Reset, +1 st)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: AppTheme.cardBorder),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            icon: const Icon(Icons.remove, size: 16),
                            label: const Text('-1 Semitom', style: TextStyle(fontSize: 11)),
                            onPressed: eng.decrementPitch,
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: AppTheme.cardBorder),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          onPressed: eng.resetPitch,
                          child: const Text('Original', style: TextStyle(fontSize: 11)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: AppTheme.cardBorder),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('+1 Semitom', style: TextStyle(fontSize: 11)),
                            onPressed: eng.incrementPitch,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // BOTÃO SALVAR DEFINITIVAMENTE NA PLAYLIST
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.emeraldSafe,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.bookmark_added, size: 18),
                        label: Text(
                          eng.currentSetlist != null
                              ? 'Salvar Tom na Playlist "${eng.currentSetlist!.title}"'
                              : 'Salvar Tom em uma Playlist',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final success = await eng.saveCurrentSongKeyToPlaylist();
                          if (context.mounted) {
                            if (success) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '✅ Tom ${curSong.currentKey} salvo para "${curSong.title}" na playlist "${eng.currentSetlist?.title}"!\nO Acervo mantém o tom original (${curSong.originalKey}).',
                                  ),
                                  backgroundColor: AppTheme.emeraldSafe,
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                            } else {
                              _showSelectPlaylistToSaveModal(context, eng, curSong);
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSelectPlaylistToSaveModal(BuildContext context, AudioEngine engine, Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E24),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Salvar Tom em qual Playlist?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'O Tom ${song.currentKey} será salvo na playlist escolhida. O tom original (${song.originalKey}) permanecerá intacto no acervo.',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 12),
              if (engine.allSetlists.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('Nenhuma playlist criada. Crie uma na aba Playlists.')),
                )
              else
                ...engine.allSetlists.map((setlist) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.playlist_play, color: AppTheme.primary),
                    title: Text(setlist.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text('${setlist.songs.length} músicas', style: const TextStyle(fontSize: 11, color: Colors.white54)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white38),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await engine.saveCurrentSongKeyToPlaylist(setlist);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '✅ Tom ${song.currentKey} salvo para "${song.title}" na playlist "${setlist.title}"!\nNo Acervo, o tom original continua ${song.originalKey}.',
                            ),
                            backgroundColor: AppTheme.emeraldSafe,
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      }
                    },
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AudioEngine>();
    final song = engine.currentSong;
    if (song == null) return const SizedBox.shrink();

    final offset = engine.pitchOffset;
    final currentKey = engine.currentKey;
    final displayKey = PitchShifterService.getDisplayKey(currentKey);
    final isCustomKey = offset != 0 || song.currentKey != song.originalKey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF451A03).withOpacity(0.35),
        border: Border.all(color: AppTheme.amberCue.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Tom Clicável (abre seletor completo)
          GestureDetector(
            onTap: () => _showKeySelectorModal(context, engine, song),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🎵', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 5),
                const Text(
                  'Tom: ',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.amberCue,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayKey,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_drop_down, size: 14, color: Colors.black),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
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
          ),

          // Controles à direita: [-] [Reset] [+] e [Salvar na Playlist]
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                      tooltip: 'Diminuir 1 semitom',
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
                      tooltip: 'Aumentar 1 semitom',
                      onPressed: engine.incrementPitch,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 6),

              // Botão Salvar na Playlist
              GestureDetector(
                onTap: () async {
                  final success = await engine.saveCurrentSongKeyToPlaylist();
                  if (context.mounted) {
                    if (success) {
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '✅ Tom ${song.currentKey} salvo para "${song.title}" na playlist "${engine.currentSetlist?.title}"!\nO Acervo mantém o tom original (${song.originalKey}).',
                          ),
                          backgroundColor: AppTheme.emeraldSafe,
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    } else {
                      _showSelectPlaylistToSaveModal(context, engine, song);
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: isCustomKey
                        ? AppTheme.emeraldSafe.withOpacity(0.22)
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isCustomKey ? AppTheme.emeraldSafe : Colors.white24,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bookmark_added,
                        size: 13,
                        color: isCustomKey ? AppTheme.emeraldSafe : Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Salvar na Playlist',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isCustomKey ? AppTheme.emeraldSafe : Colors.white70,
                        ),
                      ),
                    ],
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

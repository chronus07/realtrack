import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/audio_engine.dart';
import '../theme/app_theme.dart';

class SetlistScreen extends StatelessWidget {
  final VoidCallback onOpenMixer;
  final VoidCallback onNavigateToUpload;

  const SetlistScreen({
    super.key,
    required this.onOpenMixer,
    required this.onNavigateToUpload,
  });

  void _showAddSongsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddSongsBottomSheet(onNavigateToUpload: onNavigateToUpload),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AudioEngine>();
    final setlist = engine.currentSetlist;

    if (setlist == null) {
      return const Center(child: Text('Nenhum repertório carregado'));
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PLAYLIST DA SEMANA',
              style: TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.bold),
            ),
            Text(
              setlist.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: () => _showAddSongsModal(context),
              icon: const Icon(Icons.playlist_add, size: 18),
              label: const Text('Adicionar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
              // Banner de Sincronia Offline
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF064E3B).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.emeraldSafe.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: AppTheme.emeraldSafe,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 14, color: Colors.black),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Playlist Pronta para o Show (${setlist.songs.length} Músicas)',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const Text(
                            'Áudios baixados no aparelho para reprodução sem internet',
                            style: TextStyle(fontSize: 9, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Lista de Músicas da Playlist
              Expanded(
                child: setlist.songs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Nenhuma música nesta playlist', style: TextStyle(color: Colors.white54)),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: () => _showAddSongsModal(context),
                              child: const Text('Buscar no Acervo ou Enviar'),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: setlist.songs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final song = setlist.songs[index];
                          final isCurrent = index == engine.currentSongIndex;

                          return Dismissible(
                            key: ValueKey(song.id + index.toString()),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              decoration: BoxDecoration(
                                color: AppTheme.roseMute,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) => engine.removeSongFromSetlist(index),
                            child: GestureDetector(
                              onTap: () {
                                engine.selectSong(index);
                                onOpenMixer();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isCurrent ? const Color(0xFF075985).withOpacity(0.3) : AppTheme.card,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isCurrent ? AppTheme.primary : AppTheme.cardBorder,
                                    width: isCurrent ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 26,
                                      height: 26,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: isCurrent ? AppTheme.primary : AppTheme.cardBorder,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        (index + 1).toString().padLeft(2, '0'),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isCurrent ? Colors.black : Colors.white70,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            song.title,
                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Text(
                                                'Tom: ${song.originalKey}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.amberCue,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '• ${song.bpm} BPM',
                                                style: const TextStyle(fontSize: 11, color: Colors.white54),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: song.isMultiTrack
                                            ? AppTheme.primary.withOpacity(0.15)
                                            : Colors.white10,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        song.isMultiTrack ? 'MULTITRACK' : 'FAIXA ÚNICA',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: song.isMultiTrack ? AppTheme.primary : Colors.white60,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // Botão de Ir para o Player
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: onOpenMixer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Abrir no Player de Palco ➔',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// MODAL BOTTOM SHEET: SELECIONAR DO ACERVO OU SUBIR NOVA
// ==========================================
class _AddSongsBottomSheet extends StatefulWidget {
  final VoidCallback onNavigateToUpload;

  const _AddSongsBottomSheet({required this.onNavigateToUpload});

  @override
  State<_AddSongsBottomSheet> createState() => _AddSongsBottomSheetState();
}

class _AddSongsBottomSheetState extends State<_AddSongsBottomSheet> {
  String _searchQuery = '';
  final Set<String> _selectedSongIds = {};

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AudioEngine>();
    final allMasterSongs = engine.masterLibrary;

    final availableSongs = allMasterSongs.where((s) {
      final q = _searchQuery.toLowerCase();
      return s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q) ||
          s.originalKey.toLowerCase().contains(q);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Adicionar à Playlist', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Busque no acervo da banda ou envie uma nova', style: TextStyle(fontSize: 11, color: Colors.white54)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Botão para Cadastrar Nova Música
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              widget.onNavigateToUpload();
            },
            icon: const Icon(Icons.cloud_upload_outlined, size: 18, color: AppTheme.primary),
            label: const Text('+ Enviar Uma Nova Música Agora', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.primary),
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),

          // Campo de Busca no Acervo
          TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Buscar no acervo da banda...',
              prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.primary),
              filled: true,
              fillColor: AppTheme.background,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 10),

          // Lista de Músicas do Acervo com Checkboxes
          Expanded(
            child: ListView.separated(
              itemCount: availableSongs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final song = availableSongs[index];
                final isSelected = _selectedSongIds.contains(song.id);
                final alreadyInSetlist = engine.currentSetlist?.songs.any((s) => s.id == song.id) ?? false;

                return Container(
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppTheme.primary : AppTheme.cardBorder,
                    ),
                  ),
                  child: CheckboxListTile(
                    value: alreadyInSetlist || isSelected,
                    onChanged: alreadyInSetlist
                        ? null // Já está na playlist
                        : (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedSongIds.add(song.id);
                              } else {
                                _selectedSongIds.remove(song.id);
                              }
                            });
                          },
                    title: Text(
                      song.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: alreadyInSetlist ? Colors.white38 : Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      alreadyInSetlist
                          ? 'Já incluída nesta playlist'
                          : '${song.artist} • Tom ${song.originalKey} • ${song.bpm} BPM',
                      style: TextStyle(
                        fontSize: 10,
                        color: alreadyInSetlist ? Colors.white24 : Colors.white54,
                      ),
                    ),
                    activeColor: AppTheme.primary,
                    checkColor: Colors.black,
                  ),
                );
              },
            ),
          ),

          // Botão Confirmar
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: _selectedSongIds.isEmpty
                  ? null
                  : () {
                      final selectedSongs = allMasterSongs
                          .where((s) => _selectedSongIds.contains(s.id))
                          .toList();
                      engine.addMultipleSongsToSetlist(selectedSongs);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${selectedSongs.length} música(s) adicionada(s) à playlist!'),
                          backgroundColor: AppTheme.emeraldSafe,
                        ),
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                'Confirmar Selecionadas (${_selectedSongIds.length})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

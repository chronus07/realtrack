import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_engine.dart';
import '../theme/app_theme.dart';

class LibraryScreen extends StatefulWidget {
  final VoidCallback onNavigateToUpload;

  const LibraryScreen({super.key, required this.onNavigateToUpload});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AudioEngine>();
    final allSongs = engine.masterLibrary;

    final filteredSongs = allSongs.where((s) {
      final q = _searchQuery.toLowerCase();
      return s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q) ||
          s.originalKey.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'REPOSITÓRIO GERAL',
              style: TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Acervo de Músicas da Banda',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: widget.onNavigateToUpload,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nova Música', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
              // Barra de Pesquisa
              TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Buscar por título, artista ou tom...',
                  prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.primary),
                  filled: true,
                  fillColor: AppTheme.card,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.cardBorder),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Lista de Músicas do Acervo
              Expanded(
                child: filteredSongs.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isEmpty ? 'Nenhuma música no acervo' : 'Nenhuma música encontrada',
                          style: const TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filteredSongs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final song = filteredSongs[index];
                          final isInCurrentSetlist = engine.currentSetlist?.songs.any((s) => s.id == song.id) ?? false;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.cardBorder),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        song.title,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${song.artist} • Tom: ${song.originalKey} • ${song.bpm} BPM',
                                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(right: 8),
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
                                IconButton(
                                  icon: Icon(
                                    isInCurrentSetlist ? Icons.check_circle : Icons.add_circle_outline,
                                    color: isInCurrentSetlist ? AppTheme.emeraldSafe : AppTheme.primary,
                                  ),
                                  tooltip: isInCurrentSetlist ? 'Já está na playlist' : 'Adicionar à playlist atual',
                                  onPressed: () {
                                    if (!isInCurrentSetlist) {
                                      engine.addSongToCurrentSetlist(song);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('"${song.title}" adicionada à playlist!'),
                                          backgroundColor: AppTheme.emeraldSafe,
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

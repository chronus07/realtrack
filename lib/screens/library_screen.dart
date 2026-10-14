import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/audio_cache_service.dart';
import '../services/audio_engine.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class LibraryScreen extends StatefulWidget {
  final VoidCallback onNavigateToUpload;

  const LibraryScreen({super.key, required this.onNavigateToUpload});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _searchQuery = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _syncLibraryFromCloud();
  }

  Future<void> _syncLibraryFromCloud() async {
    setState(() => _isLoading = true);
    try {
      final cloudSongs = await SupabaseService.fetchAllLibrarySongs();
      final engine = context.read<AudioEngine>();
      // Sincroniza o acervo com as músicas oficiais do Supabase
      engine.setLibrary(cloudSongs);
    } catch (e) {
      debugPrint('Erro ao sincronizar acervo com a nuvem: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _confirmDeleteSong(Song song) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text('Excluir "${song.title}"?'),
        content: const Text(
          'Esta música será removida do Acervo Geral da banda e de todas as playlists.',
          style: TextStyle(fontSize: 13, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.roseMute),
            onPressed: () async {
              Navigator.pop(ctx);
              final engine = context.read<AudioEngine>();
              await engine.removeSongFromLibrary(song.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Música "${song.title}" excluída do acervo e playlists.')),
                );
              }
            },
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAddToPlaylistSelector(Song song) {
    final engine = context.read<AudioEngine>();
    if (engine.allSetlists.length <= 1) {
      final current = engine.currentSetlist;
      if (current != null) {
        if (!current.songs.any((s) => s.id == song.id)) {
          engine.addSongToCurrentSetlist(song);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"${song.title}" adicionada à playlist "${current.title}"!'),
              backgroundColor: AppTheme.emeraldSafe,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"${song.title}" já está na playlist "${current.title}".'),
              backgroundColor: AppTheme.amberCue,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.playlist_add, color: AppTheme.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Adicionar "${song.title}" em:',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...engine.allSetlists.map((s) {
              final inThis = s.songs.any((x) => x.id == song.id);
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                leading: Icon(
                  inThis ? Icons.check_circle : Icons.queue_music,
                  color: inThis ? AppTheme.emeraldSafe : AppTheme.primary,
                ),
                title: Text(s.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                subtitle: Text('${s.songs.length} música(s)'),
                trailing: inThis
                    ? const Text('Já inclusa', style: TextStyle(color: AppTheme.emeraldSafe, fontSize: 11))
                    : const Icon(Icons.add_circle_outline, color: AppTheme.primary, size: 20),
                onTap: () {
                  if (!inThis) {
                    engine.addSongToSetlist(s.id, song);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('"${song.title}" adicionada à playlist "${s.title}"!'),
                        backgroundColor: AppTheme.emeraldSafe,
                      ),
                    );
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }

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
            Row(
              children: [
                const Text(
                  'Acervo da Banda',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${allSongs.length}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primary),
            tooltip: 'Sincronizar com a nuvem',
            onPressed: _syncLibraryFromCloud,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: widget.onNavigateToUpload,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nova', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
                  hintText: 'Buscar no acervo por título, artista ou tom...',
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

              // Lista de Músicas com Pull to Refresh
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : filteredSongs.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: AppTheme.card,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppTheme.cardBorder),
                                    ),
                                    child: const Icon(Icons.library_music_outlined, size: 32, color: Colors.white24),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchQuery.isEmpty ? 'O acervo da banda está vazio' : 'Nenhuma música encontrada',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _searchQuery.isEmpty
                                        ? 'Cadastre as músicas da sua banda para montar playlists de culto rapidamente.'
                                        : 'Tente buscar por outro termo ou cadastre uma nova música.',
                                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (_searchQuery.isEmpty) ...[
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(
                                      onPressed: widget.onNavigateToUpload,
                                      icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                                      label: const Text('Cadastrar Primeira Música', style: TextStyle(fontWeight: FontWeight.bold)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primary,
                                        foregroundColor: Colors.black,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            color: AppTheme.primary,
                            onRefresh: _syncLibraryFromCloud,
                            child: ListView.separated(
                              itemCount: filteredSongs.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final song = filteredSongs[index];
                                final isInCurrentSetlist =
                                    engine.currentSetlist?.songs.any((s) => s.id == song.id) ?? false;

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
                                              '${song.artist} • Tom: ${song.originalKey} • ${song.bpm} BPM • ${song.stems.length} pista(s)',
                                              style: const TextStyle(fontSize: 11, color: Colors.white54),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        margin: const EdgeInsets.only(right: 6),
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
                                      if (!kIsWeb)
                                        FutureBuilder<bool>(
                                          future: AudioCacheService.isSongFullyCached(song),
                                          builder: (context, snapshot) {
                                            final isCached = snapshot.data ?? false;
                                            return IconButton(
                                              icon: Icon(
                                                isCached ? Icons.offline_pin : Icons.download_for_offline_outlined,
                                                color: isCached ? AppTheme.emeraldSafe : Colors.white38,
                                                size: 20,
                                              ),
                                              tooltip: isCached ? 'Salva no aparelho' : 'Baixar faixas no aparelho',
                                              onPressed: () async {
                                                if (isCached) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text('✅ Todas as pistas de "${song.title}" já estão no celular.'),
                                                      backgroundColor: AppTheme.emeraldSafe,
                                                      duration: const Duration(seconds: 2),
                                                    ),
                                                  );
                                                } else {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text('Baixando "${song.title}" para o aparelho...'),
                                                      duration: const Duration(seconds: 1),
                                                    ),
                                                  );
                                                  await AudioCacheService.downloadSong(song);
                                                  if (context.mounted) {
                                                    setState(() {});
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text('✅ "${song.title}" salva no aparelho com sucesso!'),
                                                        backgroundColor: AppTheme.emeraldSafe,
                                                      ),
                                                    );
                                                  }
                                                }
                                              },
                                            );
                                          },
                                        ),
                                      IconButton(
                                        icon: Icon(
                                          isInCurrentSetlist ? Icons.check_circle : Icons.playlist_add,
                                          color: isInCurrentSetlist ? AppTheme.emeraldSafe : AppTheme.primary,
                                        ),
                                        tooltip: 'Adicionar a uma playlist',
                                        onPressed: () => _showAddToPlaylistSelector(song),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white30),
                                        tooltip: 'Excluir do acervo',
                                        onPressed: () => _confirmDeleteSong(song),
                                      ),
                                    ],
                                  ),
                                );
                              },
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

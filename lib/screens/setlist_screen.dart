import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../models/setlist.dart';
import '../services/audio_engine.dart';
import '../services/pitch_shifter.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class SetlistScreen extends StatefulWidget {
  final VoidCallback onOpenMixer;
  final VoidCallback onNavigateToUpload;

  const SetlistScreen({
    super.key,
    required this.onOpenMixer,
    required this.onNavigateToUpload,
  });

  @override
  State<SetlistScreen> createState() => _SetlistScreenState();
}

class _SetlistScreenState extends State<SetlistScreen> {
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadSetlistsFromCloud();
  }

  Future<void> _loadSetlistsFromCloud() async {
    setState(() => _isSyncing = true);
    try {
      final cloudSetlists = await SupabaseService.fetchAllSetlists();
      if (cloudSetlists.isNotEmpty && mounted) {
        final engine = context.read<AudioEngine>();
        engine.setAllSetlists(cloudSetlists);
      }
    } catch (e) {
      debugPrint('Erro ao carregar playlists da nuvem: $e');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _syncSetlists() async {
    final engine = context.read<AudioEngine>();
    final current = engine.currentSetlist;

    setState(() => _isSyncing = true);
    try {
      if (current != null && current.songs.isNotEmpty) {
        await SupabaseService.saveSetlistToCloud(current);
      }
      final cloudSetlists = await SupabaseService.fetchAllSetlists();
      if (cloudSetlists.isNotEmpty && mounted) {
        engine.setAllSetlists(cloudSetlists, selectId: current?.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Sincronizado com a nuvem! (${cloudSetlists.length} playlist(s) disponível(is))'),
              backgroundColor: AppTheme.emeraldSafe,
            ),
          );
        }
      } else if (current != null) {
        await SupabaseService.saveSetlistToCloud(current);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Playlist "${current.title}" salva na nuvem!'),
              backgroundColor: AppTheme.emeraldSafe,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao sincronizar: $e'), backgroundColor: AppTheme.roseMute),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _saveSetlistToCloud() async {
    final engine = context.read<AudioEngine>();
    final current = engine.currentSetlist;
    if (current != null) {
      await SupabaseService.saveSetlistToCloud(current);
    }
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.playlist_add, color: AppTheme.primary, size: 22),
            SizedBox(width: 8),
            Text('Criar Nova Playlist', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dê um nome para a playlist (ex: Culto Domingo Manhã, Vigília, Jovens, Ensaio):',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Ex: Culto Domingo Noite',
                filled: true,
                fillColor: AppTheme.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final title = controller.text.trim();
              if (title.isEmpty) return;
              Navigator.pop(ctx);

              final engine = context.read<AudioEngine>();
              final newSetlist = engine.createNewSetlist(title);
              SupabaseService.saveSetlistToCloud(newSetlist);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ Playlist "$title" criada com sucesso!'),
                  backgroundColor: AppTheme.emeraldSafe,
                ),
              );

              // Abre direto a tela de escolher músicas para a nova playlist
              _showAddSongsModal(context);
            },
            child: const Text('Criar Playlist', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showRenamePlaylistDialog(BuildContext context, Setlist setlist) {
    final controller = TextEditingController(text: setlist.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Renomear Playlist', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Novo nome da playlist...',
            filled: true,
            fillColor: AppTheme.background,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                final engine = context.read<AudioEngine>();
                engine.updateSetlistTitle(setlist.id, newTitle);
                SupabaseService.updateSetlistTitleOnCloud(setlist.id, newTitle);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  void _showDeletePlaylistDialog(BuildContext context, Setlist setlist) {
    final engine = context.read<AudioEngine>();
    if (engine.allSetlists.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Você precisa manter pelo menos uma playlist no aplicativo.'),
          backgroundColor: AppTheme.amberCue,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Excluir Playlist', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          'Deseja excluir a playlist "${setlist.title}"?\n\nAs músicas continuarão intactas no acervo geral da banda.',
          style: const TextStyle(fontSize: 13, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.roseMute, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              engine.deleteSetlist(setlist.id);
              SupabaseService.deleteSetlistFromCloud(setlist.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Playlist "${setlist.title}" excluída.'),
                  backgroundColor: AppTheme.roseMute,
                ),
              );
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveSongFromSetlist(int index, Song song) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.playlist_remove, color: AppTheme.roseMute, size: 22),
            SizedBox(width: 8),
            Text('Tirar da Playlist?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Deseja remover "${song.title}" desta playlist?\n\nℹ️ A música CONTINUARÁ salva e intacta no seu acervo geral da banda.',
          style: const TextStyle(fontSize: 13, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.roseMute,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              final engine = context.read<AudioEngine>();
              engine.removeSongFromSetlist(index);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Música "${song.title}" removida da playlist (mantida no acervo).'),
                  backgroundColor: AppTheme.emeraldSafe,
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            child: const Text('Tirar da Playlist', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddSongsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddSongsBottomSheet(
        onNavigateToUpload: widget.onNavigateToUpload,
      ),
    );
  }

  void _showTransposeDialog(int index, Song song) {
    final engine = context.read<AudioEngine>();
    showDialog(
      context: context,
      builder: (ctx) {
        int tempOffset = song.pitchOffsetSemitones;
        return StatefulBuilder(
          builder: (context, setModalState) {
            final transposedKey = PitchShifterService.transposeNote(song.originalKey, tempOffset);
            return AlertDialog(
              backgroundColor: AppTheme.card,
              title: Text('Tom de "${song.title}"', style: const TextStyle(fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Tom Original: ${song.originalKey}',
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: AppTheme.primary),
                        onPressed: tempOffset > -6
                            ? () => setModalState(() => tempOffset--)
                            : null,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.primary),
                        ),
                        child: Column(
                          children: [
                            Text(
                              transposedKey,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.amberCue),
                            ),
                            Text(
                              tempOffset == 0 ? 'Original' : '${tempOffset > 0 ? "+$tempOffset" : tempOffset} semitons',
                              style: const TextStyle(fontSize: 10, color: Colors.white60),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary),
                        onPressed: tempOffset < 6
                            ? () => setModalState(() => tempOffset++)
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.black),
                  onPressed: () {
                    engine.updateSongPitchOffset(index, tempOffset);
                    Navigator.pop(ctx);
                    _saveSetlistToCloud();
                  },
                  child: const Text('Salvar Tom'),
                ),
              ],
            );
          },
        );
      },
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
              'PLAYLISTS & REPERTÓRIO',
              style: TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.bold),
            ),
            Text(
              setlist.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary),
            tooltip: 'Criar Nova Playlist',
            onPressed: () => _showCreatePlaylistDialog(context),
          ),
          IconButton(
            icon: _isSyncing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
                : const Icon(Icons.cloud_sync_outlined, color: AppTheme.primary),
            tooltip: 'Sincronizar playlists com a nuvem',
            onPressed: _isSyncing ? null : _syncSetlists,
          ),
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
              // 1. BARRA HORIZONTAL DE SELEÇÃO DE PLAYLISTS
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    // Botão Criar Nova Playlist
                    InkWell(
                      onTap: () => _showCreatePlaylistDialog(context),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.primary, width: 1.2),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.add, color: AppTheme.primary, size: 16),
                            SizedBox(width: 4),
                            Text(
                              '+ Nova Playlist',
                              style: TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Lista das Playlists Existentes
                    ...engine.allSetlists.map((s) {
                      final isSelected = s.id == setlist.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          onTap: () => engine.selectSetlist(s.id),
                          borderRadius: BorderRadius.circular(10),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? AppTheme.primary : AppTheme.card,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? AppTheme.primary : AppTheme.cardBorder,
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected ? Icons.playlist_play : Icons.queue_music,
                                  size: 16,
                                  color: isSelected ? Colors.black : Colors.white70,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  s.title,
                                  style: TextStyle(
                                    color: isSelected ? Colors.black : Colors.white,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.black.withOpacity(0.25) : AppTheme.cardBorder,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${s.songs.length}',
                                    style: TextStyle(
                                      color: isSelected ? Colors.black : Colors.white70,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 2. CABEÇALHO DA PLAYLIST ATIVA COM AÇÕES
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppTheme.emeraldSafe.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 16, color: AppTheme.emeraldSafe),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  setlist.title,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 15, color: Colors.white60),
                                tooltip: 'Renomear playlist',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _showRenamePlaylistDialog(context, setlist),
                              ),
                            ],
                          ),
                          Text(
                            '${setlist.songs.length} música(s) nesta playlist • Arraste ≡ para ordenar',
                            style: const TextStyle(fontSize: 10, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                    if (engine.allSetlists.length > 1)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white38),
                        tooltip: 'Excluir esta playlist',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _showDeletePlaylistDialog(context, setlist),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 3. LISTA DE MÚSICAS DA PLAYLIST COM REORDENAÇÃO
              Expanded(
                child: setlist.songs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.queue_music, size: 44, color: Colors.white24),
                            const SizedBox(height: 10),
                            Text(
                              'A playlist "${setlist.title}" está vazia',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Adicione as músicas desejadas do acervo da banda.',
                              style: TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: () => _showAddSongsModal(context),
                              icon: const Icon(Icons.playlist_add, size: 16),
                              label: const Text('Incluir Músicas Nesta Playlist', style: TextStyle(fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ReorderableListView.builder(
                        itemCount: setlist.songs.length,
                        onReorder: (oldIdx, newIdx) {
                          engine.reorderSetlistSong(oldIdx, newIdx);
                        },
                        itemBuilder: (context, index) {
                          final song = setlist.songs[index];
                          final isCurrent = index == engine.currentSongIndex;

                          return Container(
                            key: ValueKey(song.id + index.toString()),
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Dismissible(
                              key: ValueKey('dismiss_${song.id}_$index'),
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
                              onDismissed: (_) {
                                engine.removeSongFromSetlist(index);
                              },
                              child: GestureDetector(
                                onTap: () {
                                  engine.selectSong(index);
                                  widget.onOpenMixer();
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
                                                GestureDetector(
                                                  onTap: () => _showTransposeDialog(index, song),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: AppTheme.amberCue.withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: AppTheme.amberCue.withOpacity(0.4)),
                                                    ),
                                                    child: Text(
                                                      'Tom: ${song.currentKey}${song.pitchOffsetSemitones != 0 ? " (${song.pitchOffsetSemitones > 0 ? "+${song.pitchOffsetSemitones}" : song.pitchOffsetSemitones})" : ""}',
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: AppTheme.amberCue,
                                                      ),
                                                    ),
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
                                      const SizedBox(width: 4),
                                      // Botão Explícito: Tirar da Playlist (mantém no acervo)
                                      IconButton(
                                        icon: const Icon(Icons.playlist_remove, color: Colors.white54, size: 20),
                                        tooltip: 'Tirar desta playlist (mantém no acervo)',
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                        onPressed: () => _confirmRemoveSongFromSetlist(index, song),
                                      ),
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 4),
                                          child: Icon(Icons.drag_handle, color: Colors.white38, size: 20),
                                        ),
                                      ),
                                    ],
                                  ),
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
                  onPressed: widget.onOpenMixer,
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

  const _AddSongsBottomSheet({
    required this.onNavigateToUpload,
  });

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
                children: [
                  Text('Adicionar à "${engine.currentSetlist?.title ?? "Playlist"}"', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const Text('Selecione as músicas do acervo para esta playlist', style: TextStyle(fontSize: 11, color: Colors.white54)),
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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../models/song.dart';
import '../services/audio_engine.dart';
import '../services/chords_ai_service.dart';
import '../services/pitch_shifter.dart';
import '../theme/app_theme.dart';

class ChordsScreen extends StatefulWidget {
  final VoidCallback onOpenMixer;

  const ChordsScreen({super.key, required this.onOpenMixer});

  @override
  State<ChordsScreen> createState() => _ChordsScreenState();
}

class _ChordsScreenState extends State<ChordsScreen> {
  final ScrollController _scrollController = ScrollController();
  Timer? _autoScrollTimer;
  bool _isAutoScrolling = false;
  double _scrollSpeed = 1.0; // 0.5x, 1.0x, 1.5x, 2.0x

  bool _isFetchingChords = false;
  String? _lastAttemptedSongId;

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleAutoScroll() {
    setState(() {
      _isAutoScrolling = !_isAutoScrolling;
    });

    if (_isAutoScrolling) {
      _startAutoScroll();
    } else {
      _stopAutoScroll();
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      final current = _scrollController.offset;
      if (current >= max) {
        _stopAutoScroll();
        if (mounted) setState(() => _isAutoScrolling = false);
        return;
      }
      final delta = 1.2 * _scrollSpeed;
      _scrollController.jumpTo((current + delta).clamp(0.0, max));
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _checkAndAutoFetchChords(Song song, AudioEngine engine) async {
    if (song.chordsText.isNotEmpty || _isFetchingChords || _lastAttemptedSongId == song.id) return;
    _lastAttemptedSongId = song.id;

    // Dispara a busca em background
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() => _isFetchingChords = true);

      final chords = await ChordsAiService.getOrFetchChords(song);
      if (mounted && chords != null && chords.isNotEmpty) {
        await engine.updateSongChords(song.id, chords);
      }

      if (mounted) {
        setState(() => _isFetchingChords = false);
      }
    });
  }

  Future<void> _forceRegenerateChords(Song song, AudioEngine engine) async {
    setState(() => _isFetchingChords = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.amberCue),
            ),
            SizedBox(width: 10),
            Text('✨ Gerando cifra inteligente com IA...'),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );

    final chords = await ChordsAiService.getOrFetchChords(song, forceRegenerate: true);
    if (mounted) {
      if (chords != null && chords.isNotEmpty) {
        await engine.updateSongChords(song.id, chords);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚡ Cifra gerada e salva no Acervo com sucesso!'),
            backgroundColor: AppTheme.emeraldPlay,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configure uma Chave Gemini ou verifique a conexão para gerar com IA.'),
            backgroundColor: AppTheme.roseMute,
          ),
        );
      }
      setState(() => _isFetchingChords = false);
    }
  }

  void _showEditChordsDialog(Song song, AudioEngine engine) {
    final controller = TextEditingController(text: song.chordsText);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Editar Cifra - ${song.title}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 500,
          child: TextField(
            controller: controller,
            maxLines: 15,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              hintText: 'Cole ou edite a cifra e a letra da música aqui...',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Color(0xFF0A0D16),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await engine.updateSongChords(song.id, controller.text);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cifra atualizada e salva no Acervo!'), backgroundColor: AppTheme.emeraldPlay),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.black),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  void _showGeminiKeyDialog() {
    final controller = TextEditingController(text: ChordsAiService.activeApiKey);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.auto_awesome, color: AppTheme.amberCue, size: 20),
            SizedBox(width: 8),
            Text('Chave Gemini API (Grátis)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'O app busca louvores conhecidos no catálogo integrado sem gastar nada. Para gerar cifras de qualquer música inédita via IA, insira sua chave gratuita do Google AI Studio:',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'AIzaSy...',
                labelText: 'Gemini API Key',
                filled: true,
                fillColor: const Color(0xFF0A0D16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () async {
                final uri = Uri.parse('https://aistudio.google.com/app/apikey');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
              child: const Text(
                '🔗 Obter chave gratuita no Google AI Studio (leva 10s)',
                style: TextStyle(fontSize: 11, color: AppTheme.primary, decoration: TextDecoration.underline),
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
            onPressed: () {
              ChordsAiService.setUserApiKey(controller.text);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Chave Gemini configurada com sucesso!'), backgroundColor: AppTheme.emeraldPlay),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.black),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AudioEngine engine) {
    final setlists = engine.allSetlists;

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
                'Nenhuma playlist selecionada',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 6),
              const Text(
                'Selecione uma playlist abaixo para abrir o repertório completo com cifras automáticas sincronizadas.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (setlists.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: setlists.map((s) {
                    return ActionChip(
                      backgroundColor: AppTheme.card,
                      side: const BorderSide(color: AppTheme.cardBorder),
                      avatar: const Icon(Icons.playlist_play, size: 16, color: AppTheme.primary),
                      label: Text(s.title, style: const TextStyle(fontSize: 12, color: Colors.white)),
                      onPressed: () {
                        engine.selectSetlist(s.id);
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AudioEngine>();
    final currentSetlist = engine.currentSetlist;
    final song = engine.currentSong;

    if (currentSetlist == null || currentSetlist.songs.isEmpty || song == null) {
      return _buildEmptyState(engine);
    }

    // Dispara a busca automática se a música atual não possuir cifra no Acervo
    _checkAndAutoFetchChords(song, engine);

    final transposedChords = PitchShifterService.transposeChordSheet(
      song.chordsText,
      engine.pitchOffset,
    );

    final isChordsCached = song.chordsText.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    currentSetlist.title.toUpperCase(),
                    style: const TextStyle(fontSize: 9, color: AppTheme.primary, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Faixa ${(engine.currentSongIndex + 1).toString().padLeft(2, '0')}/${currentSetlist.songs.length.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
            Text(
              song.title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          // Controle de Transposição de Tom
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  tooltip: 'Diminuir 1 semitom',
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
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  tooltip: 'Aumentar 1 semitom',
                  onPressed: engine.incrementPitch,
                ),
              ],
            ),
          ),

          // Menu de opções
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            color: AppTheme.card,
            onSelected: (val) {
              if (val == 'edit') {
                _showEditChordsDialog(song, engine);
              } else if (val == 'regen') {
                _forceRegenerateChords(song, engine);
              } else if (val == 'key') {
                _showGeminiKeyDialog();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'regen',
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 16, color: AppTheme.amberCue),
                    SizedBox(width: 8),
                    Text('Regerar Cifra com IA', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 16, color: AppTheme.primary),
                    SizedBox(width: 8),
                    Text('Editar / Colar Cifra', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'key',
                child: Row(
                  children: [
                    Icon(Icons.key, size: 16, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('Chave Gemini API', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ==========================================
            // BARRA DA PLAYLIST (CARROSSEL DE MÚSICAS)
            // ==========================================
            Container(
              height: 44,
              color: const Color(0xFF101624),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                scrollDirection: Axis.horizontal,
                itemCount: currentSetlist.songs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) {
                  final item = currentSetlist.songs[i];
                  final isSelected = (i == engine.currentSongIndex);
                  final itemKey = PitchShifterService.transposeNote(item.originalKey, item.pitchOffsetSemitones);

                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      engine.selectSong(i);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primary : AppTheme.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? AppTheme.primary : AppTheme.cardBorder,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(i + 1).toString().padLeft(2, '0')}. ',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.black : Colors.white54,
                            ),
                          ),
                          Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? Colors.black : Colors.white,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.black.withOpacity(0.2) : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              itemKey,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.black : AppTheme.amberCue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // ==========================================
            // STATUS DE CACHE / TOKENS & ARTISTA
            // ==========================================
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: const BoxDecoration(
                color: Color(0xFF0E131F),
                border: Border(bottom: BorderSide(color: AppTheme.cardBorder, width: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          song.artist.isEmpty ? 'Louvor' : song.artist,
                          style: const TextStyle(fontSize: 11, color: Colors.white60),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${song.bpm} BPM',
                          style: const TextStyle(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),

                  // Badge de Cache
                  if (_isFetchingChords) ...[
                    Row(
                      children: const [
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.amberCue),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Buscando via IA...',
                          style: TextStyle(fontSize: 10, color: AppTheme.amberCue, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ] else if (isChordsCached) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.emeraldPlay.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppTheme.emeraldPlay.withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt, size: 11, color: AppTheme.emeraldPlay),
                          SizedBox(width: 3),
                          Text(
                            'Acervo (0 Tokens)',
                            style: TextStyle(fontSize: 9, color: AppTheme.emeraldPlay, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    GestureDetector(
                      onTap: () => _forceRegenerateChords(song, engine),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.amberCue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppTheme.amberCue.withOpacity(0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome, size: 10, color: AppTheme.amberCue),
                            SizedBox(width: 3),
                            Text(
                              'Buscar Cifra com IA',
                              style: TextStyle(fontSize: 9, color: AppTheme.amberCue, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ==========================================
            // ÁREA DE EXIBIÇÃO DA CIFRA
            // ==========================================
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: AppTheme.background,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: transposedChords.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.music_off, size: 36, color: Colors.white24),
                                const SizedBox(height: 12),
                                Text(
                                  _isFetchingChords
                                      ? 'Obtendo harmonia e letra para "${song.title}"...'
                                      : 'Nenhuma cifra cadastrada para esta música.',
                                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () => _forceRegenerateChords(song, engine),
                                  icon: const Icon(Icons.auto_awesome, size: 16),
                                  label: const Text('Buscar Cifra com IA Agora'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    foregroundColor: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _showEditChordsDialog(song, engine),
                                  icon: const Icon(Icons.edit, size: 14),
                                  label: const Text('Digitar / Colar Cifra Manualmente'),
                                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        )
                      : SelectableText(
                          transposedChords,
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

            // ==========================================
            // BARRA DE CONTROLE: AUTO-SCROLL & PLAYER
            // ==========================================
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: const BoxDecoration(
                color: AppTheme.card,
                border: Border(top: BorderSide(color: AppTheme.cardBorder)),
              ),
              child: Row(
                children: [
                  // Botão Play/Pause do Áudio no Mixer
                  IconButton(
                    icon: Icon(
                      engine.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                      size: 34,
                      color: AppTheme.primary,
                    ),
                    onPressed: engine.togglePlay,
                    tooltip: engine.isPlaying ? 'Pausar áudio' : 'Soltar áudio',
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          engine.isPlaying ? 'Tocando no Palco' : 'Playback pausado',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Tom ${engine.currentKey} • Compasso ${engine.currentBar}',
                          style: const TextStyle(fontSize: 10, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),

                  // Controle de Auto-Scroll
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: _isAutoScrolling ? AppTheme.primary.withOpacity(0.15) : AppTheme.cardBorder,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isAutoScrolling ? AppTheme.primary : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _isAutoScrolling ? Icons.pause : Icons.arrow_downward,
                            size: 14,
                            color: _isAutoScrolling ? AppTheme.primary : Colors.white70,
                          ),
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          padding: EdgeInsets.zero,
                          tooltip: _isAutoScrolling ? 'Pausar Rolagem' : 'Iniciar Auto-Scroll',
                          onPressed: _toggleAutoScroll,
                        ),
                        PopupMenuButton<double>(
                          tooltip: 'Velocidade de rolagem',
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              '${_scrollSpeed}x',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _isAutoScrolling ? AppTheme.primary : Colors.white70,
                              ),
                            ),
                          ),
                          onSelected: (speed) {
                            setState(() => _scrollSpeed = speed);
                            if (_isAutoScrolling) {
                              _startAutoScroll();
                            }
                          },
                          itemBuilder: (ctx) => const [
                            PopupMenuItem(value: 0.5, child: Text('0.5x (Lenta)')),
                            PopupMenuItem(value: 1.0, child: Text('1.0x (Normal)')),
                            PopupMenuItem(value: 1.5, child: Text('1.5x (Rápida)')),
                            PopupMenuItem(value: 2.0, child: Text('2.0x (Muito Rápida)')),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Atalho para o Player
                  IconButton(
                    icon: const Icon(Icons.tune, size: 20, color: AppTheme.primary),
                    tooltip: 'Abrir Player',
                    onPressed: widget.onOpenMixer,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

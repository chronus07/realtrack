import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../models/stem_track.dart';
import '../services/audio_engine.dart';
import '../services/bpm_key_detector.dart';
import '../services/supabase_service.dart';
import '../services/worship_catalog.dart';
import '../theme/app_theme.dart';

class UploadScreen extends StatefulWidget {
  final VoidCallback? onSongSaved;

  const UploadScreen({super.key, this.onSongSaved});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _titleController = TextEditingController();
  final _artistController = TextEditingController();
  final _bpmController = TextEditingController(text: '72');
  final _chordsController = TextEditingController();

  String _selectedKey = 'G';
  String _selectedTimeSignature = '4/4';
  bool _isMultiTrack = true;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _uploadStatusText = '';

  final List<UploadStemItem> _selectedStems = [];

  final List<String> _musicalKeys = [
    'C', 'C#', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'
  ];

  final List<String> _timeSignatures = ['4/4', '6/8', '3/4', '2/4', '12/8'];

  void _onTitleChanged(String text) {
    if (text.trim().length >= 3) {
      final match = WorshipCatalog.lookup(text);
      if (match != null) {
        setState(() {
          _bpmController.text = match.bpm.toString();
          if (_musicalKeys.contains(match.key)) {
            _selectedKey = match.key;
          }
          if (_timeSignatures.contains(match.timeSignature)) {
            _selectedTimeSignature = match.timeSignature;
          }
          if (_artistController.text.trim().isEmpty) {
            _artistController.text = match.artist;
          }
        });

        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppTheme.amberCue, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '⚡ Reconhecido: ${match.title} (${match.artist}) • Tom ${match.key} • ${match.bpm} BPM',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1F2937),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _pickAudioFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: _isMultiTrack,
      type: FileType.custom,
      allowedExtensions: ['m4a', 'wav', 'mp3', 'aac', 'flac'],
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        for (var file in result.files) {
          final fileNameLower = file.name.toLowerCase();
          final isCue = fileNameLower.contains('click') ||
              fileNameLower.contains('metronomo') ||
              fileNameLower.contains('metronome') ||
              fileNameLower.contains('guia') ||
              fileNameLower.contains('guide') ||
              fileNameLower.contains('cue') ||
              fileNameLower.contains('count') ||
              fileNameLower.contains('tempo');

          // Evita duplicatas pelo nome
          if (!_selectedStems.any((s) => s.file.name == file.name)) {
            _selectedStems.add(
              UploadStemItem(
                file: file,
                name: _cleanStemName(file.name),
                isCue: isCue,
              ),
            );
          }
        }
        if (_selectedStems.length > 1) {
          _isMultiTrack = true;
        }
      });

      // Auto-detecta Tom, BPM, título e artista imediatamente após a seleção dos arquivos
      _autoDetectFromSelectedFiles();
    }
  }

  Future<void> _autoDetectFromSelectedFiles() async {
    if (_selectedStems.isEmpty && _titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione os áudios ou informe o título para auto-detectar Tom e BPM.'),
          backgroundColor: AppTheme.amberCue,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final fileNames = _selectedStems.map((s) => s.file.name).toList();
    final filePaths = _selectedStems.map((s) => s.file.path ?? '').toList();
    final fileBytesList = _selectedStems.map((s) => s.file.bytes).toList();

    final result = await BpmKeyDetector.detectFromStemsAndMetadata(
      fileNames: fileNames,
      filePaths: filePaths,
      fileBytesList: fileBytesList.any((b) => b != null) ? fileBytesList : null,
      songTitle: _titleController.text,
      chordsText: _chordsController.text,
    );

    if (result.hasAny && mounted) {
      setState(() {
        if (result.hasBpm) {
          _bpmController.text = result.bpm.toString();
        }
        if (result.hasKey && _musicalKeys.contains(result.key)) {
          _selectedKey = result.key!;
        }
        if (result.timeSignature != null && _timeSignatures.contains(result.timeSignature)) {
          _selectedTimeSignature = result.timeSignature!;
        }
        if (_titleController.text.isEmpty && result.detectedTitle != null && result.detectedTitle!.isNotEmpty) {
          _titleController.text = result.detectedTitle!;
        }
        if (_artistController.text.isEmpty && result.detectedArtist != null && result.detectedArtist!.isNotEmpty) {
          _artistController.text = result.detectedArtist!;
        }
      });

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppTheme.amberCue, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '⚡ Detectado: Tom ${result.key ?? _selectedKey} • ${result.bpm ?? _bpmController.text} BPM (${result.source})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1F2937),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  String _cleanStemName(String filename) {
    // Remove extensão e limpa nome
    String name = filename.replaceAll(RegExp(r'\.(m4a|wav|mp3|aac|flac)$', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'^[0-9]+[_\-\s]*'), ''); // Remove numeração no início (ex: 01_click -> click)
    return name.toUpperCase();
  }

  void _removeStem(int index) {
    setState(() {
      _selectedStems.removeAt(index);
    });
  }

  Future<void> _handleSaveSong() async {
    final title = _titleController.text.trim();
    final artist = _artistController.text.trim();
    final bpm = int.tryParse(_bpmController.text.trim()) ?? 120;

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, informe o título da música!'), backgroundColor: AppTheme.roseMute),
      );
      return;
    }

    if (_selectedStems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione pelo menos um arquivo de áudio!'), backgroundColor: AppTheme.roseMute),
      );
      return;
    }

    // Validação preventiva: limite de 50MB da nuvem gratuita
    final oversizedStems = _selectedStems.where((s) => s.file.size > 50 * 1024 * 1024).toList();
    if (oversizedStems.isNotEmpty) {
      final names = oversizedStems.map((s) => '${s.name} (${(s.file.size / (1024 * 1024)).toStringAsFixed(1)} MB)').join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Faixa(s) maior(es) que 50 MB detectadas: $names. O limite da nuvem gratuita é 50 MB por pista. Utilize áudios em .m4a ou .mp3 (qualidade 320kbps) para subir perfeitamente.'),
          backgroundColor: AppTheme.amberCue,
          duration: const Duration(seconds: 8),
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.05;
      _uploadStatusText = 'Iniciando upload...';
    });

    try {
      final engine = context.read<AudioEngine>();
      Song? createdSong;
      String? cloudError;

      // 1. Tenta fazer o upload real para o Supabase Storage + Database
      try {
        final bool isReallyMulti = _selectedStems.length > 1 || _isMultiTrack;

        createdSong = await SupabaseService.uploadNewSong(
          title: title,
          artist: artist.isEmpty ? 'Banda' : artist,
          originalKey: _selectedKey,
          bpm: bpm,
          timeSignature: _selectedTimeSignature,
          isMultiTrack: isReallyMulti,
          chordsText: _chordsController.text,
          stemsToUpload: _selectedStems,
          onProgress: (prog, status) {
            setState(() {
              _uploadProgress = prog;
              _uploadStatusText = status;
            });
          },
        );
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('413') || msg.contains('exceeded the maximum allowed size') || msg.contains('Payload too large')) {
          cloudError = 'Faixa maior que 50 MB detectada. Converta os arquivos para .m4a ou .mp3 (qualidade 320kbps) para enviar.';
        } else {
          cloudError = msg;
        }
        debugPrint('Upload no Supabase falhou: $e');
      }

      // 2. Se o Supabase ainda estiver sem credenciais ou offline, cria a música localmente
      if (createdSong == null) {
        final List<StemTrack> stems = _selectedStems.map((item) {
          return StemTrack(
            id: 'stem-${DateTime.now().millisecondsSinceEpoch}-${item.name}',
            name: item.name,
            isCue: item.isCue,
            filePath: item.file.path,
          );
        }).toList();

        final bool isReallyMulti = _selectedStems.length > 1 || _isMultiTrack;

        createdSong = Song(
          id: 'song-${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          artist: artist.isEmpty ? 'Banda' : artist,
          originalKey: _selectedKey,
          bpm: bpm,
          timeSignature: _selectedTimeSignature,
          isMultiTrack: isReallyMulti,
          chordsText: _chordsController.text,
          stems: stems,
        );
      }

      // 3. Salva no Acervo Geral do AudioEngine e sincroniza
      engine.addSongToLibrary(createdSong);
      engine.syncFromCloudSilently();

      setState(() {
        _isUploading = false;
      });

      if (mounted) {
        if (cloudError == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Música "$title" salva na nuvem com sucesso! Disponível para todos.'),
              backgroundColor: AppTheme.emeraldSafe,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ Salva apenas localmente neste celular. Erro na nuvem: $cloudError'),
              backgroundColor: AppTheme.amberCue,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }

      // Limpa os campos
      _titleController.clear();
      _artistController.clear();
      _chordsController.clear();
      setState(() {
        _selectedStems.clear();
      });

      // Notifica para ir para a aba do Acervo
      widget.onSongSaved?.call();
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar música: $e'), backgroundColor: AppTheme.roseMute),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('ACERVO GERAL', style: TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.bold)),
            Text('Cadastrar Nova Música', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Preencha as informações da música e selecione os áudios (Multitrack ou Faixa Única). Ela ficará salva no Acervo para sempre.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 16),

              // Título e Artista
              TextField(
                controller: _titleController,
                onChanged: _onTitleChanged,
                decoration: InputDecoration(
                  labelText: 'Título da Música *',
                  hintText: 'Ex: Há Um Rio ou Me Atraiu',
                  helperText: '⚡ O app reconhece Tom e BPM de louvores conhecidos automaticamente',
                  helperStyle: const TextStyle(fontSize: 10, color: AppTheme.amberCue),
                  filled: true,
                  fillColor: AppTheme.card,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _artistController,
                decoration: InputDecoration(
                  labelText: 'Artista / Ministério',
                  hintText: 'Ex: Fernandinho',
                  filled: true,
                  fillColor: AppTheme.card,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),

              // Tom, BPM e Compasso com Botão de Auto-Detecção
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Tom, BPM e Compasso', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  GestureDetector(
                    onTap: _autoDetectFromSelectedFiles,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.amberCue.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.amberCue.withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.auto_awesome, size: 13, color: AppTheme.amberCue),
                          SizedBox(width: 4),
                          Text(
                            'Auto-Detectar',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.amberCue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Tom, BPM e Compasso
              Row(
                children: [
                  // Dropdown Tom
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedKey,
                          isExpanded: true,
                          dropdownColor: AppTheme.card,
                          items: _musicalKeys.map((k) {
                            return DropdownMenuItem(
                              value: k,
                              child: Text('Tom: $k', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedKey = val);
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // BPM
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _bpmController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'BPM',
                        filled: true,
                        fillColor: AppTheme.card,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Compasso
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedTimeSignature,
                          isExpanded: true,
                          dropdownColor: AppTheme.card,
                          items: _timeSignatures.map((ts) {
                            return DropdownMenuItem(
                              value: ts,
                              child: Text(ts, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedTimeSignature = val);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Formato do Áudio (Multitrack vs Faixa Única)
              const Text('Tipo de Áudio', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isMultiTrack = true),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isMultiTrack ? AppTheme.primary.withOpacity(0.15) : AppTheme.card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _isMultiTrack ? AppTheme.primary : AppTheme.cardBorder,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Multitrack', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            Text('Faixas e stems separados', style: TextStyle(fontSize: 10, color: Colors.white54)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isMultiTrack = false),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: !_isMultiTrack ? AppTheme.primary.withOpacity(0.15) : AppTheme.card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: !_isMultiTrack ? AppTheme.primary : AppTheme.cardBorder,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Faixa Única', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            Text('Arquivo estéreo / Split L-R', style: TextStyle(fontSize: 10, color: Colors.white54)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Botão Selecionar Áudios
              GestureDetector(
                onTap: _pickAudioFiles,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.audio_file_outlined, size: 36, color: AppTheme.primary),
                      const SizedBox(height: 8),
                      Text(
                        _selectedStems.isEmpty
                            ? 'Clique para selecionar os áudios'
                            : '${_selectedStems.length} faixa(s) selecionada(s)',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const Text(
                        'Suporta .m4a, .mp3, .wav, .aac (Mapeamento automático de Click no canal L)',
                        style: TextStyle(fontSize: 10, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ),

              // Lista de Pistas Selecionadas para o Upload
              if (_selectedStems.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Mapeamento de Saída (Cabo Y):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _selectedStems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = _selectedStems[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${(item.file.size / (1024 * 1024)).toStringAsFixed(1)} MB • ${item.file.name}${item.file.size > 50 * 1024 * 1024 ? " ⚠️ (>50MB)" : ""}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: item.file.size > 50 * 1024 * 1024 ? AppTheme.roseMute : Colors.white38,
                                    fontWeight: item.file.size > 50 * 1024 * 1024 ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Toggle Cue vs Banda
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                item.isCue = !item.isCue;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: item.isCue
                                    ? AppTheme.amberCue.withOpacity(0.2)
                                    : AppTheme.primary.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: item.isCue ? AppTheme.amberCue : AppTheme.primary,
                                ),
                              ),
                              child: Text(
                                item.isCue ? 'Fone / L (Click/Guia)' : 'P.A. / R (Banda)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: item.isCue ? AppTheme.amberCue : AppTheme.primary,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16, color: Colors.white38),
                            onPressed: () => _removeStem(index),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),


              const SizedBox(height: 20),

              // Barra de Progresso durante Upload
              if (_isUploading) ...[
                LinearProgressIndicator(value: _uploadProgress, color: AppTheme.primary, backgroundColor: AppTheme.cardBorder),
                const SizedBox(height: 8),
                Text(
                  _uploadStatusText,
                  style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 16),
              ],

              // Botão Salvar
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isUploading ? null : _handleSaveSong,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isUploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Text(
                          'Salvar no Acervo da Banda ➔',
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

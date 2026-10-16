import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../models/stem_track.dart';
import '../services/audio_engine.dart';
import '../services/bpm_key_detector.dart';
import '../services/cloud_importer_service.dart';
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
  // Modo de Upload: 0 = Arquivo Local, 1 = Link YouTube / Spotify
  int _uploadMode = 0;

  // Controladores do formulário
  final _titleController = TextEditingController();
  final _artistController = TextEditingController();
  final _bpmController = TextEditingController(text: '72');
  final _chordsController = TextEditingController();

  // Controladores do modo Link
  final _linkController = TextEditingController();
  bool _isResolvingLink = false;
  Map<String, dynamic>? _resolvedLinkData;
  String? _resolvedYoutubeUrl;

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

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _bpmController.dispose();
    _chordsController.dispose();
    _linkController.dispose();
    super.dispose();
  }

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

  // ==========================================
  // MODO 1: UPLOAD VIA ARQUIVO LOCAL
  // ==========================================

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
                  '⚡ Auto-Detectado: ${result.summary}',
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
    String name = filename.replaceAll(RegExp(r'\.(m4a|wav|mp3|aac|flac)$', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'^[0-9]+[_\-\s]*'), '');
    return name.toUpperCase();
  }

  void _removeStem(int index) {
    setState(() {
      _selectedStems.removeAt(index);
    });
  }

  Future<void> _handleSaveLocalSong() async {
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

    final oversizedStems = _selectedStems.where((s) => s.file.size > 50 * 1024 * 1024).toList();
    if (oversizedStems.isNotEmpty) {
      final names = oversizedStems.map((s) => '${s.name} (${(s.file.size / (1024 * 1024)).toStringAsFixed(1)} MB)').join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Faixa(s) maior(es) que 50 MB detectadas: $names. O limite da nuvem é 50 MB por pista. Utilize áudios em .m4a ou .mp3 (qualidade 320kbps).'),
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
      Song? createdSong;
      String? cloudError;

      try {
        createdSong = await SupabaseService.uploadNewSong(
          title: title,
          artist: artist,
          originalKey: _selectedKey,
          bpm: bpm,
          timeSignature: _selectedTimeSignature,
          isMultiTrack: _isMultiTrack,
          chordsText: _chordsController.text.trim(),
          stemsToUpload: _selectedStems,
          onProgress: (progress, status) {
            setState(() {
              _uploadProgress = progress;
              _uploadStatusText = status;
            });
          },
        );
      } catch (err) {
        cloudError = err.toString();
        debugPrint('Erro ao salvar no Supabase: $cloudError');
      }

      if (createdSong != null) {
        context.read<AudioEngine>().addSongToLibrary(createdSong);
      } else {
        final mockStems = _selectedStems.map((s) {
          return StemTrack(
            id: 'local_${DateTime.now().millisecondsSinceEpoch}_${s.name}',
            name: s.name,
            filePath: s.file.path,
            volume: 0.85,
            pan: !_isMultiTrack ? 0.0 : (s.isCue ? -1.0 : 1.0),
            isCue: s.isCue,
            outputChannel: !_isMultiTrack ? OutputChannel.stereo : (s.isCue ? OutputChannel.left : OutputChannel.right),
          );
        }).toList();

        final localOnlySong = Song(
          id: 'local_${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          artist: artist,
          originalKey: _selectedKey,
          bpm: bpm,
          timeSignature: _selectedTimeSignature,
          isMultiTrack: _isMultiTrack,
          chordsText: _chordsController.text.trim(),
          stems: mockStems,
        );

        context.read<AudioEngine>().addSongToLibrary(localOnlySong);
      }

      setState(() {
        _isUploading = false;
      });

      if (mounted) {
        if (createdSong != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Música "$title" salva com sucesso no Acervo e na Nuvem!'),
              backgroundColor: AppTheme.emeraldSafe,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ Salva apenas localmente neste aparelho. Erro na nuvem: $cloudError'),
              backgroundColor: AppTheme.amberCue,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }

      _titleController.clear();
      _artistController.clear();
      _chordsController.clear();
      setState(() {
        _selectedStems.clear();
      });

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

  // ==========================================
  // MODO 2: IMPORTAR POR LINK (YOUTUBE / SPOTIFY)
  // ==========================================

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      _linkController.text = data.text!.trim();
      _resolveLink();
    }
  }

  Future<void> _resolveLink() async {
    final rawUrl = _linkController.text.trim();
    if (rawUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cole a URL de uma música do YouTube ou do Spotify.'),
          backgroundColor: AppTheme.amberCue,
        ),
      );
      return;
    }

    setState(() {
      _isResolvingLink = true;
      _resolvedLinkData = null;
      _resolvedYoutubeUrl = null;
    });

    try {
      final info = await CloudImporterService.resolveLink(rawUrl);

      setState(() {
        _resolvedLinkData = info;
        _resolvedYoutubeUrl = info['youtubeUrl'];

        if (info['title'] != null) {
          _titleController.text = info['title'];
        }
        if (info['artist'] != null) {
          _artistController.text = info['artist'];
        }
        if (info['detectedKey'] != null && _musicalKeys.contains(info['detectedKey'])) {
          _selectedKey = info['detectedKey'];
        }
        if (info['detectedBpm'] != null) {
          _bpmController.text = info['detectedBpm'].toString();
        }
        if (info['detectedTimeSignature'] != null && _timeSignatures.contains(info['detectedTimeSignature'])) {
          _selectedTimeSignature = info['detectedTimeSignature'];
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppTheme.emeraldSafe, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '⚡ Link identificado: ${_titleController.text} (${_artistController.text})',
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
    } catch (e) {
      if (mounted) {
        _showCloudConfigOrErrorDialog(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResolvingLink = false;
        });
      }
    }
  }

  void _showCloudConfigOrErrorDialog(String errorMsg) {
    final urlController = TextEditingController(text: CloudImporterService.serviceUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        title: const Row(
          children: [
            Icon(Icons.cloud_off, color: AppTheme.amberCue, size: 22),
            SizedBox(width: 8),
            Text(
              'Serviço na Nuvem (Cloud Importer)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Não foi possível conectar ao microserviço na nuvem:\n$errorMsg',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 14),
            const Text(
              'URL do Cloud Importer:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: urlController,
              style: const TextStyle(fontSize: 13, color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.background,
                hintText: 'https://seu-servico.onrender.com ou http://localhost:3000',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '💡 Dica: Suba o microserviço da pasta "cloud_importer" no Render.com gratuitamente ou inicie com "npm start" no computador.',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fechar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              CloudImporterService.serviceUrl = urlController.text.trim();
              Navigator.of(ctx).pop();
              _resolveLink();
            },
            child: const Text('Salvar e Tentar Novamente'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleImportFromLink() async {
    final title = _titleController.text.trim();
    final artist = _artistController.text.trim();
    final bpm = int.tryParse(_bpmController.text.trim()) ?? 120;
    final ytUrl = _resolvedYoutubeUrl ?? _linkController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o título da música!'), backgroundColor: AppTheme.roseMute),
      );
      return;
    }

    if (ytUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Analise o link do YouTube ou Spotify antes de importar.'), backgroundColor: AppTheme.roseMute),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.15;
      _uploadStatusText = 'Extraindo áudio de alta fidelidade na nuvem...';
    });

    try {
      setState(() {
        _uploadProgress = 0.45;
        _uploadStatusText = 'Convertendo para MP3 (192 kbps) e enviando ao Supabase...';
      });

      final result = await CloudImporterService.importSong(
        youtubeUrl: ytUrl,
        title: title,
        artist: artist,
        key: _selectedKey,
        bpm: bpm,
        timeSignature: _selectedTimeSignature,
      );

      setState(() {
        _uploadProgress = 1.0;
        _uploadStatusText = 'Música adicionada com sucesso no Acervo!';
      });

      // Sincroniza o acervo na aplicação
      context.read<AudioEngine>().syncFromCloudSilently();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppTheme.emeraldSafe, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('🎉 Música "$title" importada e salva no Acervo!'),
                ),
              ],
            ),
            backgroundColor: AppTheme.emeraldSafe,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      // Limpa os campos
      _titleController.clear();
      _artistController.clear();
      _linkController.clear();
      setState(() {
        _resolvedLinkData = null;
        _resolvedYoutubeUrl = null;
        _isUploading = false;
      });

      widget.onSongSaved?.call();
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      if (mounted) {
        _showCloudConfigOrErrorDialog(e.toString());
      }
    }
  }

  // ==========================================
  // BUILD PRINCIPAL
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ACERVO GERAL', style: TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.bold)),
            Text('Cadastrar Nova Música', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: AppTheme.card,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. SELETOR DE MODO: ARQUIVO LOCAL VS IMPORTAR POR LINK
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                        onTap: () => setState(() => _uploadMode = 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _uploadMode == 0 ? AppTheme.primary.withOpacity(0.2) : Colors.transparent,
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                            border: Border(
                              bottom: BorderSide(
                                color: _uploadMode == 0 ? AppTheme.primary : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.folder_open,
                                size: 16,
                                color: _uploadMode == 0 ? AppTheme.primary : Colors.white54,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Arquivo Local',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _uploadMode == 0 ? Colors.white : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                        onTap: () => setState(() => _uploadMode = 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _uploadMode == 1 ? AppTheme.emeraldSafe.withOpacity(0.2) : Colors.transparent,
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                            border: Border(
                              bottom: BorderSide(
                                color: _uploadMode == 1 ? AppTheme.emeraldSafe : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.link,
                                size: 16,
                                color: _uploadMode == 1 ? AppTheme.emeraldSafe : Colors.white54,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Link YouTube / Spotify',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _uploadMode == 1 ? Colors.white : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // =======================================================
              // MODO 1: UPLOAD POR LINK (YOUTUBE / SPOTIFY)
              // =======================================================
              if (_uploadMode == 1) ...[
                const Text(
                  'Insira o link de uma música do YouTube ou Spotify. O áudio será baixado em MP3 (192 kbps) e salvo diretamente no Acervo.',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
                const SizedBox(height: 14),

                // Campo de Link com Botão Colar
                TextField(
                  controller: _linkController,
                  decoration: InputDecoration(
                    labelText: 'Link do YouTube ou Spotify',
                    hintText: 'https://youtube.com/watch?v=... ou https://open.spotify.com/track/...',
                    hintStyle: const TextStyle(fontSize: 11, color: Colors.white30),
                    prefixIcon: const Icon(Icons.link, color: AppTheme.emeraldSafe, size: 20),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_linkController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18, color: Colors.white38),
                            onPressed: () {
                              setState(() {
                                _linkController.clear();
                                _resolvedLinkData = null;
                                _resolvedYoutubeUrl = null;
                              });
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.content_paste, size: 18, color: AppTheme.emeraldSafe),
                          tooltip: 'Colar da área de transferência',
                          onPressed: _pasteFromClipboard,
                        ),
                      ],
                    ),
                    filled: true,
                    fillColor: AppTheme.card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),

                // Botão de Analisar Link
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.emeraldSafe,
                      side: const BorderSide(color: AppTheme.emeraldSafe, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _isResolvingLink
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.emeraldSafe),
                          )
                        : const Icon(Icons.search, size: 18),
                    label: Text(
                      _isResolvingLink ? 'Analisando link...' : 'Analisar Link e Extrair Dados',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: _isResolvingLink ? null : _resolveLink,
                  ),
                ),

                // Preview Card com Capa e Detalhes
                if (_resolvedLinkData != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.emeraldSafe.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        if (_resolvedLinkData!['thumbnail'] != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _resolvedLinkData!['thumbnail'],
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 60,
                                height: 60,
                                color: AppTheme.background,
                                child: const Icon(Icons.music_note, color: Colors.white38),
                              ),
                            ),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _resolvedLinkData!['source'] == 'spotify'
                                          ? const Color(0xFF1DB954).withOpacity(0.2)
                                          : Colors.red.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _resolvedLinkData!['source'] == 'spotify' ? 'SPOTIFY' : 'YOUTUBE',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: _resolvedLinkData!['source'] == 'spotify'
                                            ? const Color(0xFF1DB954)
                                            : Colors.redAccent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${((_resolvedLinkData!['durationSeconds'] ?? 240) / 60).floor()}:${((_resolvedLinkData!['durationSeconds'] ?? 240) % 60).toString().padLeft(2, '0')} min',
                                    style: const TextStyle(fontSize: 10, color: Colors.white54),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _resolvedLinkData!['title'] ?? '',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _resolvedLinkData!['artist'] ?? '',
                                style: const TextStyle(fontSize: 11, color: Colors.white70),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),
              ],

              // =======================================================
              // CAMPOS COMUNS (TÍTULO, ARTISTA, TOM, BPM, COMPASSO)
              // =======================================================
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
                  hintText: 'Ex: Fernandinho ou Julliany Souza',
                  filled: true,
                  fillColor: AppTheme.card,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),

              // Tom, BPM e Compasso
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Tom, BPM e Compasso', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  if (_uploadMode == 0)
                    GestureDetector(
                      onTap: _autoDetectFromSelectedFiles,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.amberCue.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.amberCue.withOpacity(0.5)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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

              // =======================================================
              // MODO 0: ARQUIVOS LOCAIS (MULTITRACK OU FAIXA ÚNICA)
              // =======================================================
              if (_uploadMode == 0) ...[
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
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                              ? 'Clique para selecionar os áudios do aparelho'
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

                // Lista de Pistas Selecionadas
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
              ],

              const SizedBox(height: 20),

              // Barra de Progresso durante Upload
              if (_isUploading) ...[
                LinearProgressIndicator(
                  value: _uploadProgress,
                  color: _uploadMode == 1 ? AppTheme.emeraldSafe : AppTheme.primary,
                  backgroundColor: AppTheme.cardBorder,
                ),
                const SizedBox(height: 8),
                Text(
                  _uploadStatusText,
                  style: TextStyle(
                    fontSize: 11,
                    color: _uploadMode == 1 ? AppTheme.emeraldSafe : AppTheme.primary,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // BOTÃO SALVAR
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isUploading
                      ? null
                      : (_uploadMode == 0 ? _handleSaveLocalSong : _handleImportFromLink),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _uploadMode == 1 ? AppTheme.emeraldSafe : AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isUploading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_uploadMode == 1 ? Icons.cloud_download : Icons.save, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              _uploadMode == 1
                                  ? 'Baixar e Salvar no Acervo da Banda ➔'
                                  : 'Salvar no Acervo da Banda ➔',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

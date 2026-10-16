import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/metronome_service.dart';
import '../services/audio_engine.dart';
import '../theme/app_theme.dart';

class MetronomeScreen extends StatefulWidget {
  const MetronomeScreen({super.key});

  @override
  State<MetronomeScreen> createState() => _MetronomeScreenState();
}

class _MetronomeScreenState extends State<MetronomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _tapAnimController;
  late Animation<double> _tapAnim;

  @override
  void initState() {
    super.initState();
    _tapAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _tapAnim = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _tapAnimController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _tapAnimController.dispose();
    super.dispose();
  }

  void _onTapButton(MetronomeService metronome) {
    _tapAnimController.forward().then((_) => _tapAnimController.reverse());
    HapticFeedback.lightImpact();
    metronome.tapTempo();
  }

  void _showBpmInputDialog(BuildContext context, MetronomeService metronome) {
    final controller = TextEditingController(text: metronome.bpm.toString());
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
            Icon(Icons.edit_outlined, color: AppTheme.amberCue, size: 20),
            SizedBox(width: 8),
            Text(
              'Digitar BPM',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Insira o andamento desejado (de 30 a 300 BPM):',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.background,
                suffixText: 'BPM',
                suffixStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                ),
              ),
              onSubmitted: (val) {
                final bpm = int.tryParse(val);
                if (bpm != null) {
                  metronome.setBpm(bpm);
                  Navigator.of(ctx).pop();
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final bpm = int.tryParse(controller.text);
              if (bpm != null) {
                metronome.setBpm(bpm);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _getTempoName(int bpm) {
    if (bpm < 60) return 'Largo (Muito lento)';
    if (bpm < 76) return 'Adagio (Lento)';
    if (bpm < 108) return 'Andante (Moderado suave)';
    if (bpm < 120) return 'Moderato (Moderado)';
    if (bpm < 156) return 'Allegro (Rápido / Worship pop)';
    if (bpm < 176) return 'Vivace (Muito rápido)';
    return 'Presto (Acelerado)';
  }

  @override
  Widget build(BuildContext context) {
    final metronome = context.watch<MetronomeService>();
    final engine = context.watch<AudioEngine>();
    final activeSong = engine.currentSong;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.speed, color: AppTheme.primary, size: 22),
            const SizedBox(width: 8),
            const Text(
              'Metrônomo',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const Spacer(),
            // Badge de status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: metronome.isPlaying
                    ? AppTheme.emeraldSafe.withOpacity(0.2)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: metronome.isPlaying
                      ? AppTheme.emeraldSafe
                      : Colors.white24,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: metronome.isPlaying ? AppTheme.emeraldSafe : Colors.white38,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    metronome.isPlaying ? 'ATIVO' : 'PARADO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: metronome.isPlaying ? AppTheme.emeraldSafe : Colors.white38,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.card,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            // 1. BANNER OPCIONAL: SINCRONIZAR COM A MÚSICA DO PLAYER
            if (activeSong != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.card.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.amberCue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.music_note, color: AppTheme.amberCue, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activeSong.title,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${activeSong.bpm} BPM • Compasso ${activeSong.timeSignature}',
                            style: const TextStyle(fontSize: 11, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        backgroundColor: AppTheme.amberCue.withOpacity(0.15),
                        foregroundColor: AppTheme.amberCue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: const Icon(Icons.sync, size: 14),
                      label: const Text(
                        'Importar BPM',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        metronome.syncWithSong(
                          songBpm: activeSong.bpm,
                          songTimeSignature: activeSong.timeSignature,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('BPM sincronizado com "${activeSong.title}" (${activeSong.bpm} BPM)'),
                            backgroundColor: AppTheme.amberCue,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],

            // 2. INDICADOR VISUAL DE BATIDAS (LEDS DO COMPASSO)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(metronome.beatsPerBar, (index) {
                      final beatNum = index + 1;
                      final isCurrent = metronome.isPlaying && (metronome.currentBeat == beatNum);
                      final isFirstBeat = (beatNum == 1);

                      final Color activeColor = isFirstBeat ? AppTheme.amberCue : AppTheme.primary;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 60),
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: isCurrent ? 34 : 26,
                        height: isCurrent ? 34 : 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCurrent
                              ? activeColor
                              : (isFirstBeat
                                  ? AppTheme.amberCue.withOpacity(0.2)
                                  : Colors.white10),
                          border: Border.all(
                            color: isCurrent
                                ? Colors.white
                                : (isFirstBeat ? AppTheme.amberCue.withOpacity(0.5) : Colors.white24),
                            width: isCurrent ? 2.5 : 1,
                          ),
                          boxShadow: isCurrent
                              ? [
                                  BoxShadow(
                                    color: activeColor.withOpacity(0.6),
                                    blurRadius: 14,
                                    spreadRadius: 3,
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            '$beatNum',
                            style: TextStyle(
                              fontSize: isCurrent ? 14 : 11,
                              fontWeight: FontWeight.w900,
                              color: isCurrent
                                  ? (isFirstBeat ? Colors.black : Colors.white)
                                  : (isFirstBeat ? AppTheme.amberCue : Colors.white54),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    metronome.isPlaying
                        ? 'Tempo ${metronome.currentBeat} de ${metronome.beatsPerBar}'
                        : 'Compasso ${metronome.timeSignature}',
                    style: const TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 3. DISPLAY CENTRAL DE BPM COM DIGITAÇÃO E AJUSTES FINOS
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                children: [
                  // Botão de editar BPM
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showBpmInputDialog(context, metronome),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${metronome.bpm}',
                            style: const TextStyle(
                              fontSize: 64,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'BPM',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary,
                                ),
                              ),
                              Icon(Icons.edit, size: 14, color: Colors.white38),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    _getTempoName(metronome.bpm),
                    style: const TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),

                  // Botões de ajuste rápido: [-5] [-1] [+1] [+5]
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildBpmButton('-5', () => metronome.adjustBpm(-5), isSecondary: true),
                      const SizedBox(width: 10),
                      _buildBpmButton('-1', () => metronome.adjustBpm(-1)),
                      const SizedBox(width: 16),
                      _buildBpmButton('+1', () => metronome.adjustBpm(1)),
                      const SizedBox(width: 10),
                      _buildBpmButton('+5', () => metronome.adjustBpm(5), isSecondary: true),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Slider de BPM
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppTheme.primary,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: AppTheme.primary,
                      overlayColor: AppTheme.primary.withOpacity(0.2),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: metronome.bpm.toDouble(),
                      min: 30,
                      max: 280,
                      onChanged: (val) => metronome.setBpm(val.round()),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 4. PAN L / C / R (IGUAL AO MULTITRACK DO MIXER DE PALCO)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.alt_route, color: AppTheme.amberCue, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'CANAL DE SAÍDA (PAN STAGE)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white70,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildPanSegment(
                        label: 'L',
                        subtitle: 'Esquerda (Fone)',
                        value: -1.0,
                        currentPan: metronome.pan,
                        onTap: () => metronome.setPan(-1.0),
                      ),
                      const SizedBox(width: 8),
                      _buildPanSegment(
                        label: 'C',
                        subtitle: 'Centro (Estéreo)',
                        value: 0.0,
                        currentPan: metronome.pan,
                        onTap: () => metronome.setPan(0.0),
                      ),
                      const SizedBox(width: 8),
                      _buildPanSegment(
                        label: 'R',
                        subtitle: 'Direita (Banda)',
                        value: 1.0,
                        currentPan: metronome.pan,
                        onTap: () => metronome.setPan(1.0),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 5. BOTÃO TAP TEMPO
            ScaleTransition(
              scale: _tapAnim,
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.amberCue.withOpacity(0.18),
                    foregroundColor: AppTheme.amberCue,
                    side: const BorderSide(color: AppTheme.amberCue, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.touch_app, size: 22),
                  label: const Text(
                    'TAP TEMPO (TOQUE NO RITMO)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                  onPressed: () => _onTapButton(metronome),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // 6. CONFIGURAÇÕES: COMPASSO, SUBDIVISÃO E TIMBRE
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fórmulas de Compasso
                  const Text(
                    'COMPASSO',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white54),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: ['2/4', '3/4', '4/4', '5/4', '6/8'].map((ts) {
                      final isSelected = metronome.timeSignature == ts;
                      return ChoiceChip(
                        label: Text(ts, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        selected: isSelected,
                        selectedColor: AppTheme.primary,
                        backgroundColor: AppTheme.background,
                        labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected ? AppTheme.primary : AppTheme.cardBorder,
                          ),
                        ),
                        onSelected: (_) => metronome.setTimeSignature(ts),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 14),

                  // Subdivisão rítmica
                  const Text(
                    'SUBDIVISÃO',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white54),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      _buildSubdivisionChip('1/4 (Semínima)', MetronomeSubdivision.quarter, metronome),
                      _buildSubdivisionChip('1/8 (Colcheia)', MetronomeSubdivision.eighth, metronome),
                      _buildSubdivisionChip('Tercinas', MetronomeSubdivision.triplet, metronome),
                      _buildSubdivisionChip('1/16 (Semicolcheia)', MetronomeSubdivision.sixteenth, metronome),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Timbre do Click
                  const Text(
                    'TIMBRE DO CLICK',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white54),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.cardBorder),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<MetronomeTimbre>(
                        value: metronome.timbre,
                        isExpanded: true,
                        dropdownColor: AppTheme.card,
                        icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primary),
                        items: const [
                          DropdownMenuItem(
                            value: MetronomeTimbre.digitalClave,
                            child: Row(
                              children: [
                                Icon(Icons.music_note, color: AppTheme.primary, size: 16),
                                SizedBox(width: 8),
                                Text('🔊 Clave Digital (Corta na mix)', style: TextStyle(color: Colors.white, fontSize: 13)),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: MetronomeTimbre.acousticRimshot,
                            child: Row(
                              children: [
                                Icon(Icons.circle, color: AppTheme.amberCue, size: 14),
                                SizedBox(width: 8),
                                Text('🥁 Sidestick Acústico (Bateria)', style: TextStyle(color: Colors.white, fontSize: 13)),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: MetronomeTimbre.classicBeep,
                            child: Row(
                              children: [
                                Icon(Icons.volume_up, color: AppTheme.emeraldSafe, size: 16),
                                SizedBox(width: 8),
                                Text('🔔 Beep Digital Clássico', style: TextStyle(color: Colors.white, fontSize: 13)),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: MetronomeTimbre.woodblock,
                            child: Row(
                              children: [
                                Icon(Icons.nature, color: Colors.amber, size: 16),
                                SizedBox(width: 8),
                                Text('🪵 Bloco de Madeira (Woodblock)', style: TextStyle(color: Colors.white, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (newT) {
                          if (newT != null) metronome.setTimbre(newT);
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Controle de volume
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          metronome.isMuted ? Icons.volume_off : Icons.volume_up,
                          color: metronome.isMuted ? AppTheme.roseMute : AppTheme.primary,
                        ),
                        onPressed: metronome.toggleMute,
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppTheme.primary,
                            inactiveTrackColor: Colors.white12,
                            thumbColor: AppTheme.primary,
                            trackHeight: 3,
                          ),
                          child: Slider(
                            value: metronome.volume,
                            min: 0.0,
                            max: 1.0,
                            onChanged: metronome.setVolume,
                          ),
                        ),
                      ),
                      Text(
                        '${(metronome.volume * 100).toInt()}%',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // 7. BOTÃO PRINCIPAL: INICIAR / PARAR METRÔNOMO
            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: metronome.isPlaying ? AppTheme.roseMute : AppTheme.emeraldSafe,
                  foregroundColor: Colors.white,
                  elevation: metronome.isPlaying ? 4 : 2,
                  shadowColor: (metronome.isPlaying ? AppTheme.roseMute : AppTheme.emeraldSafe).withOpacity(0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: Icon(
                  metronome.isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  size: 28,
                ),
                label: Text(
                  metronome.isPlaying ? 'PARAR METRÔNOMO' : 'INICIAR METRÔNOMO',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  metronome.togglePlay();
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildBpmButton(String text, VoidCallback onPressed, {bool isSecondary = false}) {
    return SizedBox(
      width: 48,
      height: 40,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: isSecondary ? Colors.white.withOpacity(0.04) : Colors.white10,
          side: BorderSide(
            color: isSecondary ? Colors.white24 : AppTheme.cardBorder,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onPressed,
        child: Text(
          text,
          style: TextStyle(
            fontSize: isSecondary ? 13 : 15,
            fontWeight: FontWeight.w900,
            color: isSecondary ? Colors.white70 : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildPanSegment({
    required String label,
    required String subtitle,
    required double value,
    required double currentPan,
    required VoidCallback onTap,
  }) {
    final isSelected = (currentPan - value).abs() < 0.1;
    final color = label == 'L'
        ? AppTheme.amberCue
        : (label == 'C' ? AppTheme.primary : AppTheme.emeraldSafe);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.2) : AppTheme.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : AppTheme.cardBorder,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? color : Colors.white54,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.white38,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubdivisionChip(
    String label,
    MetronomeSubdivision sub,
    MetronomeService metronome,
  ) {
    final isSelected = metronome.subdivision == sub;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      selected: isSelected,
      selectedColor: AppTheme.primary,
      backgroundColor: AppTheme.background,
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? AppTheme.primary : AppTheme.cardBorder,
        ),
      ),
      onSelected: (_) => metronome.setSubdivision(sub),
    );
  }
}

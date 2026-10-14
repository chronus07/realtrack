import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stem_track.dart';
import '../services/audio_engine.dart';
import '../theme/app_theme.dart';

class StemFader extends StatelessWidget {
  final StemTrack stem;

  const StemFader({super.key, required this.stem});

  Widget _buildPanButton({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 32,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isSelected ? color : Colors.white24,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.35),
                    blurRadius: 4,
                    spreadRadius: 0.5,
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: isSelected
                ? (color == AppTheme.amberCue ? Colors.black : Colors.white)
                : Colors.white54,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AudioEngine>();

    final isCue = stem.isCue;
    final hasSolo = engine.hasActiveSolo;
    final isSilencedBySolo = hasSolo && !stem.isSolo;
    final primaryTrackColor = isCue ? AppTheme.amberCue : AppTheme.primary;

    return Opacity(
      opacity: isSilencedBySolo ? 0.45 : (stem.isMuted ? 0.65 : 1.0),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.background.withOpacity(0.55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: stem.isSolo
                ? AppTheme.amberCue
                : stem.isMuted
                    ? AppTheme.roseMute.withOpacity(0.4)
                    : (isSilencedBySolo ? Colors.white10 : AppTheme.cardBorder),
            width: stem.isSolo ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Linha 1: Nome da Pista + Badge Tipo + Seletor de PAN [ L ] [ C ] [ R ]
            Row(
              children: [
                // Indicador visual colorido
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: stem.isSolo
                        ? AppTheme.amberCue
                        : (stem.isMuted || isSilencedBySolo ? Colors.white24 : primaryTrackColor),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                // Nome da Pista
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          stem.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: stem.isSolo
                                ? AppTheme.amberCue
                                : (stem.isMuted || isSilencedBySolo
                                    ? Colors.white38
                                    : (isCue ? AppTheme.amberCue : Colors.white)),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: isCue ? AppTheme.amberCue.withOpacity(0.18) : Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isCue ? 'CUE' : 'BANDA',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: isCue ? AppTheme.amberCue : Colors.white54,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (isSilencedBySolo) ...[
                        const SizedBox(width: 4),
                        const Text(
                          '(Solo off)',
                          style: TextStyle(fontSize: 8, color: Colors.white30, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
                ),

              // Controle de PAN
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'PAN ',
                    style: TextStyle(fontSize: 8, color: Colors.white38, fontWeight: FontWeight.bold),
                  ),
                  _buildPanButton(
                    context: context,
                    label: 'L',
                    isSelected: stem.pan <= -0.5,
                    color: AppTheme.amberCue,
                    onTap: () => engine.setStemPan(stem.id, -1.0),
                  ),
                  const SizedBox(width: 2),
                  _buildPanButton(
                    context: context,
                    label: 'C',
                    isSelected: stem.pan > -0.5 && stem.pan < 0.5,
                    color: Colors.blueGrey.shade400,
                    onTap: () => engine.setStemPan(stem.id, 0.0),
                  ),
                  const SizedBox(width: 2),
                  _buildPanButton(
                    context: context,
                    label: 'R',
                    isSelected: stem.pan >= 0.5,
                    color: AppTheme.primary,
                    onTap: () => engine.setStemPan(stem.id, 1.0),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 2),

          // Linha 2: Slider de Volume + Porcentagem + Mute (M) e Solo (S)
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: stem.isMuted ? Colors.white24 : primaryTrackColor,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: stem.isMuted ? Colors.white38 : primaryTrackColor,
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: stem.volume,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (val) => engine.setStemVolume(stem.id, val),
                  ),
                ),
              ),

              // Porcentagem de Volume
              SizedBox(
                width: 32,
                child: Text(
                  '${(stem.volume * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: stem.isMuted ? Colors.white24 : Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
              const SizedBox(width: 8),

              // Botões Mute e Solo
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => engine.toggleMute(stem.id),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 32,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: stem.isMuted ? AppTheme.roseMute : Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: stem.isMuted ? AppTheme.roseMute : Colors.white24,
                          width: stem.isMuted ? 1.5 : 1,
                        ),
                        boxShadow: stem.isMuted
                            ? [
                                BoxShadow(
                                  color: AppTheme.roseMute.withOpacity(0.4),
                                  blurRadius: 4,
                                  spreadRadius: 0.5,
                                )
                              ]
                            : null,
                      ),
                      child: Text(
                        'M',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: stem.isMuted ? Colors.white : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => engine.toggleSolo(stem.id),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 32,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: stem.isSolo ? AppTheme.amberCue : Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: stem.isSolo ? AppTheme.amberCue : Colors.white24,
                          width: stem.isSolo ? 1.5 : 1,
                        ),
                        boxShadow: stem.isSolo
                            ? [
                                BoxShadow(
                                  color: AppTheme.amberCue.withOpacity(0.4),
                                  blurRadius: 4,
                                  spreadRadius: 0.5,
                                )
                              ]
                            : null,
                      ),
                      child: Text(
                        'S',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: stem.isSolo ? Colors.black : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );
  }
}


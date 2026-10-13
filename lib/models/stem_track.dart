enum OutputChannel {
  left,   // Saída L (Cabo Y -> Retorno / In-Ear do baterista)
  right,  // Saída R (Cabo Y -> P.A. / Mesa de som)
  stereo, // Ambos os canais (Modo ensaio no fone de ouvido)
}

class StemTrack {
  final String id;
  final String name;
  final String? filePath;
  final bool isCue; // Se for true (Click/Guia), NUNCA sofre Pitch Shift e vai para o canal L
  double volume;    // 0.0 a 1.0
  bool isMuted;
  bool isSolo;
  OutputChannel outputChannel;

  StemTrack({
    required this.id,
    required this.name,
    this.filePath,
    this.isCue = false,
    this.volume = 0.8,
    this.isMuted = false,
    this.isSolo = false,
    OutputChannel? outputChannel,
  }) : outputChannel = outputChannel ?? (isCue ? OutputChannel.left : OutputChannel.right);

  // Calcula o volume real considerando Solo e Mute
  double getEffectiveVolume(bool anySoloActive) {
    if (isMuted) return 0.0;
    if (anySoloActive && !isSolo) return 0.0;
    return volume;
  }

  StemTrack copyWith({
    String? id,
    String? name,
    String? filePath,
    bool? isCue,
    double? volume,
    bool? isMuted,
    bool? isSolo,
    OutputChannel? outputChannel,
  }) {
    return StemTrack(
      id: id ?? this.id,
      name: name ?? this.name,
      filePath: filePath ?? this.filePath,
      isCue: isCue ?? this.isCue,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      isSolo: isSolo ?? this.isSolo,
      outputChannel: outputChannel ?? this.outputChannel,
    );
  }
}

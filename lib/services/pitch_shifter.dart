class PitchShifterService {
  // Escala cromática padrão (sustenidos e bemóis)
  static const List<String> chromaticSharps = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  static const List<String> chromaticFlats = [
    'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'
  ];

  static const Map<String, String> noteNamesPtBr = {
    'C': 'Dó', 'C#': 'Dó#', 'Db': 'Réb',
    'D': 'Ré', 'D#': 'Ré#', 'Eb': 'Mib',
    'E': 'Mi',
    'F': 'Fá', 'F#': 'Fá#', 'Gb': 'Solb',
    'G': 'Sol', 'G#': 'Sol#', 'Ab': 'Láb',
    'A': 'Lá', 'A#': 'Lá#', 'Bb': 'Sib',
    'B': 'Si'
  };

  /// Converte qualquer nota para o índice de 0 a 11
  static int getNoteIndex(String note) {
    int idx = chromaticSharps.indexOf(note);
    if (idx != -1) return idx;
    return chromaticFlats.indexOf(note);
  }

  /// Transpõe uma nota individual por um número de semitons (-6 a +6)
  static String transposeNote(String note, int semitones, {bool preferSharps = true}) {
    int currentIdx = getNoteIndex(note);
    if (currentIdx == -1) return note; // Não é uma nota reconhecida

    int newIdx = (currentIdx + semitones) % 12;
    if (newIdx < 0) newIdx += 12;

    return preferSharps ? chromaticSharps[newIdx] : chromaticFlats[newIdx];
  }

  /// Retorna o nome amigável em português (ex: "G (Sol)")
  static String getDisplayKey(String note) {
    final pt = noteNamesPtBr[note] ?? note;
    return '$note ($pt)';
  }

  /// Transpõe cifras dentro de um texto completo de cifra
  /// Reconhece padrões como Em7, D/F#, C9, G#m, Bb, etc.
  static String transposeChordSheet(String text, int semitones) {
    if (semitones == 0) return text;

    // Expressão regular para encontrar acordes musicais
    final chordRegex = RegExp(r'\b([A-G][b#]?)([^ \n\r\t\/]*)(\/([A-G][b#]?))?');

    return text.replaceAllMapped(chordRegex, (match) {
      final rootNote = match.group(1)!;
      final chordSuffix = match.group(2) ?? '';
      final bassNote = match.group(4);

      final transposedRoot = transposeNote(rootNote, semitones);
      
      if (bassNote != null) {
        final transposedBass = transposeNote(bassNote, semitones);
        return '$transposedRoot$chordSuffix/$transposedBass';
      }

      return '$transposedRoot$chordSuffix';
    });
  }
}

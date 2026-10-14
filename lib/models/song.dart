import 'stem_track.dart';

class SongSection {
  final String name;       // "Intro", "Verso 1", "Refrão", "Ponte", "Final"
  final double startSeconds;
  final int startBar;

  const SongSection({
    required this.name,
    required this.startSeconds,
    required this.startBar,
  });
}

class Song {
  final String id;
  final String title;
  final String artist;
  final String originalKey;   // ex: "G", "Ab", "D"
  String currentKey;            // Tom transposto atual
  int pitchOffsetSemitones;     // -6 a +6
  final int bpm;
  final String timeSignature;  // "4/4", "6/8"
  final bool isMultiTrack;      // true: stems separados, false: faixa única
  final List<StemTrack> stems;
  final List<SongSection> sections;
  final String chordsText;      // Texto com cifras e letra
  final bool isDownloaded;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.originalKey,
    String? currentKey,
    this.pitchOffsetSemitones = 0,
    required this.bpm,
    this.timeSignature = '4/4',
    this.isMultiTrack = true,
    required this.stems,
    this.sections = const [],
    this.chordsText = '',
    this.isDownloaded = true,
  }) : currentKey = currentKey ?? originalKey;

  Song clone({
    String? currentKey,
    int? pitchOffsetSemitones,
  }) {
    return Song(
      id: id,
      title: title,
      artist: artist,
      originalKey: originalKey,
      currentKey: currentKey ?? this.currentKey,
      pitchOffsetSemitones: pitchOffsetSemitones ?? this.pitchOffsetSemitones,
      bpm: bpm,
      timeSignature: timeSignature,
      isMultiTrack: isMultiTrack,
      stems: stems.map((s) => StemTrack(
        id: s.id,
        name: s.name,
        volume: s.volume,
        isMuted: s.isMuted,
        isSolo: s.isSolo,
        isCue: s.isCue,
        pan: s.pan,
        filePath: s.filePath,
      )).toList(),
      sections: List.from(sections),
      chordsText: chordsText,
      isDownloaded: isDownloaded,
    );
  }
}

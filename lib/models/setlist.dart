import 'song.dart';

class Setlist {
  final String id;
  final String title;
  final DateTime date;
  final List<Song> songs;
  bool isOfflineReady;

  Setlist({
    required this.id,
    required this.title,
    required this.date,
    required this.songs,
    this.isOfflineReady = false,
  });

  int get totalSongs => songs.length;
}

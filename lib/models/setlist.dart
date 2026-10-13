import 'song.dart';

class Setlist {
  final String id;
  String title;
  DateTime date;
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/audio_engine.dart';
import 'theme/app_theme.dart';
import 'screens/setlist_screen.dart';
import 'screens/mixer_screen.dart';
import 'screens/chords_screen.dart';
import 'screens/upload_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AudioEngine()),
      ],
      child: const RealTracksApp(),
    ),
  );
}

class RealTracksApp extends StatelessWidget {
  const RealTracksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RealTracks',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 1; // Inicia no Mixer (Player de Palco)

  void _switchTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      SetlistScreen(onOpenMixer: () => _switchTab(1)),
      const MixerScreen(),
      ChordsScreen(onOpenMixer: () => _switchTab(1)),
      const UploadScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.card,
          border: Border(top: BorderSide(color: AppTheme.cardBorder, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _switchTab,
          backgroundColor: AppTheme.card,
          selectedItemColor: AppTheme.primary,
          unselectedItemColor: Colors.white54,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.playlist_play),
              label: 'Setlists',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.tune),
              label: 'Mixer Palco',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.music_note),
              label: 'Cifras',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.cloud_upload_outlined),
              label: 'Músicas',
            ),
          ],
        ),
      ),
    );
  }
}

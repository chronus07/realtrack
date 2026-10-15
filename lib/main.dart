import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'services/audio_engine.dart';
import 'services/supabase_service.dart';
import 'theme/app_theme.dart';
import 'screens/setlist_screen.dart';
import 'screens/library_screen.dart';
import 'screens/mixer_screen.dart';
import 'screens/chords_screen.dart';
import 'screens/upload_screen.dart';
import 'services/update_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializa o motor de áudio C++ SoLoud de alta performance e baixa latência
  try {
    if (!SoLoud.instance.isInitialized) {
      await SoLoud.instance.init();
      SoLoud.instance.setMaxActiveVoiceCount(128);
      debugPrint('SoLoud C++ Audio Engine inicializado com sucesso (128 vozes ativas).');
    }
  } catch (e) {
    debugPrint('Aviso ao inicializar SoLoud: $e');
  }

  try {
    await SupabaseService.initialize();
  } catch (e) {
    debugPrint('Supabase inicializado em modo offline/demonstração: $e');
  }

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

class _MainNavigationShellState extends State<MainNavigationShell> with WidgetsBindingObserver {
  int _currentIndex = 0; // Inicia na tela de Playlists

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAppUpdates();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Quando o app volta ao primeiro plano no celular, sincroniza imediatamente
      context.read<AudioEngine>().syncFromCloudSilently();
    }
  }

  Future<void> _checkAppUpdates() async {
    // Na Web, o usuário simplesmente recarrega com F5. O aviso de download de APK só é exibido no app Android instalado.
    if (kIsWeb) return;

    final updateInfo = await UpdateService.checkForUpdate();
    if (updateInfo != null && updateInfo.hasUpdate && mounted) {
      UpdateService.showUpdateDialog(context, updateInfo);
    }
  }

  void _switchTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      SetlistScreen(
        onOpenMixer: () => _switchTab(1),
      ),
      const MixerScreen(),
      ChordsScreen(
        onOpenMixer: () => _switchTab(1),
      ),
      LibraryScreen(
        onOpenMixer: () => _switchTab(1),
        onNavigateToUpload: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => UploadScreen(
                onSongSaved: () {
                  Navigator.of(context).pop();
                  context.read<AudioEngine>().syncFromCloudSilently();
                },
              ),
            ),
          );
        },
      ),
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
              label: 'Playlist',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.tune),
              label: 'Player',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.music_note),
              label: 'Cifras',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.library_music_outlined),
              label: 'Acervo',
            ),
          ],
        ),
      ),
    );
  }
}

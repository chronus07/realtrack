import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
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
  
  // Configuração global de áudio: Permite reproduzir 16+ pistas simultâneas sem conflito de foco no Android/iOS
  try {
    await AudioPlayer.global.setAudioContext(
      AudioContextConfig(
        focus: AudioContextConfigFocus.mixWithOthers,
        stayAwake: true,
      ).build(),
    );
  } catch (e) {
    debugPrint('Configuração global de AudioContext: $e');
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
        onOpenMixer: () => _switchTab(2),
        onNavigateToUpload: () => _switchTab(4),
      ),
      LibraryScreen(
        onOpenMixer: () => _switchTab(2),
        onNavigateToUpload: () => _switchTab(4),
      ),
      const MixerScreen(),
      ChordsScreen(
        onOpenMixer: () => _switchTab(2),
      ),
      UploadScreen(
        onSongSaved: () => _switchTab(1), // Ao salvar, vai direto para a aba de Acervo
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
              label: 'Playlists',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.library_music_outlined),
              label: 'Acervo',
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
              label: 'Nova Música',
            ),
          ],
        ),
      ),
    );
  }
}

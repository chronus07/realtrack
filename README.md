# 🎵 RealTracks (v1.0)
**Disparador de Multitracks, Gestor de Repertório e Transpositor de Tom para Bandas**

Aplicativo multiplataforma para **Android, iOS, Tablets e iPads**, projetado especificamente para uso em apresentações ao vivo, cultos e ensaios musicais.

---

## ⚡ Como Funciona a Ligação no Palco (Cabo Y)

```
                     ┌────────────────────────────────────────┐
                     │          RealTracks (Celular/Tablet)   │
                     └───────────────────┬────────────────────┘
                                         │ Cabo Y (1x P2 para 2x P10)
                      ┌──────────────────┴──────────────────┐
                      ▼                                     ▼
      ┌───────────────────────────────┐     ┌────────────────────────────────┐
      │       CANAL ESQUERDO (L)      │     │       CANAL DIREITO (R)        │
      ├───────────────────────────────┤     ├────────────────────────────────┤
      │ • Metrônomo (Click)           │     │ • Pistas da Banda (Pads, Keys) │
      │ • Voz Guia ("Intro, 1, 2, 3") │     │ • Mute/Solo por Instrumento    │
      │ • Sem Pitch Shift (Original)  │     │ • PITCH SHIFT APLICADO (±6 st) │
      ├───────────────────────────────┤     ├────────────────────────────────┤
      │  Destino: In-Ear / Baterista  │     │   Destino: Mesa de Som (P.A.)   │
      └───────────────────────────────┘     └────────────────────────────────┘
```

---

## 📁 Estrutura do Projeto

```
realtracks/
├── .github/workflows/
│   └── build_ios_android.yml   # Compilação simultânea do Android e iOS na nuvem
├── lib/
│   ├── main.dart               # Ponto de entrada e barra de navegação
│   ├── models/
│   │   ├── song.dart           # Modelo de música e seções
│   │   ├── setlist.dart        # Modelo de repertório
│   │   └── stem_track.dart     # Modelo de pista com canais L/R e Mute/Solo
│   ├── services/
│   │   ├── audio_engine.dart   # Motor de áudio, transporte e wakelock de palco
│   │   └── pitch_shifter.dart  # Algoritmo de transposição cromática e cifras
│   ├── screens/
│   │   ├── mixer_screen.dart   # Player de palco com mixer e Split L/R
│   │   ├── setlist_screen.dart # Lista de músicas e download offline
│   │   ├── chords_screen.dart  # Cifras sincronizadas com o tom atual
│   │   └── upload_screen.dart  # Cadastro de músicas (Multitrack vs Faixa Única)
│   ├── widgets/
│   │   ├── pitch_control_bar.dart # Barra de controle do Tom (-6 a +6 semitons)
│   │   ├── stem_fader.dart        # Fader de volume, Mute e Solo por canal
│   │   ├── section_markers.dart   # Pads de salto de seção (Intro, Verso, Refrão)
│   │   └── transport_bar.dart     # Botões de Play/Pause, compasso e tempo
│   └── theme/
│       └── app_theme.dart         # Tema escuro de palco de alto contraste
└── pubspec.yaml                # Dependências do projeto
```

---

## 🚀 Como Executar Localmente

### 1. Instalar o Flutter SDK no Windows
Caso ainda não tenha o Flutter instalado:
1. Baixe o instalador oficial do Flutter em: https://docs.flutter.dev/get-started/install/windows
2. Extraia em `C:\src\flutter` e adicione `C:\src\flutter\bin` nas variáveis de ambiente (PATH).
3. Execute `flutter doctor` no terminal.

### 2. Rodar o App
```bash
cd realtracks
flutter pub get
flutter run
```

---

## 🍏 Como Gerar o App de iOS sem precisar de um Mac

O repositório já inclui um fluxo de trabalho do **GitHub Actions** em `.github/workflows/build_ios_android.yml`:
1. Suba este código para um repositório no seu GitHub.
2. A cada alteração (ou acionamento manual), os servidores em nuvem da Apple e do Ubuntu irão compilar automaticamente:
   * O arquivo **`.apk`** pronto para instalar no Android.
   * O pacote **`.ipa`** pronto para instalar no iPhone/iPad via TestFlight!

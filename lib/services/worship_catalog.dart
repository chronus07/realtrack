class WorshipSongInfo {
  final String title;
  final String artist;
  final String key;
  final int bpm;
  final String timeSignature;

  const WorshipSongInfo({
    required this.title,
    required this.artist,
    required this.key,
    required this.bpm,
    this.timeSignature = '4/4',
  });
}

class WorshipCatalog {
  /// Base de dados de referência dos maiores louvores nacionais e internacionais
  static const List<WorshipSongInfo> songs = [
    // Gabriela Rocha
    WorshipSongInfo(title: 'Me Atraiu', artist: 'Gabriela Rocha', key: 'A', bpm: 125, timeSignature: '4/4'),
    WorshipSongInfo(title: 'A Ele a Glória', artist: 'Gabriela Rocha', key: 'G', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Lugar Secreto', artist: 'Gabriela Rocha', key: 'E', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Diz', artist: 'Gabriela Rocha', key: 'G', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Eu Navegarei', artist: 'Gabriela Rocha', key: 'C', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Atos 2', artist: 'Gabriela Rocha', key: 'E', bpm: 130, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Teu Santo Nome', artist: 'Gabriela Rocha', key: 'G', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Creio em Ti', artist: 'Gabriela Rocha', key: 'C', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Vida Aos Sepulcros', artist: 'Gabriela Rocha', key: 'B', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Leão', artist: 'Gabriela Rocha', key: 'G', bpm: 68, timeSignature: '4/4'),

    // Casa Worship
    WorshipSongInfo(title: 'A Casa É Sua', artist: 'Casa Worship', key: 'G', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Vento Suave', artist: 'Casa Worship', key: 'G', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Era Eu', artist: 'Casa Worship', key: 'D', bpm: 68, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Eu Te Vejo Em Tudo', artist: 'Casa Worship', key: 'D', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Seja Forte', artist: 'Casa Worship', key: 'E', bpm: 70, timeSignature: '4/4'),

    // Isaías Saad
    WorshipSongInfo(title: 'Ousado Amor', artist: 'Isaías Saad', key: 'Bb', bpm: 68, timeSignature: '6/8'),
    WorshipSongInfo(title: 'Bondade de Deus', artist: 'Isaías Saad', key: 'G', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Enche-me', artist: 'Isaías Saad', key: 'C', bpm: 68, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Pra Onde Eu Iria', artist: 'Isaías Saad', key: 'C', bpm: 70, timeSignature: '4/4'),

    // Morada
    WorshipSongInfo(title: 'É Tudo Sobre Você', artist: 'Morada', key: 'G', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Só Tu És Santo', artist: 'Morada', key: 'D', bpm: 68, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Emaús', artist: 'Morada', key: 'G', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Uma Coisa', artist: 'Morada', key: 'D', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Ele É Exaltado', artist: 'Morada', key: 'F', bpm: 120, timeSignature: '4/4'),

    // Laura Souguellis / Rodolfo Abrantes / Livres
    WorshipSongInfo(title: 'Santo Espírito', artist: 'Laura Souguellis', key: 'E', bpm: 76, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Em Teus Braços', artist: 'Laura Souguellis', key: 'E', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Amor Que Enche', artist: 'Laura Souguellis', key: 'C', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Lindo És', artist: 'Juliano Son', key: 'D', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Só Quero Ver Você', artist: 'Laura Souguellis', key: 'D', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Quando o Mundo Cai Ao Meu Redor', artist: 'Juliano Son', key: 'G', bpm: 72, timeSignature: '4/4'),

    // Fernandinho
    WorshipSongInfo(title: 'Todas as Coisas', artist: 'Fernandinho', key: 'C', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Galileu', artist: 'Fernandinho', key: 'E', bpm: 134, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Uma Nova História', artist: 'Fernandinho', key: 'E', bpm: 128, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Grandes Coisas', artist: 'Fernandinho', key: 'B', bpm: 130, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Nada Além do Sangue', artist: 'Fernandinho', key: 'C', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Faz Chover', artist: 'Fernandinho', key: 'G', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Caia Fogo', artist: 'Fernandinho', key: 'G', bpm: 128, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Yeshua', artist: 'Fernandinho', key: 'G', bpm: 72, timeSignature: '4/4'),

    // Gabriel Guedes
    WorshipSongInfo(title: 'Vitorioso És', artist: 'Gabriel Guedes', key: 'C', bpm: 130, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Minhas Guerras', artist: 'Gabriel Guedes', key: 'G', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Santo Pra Sempre', artist: 'Gabriel Guedes', key: 'Bb', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'A Bênção', artist: 'Gabriel Guedes', key: 'B', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Ele Vem', artist: 'Gabriel Guedes', key: 'G', bpm: 128, timeSignature: '4/4'),

    // Samuel Messias / Paulo César Baruk
    WorshipSongInfo(title: 'Todavia Me Alegrarei', artist: 'Samuel Messias', key: 'C', bpm: 68, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Os Planos de Deus', artist: 'Samuel Messias', key: 'G', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Eu Te Agradeço', artist: 'Preto no Branco', key: 'F', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Ninguém Explica Deus', artist: 'Preto no Branco', key: 'G', bpm: 72, timeSignature: '4/4'),

    // Central 3 / Fhop / Alessandro Vilas Boas
    WorshipSongInfo(title: 'Ruja o Leão', artist: 'Central 3', key: 'D', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Para Ti Eu Vou', artist: 'Central 3', key: 'C', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Tudo É Teu', artist: 'Central 3', key: 'E', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Quero Conhecer Jesus', artist: 'Alessandro Vilas Boas', key: 'G', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'O Fogo Nunca Dorme', artist: 'Alessandro Vilas Boas', key: 'D', bpm: 74, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Ser Mudado', artist: 'Alessandro Vilas Boas', key: 'A', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Tu És o Rei', artist: 'Fhop Music', key: 'D', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Colossenses 1', artist: 'Fhop Music', key: 'G', bpm: 72, timeSignature: '4/4'),

    // Isadora Pompeo / Jessé Aguiar / Israel Subirá
    WorshipSongInfo(title: 'Hey Pai', artist: 'Isadora Pompeo', key: 'G', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Como Nunca Antes', artist: 'Isadora Pompeo', key: 'A', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Bênçãos Que Não Têm Fim', artist: 'Isadora Pompeo', key: 'Eb', bpm: 76, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Alívio', artist: 'Jessé Aguiar', key: 'G', bpm: 68, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Me Leva Pra Casa', artist: 'Israel Subirá', key: 'G', bpm: 72, timeSignature: '4/4'),

    // Diante do Trono / Trazendo a Arca / Toque no Altar
    WorshipSongInfo(title: 'Canção do Apocalipse', artist: 'Diante do Trono', key: 'G', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Águas Purificadoras', artist: 'Diante do Trono', key: 'F', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Preciso de Ti', artist: 'Diante do Trono', key: 'F', bpm: 68, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Manancial', artist: 'Diante do Trono', key: 'A', bpm: 68, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Tua Graça Me Basta', artist: 'Toque no Altar', key: 'G', bpm: 68, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Deus de Promessas', artist: 'Toque no Altar', key: 'C', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Olha Pra Mim', artist: 'Toque no Altar', key: 'F', bpm: 68, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Sobre as Águas', artist: 'Trazendo a Arca', key: 'G', bpm: 72, timeSignature: '4/4'),

    // Clássicos Internacionais Traduzidos (Hillsong, Bethel, Elevation)
    WorshipSongInfo(title: 'Way Maker', artist: 'Sinach', key: 'E', bpm: 68, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Caminho no Deserto', artist: 'Soraya Moraes', key: 'E', bpm: 68, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Oceans', artist: 'Hillsong United', key: 'D', bpm: 66, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Onde Meus Pés Podem Falhar', artist: 'Hillsong', key: 'D', bpm: 66, timeSignature: '4/4'),
    WorshipSongInfo(title: 'What a Beautiful Name', artist: 'Hillsong Worship', key: 'D', bpm: 68, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Que Lindo Nome', artist: 'Kemuel', key: 'D', bpm: 68, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Reckless Love', artist: 'Cory Asbury', key: 'Bb', bpm: 68, timeSignature: '6/8'),
    WorshipSongInfo(title: 'Graves Into Gardens', artist: 'Elevation Worship', key: 'B', bpm: 70, timeSignature: '6/8'),
    WorshipSongInfo(title: 'Rattle', artist: 'Elevation Worship', key: 'Eb', bpm: 76, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Ressuscita', artist: 'Elevation Worship', key: 'Eb', bpm: 76, timeSignature: '4/4'),
    WorshipSongInfo(title: 'King of Kings', artist: 'Hillsong Worship', key: 'D', bpm: 68, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Rei dos Reis', artist: 'Hillsong', key: 'D', bpm: 68, timeSignature: '4/4'),
    WorshipSongInfo(title: 'The Blessing', artist: 'Kari Jobe', key: 'B', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Great Are You Lord', artist: 'All Sons & Daughters', key: 'G', bpm: 72, timeSignature: '6/8'),
    WorshipSongInfo(title: 'Build My Life', artist: 'Housefires', key: 'G', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Construir Minha Vida', artist: 'Gabriel Guedes', key: 'G', bpm: 70, timeSignature: '4/4'),
    WorshipSongInfo(title: '10,000 Reasons', artist: 'Matt Redman', key: 'G', bpm: 72, timeSignature: '4/4'),
    WorshipSongInfo(title: 'Goodness of God', artist: 'Bethel Music', key: 'G', bpm: 70, timeSignature: '4/4'),
  ];

  /// Normaliza texto para busca insensível a acentos, pontuações e maiúsculas
  static String normalize(String text) {
    var s = text.toLowerCase().trim();
    // Remove extensões
    s = s.replaceAll(RegExp(r'\.(m4a|wav|mp3|aac|flac)$'), '');
    // Remove numerações iniciais (ex: 01 - me atraiu -> me atraiu)
    s = s.replaceAll(RegExp(r'^\d+[\s_\-.]+'), '');
    // Remove caracteres especiais e acentos comuns
    s = s
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c');
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Busca no catálogo por correspondência exata ou por trecho do título
  static WorshipSongInfo? lookup(String rawText) {
    if (rawText.trim().isEmpty) return null;
    final normalized = normalize(rawText);
    if (normalized.isEmpty) return null;

    // 1. Busca exata
    for (final song in songs) {
      final normSong = normalize(song.title);
      if (normalized == normSong) {
        return song;
      }
    }

    // 2. Busca por contenção (ex: "Me Atraiu Ao Vivo" ou "13 Me Atraiu Click")
    for (final song in songs) {
      final normSong = normalize(song.title);
      if (normalized.contains(normSong) || normSong.contains(normalized)) {
        // Exige pelo menos 4 caracteres de match para evitar falsos positivos
        if (normSong.length >= 4 && normalized.length >= 4) {
          return song;
        }
      }
    }

    return null;
  }

  /// Cifras de referência completas integradas para os louvores mais tocados (0 tokens)
  static String? getBuiltInChords(String rawTitle) {
    final norm = normalize(rawTitle);

    if (norm.contains('me atraiu')) {
      return '''[Intro]
A  D  F#m  E
A  D  F#m  E

[Verso 1]
A                       D
Me atraiu, não deu pra resistir
                   F#m
Foi tudo o que eu ouvi
                E
Foi tudo o que senti
A                     D
Me atraiu, Teu Santo Espírito
               F#m             E
Rasgou todo o abismo e me encontrou aqui

[Refrão]
D               A
Eu tenho fogo em mim
                 E
Que não se apaga mais
            F#m
Pois Teu amor me consumiu
D               A
Eu tenho fogo em mim
                 E
Que queima tudo aqui
        F#m         D
E faz nascer adoração

[Ponte]
D          A
Santo, Santo
           E             F#m
És incomparável em Tua glória
D          A
Santo, Santo
          E
Para sempre reinas''';
    }

    if (norm.contains('casa e sua') || norm.contains('a casa e sua')) {
      return '''[Intro]
G  C  Em  D
G  C  Em  D

[Verso]
G
Essa casa é Sua casa
C
Nós deixamos ela pra Você
Em
Essa casa é Sua casa
D
Nós deixamos ela pra Você
G
Jesus, Jesus

[Refrão]
G
Abre a porta e entra
C
Nós queremos Tua presença
Em
Vem incendiar
D
Este lugar
G
Abre a porta e entra
C
Nós queremos Tua presença
Em             D
Vem fazer morada aqui''';
    }

    if (norm.contains('consagracao') || norm.contains('louvor ao rei')) {
      return '''[Intro]
G  C/G  D/F#  Em  C  D  G

[Verso]
G           D/F#          Em
Ao Rei dos reis consagro tudo o que sou
          C          Am          D
De gratos louvores a Ele a minh'alma transborda
G          D/F#         Em
A minha vida eu entrego em Tuas mãos
         C           D          G
Meu Salvador, meu Senhor e meu Deus

[Refrão]
         C           D        G   D/F#  Em
Pois Teu Reino é de justiça e paz
      C           D       G
Tua glória resplandece em mim
      C           D          G   D/F#  Em
Teu amor derramado em meu coração
      C             D          G
Faz reinar o louvor ao Grande Rei''';
    }

    if (norm.contains('lindo momento')) {
      return '''[Intro]
D  A  Bm  G
D  A  Bm  G

[Verso 1]
D                        A
O Teu amor me encontrou quando eu chorei
Bm                    G
A Tua paz me abraçou quando errei
D                       A
Toda angústia se foi e agora posso crer
Bm                    G
Que Tua graça me basta pra viver

[Refrão]
D
Foi um lindo momento
A
Quando Você me salvou
Bm
Foi um lindo momento
G
Quando Teu amor me alcançou
D              A
Jesus, Jesus, Te amo
Bm             G
Jesus, és tudo pra mim''';
    }

    if (norm.contains('santo pra sempre')) {
      return '''[Intro]
F  Bb  Dm  C
F  Bb  Dm  C

[Verso 1]
F
Mil gerações se prostram em adoração
Bb
Ao Deus que era, que é e sempre há de ser
Dm                          C
E aos anjos que ao redor do trono estão
Bb
Cantando Santo ao Grande Rei

[Refrão]
Bb            Dm
A criação proclama
       C
És o Senhor
Bb             Dm
Tua Igreja canta
         C
És o Salvador
Bb        Dm          C
Santo, Santo és pra sempre
F
Nosso Deus''';
    }

    if (norm.contains('ousado amor')) {
      return '''[Intro]
Gm  F  Eb  Bb

[Verso 1]
Gm             F               Eb
Antes de eu falar, Tu cantavas sobre mim
Gm           F         Eb
Tu tens sido tão, tão bom pra mim
Gm             F               Eb
Antes de eu respirar, sopraste Tua vida em mim
Gm           F         Eb
Tu tens sido tão, tão bom pra mim

[Refrão]
     Gm              F
Oh, impressionante, infinito
      Eb           Bb
E ousado amor de Deus
     Gm               F
Oh, que deixa as noventa e nove
     Eb             Bb
Só pra me encontrar
       Gm              F
Não posso comprá-lo, nem merecê-lo
    Eb          Bb
Mesmo assim se entregou
     Gm              F
Oh, impressionante, infinito
      Eb           Bb
E ousado amor de Deus''';
    }

    return null;
  }
}

const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const axios = require('axios');
const { createClient } = require('@supabase/supabase-js');
const YtDlpWrap = require('yt-dlp-wrap').default || require('yt-dlp-wrap');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Diretório de binários e temporários
const BIN_DIR = path.join(__dirname, 'bin');
const TEMP_DIR = path.join(__dirname, 'temp');

if (!fs.existsSync(BIN_DIR)) fs.mkdirSync(BIN_DIR, { recursive: true });
if (!fs.existsSync(TEMP_DIR)) fs.mkdirSync(TEMP_DIR, { recursive: true });

const ytDlpPath = path.join(BIN_DIR, process.platform === 'win32' ? 'yt-dlp.exe' : 'yt-dlp');
let ytDlp = null;

// Garante que o executável yt-dlp esteja disponível (baixa automaticamente se necessário)
async function ensureYtDlp() {
  if (fs.existsSync('/usr/local/bin/yt-dlp')) {
    console.log('[yt-dlp] Usando binário do sistema: /usr/local/bin/yt-dlp');
    ytDlp = new YtDlpWrap('/usr/local/bin/yt-dlp');
    return;
  }
  if (fs.existsSync(ytDlpPath)) {
    console.log(`[yt-dlp] Binário encontrado em: ${ytDlpPath}`);
    ytDlp = new YtDlpWrap(ytDlpPath);
    return;
  }

  console.log('[yt-dlp] Baixando a versão mais recente do yt-dlp do GitHub...');
  try {
    await YtDlpWrap.downloadFromGithub(ytDlpPath);
    if (process.platform !== 'win32') {
      fs.chmodSync(ytDlpPath, '755');
    }
    console.log('[yt-dlp] Download concluído com sucesso!');
    ytDlp = new YtDlpWrap(ytDlpPath);
  } catch (err) {
    console.error('[yt-dlp] Erro ao baixar yt-dlp:', err.message);
  }
}

// Catálogo básico de detecção de Tom e BPM para louvores e worship
function detectKeyAndBpm(title, artist = '') {
  const norm = `${title} ${artist}`.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');

  if (norm.includes('lindo momento')) return { key: 'E', bpm: 136, timeSignature: '4/4' };
  if (norm.includes('ha um rio') || norm.includes('ha um rio fluindo')) return { key: 'G', bpm: 72, timeSignature: '4/4' };
  if (norm.includes('me atraiu')) return { key: 'D', bpm: 68, timeSignature: '4/4' };
  if (norm.includes('todavia me alegrarei')) return { key: 'Bb', bpm: 70, timeSignature: '4/4' };
  if (norm.includes('bondade de deus')) return { key: 'G', bpm: 70, timeSignature: '4/4' };
  if (norm.includes('a bencao')) return { key: 'Bb', bpm: 70, timeSignature: '4/4' };
  if (norm.includes('vitorioso es')) return { key: 'D', bpm: 76, timeSignature: '4/4' };
  if (norm.includes('ruja o leao')) return { key: 'Em', bpm: 74, timeSignature: '4/4' };
  if (norm.includes('leao e cordeiro') || norm.includes('lion and the lamb')) return { key: 'B', bpm: 74, timeSignature: '4/4' };

  // Detecção via Regex no título (Ex: "Musica - Tom D - 130 BPM")
  const keyMatch = title.match(/\b(tom|tom\s*:|key)\s*([A-G][#b]?m?)\b/i);
  const bpmMatch = title.match(/\b(\d{2,3})\s*(bpm|bpm\b)/i);

  return {
    key: keyMatch ? keyMatch[2].toUpperCase() : 'G',
    bpm: bpmMatch ? parseInt(bpmMatch[1], 10) : 120,
    timeSignature: '4/4',
  };
}

// ==========================================
// ENDPOINT: HEALTH CHECK
// ==========================================
app.get('/health', (req, res) => {
  res.json({
    status: 'online',
    service: 'realtracks-cloud-importer',
    version: '1.0.1',
    ytdlpReady: !!ytDlp,
  });
});

// ==========================================
// ENDPOINT: RESOLVER METADADOS DA URL (YOUTUBE / SPOTIFY)
// ==========================================
app.post('/api/resolve', async (req, res) => {
  try {
    const { url } = req.body;
    if (!url || typeof url !== 'string') {
      return res.status(400).json({ error: 'Parâmetro "url" é obrigatório.' });
    }

    const trimmedUrl = url.trim();

    // 1. CASO SEJA LINK DO SPOTIFY
    if (trimmedUrl.includes('spotify.com')) {
      console.log(`[Resolve] Analisando link Spotify: ${trimmedUrl}`);
      try {
        const oembedRes = await axios.get(`https://open.spotify.com/oembed?url=${encodeURIComponent(trimmedUrl)}`);
        const spotifyData = oembedRes.data;

        let title = spotifyData.title || 'Música Desconhecida';
        let artist = '';
        const thumbnail = spotifyData.thumbnail_url || '';

        // Tenta buscar o artista na descrição oficial da página
        try {
          const pageRes = await axios.get(trimmedUrl, {
            headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' },
          });
          const matchDesc = pageRes.data.match(/<meta property="og:description" content="([^"]+)"/i);
          if (matchDesc) {
            const desc = matchDesc[1];
            const parts = desc.split('·');
            if (parts.length > 0) {
              artist = parts[0].replace(/Ouça [^.]+ no Spotify\./i, '').trim();
            }
          }
        } catch (_) {}

        // Busca o vídeo correspondente no YouTube usando o cliente móvel android para contornar verificações de datacenter
        let resolvedYtUrl = '';
        try {
          const searchQuery = `ytsearch1:${artist ? `${artist} - ` : ''}${title} audio`;
          console.log(`[Resolve] Buscando correspondência no YouTube: "${searchQuery}"`);
          const ytJson = await ytDlp.execPromise([
            searchQuery,
            '--dump-json',
            '--no-warnings',
            '--extractor-args',
            'youtube:player_client=android,ios,web'
          ]);
          const ytInfo = JSON.parse(ytJson);
          resolvedYtUrl = ytInfo.webpage_url;
        } catch (ytErr) {
          console.warn('[Resolve] Busca yt-dlp falhou, usando query direta:', ytErr.message);
          // Fallback de busca no YouTube
          resolvedYtUrl = `https://www.youtube.com/results?search_query=${encodeURIComponent(`${artist} ${title}`)}`;
        }

        const detected = detectKeyAndBpm(title, artist);

        return res.json({
          source: 'spotify',
          title: title,
          artist: artist || 'Artista Desconhecido',
          thumbnail: thumbnail,
          durationSeconds: 240,
          youtubeUrl: resolvedYtUrl,
          detectedKey: detected.key,
          detectedBpm: detected.bpm,
          detectedTimeSignature: detected.timeSignature,
        });
      } catch (err) {
        return res.status(422).json({ error: `Erro ao resolver link do Spotify: ${err.message}` });
      }
    }

    // 2. CASO SEJA LINK DO YOUTUBE
    if (trimmedUrl.includes('youtube.com') || trimmedUrl.includes('youtu.be')) {
      console.log(`[Resolve] Analisando link YouTube: ${trimmedUrl}`);

      let cleanTitle = '';
      let artist = '';
      let thumbnail = '';
      let durationSeconds = 240;

      // 2.1 Usa o YouTube oEmbed oficial (instantâneo, sem rate-limit e sem CAPTCHA de datacenter)
      try {
        const oembedRes = await axios.get(`https://www.youtube.com/oembed?url=${encodeURIComponent(trimmedUrl)}&format=json`);
        cleanTitle = oembedRes.data.title || '';
        artist = oembedRes.data.author_name || '';
        thumbnail = oembedRes.data.thumbnail_url || '';
      } catch (oembedErr) {
        console.warn('[Resolve] oEmbed YouTube falhou:', oembedErr.message);
      }

      // 2.2 Se oEmbed não preencheu, tenta yt-dlp com cliente Android
      if (!cleanTitle) {
        try {
          const ytJson = await ytDlp.execPromise([
            trimmedUrl,
            '--dump-json',
            '--no-warnings',
            '--extractor-args',
            'youtube:player_client=android,ios,web'
          ]);
          const ytInfo = JSON.parse(ytJson);
          cleanTitle = ytInfo.title || '';
          artist = ytInfo.uploader || artist;
          thumbnail = ytInfo.thumbnail || thumbnail;
          durationSeconds = ytInfo.duration || durationSeconds;
        } catch (dumpErr) {
          console.warn('[Resolve] yt-dlp dump falhou:', dumpErr.message);
        }
      }

      // Tenta separar "Artista - Título" se estiver no formato comum
      if (cleanTitle.includes(' - ')) {
        const split = cleanTitle.split(' - ');
        artist = split[0].trim();
        cleanTitle = split.slice(1).join(' - ').trim();
      }

      // Limpa termos como (Official Video), [Audio Oficial], etc.
      cleanTitle = cleanTitle.replace(/\((oficial|official|video|áudio|audio|clipe|lyric)\)/gi, '').trim();

      const detected = detectKeyAndBpm(cleanTitle, artist);

      return res.json({
        source: 'youtube',
        title: cleanTitle || 'Música do YouTube',
        artist: artist || 'Artista',
        thumbnail: thumbnail,
        durationSeconds: durationSeconds,
        youtubeUrl: trimmedUrl,
        detectedKey: detected.key,
        detectedBpm: detected.bpm,
        detectedTimeSignature: detected.timeSignature,
      });
    }

    return res.status(400).json({ error: 'URL não reconhecida. Insira um link válido do YouTube ou Spotify.' });
  } catch (err) {
    console.error('[Resolve Error]:', err);
    res.status(500).json({ error: err.message || 'Falha interna ao analisar a URL.' });
  }
});

// ==========================================
// ENDPOINT: BAIXAR MP3, PROCESSAR E FAZER UPLOAD NO SUPABASE
// ==========================================
app.post('/api/import', async (req, res) => {
  let tempFilePath = null;
  try {
    const {
      youtubeUrl,
      title,
      artist,
      key,
      bpm,
      timeSignature,
      supabaseUrl,
      supabaseKey,
    } = req.body;

    if (!youtubeUrl) {
      return res.status(400).json({ error: 'youtubeUrl é obrigatório.' });
    }

    const finalTitle = (title || 'Nova Música').trim();
    const finalArtist = (artist || '').trim();
    const finalKey = key || 'G';
    const finalBpm = parseInt(bpm, 10) || 120;
    const finalTs = timeSignature || '4/4';

    const targetSbUrl = supabaseUrl || process.env.SUPABASE_URL;
    const targetSbKey = supabaseKey || process.env.SUPABASE_ANON_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!targetSbUrl || !targetSbKey) {
      return res.status(400).json({ error: 'Credenciais do Supabase não informadas.' });
    }

    const supabase = createClient(targetSbUrl, targetSbKey);
    const fileId = `yt_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    const outputPattern = path.join(TEMP_DIR, `${fileId}.%(ext)s`);

    console.log(`[Import] Baixando áudio de "${youtubeUrl}" para converter em MP3...`);

    // Baixa o áudio na melhor qualidade e converte para MP3 192k usando emulação de cliente móvel android/ios
    await ytDlp.execPromise([
      youtubeUrl,
      '-x',
      '--audio-format',
      'mp3',
      '--audio-quality',
      '192K',
      '--no-playlist',
      '--extractor-args',
      'youtube:player_client=android,ios,web',
      '-o',
      outputPattern,
    ]);

    tempFilePath = path.join(TEMP_DIR, `${fileId}.mp3`);
    if (!fs.existsSync(tempFilePath)) {
      throw new Error('O arquivo MP3 resultante não foi encontrado após o download.');
    }

    const fileStats = fs.statSync(tempFilePath);
    console.log(`[Import] Áudio MP3 gerado com sucesso: ${(fileStats.size / 1024 / 1024).toFixed(2)} MB`);

    const fileBuffer = fs.readFileSync(tempFilePath);

    // 1. Criar registro na tabela `songs`
    const { data: songData, error: songErr } = await supabase
      .from('songs')
      .insert({
        title: finalTitle,
        artist: finalArtist,
        original_key: finalKey,
        bpm: finalBpm,
        time_signature: finalTs,
        is_multitrack: false,
        chords_text: '',
      })
      .select()
      .single();

    if (songErr) throw songErr;

    const songId = songData.id;
    const safeStemFileName = `${finalTitle.toLowerCase().replace(/[^a-z0-9]/g, '_')}_playback.mp3`;
    const storagePath = `songs/${songId}/${safeStemFileName}`;

    console.log(`[Import] Fazendo upload para o Supabase Storage em: ${storagePath}...`);

    // 2. Upload para o bucket `audio-tracks`
    const { error: uploadErr } = await supabase.storage
      .from('audio-tracks')
      .upload(storagePath, fileBuffer, {
        contentType: 'audio/mpeg',
        upsert: true,
      });

    if (uploadErr) {
      await supabase.from('songs').delete().eq('id', songId);
      throw uploadErr;
    }

    // 3. Criar a pista única (single track) na tabela `stems`
    const { data: stemData, error: stemErr } = await supabase
      .from('stems')
      .insert({
        song_id: songId,
        name: finalTitle.toUpperCase(),
        file_path: storagePath,
        volume: 0.85,
        pan: 0.0, // Centralizado no C (Centro)
        is_cue: false,
      })
      .select()
      .single();

    if (stemErr) {
      console.warn('[Import Warning] Erro ao cadastrar stem:', stemErr);
    }

    console.log(`[Import] ✅ Música "${finalTitle}" salva com sucesso no Acervo (ID: ${songId})!`);

    res.json({
      success: true,
      songId: songId,
      song: {
        ...songData,
        stems: stemData ? [stemData] : [],
      },
    });
  } catch (err) {
    console.error('[Import Error]:', err);
    res.status(500).json({ error: err.message || 'Falha ao importar e salvar no Supabase.' });
  } finally {
    if (tempFilePath && fs.existsSync(tempFilePath)) {
      try {
        fs.unlinkSync(tempFilePath);
      } catch (_) {}
    }
  }
});

// Inicialização
ensureYtDlp().then(() => {
  app.listen(PORT, () => {
    console.log(`🚀 RealTracks Cloud Importer rodando na porta ${PORT}`);
  });
});

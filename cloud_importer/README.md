# 🚀 RealTracks Cloud Importer (YouTube & Spotify to Supabase)

Microserviço em nuvem de alta velocidade para o **RealTracks**. Permite colar qualquer link de música do **YouTube** ou do **Spotify**, extrair o áudio na melhor fidelidade, convertê-lo em MP3 (192 kbps), auto-detectar Tom e BPM e salvar automaticamente no bucket do Supabase `audio-tracks` e no catálogo de músicas (`songs`).

---

## ⚡ Como Rodar Localmente (no seu computador)

1. Abra a pasta `cloud_importer` no terminal:
   ```bash
   cd cloud_importer
   ```
2. Instale as dependências:
   ```bash
   npm install
   ```
3. Inicie o servidor:
   ```bash
   npm start
   ```
   *O script baixará o binário do `yt-dlp` automaticamente no primeiro uso.*
4. O servidor iniciará em `http://localhost:3000`.

---

## ☁️ Como Fazer Deploy Gratuito na Nuvem (Render.com)

Você pode hospedar este serviço gratuitamente no **Render.com** com suporte a Docker:

1. Acesse **[Render.com](https://render.com)** e crie uma conta gratuita.
2. Clique em **New +** -> **Web Service**.
3. Conecte o repositório GitHub do RealTracks.
4. Selecione:
   - **Root Directory:** `cloud_importer`
   - **Runtime:** `Docker`
   - **Instance Type:** `Free`
5. Clique em **Create Web Service**.
6. Assim que o deploy finalizar, o Render fornecerá uma URL pública (ex: `https://realtracks-importer.onrender.com`).
7. Copie essa URL e cole no aplicativo RealTracks na tela de **Upload por Link**!

---

## 📡 Endpoints da API

### `GET /health`
Verifica se o serviço e o motor `yt-dlp` estão online.

### `POST /api/resolve`
Analisa a URL do YouTube ou Spotify e extrai os metadados (Título, Artista, Tom detectado, BPM, Capa e Duração).
```json
{
  "url": "https://open.spotify.com/track/..."
}
```

### `POST /api/import`
Baixa o áudio, converte para MP3 192k e salva diretamente no seu Supabase:
```json
{
  "youtubeUrl": "https://www.youtube.com/watch?v=...",
  "title": "Lindo Momento",
  "artist": "Julliany Souza",
  "key": "E",
  "bpm": 136,
  "timeSignature": "4/4",
  "supabaseUrl": "https://seu-projeto.supabase.co",
  "supabaseKey": "sua-anon-key"
}
```

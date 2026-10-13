-- ==============================================================
-- REALTRACKS - SUPABASE DATABASE SCHEMA (100% GRATUITO)
-- Execute este script no SQL Editor do seu projeto Supabase
-- ==============================================================

-- 1. Tabela de Bandas / Grupos de Louvor
CREATE TABLE IF NOT EXISTS public.bands (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Inserir uma banda padrão para uso imediato
INSERT INTO public.bands (id, name)
VALUES ('00000000-0000-0000-0000-000000000000', 'Minha Banda')
ON CONFLICT (id) DO NOTHING;

-- 2. Tabela de Integrantes da Banda
CREATE TABLE IF NOT EXISTS public.band_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    band_id UUID REFERENCES public.bands(id) ON DELETE CASCADE,
    user_id UUID,
    role TEXT DEFAULT 'leader',
    instrument TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 3. Tabela do Acervo de Músicas (Master Song Library)
CREATE TABLE IF NOT EXISTS public.songs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    band_id UUID DEFAULT '00000000-0000-0000-0000-000000000000',
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    original_key TEXT NOT NULL,
    bpm INTEGER NOT NULL,
    time_signature TEXT DEFAULT '4/4',
    is_multitrack BOOLEAN DEFAULT true,
    chords_text TEXT DEFAULT '',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 4. Tabela de Pistas / Stems de Áudio
CREATE TABLE IF NOT EXISTS public.song_stems (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    song_id UUID REFERENCES public.songs(id) ON DELETE CASCADE,
    name TEXT NOT NULL,                -- 'CLICK', 'GUIA', 'PAD', 'TECLADOS', etc.
    is_cue BOOLEAN DEFAULT false,      -- true = Click/Guia (Saída L, sem pitch shift)
    storage_path TEXT NOT NULL,        -- Caminho no bucket de áudio
    file_size_bytes BIGINT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 5. Tabela de Repertórios / Playlists Semanais
CREATE TABLE IF NOT EXISTS public.setlists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    band_id UUID DEFAULT '00000000-0000-0000-0000-000000000000',
    title TEXT NOT NULL,
    event_date TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 6. Tabela de Associação: Músicas na Playlist
CREATE TABLE IF NOT EXISTS public.setlist_songs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    setlist_id UUID REFERENCES public.setlists(id) ON DELETE CASCADE,
    song_id UUID REFERENCES public.songs(id) ON DELETE CASCADE,
    order_index INTEGER NOT NULL,
    custom_key TEXT,
    pitch_offset INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- ==============================================================
-- POLÍTICAS DE ACESSO (RLS PERMISSIVO PARA O APP DA BANDA)
-- Permite leitura e gravação imediatas pela chave pública do app
-- ==============================================================
ALTER TABLE public.bands ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.songs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.song_stems ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.setlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.setlist_songs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Permitir leitura de bandas" ON public.bands FOR SELECT USING (true);
CREATE POLICY "Permitir insercao de bandas" ON public.bands FOR INSERT WITH CHECK (true);

CREATE POLICY "Permitir leitura do acervo de musicas" ON public.songs FOR SELECT USING (true);
CREATE POLICY "Permitir insercao no acervo de musicas" ON public.songs FOR INSERT WITH CHECK (true);
CREATE POLICY "Permitir exclusao no acervo de musicas" ON public.songs FOR DELETE USING (true);

CREATE POLICY "Permitir leitura de pistas" ON public.song_stems FOR SELECT USING (true);
CREATE POLICY "Permitir insercao de pistas" ON public.song_stems FOR INSERT WITH CHECK (true);
CREATE POLICY "Permitir exclusao de pistas" ON public.song_stems FOR DELETE USING (true);

CREATE POLICY "Permitir leitura de playlists" ON public.setlists FOR SELECT USING (true);
CREATE POLICY "Permitir insercao de playlists" ON public.setlists FOR INSERT WITH CHECK (true);
CREATE POLICY "Permitir exclusao de playlists" ON public.setlists FOR DELETE USING (true);

CREATE POLICY "Permitir leitura de musicas na playlist" ON public.setlist_songs FOR SELECT USING (true);
CREATE POLICY "Permitir insercao de musicas na playlist" ON public.setlist_songs FOR INSERT WITH CHECK (true);
CREATE POLICY "Permitir exclusao de musicas na playlist" ON public.setlist_songs FOR DELETE USING (true);

-- Bucket de Armazenamento para os Áudios
INSERT INTO storage.buckets (id, name, public) 
VALUES ('audio-tracks', 'audio-tracks', true)
ON CONFLICT (id) DO NOTHING;

-- Políticas de Storage para o Bucket audio-tracks
CREATE POLICY "Permitir upload de audios" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'audio-tracks');
CREATE POLICY "Permitir leitura de audios" ON storage.objects FOR SELECT USING (bucket_id = 'audio-tracks');

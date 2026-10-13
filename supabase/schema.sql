-- ==============================================================
-- REALTRACKS - SUPABASE COMPLETO & 100% GRATUITO
-- Execute este script no SQL Editor do seu projeto Supabase:
-- https://supabase.com/dashboard/project/mkafhbwuzbvbusdavwdo/sql
-- ==============================================================

-- 1. Tabela de Bandas / Grupos de Louvor
CREATE TABLE IF NOT EXISTS public.bands (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

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
-- POLÍTICAS DE ACESSO (RLS PERMISSIVO TOTAL PARA O APP DA BANDA)
-- Permite leitura e gravação imediatas pela chave anônima da banda
-- ==============================================================
ALTER TABLE public.bands ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.songs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.song_stems ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.setlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.setlist_songs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Acesso publico bandas" ON public.bands;
CREATE POLICY "Acesso publico bandas" ON public.bands FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acesso publico musicas" ON public.songs;
CREATE POLICY "Acesso publico musicas" ON public.songs FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acesso publico pistas" ON public.song_stems;
CREATE POLICY "Acesso publico pistas" ON public.song_stems FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acesso publico playlists" ON public.setlists;
CREATE POLICY "Acesso publico playlists" ON public.setlists FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Acesso publico itens playlist" ON public.setlist_songs;
CREATE POLICY "Acesso publico itens playlist" ON public.setlist_songs FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- ==============================================================
-- BUCKET DE ARMAZENAMENTO PARA OS ÁUDIOS (audio-tracks)
-- ==============================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) 
VALUES ('audio-tracks', 'audio-tracks', true, 104857600, null)
ON CONFLICT (id) DO UPDATE SET public = true;

DROP POLICY IF EXISTS "Permitir upload de audios" ON storage.objects;
DROP POLICY IF EXISTS "Permitir leitura de audios" ON storage.objects;
DROP POLICY IF EXISTS "Permitir update de audios" ON storage.objects;
DROP POLICY IF EXISTS "Permitir exclusao de audios" ON storage.objects;

CREATE POLICY "Permitir upload de audios" ON storage.objects 
FOR INSERT TO anon, authenticated 
WITH CHECK (bucket_id = 'audio-tracks');

CREATE POLICY "Permitir leitura de audios" ON storage.objects 
FOR SELECT TO anon, authenticated 
USING (bucket_id = 'audio-tracks');

CREATE POLICY "Permitir update de audios" ON storage.objects 
FOR UPDATE TO anon, authenticated 
USING (bucket_id = 'audio-tracks');

CREATE POLICY "Permitir exclusao de audios" ON storage.objects 
FOR DELETE TO anon, authenticated 
USING (bucket_id = 'audio-tracks');

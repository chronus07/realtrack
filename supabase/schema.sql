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

-- 2. Tabela de Integrantes da Banda (Controle de Acesso Privado)
CREATE TABLE IF NOT EXISTS public.band_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    band_id UUID REFERENCES public.bands(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'musician' CHECK (role IN ('leader', 'musician')),
    instrument TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(band_id, user_id)
);

-- 3. Tabela de Músicas
CREATE TABLE IF NOT EXISTS public.songs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    band_id UUID REFERENCES public.bands(id) ON DELETE CASCADE,
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

-- 5. Tabela de Repertórios / Setlists
CREATE TABLE IF NOT EXISTS public.setlists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    band_id UUID REFERENCES public.bands(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    event_date TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 6. Tabela de Associação: Músicas na Setlist (Ordem e Tom Específico da Noite)
CREATE TABLE IF NOT EXISTS public.setlist_songs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    setlist_id UUID REFERENCES public.setlists(id) ON DELETE CASCADE,
    song_id UUID REFERENCES public.songs(id) ON DELETE CASCADE,
    order_index INTEGER NOT NULL,
    custom_key TEXT,                   -- Tom transposto específico para esta noite (ex: se o líder mudou)
    pitch_offset INTEGER DEFAULT 0,    -- Semitons (-6 a +6)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- ==============================================================
-- SEGURANÇA E PRIVACIDADE (ROW LEVEL SECURITY - RLS)
-- Apenas os integrantes da banda podem ver e baixar o conteúdo!
-- ==============================================================
ALTER TABLE public.bands ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.band_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.songs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.song_stems ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.setlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.setlist_songs ENABLE ROW LEVEL SECURITY;

-- Política de leitura: o músico só vê se pertencer à banda
CREATE POLICY "Membros da banda podem ler suas bandas" 
    ON public.bands FOR SELECT 
    USING (id IN (SELECT band_id FROM public.band_members WHERE user_id = auth.uid()));

CREATE POLICY "Membros da banda podem ler as músicas" 
    ON public.songs FOR SELECT 
    USING (band_id IN (SELECT band_id FROM public.band_members WHERE user_id = auth.uid()));

CREATE POLICY "Membros da banda podem ler as pistas de áudio" 
    ON public.song_stems FOR SELECT 
    USING (song_id IN (
        SELECT id FROM public.songs WHERE band_id IN (
            SELECT band_id FROM public.band_members WHERE user_id = auth.uid()
        )
    ));

CREATE POLICY "Membros da banda podem ler as setlists" 
    ON public.setlists FOR SELECT 
    USING (band_id IN (SELECT band_id FROM public.band_members WHERE user_id = auth.uid()));

CREATE POLICY "Membros da banda podem ler as músicas da setlist" 
    ON public.setlist_songs FOR SELECT 
    USING (setlist_id IN (
        SELECT id FROM public.setlists WHERE band_id IN (
            SELECT band_id FROM public.band_members WHERE user_id = auth.uid()
        )
    ));

-- Bucket de Armazenamento para os Áudios
INSERT INTO storage.buckets (id, name, public) 
VALUES ('audio-tracks', 'audio-tracks', true)
ON CONFLICT (id) DO NOTHING;

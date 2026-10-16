class AppConfig {
  // Substitua com as credenciais do seu projeto gratuito no Supabase
  // (Encontradas em: Project Settings -> API)
  static const String supabaseUrl = 'https://mkafhbwuzbvbusdavwdo.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_N8OL_UH-CxwsPdsf4ZiQGQ_mK0PoV1j';

  // Nome do bucket onde ficam os arquivos de áudio (.m4a / .mp3)
  static const String audioBucketName = 'audio-tracks';

  // Chave de API opcional do Google Gemini para geração automática de cifras
  static String geminiApiKey = '';

  // URL do serviço na nuvem RealTracks Cloud Importer (YouTube / Spotify)
  // Pode ser o localhost durante testes locais ou a URL do Render/Railway em produção
  static String cloudImporterUrl = 'http://localhost:3000';

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      !supabaseUrl.contains('SUA-URL');
}

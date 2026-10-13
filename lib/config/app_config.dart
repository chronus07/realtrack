class AppConfig {
  // Substitua com as credenciais do seu projeto gratuito no Supabase
  // (Encontradas em: Project Settings -> API)
  static const String supabaseUrl = 'https://SUA-URL-DO-SUPABASE.supabase.co';
  static const String supabaseAnonKey = 'SUA-ANON-PUBLIC-KEY-AQUI';

  // Nome do bucket onde ficam os arquivos de áudio (.m4a / .mp3)
  static const String audioBucketName = 'audio-tracks';

  static bool get isConfigured =>
      supabaseUrl != 'https://SUA-URL-DO-SUPABASE.supabase.co' &&
      supabaseAnonKey != 'SUA-ANON-PUBLIC-KEY-AQUI';
}

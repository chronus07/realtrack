import 'web_audio_helper_stub.dart'
    if (dart.library.html) 'web_audio_helper_web.dart';

void ensureWebAudioUnlocked() {
  triggerWebAudioUnlock();
}

import 'package:audioplayers/audioplayers.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();

  // Play the siren and LOOP it forever
  Future<void> playSiren() async {
    // Ensure the player is reset
    await _player.stop();
    
    // Set to LOOP mode
    await _player.setReleaseMode(ReleaseMode.loop);
    
    // Play a built-in screeching sound (or add your own mp3 to assets)
    // We use a high-pitch frequency sound for maximum alert
    await _player.setSource(AssetSource('siren.mp3')); 
    // NOTE: If you don't have an mp3, we can generate a tone, 
    // but for now, ensure you have a 'siren.mp3' in assets OR use a URL:
    // await _player.play(UrlSource('https://www.soundjay.com/mechanical/sounds/smoke-detector-1.mp3'));
    await _player.resume();
  }

  Future<void> stopSiren() async {
    await _player.stop();
    await _player.setReleaseMode(ReleaseMode.stop); // Turn off loop
  }
}
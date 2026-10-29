import 'package:speech_to_text/speech_to_text.dart';

abstract interface class VoiceInput {
  Future<bool> initialize({
    required void Function(String) onStatus,
    required void Function() onError,
  });

  Future<List<String>> availableLocales();
  Future<void> listen({
    required String localeId,
    required void Function(String) onWords,
  });
  Future<void> stop();
}

class DeviceVoiceInput implements VoiceInput {
  factory DeviceVoiceInput() => _instance;
  DeviceVoiceInput._();

  static final DeviceVoiceInput _instance = DeviceVoiceInput._();
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  void Function(String)? _onStatus;
  void Function()? _onError;

  @override
  Future<bool> initialize({
    required void Function(String) onStatus,
    required void Function() onError,
  }) async {
    _onStatus = onStatus;
    _onError = onError;
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onStatus: (status) => _onStatus?.call(status),
      onError: (_) => _onError?.call(),
    );
    return _initialized;
  }

  @override
  Future<List<String>> availableLocales() async =>
      (await _speech.locales()).map((locale) => locale.localeId).toList();

  @override
  Future<void> listen({
    required String localeId,
    required void Function(String) onWords,
  }) =>
      _speech.listen(
        listenOptions: SpeechListenOptions(localeId: localeId),
        onResult: (result) => onWords(result.recognizedWords),
      );

  @override
  Future<void> stop() => _speech.stop();
}

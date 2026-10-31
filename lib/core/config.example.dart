/// Copy this file to `config.dart` (gitignored) and fill in your own keys.
class AppConfig {
  AppConfig._();

  static const String huggingFaceToken = 'YOUR_HUGGING_FACE_TOKEN';

  static bool get hasHuggingFaceToken =>
      huggingFaceToken.isNotEmpty && !huggingFaceToken.startsWith('YOUR_');

  static const String geminiApiKey = 'YOUR_GEMINI_API_KEY';

  static bool get hasGeminiKey =>
      geminiApiKey.isNotEmpty && !geminiApiKey.startsWith('YOUR_');
}

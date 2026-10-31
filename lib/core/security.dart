/// Security utilities — input sanitization and validation.
/// Prevents malformed data from entering the database.
library;

class SecurityUtils {
  SecurityUtils._();

  static const int maxTitleLength = 80;
  static const int maxNotesLength = 500;
  static const int maxEmailLength = 254;

  /// Strips control characters, trims whitespace, and enforces length.
  /// Safe for Firestore field values and UI display.
  static String sanitizeText(String input, {int maxLength = maxTitleLength}) {
    final cleaned = input
        .trim()
        // Remove ASCII control chars (except newline/tab which are fine in notes)
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
        // Collapse multiple spaces
        .replaceAll(RegExp(r'  +'), ' ');

    return cleaned.length > maxLength
        ? cleaned.substring(0, maxLength)
        : cleaned;
  }

  static String sanitizeTitle(String input) =>
      sanitizeText(input, maxLength: maxTitleLength);

  static String sanitizeNotes(String input) =>
      sanitizeText(input, maxLength: maxNotesLength);

  /// Basic email format check. Firebase Auth does the real validation —
  /// this is just a fast client-side guard before sending network requests.
  static bool isValidEmail(String email) {
    final e = email.trim();
    if (e.isEmpty || e.length > maxEmailLength) return false;
    return RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$')
        .hasMatch(e);
  }

  /// Returns a safe display version of a Firebase error message.
  /// Prevents internal implementation details leaking to users.
  static String friendlyAuthError(String? rawMessage) {
    if (rawMessage == null) return 'Something went wrong. Please try again.';
    final lower = rawMessage.toLowerCase();
    if (lower.contains('email-already-in-use')) return 'This email is already registered.';
    if (lower.contains('user-not-found') || lower.contains('wrong-password') || lower.contains('invalid-credential')) {
      return 'Incorrect email or password.';
    }
    if (lower.contains('too-many-requests')) return 'Too many attempts. Please wait a moment.';
    if (lower.contains('network')) return 'Check your internet connection and try again.';
    if (lower.contains('weak-password')) return 'Password must be at least 6 characters.';
    return 'Something went wrong. Please try again.';
  }
}

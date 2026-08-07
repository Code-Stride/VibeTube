/// Small text helpers shared by the avatar placeholders.
library;

/// Returns the first *user-perceived* character of [name], uppercased.
///
/// `name[0]` indexes UTF-16 code units, so a channel whose name starts with an
/// emoji or any non-BMP character (🎵, 𝕏, many Devanagari ligature forms with
/// combining marks) yielded a lone surrogate — rendered as a tofu box in the
/// circular avatars on the player, the video cards and the Shorts overlay.
/// Taking a full rune and carrying its combining marks along fixes that.
String initialLetter(String name, {String fallback = 'V'}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return fallback;

  final runes = trimmed.runes.toList();
  if (runes.isEmpty) return fallback;

  // Keep any combining marks that belong to the first base character.
  var end = 1;
  while (end < runes.length && _isCombining(runes[end])) {
    end++;
  }

  final first = String.fromCharCodes(runes.sublist(0, end));
  final upper = first.toUpperCase();
  return upper.isEmpty ? fallback : upper;
}

/// Unicode combining / variation-selector ranges that must stay attached to
/// the preceding base character.
bool _isCombining(int rune) =>
    (rune >= 0x0300 && rune <= 0x036F) || // combining diacritical marks
    (rune >= 0x0900 && rune <= 0x0903) || // Devanagari signs
    (rune >= 0x093A && rune <= 0x094F) || // Devanagari vowel signs / virama
    (rune >= 0x0951 && rune <= 0x0957) ||
    (rune >= 0x1AB0 && rune <= 0x1AFF) ||
    (rune >= 0x20D0 && rune <= 0x20FF) ||
    (rune >= 0xFE00 && rune <= 0xFE0F) || // variation selectors
    (rune >= 0xFE20 && rune <= 0xFE2F) ||
    rune == 0x200D; // zero-width joiner (emoji sequences)

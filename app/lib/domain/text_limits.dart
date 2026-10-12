/// Corta [text] em no máximo [maxUnits] unidades UTF-16 (a conta do
/// `size()` das Security Rules) sem quebrar um caractere: um emoji fora do
/// BMP (par substituto) que não cabe inteiro sai todo. Espaços nas pontas do
/// resultado são aparados.
String truncateUtf16(String text, int maxUnits) {
  if (text.length <= maxUnits) return text;
  final out = StringBuffer();
  var used = 0;
  for (final rune in text.runes) {
    final size = rune > 0xFFFF ? 2 : 1;
    if (used + size > maxUnits) break;
    out.writeCharCode(rune);
    used += size;
  }
  return out.toString().trim();
}

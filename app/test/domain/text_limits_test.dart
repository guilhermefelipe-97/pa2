import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/text_limits.dart';

void main() {
  test('cabe: igual', () {
    expect(truncateUtf16('Bar do Zé', 120), 'Bar do Zé');
  });

  test('emoji na posição 120 não é partido ao meio', () {
    final s = '${'x' * 119}😀resto';
    final cut = truncateUtf16(s, 120);
    expect(cut, 'x' * 119);
    expect(cut.length, 119);
    // Nenhum substituto solto.
    expect(cut.codeUnits.any((c) => c >= 0xD800 && c <= 0xDFFF), isFalse);
  });

  test('emoji que cabe inteiro fica', () {
    final s = '${'x' * 118}😀resto';
    expect(truncateUtf16(s, 120), '${'x' * 118}😀');
  });
}

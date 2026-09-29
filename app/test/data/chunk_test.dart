import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/chunk.dart';

void main() {
  test('lista vazia gera nenhum lote', () {
    expect(chunked(<int>[], 30), isEmpty);
  });

  test('até 30 cabe em um lote', () {
    expect(chunked(List.generate(30, (i) => i), 30), hasLength(1));
  });

  test('31 vira 30 + 1; 65 vira 30 + 30 + 5', () {
    expect(chunked(List.generate(31, (i) => i), 30).map((b) => b.length), [30, 1]);
    expect(chunked(List.generate(65, (i) => i), 30).map((b) => b.length), [30, 30, 5]);
  });

  test('preserva todos os itens na ordem', () {
    final items = List.generate(65, (i) => 'u$i');
    expect(chunked(items, 30).expand((b) => b), items);
  });

  test('size inválido', () {
    expect(() => chunked([1], 0), throwsArgumentError);
  });
}

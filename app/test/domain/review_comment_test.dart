import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/review.dart';
import 'package:naarea/domain/models/scores.dart';

NewReview _newReview(String? comment) => NewReview(
  authorId: 'a',
  authorName: 'Ana',
  placeId: 'p',
  placeName: 'P',
  scores: Scores(food: 4, ambience: 4, service: 4),
  comment: comment,
);

void main() {
  group('Review.normalizeComment', () {
    test('null, vazio e só espaços viram null', () {
      expect(Review.normalizeComment(null), isNull);
      expect(Review.normalizeComment(''), isNull);
      expect(Review.normalizeComment('   \n\t '), isNull);
    });

    test('apara espaços das pontas e preserva o meio', () {
      expect(
        Review.normalizeComment('  Camarão top,  fila grande. \n'),
        'Camarão top,  fila grande.',
      );
    });
  });

  group('Review.isCommentWithinLimit (mesma contagem das Rules: UTF-16)', () {
    test('até 280 ok, 281 não', () {
      expect(Review.isCommentWithinLimit('x' * 280), isTrue);
      expect(Review.isCommentWithinLimit('x' * 281), isFalse);
    });

    test('acentos contam 1; emoji fora do BMP conta 2', () {
      expect(Review.isCommentWithinLimit('ã' * 280), isTrue);
      expect(Review.isCommentWithinLimit('😀' * 140), isTrue);
      expect(Review.isCommentWithinLimit('😀' * 141), isFalse);
    });

    test(
      'espaços nas pontas não contam (o limite vale para o texto aparado)',
      () {
        expect(Review.isCommentWithinLimit('  ${'x' * 280}  '), isTrue);
      },
    );

    test('sem comentário está dentro do limite', () {
      expect(Review.isCommentWithinLimit(null), isTrue);
      expect(Review.isCommentWithinLimit('   '), isTrue);
    });
  });

  group('NewReview.comment', () {
    test('é normalizado na criação', () {
      expect(_newReview(null).comment, isNull);
      expect(_newReview('  ').comment, isNull);
      expect(_newReview(' Vale a pena ').comment, 'Vale a pena');
    });
  });
}

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/repositories/privacy_repository.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/ui/review/review_view_model.dart';
import 'package:naarea/ui/visit/visit_view_model.dart';
import '../support/fakes.dart';

class _Privacy implements PrivacyRepository {
  final read = Completer<bool>();
  @override
  Future<bool> silentDefault(String uid) => read.future;
  @override
  Future<void> setSilentDefault(String uid, bool value) async {}
}

void main() {
  const place = Place(
    id: 'p',
    name: 'Local',
    category: 'Bar',
    neighborhood: '',
    city: '',
  );
  test(
    'Padrão TRUE salvo segue automaticamente na REVIEW e VISIT sem toque no switch',
    () async {
      final auth = FakeAuthRepository(uid: 'a');
      final users = FakeUserRepository()..addUser('a', 'Ana');
      final privacy = _Privacy()..read.complete(true);
      final reviews = FakeReviewRepository();
      final visits = FakeVisitRepository();
      final review = ReviewViewModel(
        place: place,
        authRepository: auth,
        userRepository: users,
        reviewRepository: reviews,
        photoPicker: FakePhotoPicker(),
        compress: (b) async => b,
        privacyRepository: privacy,
      )..setFood(4);
      final visit = VisitViewModel(
        place: place,
        authRepository: auth,
        userRepository: users,
        visitRepository: visits,
        privacyRepository: privacy,
      );
      await review.checkLock();
      await visit.checkLock();
      expect(await review.submit(), true);
      expect(await visit.submit(), true);
      expect(reviews.created.single.silent, true);
      expect(visits.created.single.silent, true);
      review.dispose();
      visit.dispose();
    },
  );
  test(
    'Visita: escolha explícita vence preferência tardia; envio mantém silent',
    () async {
      final privacy = _Privacy();
      final visits = FakeVisitRepository();
      final auth = FakeAuthRepository(uid: 'a');
      final users = FakeUserRepository()..addUser('a', 'Ana');
      final vm = VisitViewModel(
        place: place,
        authRepository: auth,
        userRepository: users,
        visitRepository: visits,
        privacyRepository: privacy,
      );
      final pending = vm.checkLock();
      expect(vm.canSubmit, false);
      vm.setSilent(true);
      privacy.read.complete(false);
      await pending;
      expect(vm.silent, true);
      expect(await vm.submit(), true);
      expect(visits.created.single.silent, true);
      vm.dispose();
    },
  );
  test(
    'Avaliação: preferência tardia não sobrescreve escolha; troca de conta impede envio',
    () async {
      final privacy = _Privacy();
      final reviews = FakeReviewRepository();
      final auth = FakeAuthRepository(uid: 'a');
      final users = FakeUserRepository()..addUser('a', 'Ana');
      final vm = ReviewViewModel(
        place: place,
        authRepository: auth,
        userRepository: users,
        reviewRepository: reviews,
        photoPicker: FakePhotoPicker(),
        compress: (bytes) async => bytes,
        privacyRepository: privacy,
      );
      vm.setFood(4);
      final pending = vm.checkLock(showProgress: false);
      vm.setSilent(true);
      privacy.read.complete(false);
      await pending;
      expect(vm.silent, true);
      auth.restoreSession('b');
      expect(await vm.submit(), false);
      expect(reviews.created, isEmpty);
      vm.dispose();
    },
  );
}

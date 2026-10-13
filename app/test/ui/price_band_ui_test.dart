import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/price_band.dart';
import 'package:naarea/domain/price_summary.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/core/follow_events.dart';
import 'package:naarea/ui/core/price_band_picker.dart';
import 'package:naarea/ui/nearby/nearby_view.dart';
import 'package:naarea/ui/nearby/nearby_view_model.dart';
import 'package:naarea/ui/place/place_detail_view_model.dart';
import 'package:naarea/ui/place/price_section.dart';
import 'package:naarea/ui/review/review_view.dart';
import 'package:naarea/ui/review/review_view_model.dart';
import 'package:naarea/ui/visit/visit_sheet.dart';
import 'package:naarea/ui/visit/visit_view_model.dart';

import '../support/app_harness.dart';
import '../support/builders.dart';
import '../support/fakes.dart';
import '../support/geo_helpers.dart';

const _mangai = Place(
  id: 'mangai',
  name: 'Mangai',
  category: 'Restaurante',
  neighborhood: 'Tirol',
  city: 'Natal',
);

final _today = DateTime.utc(2030, 10, 12, 23);

Finder _tab(String label) => find.descendant(
  of: find.byKey(const Key('app-nav')),
  matching: find.text(label),
);

/// [me] (uid "me") segue Ana e Bia.
FakeUserRepository _users(String me) => FakeUserRepository()
  ..addUser('me', me)
  ..addUser('ana', 'Ana')
  ..addUser('bia', 'Bia')
  ..followingByUser['me'] = {'ana', 'bia'};

/// Ana e Bia informaram R$ 30–60 no Mangai.
FakeReviewRepository _reviews({String placeId = 'mangai'}) =>
    FakeReviewRepository()
      ..stored.addAll([
        review(
          authorId: 'ana',
          authorName: 'Ana',
          placeId: placeId,
          placeName: 'Mangai',
          createdAt: _today.subtract(const Duration(days: 2)),
          priceBand: PriceBand.from30To60,
        ),
        review(
          authorId: 'bia',
          authorName: 'Bia',
          placeId: placeId,
          placeName: 'Mangai',
          createdAt: _today.subtract(const Duration(days: 3)),
          priceBand: PriceBand.from30To60,
        ),
      ]);

ReviewViewModel _reviewVm(FakeReviewRepository reviews) => ReviewViewModel(
  place: _mangai,
  authRepository: FakeAuthRepository(uid: 'me'),
  userRepository: FakeUserRepository()..addUser('me', 'Eu'),
  reviewRepository: reviews,
  photoPicker: FakePhotoPicker(),
  compress: (b) async => b,
);

/// Semântica sem os chips do seletor: o nó do [finder] está dentro do nó
/// do grupo [group]?
bool _isInside(WidgetTester tester, Finder finder, Finder group) {
  final groupNode = tester.getSemantics(group);
  SemanticsNode? node = tester.getSemantics(finder);
  while (node != null) {
    if (identical(node, groupNode)) return true;
    node = node.parent;
  }
  return false;
}

ChoiceChip _chip(WidgetTester tester, int value) => tester.widget<ChoiceChip>(
  find.descendant(
    of: find.byKey(Key('price-band-$value')),
    matching: find.byType(ChoiceChip),
  ),
);

/// Abre o detalhe e rola até [key].
Future<void> _scrollTo(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  group('PriceBandPicker', () {
    Future<PriceBand? Function()> pumpPicker(
      WidgetTester tester, {
      bool enabled = true,
    }) async {
      PriceBand? value;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => PriceBandPicker(
                value: value,
                enabled: enabled,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      );
      return () => value;
    }

    testWidgets('1 toque escolhe, 1 toque limpa; semântica com "selecionado"', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final value = await pumpPicker(tester);
      expect(find.text(priceBandQuestion), findsOneWidget);
      expect(find.text('até R\$ 30'), findsOneWidget);
      expect(find.text('R\$ 150+'), findsOneWidget);
      expect(find.bySemanticsLabel('Até 30 reais por pessoa'), findsOneWidget);
      expect(
        find.bySemanticsLabel('De 30 a 60 reais por pessoa'),
        findsOneWidget,
      );

      await tester.tap(find.text('até R\$ 30'));
      await tester.pump();
      expect(value(), PriceBand.upTo30);
      expect(
        find.bySemanticsLabel('Até 30 reais por pessoa, selecionado'),
        findsOneWidget,
      );

      await tester.tap(find.text('R\$ 30–60'));
      await tester.pump();
      expect(value(), PriceBand.from30To60);

      await tester.tap(find.text('R\$ 30–60'));
      await tester.pump();
      expect(value(), isNull, reason: 'tocar na escolhida limpa');
      expect(find.bySemanticsLabel(RegExp('selecionado')), findsNothing);
      handle.dispose();
    });

    testWidgets('título é cabeçalho, chips agrupados sob ele e dica da '
        'faixa de cima', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpPicker(tester);
      expect(
        tester.getSemantics(find.text(priceBandQuestion)),
        containsSemantics(label: priceBandQuestion, isHeader: true),
      );
      final group = find.byKey(const Key('price-band-picker'));
      for (final b in PriceBand.values) {
        expect(
          _isInside(tester, find.byKey(Key('price-band-${b.value}')), group),
          isTrue,
          reason: 'chip ${b.value} fora do grupo',
        );
      }
      expect(_isInside(tester, find.text(priceBandQuestion), group), isTrue);
      expect(find.text(priceBandHint), findsOneWidget);
      expect(priceBandHint, 'Em caso de dúvida, escolha a faixa de cima.');
      handle.dispose();
    });

    testWidgets('desabilitado: chips sem ação', (tester) async {
      final value = await pumpPicker(tester, enabled: false);
      expect(_chip(tester, 1).onSelected, isNull);
      await tester.tap(find.text('até R\$ 30'), warnIfMissed: false);
      await tester.pump();
      expect(value(), isNull);
    });
  });

  group('ViewModels', () {
    test('avaliação com preço: priceBand 2; limpar: null', () async {
      final withPrice = FakeReviewRepository();
      final vm = _reviewVm(withPrice)
        ..setFood(4)
        ..setPriceBand(PriceBand.from30To60);
      expect(vm.canSubmit, isTrue);
      expect(await vm.submit(), isTrue);
      expect(withPrice.created.single.priceBand, PriceBand.from30To60);

      final cleared = FakeReviewRepository();
      final vm2 = _reviewVm(cleared)
        ..setFood(4)
        ..setPriceBand(PriceBand.from150)
        ..setPriceBand(null);
      expect(await vm2.submit(), isTrue);
      expect(cleared.created.single.priceBand, isNull);
    });

    test(
      'preço nunca libera envio sem eixo (opcional, não substitui nota)',
      () {
        final vm = _reviewVm(FakeReviewRepository())
          ..setPriceBand(PriceBand.upTo30);
        expect(vm.canSubmit, isFalse);
      },
    );

    test('avaliação: setPriceBand é ignorado durante o envio', () async {
      final reviews = FakeReviewRepository()..createGate = Completer<void>();
      final vm = _reviewVm(reviews)
        ..setFood(4)
        ..setPriceBand(PriceBand.from30To60);
      final sending = vm.submit();
      expect(vm.isSubmitting, isTrue);
      vm.setPriceBand(PriceBand.from150);
      vm.setPriceBand(null);
      expect(vm.priceBand, PriceBand.from30To60);
      reviews.createGate!.complete();
      expect(await sending, isTrue);
      expect(reviews.created.single.priceBand, PriceBand.from30To60);
    });

    test('avaliação: escolher o preço não apaga a mensagem de erro', () async {
      final reviews = FakeReviewRepository()..createError = StateError('x');
      final vm = _reviewVm(reviews)..setFood(4);
      expect(await vm.submit(), isFalse);
      final error = vm.errorMessage;
      expect(error, isNotNull);
      var notified = 0;
      vm.addListener(() => notified++);
      vm.setPriceBand(PriceBand.upTo30);
      expect(vm.errorMessage, error);
      expect(notified, 1);
      vm.setPriceBand(PriceBand.upTo30);
      expect(notified, 1, reason: 'mesma faixa: nada muda');
    });

    VisitViewModel visitVm(FakeVisitRepository visits, String uid) =>
        VisitViewModel(
          place: _mangai,
          authRepository: FakeAuthRepository(uid: uid),
          userRepository: FakeUserRepository()
            ..addUser('toni', 'Toni')
            ..addUser('bia', 'Bia'),
          visitRepository: visits,
          clock: () => _today,
        );

    test('visita com preço: priceBand 1; sem preço: null', () async {
      final visits = FakeVisitRepository()..clock = () => _today;
      final toni = visitVm(visits, 'toni');
      await toni.checkLock();
      toni.setPriceBand(PriceBand.upTo30);
      expect(await toni.submit(), isTrue);
      expect(visits.created.last.priceBand, PriceBand.upTo30);

      final bia = visitVm(visits, 'bia');
      await bia.checkLock();
      expect(await bia.submit(), isTrue);
      expect(visits.created.last.priceBand, isNull);
    });

    test('visita: setPriceBand ignorado bloqueada e durante o envio', () async {
      final blockedRepo = FakeVisitRepository()
        ..clock = (() => _today)
        ..lock('toni', 'mangai', _today.subtract(const Duration(hours: 2)));
      final blocked = visitVm(blockedRepo, 'toni');
      await blocked.checkLock();
      expect(blocked.isBlocked, isTrue);
      blocked.setPriceBand(PriceBand.from30To60);
      expect(blocked.priceBand, isNull);

      final visits = FakeVisitRepository()
        ..clock = (() => _today)
        ..createGate = Completer<void>();
      final vm = visitVm(visits, 'toni');
      await vm.checkLock();
      vm.setPriceBand(PriceBand.from60To100);
      final sending = vm.submit();
      expect(vm.isSubmitting, isTrue);
      vm.setPriceBand(null);
      expect(vm.priceBand, PriceBand.from60To100);
      visits.createGate!.complete();
      expect(await sending, isTrue);
      expect(visits.created.single.priceBand, PriceBand.from60To100);
    });
  });

  group('telas de envio', () {
    testWidgets('ReviewView mostra o seletor e envia a faixa', (tester) async {
      final vm = _reviewVm(FakeReviewRepository());
      await tester.pumpWidget(MaterialApp(home: ReviewView(viewModel: vm)));
      await tester.pump();
      final chip = find.byKey(const Key('price-band-3'));
      await tester.scrollUntilVisible(chip, 200);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pump();
      expect(vm.priceBand, PriceBand.from60To100);
    });

    Future<FakeVisitRepository> openSheet(
      WidgetTester tester, {
      FakeVisitRepository? visits,
    }) async {
      final repo = visits ?? (FakeVisitRepository()..clock = () => _today);
      final app = await pumpApp(
        tester,
        places: [_mangai],
        visits: repo,
        clock: () => _today,
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('place-visit')));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('sheet "Voltei aqui" grava a faixa escolhida', (tester) async {
      final visits = await openSheet(tester);
      expect(find.text(priceBandQuestion), findsOneWidget);
      await tester.tap(find.byKey(const Key('price-band-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('visit-confirm')));
      await tester.pumpAndSettle();
      expect(visits.created.single.priceBand, PriceBand.upTo30);
    });

    testWidgets('sheet: tocar de novo limpa a faixa e a visita vai sem preço', (
      tester,
    ) async {
      final visits = await openSheet(tester);
      await tester.tap(find.byKey(const Key('price-band-2')));
      await tester.pump();
      expect(_chip(tester, 2).selected, isTrue);
      await tester.tap(find.byKey(const Key('price-band-2')));
      await tester.pump();
      expect(_chip(tester, 2).selected, isFalse);
      await tester.tap(find.byKey(const Key('visit-confirm')));
      await tester.pumpAndSettle();
      expect(visits.created.single.priceBand, isNull);
    });

    testWidgets('sheet: seletor desabilitado durante o envio', (tester) async {
      final visits = FakeVisitRepository()
        ..clock = (() => _today)
        ..createGate = Completer<void>();
      await openSheet(tester, visits: visits);
      await tester.tap(find.byKey(const Key('price-band-3')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('visit-confirm')));
      await tester.pump();
      expect(_chip(tester, 3).onSelected, isNull);
      expect(_chip(tester, 4).onSelected, isNull);
      visits.createGate!.complete();
      await tester.pumpAndSettle();
      expect(visits.created.single.priceBand, PriceBand.from60To100);
    });

    testWidgets('sheet: seletor desabilitado com a visita bloqueada', (
      tester,
    ) async {
      final visits = FakeVisitRepository()
        ..clock = (() => _today)
        ..lock('me', 'mangai', _today.subtract(const Duration(hours: 2)));
      // O "Voltei aqui" do detalhe fica desabilitado com a trava: monta o
      // sheet direto, como depois de um toque dado antes da trava chegar.
      final vm = VisitViewModel(
        place: _mangai,
        authRepository: FakeAuthRepository(uid: 'me'),
        userRepository: FakeUserRepository()..addUser('me', 'Eu'),
        visitRepository: visits,
        clock: () => _today,
      );
      await vm.checkLock();
      expect(vm.isBlocked, isTrue);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VisitSheet(viewModel: vm)),
        ),
      );
      expect(_chip(tester, 1).onSelected, isNull);
      expect(_chip(tester, 5).onSelected, isNull);
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
    });

    testWidgets('sheet em 320×568: "Confirmar" alcançável', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final visits = await openSheet(tester);
      final confirm = find.byKey(const Key('visit-confirm'));
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      final rect = tester.getRect(confirm);
      expect(rect.bottom, lessThanOrEqualTo(568));
      expect(rect.top, greaterThanOrEqualTo(0));
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(visits.created, hasLength(1));
    });
  });

  group('exibição', () {
    testWidgets('AC: Ana e Bia (seguidas) informaram R\$ 30–60 no Mangai; '
        'Toni vê no card "R\$ 30–60 por pessoa · 2 relatos"', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(
        tester,
        users: _users('Toni'),
        reviews: _reviews(),
        places: [_mangai],
        clock: () => _today,
      );
      await tester.pumpAndSettle();
      final chip = find.byKey(const Key('feed-price'));
      expect(
        find.descendant(
          of: chip,
          matching: find.text('R\$ 30–60 por pessoa · 2 relatos'),
        ),
        findsOneWidget,
      );
      // O card é um botão com rótulo agregado: o preço entra nele.
      final label = tester.getSemantics(chip).label;
      expect(label, contains('Abrir Mangai'));
      expect(label, contains('De 30 a 60 reais por pessoa, 2 relatos'));
      handle.dispose();
    });

    testWidgets('card sem relatos de preço: nada de preço', (tester) async {
      final reviews = FakeReviewRepository()
        ..stored.add(
          review(authorId: 'ana', authorName: 'Ana', placeId: 'mangai'),
        );
      await pumpApp(
        tester,
        users: _users('Toni'),
        reviews: reviews,
        places: [_mangai],
        clock: () => _today,
      );
      await tester.pumpAndSettle();
      expect(find.text('Mangai'), findsWidgets);
      expect(find.byKey(const Key('feed-price')), findsNothing);
    });

    testWidgets('AC: no detalhe do Mangai, a Bianca escolhe 4 pessoas e vê '
        '"Para 4 pessoas: R\$ 120–240"', (tester) async {
      final handle = tester.ensureSemantics();
      final app = await pumpApp(
        tester,
        users: _users('Bianca'),
        reviews: _reviews(),
        places: [_mangai],
        clock: () => _today,
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('place-price-chip')),
          matching: find.text('R\$ 30–60 por pessoa · 2 relatos de amigos'),
        ),
        findsOneWidget,
      );

      await _scrollTo(tester, const Key('place-price-split'));
      expect(find.byType(PriceSection), findsOneWidget);
      expect(find.text('R\$ 30–60 por pessoa'), findsOneWidget);
      expect(find.text('· 2 relatos de amigos'), findsOneWidget);
      expect(find.text('Relatado por Ana e Bia'), findsOneWidget);
      expect(find.text(priceReportWindowLabel), findsOneWidget);
      expect(find.byKey(const Key('place-price-spread')), findsNothing);
      expect(
        find.bySemanticsLabel('De 30 a 60 reais por pessoa: 2 relatos'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Até 30 reais por pessoa: 0 relatos'),
        findsOneWidget,
      );
      expect(find.text('Para 2 pessoas: R\$ 60–120'), findsOneWidget);

      final more = find.byKey(const Key('place-price-people-more'));
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pump();
      await tester.tap(more);
      await tester.pump();
      expect(find.text('4 pessoas'), findsOneWidget);
      expect(find.text('Para 4 pessoas: R\$ 120–240'), findsOneWidget);
      // Uma região só, que fala quantidade e estimativa juntas.
      expect(
        tester.getSemantics(find.byKey(const Key('place-price-split-live'))),
        containsSemantics(
          label: 'Para 4 pessoas: de 120 a 240 reais',
          isLiveRegion: true,
        ),
      );
      expect(
        find.descendant(
          of: find.byType(PriceSection),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.text(priceSectionTitle)),
        containsSemantics(isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('detalhe: dispersão "varia de até R\$ 30 a R\$ 150+"; o chip '
        'segue com a mediana', (tester) async {
      final users = _users('Bianca')
        ..addUser('caio', 'Caio')
        ..followingByUser['me'] = {'ana', 'bia', 'caio'};
      final reviews = FakeReviewRepository()
        ..stored.addAll([
          review(
            authorId: 'ana',
            authorName: 'Ana',
            placeId: 'mangai',
            createdAt: _today.subtract(const Duration(days: 1)),
            priceBand: PriceBand.upTo30,
          ),
          review(
            authorId: 'bia',
            authorName: 'Bia',
            placeId: 'mangai',
            createdAt: _today.subtract(const Duration(days: 2)),
            priceBand: PriceBand.from60To100,
          ),
          review(
            authorId: 'caio',
            authorName: 'Caio',
            placeId: 'mangai',
            createdAt: _today.subtract(const Duration(days: 3)),
            priceBand: PriceBand.from150,
          ),
        ]);
      final app = await pumpApp(
        tester,
        users: users,
        reviews: reviews,
        places: [_mangai],
        clock: () => _today,
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      expect(
        find.text('R\$ 60–100 por pessoa · 3 relatos de amigos'),
        findsOneWidget,
      );
      await _scrollTo(tester, const Key('place-price-spread'));
      expect(find.text('varia de até R\$ 30 a R\$ 150+'), findsOneWidget);
    });

    testWidgets('detalhe com a ida do próprio usuário: "Você" entre quem '
        'relatou e a contagem "(seu e de amigos)" no chip e na seção', (
      tester,
    ) async {
      final reviews = _reviews()
        ..stored.add(
          review(
            authorId: 'me',
            authorName: 'Bianca',
            placeId: 'mangai',
            createdAt: _today.subtract(const Duration(hours: 5)),
            priceBand: PriceBand.from60To100,
          ),
        );
      final app = await pumpApp(
        tester,
        users: _users('Bianca'),
        reviews: reviews,
        places: [_mangai],
        clock: () => _today,
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      expect(
        find.text('R\$ 30–60 por pessoa · 3 relatos (seu e de amigos)'),
        findsOneWidget,
      );
      await _scrollTo(tester, const Key('place-price-reporters'));
      expect(find.text('Relatado por Você, Ana e Bia'), findsOneWidget);
      expect(find.text('· 3 relatos (seu e de amigos)'), findsOneWidget);
      expect(find.byType(PriceSection), findsOneWidget);
    });

    testWidgets('só o relato do próprio usuário: uma seção, com o resumo '
        'dele ("1 relato seu")', (tester) async {
      final reviews = FakeReviewRepository()
        ..stored.add(
          review(
            authorId: 'me',
            authorName: 'Bianca',
            placeId: 'mangai',
            createdAt: _today.subtract(const Duration(days: 1)),
            priceBand: PriceBand.from100To150,
          ),
        );
      final app = await pumpApp(
        tester,
        users: FakeUserRepository()..addUser('me', 'Bianca'),
        reviews: reviews,
        places: [_mangai],
        clock: () => _today,
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      expect(
        find.text('R\$ 100–150 por pessoa · 1 relato seu'),
        findsOneWidget,
      );
      await _scrollTo(tester, const Key('place-price-reporters'));
      expect(find.byType(PriceSection), findsOneWidget);
      expect(find.text(noPriceText), findsNothing);
      expect(find.text('Relatado por Você'), findsOneWidget);
      expect(find.text('· 1 relato seu'), findsOneWidget);
    });

    testWidgets('detalhe sem relatos: "Ninguém informou o preço ainda"', (
      tester,
    ) async {
      final reviews = FakeReviewRepository()
        ..stored.add(
          review(authorId: 'ana', authorName: 'Ana', placeId: 'mangai'),
        );
      final app = await pumpApp(
        tester,
        users: _users('Bianca'),
        reviews: reviews,
        places: [_mangai],
        clock: () => _today,
      );
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      await _scrollTo(tester, const Key('place-price-empty'));
      expect(find.text(noPriceText), findsOneWidget);
      expect(find.byKey(const Key('place-price-chip')), findsNothing);
      expect(find.byType(PriceSection), findsOneWidget);
    });

    testWidgets('detalhe sem nenhuma ida: uma seção dizendo que ninguém '
        'informou', (tester) async {
      final app = await pumpApp(tester, places: [_mangai], clock: () => _today);
      app.router.go(Routes.placeDetail('mangai'));
      await tester.pumpAndSettle();
      expect(find.text(noPriceText), findsOneWidget);
      expect(find.byType(PriceSection), findsOneWidget);
    });

    testWidgets('seletor de pessoas fica entre 2 e 12', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PriceSection(
                summary: PriceSummary.of([
                  review(authorId: 'a', priceBand: PriceBand.from150),
                ], now: DateTime.utc(2026, 9, 2)),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Para 2 pessoas: a partir de R\$ 300'), findsOneWidget);
      final less = find.byKey(const Key('place-price-people-less'));
      expect(tester.widget<IconButton>(less).onPressed, isNull);
      final more = find.byKey(const Key('place-price-people-more'));
      for (var i = 0; i < 15; i++) {
        if (tester.widget<IconButton>(more).onPressed == null) break;
        await tester.tap(more);
        await tester.pump();
      }
      expect(find.text('12 pessoas'), findsOneWidget);
      expect(tester.widget<IconButton>(more).onPressed, isNull);
      expect(find.text('Para 12 pessoas: a partir de R\$ 1.800'), findsOne);
    });

    testWidgets('seção e seletor sem overflow com fonte 2x em 320 px', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final names = ['Ana', 'Bia', 'Caio', 'Duda', 'Edu'];
      final summary = PriceSummary.of([
        for (var i = 0; i < names.length; i++)
          review(
            authorId: names[i],
            authorName: names[i],
            createdAt: DateTime.utc(2026, 9, 1, i),
            priceBand: PriceBand.values[i],
          ),
      ], now: DateTime.utc(2026, 9, 2))!;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 900),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    PriceSection(
                      summary: summary,
                      countLabel: '5 relatos de amigos',
                    ),
                    PriceBandPicker(
                      value: PriceBand.from100To150,
                      onChanged: (_) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Relatado por Edu, Duda e mais 3'), findsOneWidget);
      expect(find.text('varia de até R\$ 30 a R\$ 150+'), findsOneWidget);
    });

    test('detalhe: um resumo por snapshot, compartilhado pelo chip e pela '
        'seção; recalcula quando as idas mudam', () async {
      final reviews = _reviews();
      final vm = PlaceDetailViewModel(
        placeId: 'mangai',
        authRepository: FakeAuthRepository(uid: 'me'),
        userRepository: _users('Bianca'),
        placeRepository: FakePlaceRepository([_mangai]),
        reviewRepository: reviews,
        followEvents: FollowEvents(),
        visitRepository: FakeVisitRepository(),
        clock: () => _today,
      );
      await vm.load();
      final first = vm.price!;
      expect(identical(vm.price, first), isTrue);
      expect(identical(vm.item, vm.item), isTrue);
      expect(vm.priceCountLabel, '2 relatos de amigos');
      reviews.stored.add(
        review(
          authorId: 'me',
          authorName: 'Bianca',
          placeId: 'mangai',
          createdAt: _today.subtract(const Duration(hours: 1)),
          priceBand: PriceBand.from150,
        ),
      );
      await vm.load();
      expect(identical(vm.price, first), isFalse);
      expect(vm.price!.count, 3);
      expect(vm.priceCountLabel, '3 relatos (seu e de amigos)');
      vm.dispose();
    });

    test('nearbySemanticsLabel com e sem preço', () {
      final summary = PriceSummary.of([
        review(authorId: 'ana', priceBand: PriceBand.from30To60),
        review(authorId: 'bia', priceBand: PriceBand.from30To60),
      ], now: DateTime.utc(2026, 9, 2))!;
      final withPrice = NearbyItem(
        place: _mangai,
        distanceMeters: 120,
        friends: const ['Ana', 'Bia'],
        price: summary,
      );
      final label = nearbySemanticsLabel(withPrice, saved: false);
      expect(label, contains('Ana e Bia foram aqui'));
      expect(label, endsWith('De 30 a 60 reais por pessoa, 2 relatos'));
      final without = NearbyItem(
        place: _mangai,
        distanceMeters: 120,
        friends: const ['Ana', 'Bia'],
      );
      final plain = nearbySemanticsLabel(without, saved: false);
      expect(plain, endsWith('Ana e Bia foram aqui'));
      expect(plain, isNot(contains('reais')));
    });

    test('Perto: FriendSignal.price vem do NearbyViewModel real (avaliações '
        'e visitas dos amigos, janela de 12 meses)', () async {
      final users = _users('Toni');
      final reviews = _reviews(placeId: 'perto240')
        ..stored.add(
          review(
            authorId: 'ana',
            authorName: 'Ana',
            placeId: 'perto80',
            createdAt: _today.subtract(const Duration(days: 400)),
            priceBand: PriceBand.from150,
          ),
        );
      final visits = FakeVisitRepository()
        ..stored.add(
          visit(
            authorId: 'bia',
            authorName: 'Bia',
            placeId: 'perto240',
            createdAt: _today.subtract(const Duration(hours: 1)),
            priceBand: PriceBand.from60To100,
          ),
        );
      final vm = NearbyViewModel(
        locationService: FakeLocationService(
          position: pontaNegra,
          granted: true,
        ),
        placeRepository: FakePlaceRepository([
          placeNear('perto80', 80, bearingDeg: 10, name: 'Tapiocaria 80'),
          placeNear('perto240', 240, bearingDeg: 200, name: 'Camarões 240'),
        ]),
        authRepository: FakeAuthRepository(uid: 'me'),
        userRepository: users,
        reviewRepository: reviews,
        visitRepository: visits,
        followEvents: FollowEvents(),
        clock: () => _today,
      );
      await vm.start();
      expect(vm.phase, NearbyPhase.ready);
      final byId = {for (final i in vm.items) i.place.id: i};
      final price = byId['perto240']!.price!;
      // Bia: a visita de 1 h atrás (60–100) substitui a avaliação de 3 dias
      // (30–60); Ana: 30–60. Mediana com empate: a mais baixa.
      expect(price.count, 2);
      expect(price.typical, PriceBand.from30To60);
      expect(byId['perto80']!.price, isNull, reason: 'relato de 400 dias');
    });

    testWidgets('Perto mostra o preço relatado pelos amigos', (tester) async {
      await pumpApp(
        tester,
        users: _users('Toni'),
        reviews: _reviews(placeId: 'perto240'),
        places: [
          placeNear('perto240', 240, bearingDeg: 200, name: 'Camarões 240'),
        ],
        location: FakeLocationService(position: pontaNegra, granted: true),
        clock: () => _today,
      );
      await tester.tap(_tab('Perto'));
      await tester.pumpAndSettle();
      final item = find.byKey(const ValueKey('nearby-perto240'));
      expect(
        find.descendant(
          of: item,
          matching: find.text('R\$ 30–60 por pessoa · 2 relatos'),
        ),
        findsOneWidget,
      );
    });
  });
}

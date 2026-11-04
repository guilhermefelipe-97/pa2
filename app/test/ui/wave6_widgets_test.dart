import '../support/app_harness.dart';
import 'package:naarea/routing/routes.dart';
import 'package:naarea/ui/review/review_view.dart';
import 'package:naarea/ui/review/review_view_model.dart';
import 'package:naarea/ui/visit/visit_sheet.dart';
import 'package:naarea/ui/visit/visit_view_model.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:naarea/data/firebase/firestore_privacy_repository.dart';
import 'package:naarea/data/firebase/firestore_reputation_repository.dart';
import 'package:naarea/data/repositories/auth_repository.dart';
import 'package:naarea/data/repositories/privacy_repository.dart';
import 'package:naarea/data/repositories/reputation_repository.dart';
import 'package:naarea/data/repositories/queue_repository.dart';
import 'package:naarea/data/repositories/owner_repository.dart';
import 'package:naarea/data/repositories/user_repository.dart';
import 'package:naarea/data/repositories/sponsorship_repository.dart';
import 'package:naarea/data/repositories/place_repository.dart';
import 'package:naarea/data/services/location_service.dart';
import 'package:naarea/domain/models/place.dart';
import 'package:naarea/domain/models/review.dart';
import 'package:naarea/ui/core/app_clock.dart';
import 'package:naarea/ui/core/app_shell.dart';
import 'package:naarea/ui/privacy/privacy_view.dart';
import 'package:naarea/ui/owner/reply_line.dart';
import 'package:naarea/ui/owner/owner_reviews_view.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:naarea/ui/queue/queue_section.dart';
import 'package:naarea/ui/sponsored/sponsored_view.dart';
import 'package:naarea/ui/nearby/nearby_view.dart';
import 'package:naarea/ui/nearby/nearby_view_model.dart';
import 'package:naarea/ui/place/place_detail_view.dart';
import 'package:naarea/ui/owner/owner_view.dart';
import '../support/geo_helpers.dart';
import '../support/fakes.dart';

class _QueueRepository implements QueueRepository {
  _QueueRepository(this.now);
  final DateTime now;
  final reports = <QueueReport>[];
  int writes = 0, reads = 0;
  bool loseAck = false, createdPlace = false;
  QueueReceipt? pending;
  DateTime? lastAt;
  Completer<List<QueueReport>>? readGate;
  @override
  Future<List<QueueReport>> fetchForPlace(
    String id, {
    required DateTime since,
  }) async {
    reads++;
    if (readGate != null) return readGate!.future;
    return reports.toList();
  }

  @override
  Future<QueueReceipt?> reconcilePending(String uid, String placeId) async {
    final result = pending;
    pending = null;
    return result;
  }

  @override
  Future<DateTime?> queueReportLockOf(String uid, String id) async => lastAt;
  @override
  Future<QueueReceipt> createReport(NewQueueReport r, {Place? newPlace}) async {
    writes++;
    reports.add(
      QueueReport(
        id: 'r',
        authorId: r.authorId,
        authorName: r.authorName,
        placeId: r.placeId,
        minutes: r.minutes,
        createdAt: now,
      ),
    );
    final receipt = QueueReceipt(
      id: 'r',
      minutes: r.minutes,
      createdAt: now,
      placeCreated: createdPlace,
      recovered: loseAck,
    );
    if (loseAck) {
      pending = receipt;
      loseAck = false;
      lastAt = now;
      throw TimeoutException('ACK perdido');
    }
    return receipt;
  }
}

class _Sponsors implements SponsorshipRepository {
  _Sponsors(this.slot, {this.count = 1});
  final SponsoredSlot slot;
  final int count;
  @override
  Future<List<SponsoredSlot>> current(DateTime now) async => List.generate(
    count,
    (i) => SponsoredSlot(
      '${slot.id}-$i',
      slot.placeId,
      slot.startsAt,
      slot.endsAt,
    ),
  );
}

class _ControlledSponsors implements SponsorshipRepository {
  final reads = <Completer<List<SponsoredSlot>>>[];
  @override
  Future<List<SponsoredSlot>> current(DateTime now) {
    final read = Completer<List<SponsoredSlot>>();
    reads.add(read);
    return read.future;
  }
}

class _UnavailableOwner extends FakeOwnerRepository {
  @override
  Future<String?> ownerOf(String placeId) async => throw StateError('rede');
}

class _ReplyRepository implements ReputationRepository {
  OwnerReply? written;
  final pending = <Completer<OwnerReply?>>[];
  bool hold = false;
  int writes = 0;
  @override
  Future<ReviewPage> reviewsForPlace(String id, {String? after}) async =>
      (reviews: <Review>[], next: null);
  @override
  Future<OwnerReply?> replyFor(String id) {
    if (hold && written == null) {
      final c = Completer<OwnerReply?>();
      pending.add(c);
      return c.future;
    }
    return Future.value(written);
  }

  @override
  Future<void> reply(String uid, String id, String text) async {
    writes++;
    written = OwnerReply(uid, 'Titular', text.trim(), DateTime.now());
  }
}

class _SlowSponsors implements SponsorshipRepository {
  final gate = Completer<List<SponsoredSlot>>();
  int calls = 0;
  @override
  Future<List<SponsoredSlot>> current(DateTime now) {
    calls++;
    return gate.future;
  }
}

void main() {
  final at = DateTime.utc(2026, 10, 30, 21);
  const place = Place(
    id: 'p',
    name: 'Local',
    category: 'Bar',
    neighborhood: '',
    city: '',
    lat: -23.5,
    lng: -46.6,
  );
  SponsoredSlot validSlot(String id) => SponsoredSlot(
    id,
    'p',
    at.subtract(const Duration(hours: 1)),
    at.add(const Duration(hours: 1)),
  );

  testWidgets('Perto mantém sugestão e ordem orgânica separadas do destaque', (
    tester,
  ) async {
    final organic = [
      placeNear('near', 80),
      placeNear('middle', 150),
      placeNear('far', 240),
    ];
    final app = await pumpApp(
      tester,
      places: [place, ...organic],
      sponsors: _Sponsors(validSlot('s')),
      clock: () => at,
      location: FakeLocationService(position: pontaNegra, granted: true),
    );
    app.router.go(Routes.nearby);
    await tester.pumpAndSettle();
    final view = tester.widget<NearbyView>(find.byType(NearbyView));
    expect(view.viewModel.visibleItems.map((item) => item.place.id), [
      'near',
      'middle',
      'far',
    ]);
    expect(view.viewModel.suggestion?.item.place.id, 'near');
    expect(find.byType(SponsoredCard), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('nearby-suggestion')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('nearby-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.byKey(const Key('nearby-suggestion')), findsOneWidget);
    expect(
      find.byTooltip(
        'Os destaques não seguem o raio escolhido nem o filtro Aberto agora.',
      ),
      findsOneWidget,
    );
    final scroll = find.descendant(
      of: find.byKey(const Key('nearby-list')),
      matching: find.byType(Scrollable),
    );
    final tiles = <String>[];
    for (final id in ['near', 'middle', 'far']) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('nearby-$id')),
        100,
        scrollable: scroll,
      );
      tiles.add(
        tester
            .widget<NearbyTile>(find.byKey(ValueKey('nearby-$id')))
            .item
            .place
            .id,
      );
    }
    expect(tiles, ['near', 'middle', 'far']);
    expect(find.byKey(const ValueKey('nearby-p')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Troca de conta descarta leitura antiga antes do timeout com nova leitura pendente',
    (tester) async {
      final auth = FakeAuthRepository(uid: 'a');
      final repo = _ControlledSponsors();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            Provider<SponsorshipRepository>.value(value: repo),
            Provider<PlaceRepository>(
              create: (_) => FakePlaceRepository([place]),
            ),
            Provider<AppClock>.value(value: AppClock(() => at)),
          ],
          child: const MaterialApp(home: Scaffold(body: SponsoredSection())),
        ),
      );
      await tester.pump();
      expect(repo.reads, hasLength(1));
      await tester.pump(const Duration(seconds: 2));
      auth.restoreSession('b');
      await tester.pump();
      expect(repo.reads, hasLength(2));
      repo.reads.first.complete([validSlot('old')]);
      await tester.pumpAndSettle();
      expect(find.byType(SponsoredCard), findsNothing);
      expect(tester.getSize(find.byType(SponsoredSection)).height, 0);
      repo.reads.last.complete([validSlot('new')]);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SponsoredCard>(find.byType(SponsoredCard)).slot.id,
        'new',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Erro real oculta seção e polling recupera sem leituras concorrentes',
    (tester) async {
      final auth = FakeAuthRepository(uid: 'a');
      final repo = _ControlledSponsors();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            Provider<SponsorshipRepository>.value(value: repo),
            Provider<PlaceRepository>(
              create: (_) => FakePlaceRepository([place]),
            ),
            Provider<AppClock>.value(value: AppClock(() => at)),
          ],
          child: const MaterialApp(home: Scaffold(body: SponsoredSection())),
        ),
      );
      await tester.pump();
      repo.reads.single.completeError(StateError('rede'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SponsoredSection)).height, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(seconds: 15));
      expect(repo.reads, hasLength(2));
      await tester.pump(const Duration(seconds: 18));
      expect(repo.reads, hasLength(2));
      repo.reads.last.complete([validSlot('recovered')]);
      await tester.pumpAndSettle();
      expect(find.byType(SponsoredCard), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Seção pausa polling na aba inativa e relê ao voltar', (
    tester,
  ) async {
    final auth = FakeAuthRepository(uid: 'a');
    final repo = _ControlledSponsors();
    final active = ValueNotifier(true);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthRepository>.value(value: auth),
          Provider<SponsorshipRepository>.value(value: repo),
          Provider<PlaceRepository>(
            create: (_) => FakePlaceRepository([place]),
          ),
          Provider<AppClock>.value(value: AppClock(() => at)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: active,
              builder: (_, value, child) =>
                  ActiveTab(isActive: value, child: child!),
              child: const SponsoredSection(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    repo.reads.single.complete([validSlot('initial')]);
    await tester.pumpAndSettle();
    active.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 45));
    expect(repo.reads, hasLength(1));
    active.value = true;
    await tester.pump();
    expect(repo.reads, hasLength(2));
    active.value = false;
    await tester.pump();
    repo.reads.last.complete([]);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 45));
    expect(repo.reads, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    active.dispose();
  });

  testWidgets(
    'Falha ao consultar titularidade mantém aviso e oculta Divulgação',
    (tester) async {
      final owners = _UnavailableOwner()
        ..requests['me'] = [const OwnershipRequest('p', 'approved')];
      final app = await pumpApp(tester, places: [place], owners: owners);
      app.router.go('/meus-estabelecimentos');
      await tester.pumpAndSettle();
      expect(
        find.text('Não foi possível verificar titularidade'),
        findsOneWidget,
      );
      expect(find.text('Divulgação'), findsNothing);
      expect(find.text('Avaliações e respostas'), findsNothing);
    },
  );
  testWidgets(
    'Descoberta limita destaques e abre catálogo completo em tela pequena',
    (tester) async {
      tester.view.physicalSize = const Size(400, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = await pumpApp(
        tester,
        places: [place],
        sponsors: _Sponsors(
          SponsoredSlot(
            's',
            'p',
            at.subtract(const Duration(hours: 1)),
            at.add(const Duration(hours: 1)),
          ),
          count: 12,
        ),
        clock: () => at,
        location: FakeLocationService(position: pontaNegra, granted: true),
      );
      app.router.go(Routes.nearby);
      await tester.pumpAndSettle();
      expect(find.byType(SponsoredCard), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      final all = find.text('Ver todos os destaques');
      await tester.ensureVisible(all);
      await tester.tap(all);
      await tester.pumpAndSettle();
      expect(find.byType(SponsoredView), findsOneWidget);
      final catalogScroll = find.descendant(
        of: find.byType(SponsoredView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('sponsored-slot-s-11')),
        300,
        scrollable: catalogScroll,
      );
      await tester.pumpAndSettle();
      final visibleIds = tester
          .widgetList<SponsoredCard>(find.byType(SponsoredCard))
          .map((card) => card.slot.id)
          .toSet();
      expect(visibleIds, contains('s-11'));
      app.router.pop();
      await tester.pumpAndSettle();
      final action = find.text('Ampliar para 1 km');
      await tester.scrollUntilVisible(
        action,
        250,
        scrollable: find
            .descendant(
              of: find.byType(NearbyView),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Nada a 1 km'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Perto mostra destaque mesmo sem orgânicos, abre ficha e não anuncia em Amigos ou perfil',
    (tester) async {
      final slot = SponsoredSlot(
        's',
        'p',
        at.subtract(const Duration(hours: 1)),
        at.add(const Duration(hours: 1)),
      );
      final app = await pumpApp(
        tester,
        places: [place],
        sponsors: _Sponsors(slot),
        clock: () => at,
        location: FakeLocationService(position: pontaNegra, granted: true),
      );
      expect(find.byType(SponsoredCard), findsNothing);
      app.router.go(Routes.nearby);
      await tester.pumpAndSettle();
      expect(find.byType(SponsoredCard), findsOneWidget);
      expect(
        find.text(NearbyView.emptyMessage(NearbyRadius.m300)),
        findsOneWidget,
      );
      await tester.tap(find.byType(SponsoredCard));
      await tester.pumpAndSettle();
      expect(find.byType(PlaceDetailView), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PlaceDetailView),
          matching: find.text('Local'),
        ),
        findsWidgets,
      );
      app.router.go(Routes.person('me'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pumpAndSettle();
      expect(find.text('Patrocinado'), findsNothing);
      await tester.scrollUntilVisible(find.text('Meus estabelecimentos'), 200);
      expect(find.text('Meus estabelecimentos'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Seção embutida oculta carregamento, timeout e resposta de sessão anterior',
    (tester) async {
      final auth = FakeAuthRepository(uid: 'a');
      final repo = _SlowSponsors();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            Provider<SponsorshipRepository>.value(value: repo),
            Provider<PlaceRepository>(
              create: (_) => FakePlaceRepository([place]),
            ),
            Provider<AppClock>.value(value: AppClock(() => at)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [SponsoredSection(), Text('Descoberta disponível')],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.getSize(find.byType(SponsoredSection)).height, 0);
      await tester.pump(const Duration(seconds: 18));
      expect(repo.calls, 1);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.getSize(find.byType(SponsoredSection)).height, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Descoberta disponível'), findsOneWidget);
      auth.restoreSession(null);
      await tester.pump();
      repo.gate.complete([
        SponsoredSlot(
          's',
          'p',
          at.subtract(const Duration(hours: 1)),
          at.add(const Duration(hours: 1)),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(SponsoredCard), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Seção embutida expira sem espaço reservado', (tester) async {
    var clock = at;
    final auth = FakeAuthRepository(uid: 'a');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthRepository>.value(value: auth),
          Provider<SponsorshipRepository>(
            create: (_) => _Sponsors(
              SponsoredSlot(
                's',
                'p',
                at.subtract(const Duration(hours: 1)),
                at.add(const Duration(seconds: 10)),
              ),
            ),
          ),
          Provider<PlaceRepository>(
            create: (_) => FakePlaceRepository([place]),
          ),
          Provider<AppClock>.value(value: AppClock(() => clock)),
        ],
        child: const MaterialApp(home: Scaffold(body: SponsoredSection())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SponsoredCard), findsOneWidget);
    clock = at.add(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(tester.getSize(find.byType(SponsoredSection)).height, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Divulgação é exclusiva do titular atual e informa indisponibilidade',
    (tester) async {
      final owners = FakeOwnerRepository()
        ..owners['p'] = 'me'
        ..requests['me'] = [const OwnershipRequest('p', 'approved')];
      final app = await pumpApp(tester, places: [place], owners: owners);
      app.router.go('/meus-estabelecimentos');
      await tester.pumpAndSettle();
      expect(find.byType(OwnerView), findsOneWidget);
      expect(find.text('Responder'), findsOneWidget);
      await tester.ensureVisible(find.text('Divulgação'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Divulgação'));
      await tester.pumpAndSettle();
      expect(
        find.text('A contratação de divulgação está indisponível no momento.'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextButton),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      owners.owners.clear();
      await tester.tap(find.byTooltip('Atualizar titularidade'));
      await tester.pumpAndSettle();
      expect(find.text('Divulgação'), findsNothing);
      expect(find.text('Responder'), findsNothing);
      owners.requests['me'] = [const OwnershipRequest('p', 'pending')];
      await tester.tap(find.byTooltip('Atualizar titularidade'));
      await tester.pumpAndSettle();
      expect(find.text('Divulgação'), findsNothing);
      expect(
        find.text('Em análise'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'Avaliação silenciosa retorna à ficha com confirmação neutra, sem promessa de feed',
    (tester) async {
      final reviews = FakeReviewRepository();
      final app = await pumpApp(tester, reviews: reviews, places: [place]);
      app.router.go(Routes.placeDetail('p'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('place-review')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('axis-food-4')));
      await tester.pump();
      final formScroll = find
          .descendant(
            of: find.byType(ReviewView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byType(Switch),
        200,
        scrollable: formScroll,
      );
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('review-submit')),
        200,
        scrollable: formScroll,
      );
      await tester.ensureVisible(find.byKey(const Key('review-submit')));
      await tester.tap(find.byKey(const Key('review-submit')));
      await tester.pumpAndSettle();
      expect(reviews.created.single.silent, true);
      expect(find.text('Avaliação registrada.'), findsOneWidget);
      expect(find.textContaining('Quem segue você já pode ver'), findsNothing);
    },
  );
  testWidgets(
    'Resposta existente atualiza por ação explícita; leitura null antiga não desfaz envio; valida limite',
    (tester) async {
      final auth = FakeAuthRepository(uid: 'a');
      final repo = _ReplyRepository();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            Provider<ReputationRepository>.value(value: repo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ReplyLine(reviewId: 'r', canReply: true),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Responder uma vez'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'x' * 1001);
      await tester.pump();
      expect(
        find.text('A resposta pode ter até 1000 caracteres.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Responder uma vez'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Obrigado');
      await tester.pump();
      repo.hold = true;
      await tester.tap(find.text('Atualizar resposta'));
      await tester.pump();
      await tester.tap(find.text('Responder uma vez'));
      await tester.pumpAndSettle();
      repo.pending.single.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('Obrigado'), findsOneWidget);
      expect(repo.writes, 1);
      // Outra ficha já aberta recebe resposta externa sem reconstruir sua rota.
      await tester.pumpWidget(const SizedBox());
      repo.written = null;
      repo.hold = false;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            Provider<ReputationRepository>.value(value: repo),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ReplyLine(reviewId: 'r')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      repo.written = OwnerReply(
        'titular',
        'Outra pessoa',
        'Resposta externa',
        at,
      );
      await tester.tap(find.text('Atualizar resposta'));
      await tester.pumpAndSettle();
      expect(find.text('Resposta externa'), findsOneWidget);
    },
  );
  testWidgets('Destaque lento é serializado e timeout inclui getPlaces', (
    tester,
  ) async {
    final auth = FakeAuthRepository(uid: 'a');
    final repo = _SlowSponsors();
    final places = FakePlaceRepository([place]);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthRepository>.value(value: auth),
          Provider<SponsorshipRepository>.value(value: repo),
          Provider<PlaceRepository>.value(value: places),
        ],
        child: const MaterialApp(home: SponsoredView()),
      ),
    );
    await tester.pump(const Duration(seconds: 18));
    expect(repo.calls, 1);
    repo.gate.complete([
      SponsoredSlot(
        's',
        'p',
        DateTime.now().subtract(const Duration(hours: 1)),
        DateTime.now().add(const Duration(hours: 1)),
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.byType(SponsoredCard), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    final places2 = FakePlaceRepository([place])..getGate = Completer<void>();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthRepository>.value(value: auth),
          Provider<SponsorshipRepository>.value(value: repo),
          Provider<PlaceRepository>.value(value: places2),
        ],
        child: const MaterialApp(home: SponsoredView()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 21));
    await tester.pump();
    expect(
      find.text('Não foi possível carregar. Tentar novamente'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    places2.getGate!.complete();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Fila atualiza relatos externos e reconcilia antes do cooldown com valor real e local descoberto',
    (tester) async {
      final auth = FakeAuthRepository(uid: 'a');
      final queue = _QueueRepository(at)
        ..loseAck = true
        ..createdPlace = true;
      final places = FakePlaceRepository([place]);
      final location = FakeLocationService(position: (lat: -23.5, lng: -46.6));
      final users = FakeUserRepository()..addUser('a', 'Ana');
      const discovered = Place(
        id: 'p',
        name: 'Local',
        category: 'Bar',
        neighborhood: '',
        city: '',
        lat: -23.5,
        lng: -46.6,
        discovered: true,
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            Provider<QueueRepository>.value(value: queue),
            Provider<PlaceRepository>.value(value: places),
            Provider<LocationService>.value(value: location),
            Provider<UserRepository>.value(value: users),
            Provider<OwnerRepository>(create: (_) => FakeOwnerRepository()),
            Provider<AppClock>.value(value: AppClock(() => at)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: QueueSection(place: discovered, compact: true),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      queue.reports.add(
        QueueReport(
          id: 'externo',
          authorId: 'b',
          authorName: 'Bia',
          placeId: 'p',
          minutes: 30,
          createdAt: at,
        ),
      );
      await tester.tap(find.byKey(const Key('place-queue-summary')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Atualizar fila'));
      await tester.pumpAndSettle();
      expect(find.textContaining('mediana 30 min'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '10');
      await tester.tap(find.text('Relatar espera'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '40');
      await tester.tap(find.text('Relatar espera'));
      await tester.pumpAndSettle();
      expect(queue.writes, 1);
      expect(find.text('Envio anterior confirmado: 10 min.'), findsOneWidget);
      expect(places.markedPersisted, ['p']);
      expect(find.text('Relatar espera'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Padrão silencioso TRUE aparece nos formulários sem interação manual',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/a/preferences/privacy').set({'silent': true});
      final auth = FakeAuthRepository(uid: 'a');
      final users = FakeUserRepository()..addUser('a', 'Ana');
      final reviews = FakeReviewRepository();
      final visits = FakeVisitRepository();
      final privacy = FirestorePrivacyRepository(db);
      final review = ReviewViewModel(
        place: place,
        authRepository: auth,
        userRepository: users,
        reviewRepository: reviews,
        photoPicker: FakePhotoPicker(),
        compress: (b) async => b,
        privacyRepository: privacy,
      )..setFood(4);
      await tester.pumpWidget(MaterialApp(home: ReviewView(viewModel: review)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(Switch),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ReviewView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.widget<Switch>(find.byType(Switch)).value, true);
      expect(await review.submit(), true);
      expect(reviews.created.single.silent, true);
      await tester.pumpWidget(const SizedBox());
      review.dispose();
      final visit = VisitViewModel(
        place: place,
        authRepository: auth,
        userRepository: users,
        visitRepository: visits,
        privacyRepository: privacy,
      );
      await visit.checkLock();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VisitSheet(viewModel: visit)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, true);
      expect(await visit.submit(), true);
      expect(visits.created.single.silent, true);
      await tester.pumpWidget(const SizedBox());
      visit.dispose();
    },
  );
  testWidgets(
    'Titular abre avaliações globais paginadas e rota falsa não oferece resposta',
    (tester) async {
      final db = FakeFirebaseFirestore();
      final auth = FakeAuthRepository(uid: 'owner');
      final owners = FakeOwnerRepository()..owners['p'] = 'owner';
      for (var i = 0; i < 21; i++) {
        await db.doc('reviews/r$i').set({
          'authorId': 'cliente$i',
          'authorName': 'Cliente $i',
          'placeId': 'p',
          'placeName': 'Local',
          'food': 4,
          'ambience': null,
          'service': null,
          'companion': null,
          'createdAt': Timestamp.fromDate(at.subtract(Duration(minutes: i))),
        });
      }
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            Provider<OwnerRepository>.value(value: owners),
            Provider<ReputationRepository>(
              create: (_) => FirestoreReputationRepository(db),
            ),
          ],
          child: const MaterialApp(home: OwnerReviewsView(placeId: 'p')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cliente 0'), findsOneWidget);
      final more = find.text('Carregar mais');
      await tester.scrollUntilVisible(
        more,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Cliente 20'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Cliente 20'), findsOneWidget);
      owners.owners.clear();
      auth.restoreSession('false-owner');
      await tester.pumpAndSettle();
      expect(
        find.text('Titularidade atual necessária para responder.'),
        findsOneWidget,
      );
      expect(find.text('Responder uma vez'), findsNothing);
    },
  );
  testWidgets('Destaque fica separado, rotulado Patrocinado e expira na tela', (
    tester,
  ) async {
    final auth = FakeAuthRepository(uid: 'a');
    var clock = at;
    final slot = SponsoredSlot(
      'slot',
      'p',
      at.subtract(const Duration(hours: 1)),
      at.add(const Duration(seconds: 10)),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthRepository>.value(value: auth),
          Provider<SponsorshipRepository>(create: (_) => _Sponsors(slot)),
          Provider<PlaceRepository>(
            create: (_) => FakePlaceRepository([place]),
          ),
          Provider<AppClock>.value(value: AppClock(() => clock)),
        ],
        child: const MaterialApp(home: SponsoredView()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SponsoredCard), findsOneWidget);
    expect(find.text('Patrocinado'), findsNWidgets(2));
    expect(find.text('Local'), findsOneWidget);
    clock = at.add(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(find.byType(SponsoredCard), findsNothing);
    expect(find.text('Nenhum destaque disponível.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Modo silencioso salva preferência privada futura e troca de conta limpa valor',
    (tester) async {
      final db = FakeFirebaseFirestore();
      final auth = FakeAuthRepository(uid: 'a');
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            Provider<PrivacyRepository>(
              create: (_) => FirestorePrivacyRepository(db),
            ),
          ],
          child: const MaterialApp(home: PrivacyView()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('nome e todos os dados'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        (await db.doc('users/a/preferences/privacy').get()).data()!['silent'],
        true,
      );
      auth.restoreSession('b');
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
    },
  );
  testWidgets(
    'Resposta envia uma vez, aparece rotulada com autoria e horário',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/a').set({'displayName': 'Titular A'});
      await db.doc('reviews/r').set({'placeId': 'p'});
      final auth = FakeAuthRepository(uid: 'a');
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            Provider<ReputationRepository>(
              create: (_) => FirestoreReputationRepository(db),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ReplyLine(reviewId: 'r', canReply: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        '  Obrigado pela visita!  ',
      );
      await tester.pump();
      await tester.tap(find.text('Responder uma vez'));
      await tester.pumpAndSettle();
      expect(find.text('Obrigado pela visita!'), findsOneWidget);
      expect(
        find.textContaining('Resposta do estabelecimento · Titular A ·'),
        findsOneWidget,
      );
      expect(find.text('Responder uma vez'), findsNothing);
      expect((await db.collection('auditLog').get()).docs, hasLength(1));
    },
  );
  testWidgets(
    'Fila recusa GPS ausente sem spinner preso; envio válido identificado expira',
    (tester) async {
      final auth = FakeAuthRepository(uid: 'a');
      final users = FakeUserRepository()..addUser('a', 'Ana');
      final location = FakeLocationService();
      final queue = _QueueRepository(at);
      var clock = at;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthRepository>.value(value: auth),
            Provider<UserRepository>.value(value: users),
            Provider<QueueRepository>.value(value: queue),
            Provider<OwnerRepository>(create: (_) => FakeOwnerRepository()),
            Provider<LocationService>.value(value: location),
            Provider<AppClock>.value(value: AppClock(() => clock)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: QueueSection(place: place)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '12');
      await tester.tap(find.text('Relatar espera'));
      await tester.pumpAndSettle();
      expect(find.textContaining('até 150 m.'), findsOneWidget);
      expect(find.text('Relatar espera'), findsOneWidget);
      expect(queue.writes, 0);
      location.position = (lat: -23.5, lng: -46.6);
      await tester.tap(find.text('Relatar espera'));
      await tester.pumpAndSettle();
      expect(queue.writes, 1);
      expect(queue.reports.single.authorName, 'Ana');
      queue.lastAt = at;
      await tester.tap(find.text('Relatar espera'));
      await tester.pumpAndSettle();
      expect(
        find.text('Aguarde 30 minutos entre relatos neste local.'),
        findsOneWidget,
      );
      expect(queue.writes, 1);
      expect(location.locateCalls, 2);
      expect(
        find.textContaining('Ao vivo: mediana 12 min · 1 pessoas'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Histórico: amostra insuficiente'),
        findsOneWidget,
      );
      clock = at.add(const Duration(hours: 1));
      await tester.pump(const Duration(seconds: 15));
      expect(find.text('Sem sinal recente de fila'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Conta muda enquanto fila carrega: resposta antiga descartada', (
    tester,
  ) async {
    final auth = FakeAuthRepository(uid: 'a');
    final queue = _QueueRepository(at)
      ..readGate = Completer<List<QueueReport>>();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthRepository>.value(value: auth),
          Provider<QueueRepository>.value(value: queue),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: QueueSection(place: place)),
          ),
        ),
      ),
    );
    await tester.pump();
    auth.restoreSession(null);
    await tester.pump();
    queue.readGate!.complete([
      QueueReport(
        id: 'old',
        authorId: 'a',
        authorName: 'Ana',
        placeId: 'p',
        minutes: 99,
        createdAt: at,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.textContaining('99 min'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

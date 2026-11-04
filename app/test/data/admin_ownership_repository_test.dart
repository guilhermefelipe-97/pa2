import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/data/firebase/firestore_admin_ownership_repository.dart';
import 'package:naarea/data/firebase/firestore_owner_repository.dart';
import 'package:naarea/data/repositories/admin_ownership_repository.dart';

class LostResponseFirestore extends FakeFirebaseFirestore {
  bool loseResponse = false, failReconciliation = false;
  bool readsBlocked = false;
  Completer<void>? responseGate;
  @override
  DocumentReference<Map<String, dynamic>> doc(String path) {
    final original = super.doc(path);
    return path == 'users/alice/ownershipRequests/p'
        ? RequestReference(original, this)
        : original;
  }

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final result = await super.runTransaction(
      handler,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
    if (responseGate != null) await responseGate!.future;
    readsBlocked = failReconciliation;
    if (loseResponse) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return result;
  }
}

// ignore: subtype_of_sealed_class
class RequestReference implements DocumentReference<Map<String, dynamic>> {
  RequestReference(this.delegate, this.db);
  final DocumentReference<Map<String, dynamic>> delegate;
  final LostResponseFirestore db;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) {
    if (db.readsBlocked) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return delegate.get(options);
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) =>
      delegate.set(data, options);
  @override
  Future<void> update(Map<Object, Object?> data) => delegate.update(data);
  @override
  String get path => delegate.path;
  @override
  String get id => delegate.id;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Metadata implements SnapshotMetadata {
  Metadata(this.isFromCache, this.hasPendingWrites);
  @override
  final bool isFromCache;
  @override
  final bool hasPendingWrites;
}

// ignore: subtype_of_sealed_class
class AccessSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  AccessSnapshot(this.metadata, this.enabled);
  @override
  final SnapshotMetadata metadata;
  final bool enabled;
  @override
  Map<String, dynamic> data() => {'enabled': enabled};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late LostResponseFirestore db;
  late FirestoreAdminOwnershipRepository repo;
  setUp(() async {
    db = LostResponseFirestore();
    repo = FirestoreAdminOwnershipRepository(db);
    await db.doc('admins/operator').set({'enabled': true});
    await db.doc('users/alice').set({'displayName': 'Alice'});
    await db.doc('places/p').set({'name': 'Local'});
    await db.doc('users/alice/ownershipRequests/p').set({
      'status': 'pending',
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(1000),
    });
  });
  Future<void> decide({bool approve = true}) => repo.decide(
    operator: 'operator',
    uid: 'alice',
    placeId: 'p',
    approve: approve,
    reason: ' Verificado ',
  );
  test(
    'collection group derives identity from path; approval preserves script schema and applicant reason',
    () async {
      final page = await repo.pending();
      expect(page.requests.single.uid, 'alice');
      expect(page.requests.single.place, 'Local');
      await decide();
      final d = (await db.doc('users/alice/ownershipRequests/p').get()).data()!;
      expect(d['createdAt'], Timestamp.fromMillisecondsSinceEpoch(1000));
      expect(d['operator'], 'operator');
      expect(d['reason'], 'Verificado');
      expect(d['approval']['operator'], d['operator']);
      expect(d['approval']['reason'], d['reason']);
      expect((await db.doc('placeOwners/p').get()).data()!['uid'], 'alice');
      expect(
        (await FirestoreOwnerRepository(db).requestsOf('alice')).single.reason,
        'Verificado',
      );
      await expectLater(decide(), throwsA(isA<AdminConflict>()));
    },
  );
  test(
    'lost committed response is reconciled before a second submission',
    () async {
      db.loseResponse = true;
      await decide();
      expect((await repo.detail('alice', 'p'))!.status, 'approved');
    },
  );
  test(
    'rejection writes only request and existing owner is never replaced',
    () async {
      await db.doc('placeOwners/p').set({
        'uid': 'alice',
        'verifiedAt': Timestamp.now(),
      });
      await expectLater(decide(), throwsA(isA<AdminConflict>()));
      await decide(approve: false);
      final d = (await db.doc('users/alice/ownershipRequests/p').get()).data()!;
      expect(d['status'], 'rejected');
      expect(d['rejection']['reason'], 'Verificado');
    },
  );
  test(
    'páginas reais com 45 datas iguais avançam sem repetir e terminam',
    () async {
      for (var i = 0; i < 44; i++) {
        final id = 'local-${i.toString().padLeft(2, '0')}';
        await db.doc('places/$id').set({'name': id});
        await db.doc('users/alice/ownershipRequests/$id').set({
          'status': 'pending',
          'createdAt': Timestamp.fromMillisecondsSinceEpoch(1000),
        });
      }
      final ids = <String>[];
      Object? cursor;
      var pages = 0;
      do {
        final page = await repo.pending(cursor: cursor);
        pages++;
        ids.addAll(page.requests.map((r) => '${r.uid}/${r.placeId}'));
        cursor = page.cursor;
        expect(pages, lessThan(5));
      } while (cursor != null);
      expect(ids, hasLength(45));
      expect(ids.toSet(), hasLength(45));
      expect(pages, 3);
    },
  );
  test(
    'pedido corrompido preserva vizinhos; histórico mostra operador/data/titular',
    () async {
      await db.doc('places/corrompido').set({'name': 'Quebrado'});
      await db.doc('users/alice/ownershipRequests/corrompido').set({
        'status': 'pending',
        'createdAt': Timestamp.now(),
        'reason': 42,
      });
      final page = await repo.pending();
      expect(page.requests, hasLength(2));
      expect(
        page.requests.where((r) => !r.available).single.placeId,
        'corrompido',
      );
      expect(page.requests.where((r) => r.available).single.placeId, 'p');
      await decide();
      final detail = (await repo.detail('alice', 'p'))!;
      expect(detail.operator, 'operator');
      expect(detail.decidedAt, isNotNull);
      expect(detail.ownerUid, 'alice');
    },
  );
  test(
    'timeout mantém trava até terminar operação; falha de reconciliação exige leitura confiável',
    () async {
      repo = FirestoreAdminOwnershipRepository(
        db,
        decisionTimeout: const Duration(milliseconds: 10),
      );
      db.responseGate = Completer();
      db.loseResponse = true;
      db.failReconciliation = true;
      await expectLater(decide(), throwsA(isA<AdminUncertain>()));
      await expectLater(decide(), throwsA(isA<AdminUncertain>()));
      await expectLater(
        repo.detail('alice', 'p'),
        throwsA(isA<AdminUncertain>()),
      );
      db.responseGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await expectLater(
        repo.detail('alice', 'p'),
        throwsA(isA<FirebaseException>()),
      );
      db.readsBlocked = false;
      expect((await repo.detail('alice', 'p'))!.status, 'approved');
    },
  );
  test(
    'observeAccess exige servidor sem escrita pendente e propaga erro recuperável',
    () async {
      final snapshots =
          StreamController<DocumentSnapshot<Map<String, dynamic>>>();
      repo = FirestoreAdminOwnershipRepository(
        db,
        accessSnapshots: (_) => snapshots.stream,
      );
      final values = <bool>[];
      final errors = <Object>[];
      final subscription = repo
          .observeAccess('operator')
          .listen(values.add, onError: errors.add);
      snapshots.add(AccessSnapshot(Metadata(true, false), true));
      snapshots.add(AccessSnapshot(Metadata(false, true), true));
      snapshots.add(AccessSnapshot(Metadata(false, false), true));
      snapshots.addError(StateError('sem conexão'));
      snapshots.add(AccessSnapshot(Metadata(false, false), false));
      await Future<void>.delayed(Duration.zero);
      expect(values, [false, false, true, false]);
      expect(errors, hasLength(1));
      await subscription.cancel();
      await snapshots.close();
    },
  );
  test('papel revogado na transação retorna negativa de permissão', () async {
    await db.doc('admins/operator').set({'enabled': false});
    await expectLater(
      decide(),
      throwsA(
        isA<FirebaseException>().having(
          (e) => e.code,
          'código',
          'permission-denied',
        ),
      ),
    );
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/sponsorship_repository.dart';

class FirestoreSponsorshipRepository implements SponsorshipRepository {
  FirestoreSponsorshipRepository(this.db, {this.emulator = false});
  final FirebaseFirestore db;
  final bool emulator;
  @override
  Future<List<SponsoredSlot>> current(DateTime now) async {
    // Produção desligada até F23/F26, independentemente da flag do servidor.
    if (!emulator) return [];
    final config = await db
        .collection('config')
        .doc('features')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));
    if (config.data()?['sponsorshipEnabled'] != true) return [];
    // Catálogo confiável: leituras por ID permitem às Rules validar vigência
    // e titularidade de cada slot sem tratar regras como filtros de consulta.
    final ids = config.data()?['sponsoredSlotIds'];
    if (ids is! List || ids.any((id) => id is! String)) return [];
    final docs = <DocumentSnapshot<Map<String, dynamic>>>[];
    for (final id in ids.cast<String>().toSet()) {
      try {
        final doc = await db
            .collection('sponsoredSlots')
            .doc(id)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));
        if (doc.exists) docs.add(doc);
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
      }
    }
    final result = <SponsoredSlot>[];
    for (final doc in docs) {
      final d = doc.data()!;
      final placeId = d['placeId'];
      if (placeId is! String ||
          placeId.isEmpty ||
          placeId.contains('/') ||
          d['startsAt'] is! Timestamp ||
          d['endsAt'] is! Timestamp ||
          d.keys.toSet().difference({
            'placeId',
            'startsAt',
            'endsAt',
          }).isNotEmpty) {
        continue;
      }
      final owner = await db
          .collection('placeOwners')
          .doc(placeId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      if (!owner.exists) continue;
      final slot = SponsoredSlot(
        doc.id,
        placeId,
        (d['startsAt'] as Timestamp).toDate(),
        (d['endsAt'] as Timestamp).toDate(),
      );
      if (slot.active(now)) result.add(slot);
    }
    return result;
  }
}

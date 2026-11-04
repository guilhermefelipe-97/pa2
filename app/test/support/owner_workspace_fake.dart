import 'package:naarea/data/repositories/owner_workspace_repository.dart';

class FakeOwnerWorkspace implements OwnerWorkspaceRepository {
  final values = <String, PlacePresentation>{};
  final summaries = <String, OwnerPlaceSummary>{};
  bool failSave = false, failSummary = false;
  int saves = 0;
  @override
  Future<PlacePresentation> presentation(String placeId) async =>
      values[placeId] ?? const PlacePresentation();
  @override
  Future<void> save(String placeId, String uid, PlacePresentation value) async {
    if (failSave) throw StateError('offline');
    saves++;
    values[placeId] = value;
  }

  @override
  Future<OwnerPlaceSummary> summary(String placeId) async {
    if (failSummary) throw StateError('offline');
    return summaries[placeId] ??
        const OwnerPlaceSummary(reviews: 0, unanswered: 0);
  }
}

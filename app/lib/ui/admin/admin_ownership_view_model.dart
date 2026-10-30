import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/safe_change_notifier.dart';
import '../../data/repositories/admin_ownership_repository.dart';
import '../../domain/models/admin_ownership_request.dart';
import 'admin_access.dart';

class AdminOwnershipViewModel extends SafeChangeNotifier {
  AdminOwnershipViewModel(
    this.access,
    this.repository, {
    this.uid,
    this.placeId,
  }) {
    access.addListener(_accessChanged);
    _accessChanged();
  }
  final AdminAccess access;
  final AdminOwnershipRepository repository;
  final String? uid, placeId;
  List<AdminOwnershipRequest> requests = [];
  AdminOwnershipRequest? request;
  Object? cursor;
  bool busy = false, uncertain = false;
  String? message;
  int _epoch = 0;
  bool _disposed = false;
  void _accessChanged() {
    _epoch++;
    requests = [];
    request = null;
    cursor = null;
    busy = false;
    uncertain = false;
    message = null;
    notifyListeners();
    if (access.enabled) load();
  }

  bool _current(int epoch) => !_disposed && access.enabled && epoch == _epoch;
  Future<void> load({bool more = false}) async {
    if (!access.enabled || busy) return;
    final epoch = _epoch;
    busy = true;
    if (uid != null) uncertain = true;
    message = null;
    notifyListeners();
    try {
      if (uid != null) {
        final result = await repository
            .detail(uid!, placeId!)
            .timeout(const Duration(seconds: 15));
        if (!_current(epoch)) return;
        request = result;
        uncertain = false;
        if (result == null) message = 'Pedido não encontrado';
      } else {
        final result = await repository
            .pending(cursor: more ? cursor : null)
            .timeout(const Duration(seconds: 15));
        if (!_current(epoch)) return;
        requests = more ? [...requests, ...result.requests] : result.requests;
        cursor = result.cursor;
      }
    } on FirebaseException catch (error) {
      if (_current(epoch)) {
        if (error.code == 'permission-denied') {
          access.invalidate();
        } else {
          message = 'Não foi possível carregar. Tente novamente.';
        }
      }
    } on Object {
      if (_current(epoch)) {
        message = 'Não foi possível carregar. Tente novamente.';
      }
    } finally {
      if (_current(epoch)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> decide(bool approve, String reason) async {
    if (!access.enabled ||
        busy ||
        uncertain ||
        request?.status != 'pending' ||
        request?.available != true ||
        (approve && request?.ownerUid != null) ||
        access.uid == uid ||
        reason.trim().isEmpty ||
        reason.trim().length > 500) {
      return;
    }
    final epoch = _epoch;
    busy = true;
    message = null;
    notifyListeners();
    try {
      await repository.decide(
        operator: access.uid!,
        uid: uid!,
        placeId: placeId!,
        approve: approve,
        reason: reason,
      );
      if (!_current(epoch)) return;
      busy = false;
      uncertain = true;
      await load();
      if (_current(epoch)) {
        message = uncertain
            ? 'Decisão concluída, mas o detalhe está indisponível. Atualize para conferir.'
            : 'Decisão registrada';
      }
    } on FirebaseException catch (error) {
      if (_current(epoch)) {
        if (error.code == 'permission-denied') {
          access.invalidate();
        } else {
          uncertain = true;
          message = 'Não foi possível decidir. Atualize e tente novamente.';
        }
      }
    } on AdminUncertain {
      if (_current(epoch)) {
        uncertain = true;
        message =
            'Confirmação indisponível. Atualize o pedido antes de tentar novamente.';
      }
    } on AdminConflict {
      if (!_current(epoch)) return;
      busy = false;
      uncertain = true;
      await load();
      if (_current(epoch)) {
        message =
            'Conflito: pedido decidido, titular existente ou acesso alterado. Confira os dados atualizados.';
      }
    } on Object {
      if (_current(epoch)) {
        message = 'Não foi possível decidir. Atualize e tente novamente.';
      }
    } finally {
      if (_current(epoch)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    access.removeListener(_accessChanged);
    super.dispose();
  }
}

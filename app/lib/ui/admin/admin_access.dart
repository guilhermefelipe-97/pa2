import 'dart:async';
import '../core/safe_change_notifier.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/admin_ownership_repository.dart';

enum AdminAccessState { loading, denied, error, enabled }

class AdminAccess extends SafeChangeNotifier {
  AdminAccess(this.auth, this.repository) {
    auth.addListener(_session);
    _session();
  }
  final AuthRepository auth;
  final AdminOwnershipRepository repository;
  StreamSubscription<bool>? _subscription;
  String? uid;
  AdminAccessState state = AdminAccessState.denied;
  bool get enabled => state == AdminAccessState.enabled;
  int generation = 0, _sessionGeneration = 0;
  void _session() {
    if (uid == auth.currentUserId) return;
    uid = auth.currentUserId;
    retry();
  }

  void retry() {
    final session = ++_sessionGeneration;
    _subscription?.cancel();
    state = uid == null ? AdminAccessState.denied : AdminAccessState.loading;
    generation++;
    notifyListeners();
    if (uid == null) return;
    _subscription = repository
        .observeAccess(uid!)
        .listen(
          (value) {
            if (_sessionGeneration != session || isDisposed) return;
            final next = value
                ? AdminAccessState.enabled
                : AdminAccessState.denied;
            if (state == next) return;
            state = next;
            generation++;
            notifyListeners();
          },
          onError: (Object _) {
            if (_sessionGeneration != session || isDisposed) return;
            invalidate();
          },
        );
  }

  void invalidate() {
    _sessionGeneration++;
    _subscription?.cancel();
    state = AdminAccessState.error;
    generation++;
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionGeneration++;
    auth.removeListener(_session);
    _subscription?.cancel();
    super.dispose();
  }
}

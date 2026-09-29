import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../domain/models/companion.dart';
import '../../domain/models/place.dart';
import '../../domain/models/review.dart';
import '../../domain/models/scores.dart';
import '../core/safe_change_notifier.dart';

/// Avaliação em 3 eixos (F01) com contexto (F02) e comentário opcional.
class ReviewViewModel extends SafeChangeNotifier {
  ReviewViewModel({
    required this.place,
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required ReviewRepository reviewRepository,
  })  : _auth = authRepository,
        _users = userRepository,
        _reviews = reviewRepository;

  final Place place;
  final AuthRepository _auth;
  final UserRepository _users;
  final ReviewRepository _reviews;

  static const String saveError = 'Não foi possível salvar';

  int? _food;
  int? _ambience;
  int? _service;
  Companion? _companion;
  String _comment = '';

  int? get food => _food;
  int? get ambience => _ambience;
  int? get service => _service;
  Companion? get companion => _companion;

  /// Texto como digitado (é aparado só no envio).
  String get comment => _comment;

  /// Acima de 280 unidades UTF-16 depois do trim (mesma conta das Rules).
  bool get commentTooLong => !Review.isCommentWithinLimit(_comment);

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Os 3 eixos são obrigatórios; companhia e comentário são opcionais.
  bool get canSubmit =>
      !_isSubmitting &&
      Scores.isValid(_food) &&
      Scores.isValid(_ambience) &&
      Scores.isValid(_service) &&
      !commentTooLong;

  void setFood(int value) => _set(() => _food = _clamp(value));
  void setAmbience(int value) => _set(() => _ambience = _clamp(value));
  void setService(int value) => _set(() => _service = _clamp(value));

  /// Tocar de novo na companhia selecionada desmarca.
  void toggleCompanion(Companion value) =>
      _set(() => _companion = _companion == value ? null : value);

  void setComment(String value) => _set(() => _comment = value);

  int? _clamp(int v) => Scores.isValid(v) ? v : null;

  void _set(void Function() change) {
    change();
    _errorMessage = null;
    notifyListeners();
  }

  /// Retorna `true` quando a avaliação foi gravada.
  Future<bool> submit() async {
    if (!canSubmit) return false;
    final uid = _auth.currentUserId;
    if (uid == null) {
      _errorMessage = saveError;
      notifyListeners();
      return false;
    }
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final profile = await _users.getProfile(uid);
      if (profile == null) throw StateError('perfil ausente');
      await _reviews.createReview(NewReview(
        authorId: uid,
        authorName: profile.displayName,
        placeId: place.id,
        placeName: place.name,
        scores: Scores(food: _food!, ambience: _ambience!, service: _service!),
        companion: _companion,
        comment: _comment, // NewReview normaliza: trim, vazio → null
      ));
      return true;
    } on Object {
      // Inclui permission-denied das Rules.
      _errorMessage = saveError;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}

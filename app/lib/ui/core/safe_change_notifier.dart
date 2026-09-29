import 'package:flutter/foundation.dart';

/// ChangeNotifier que ignora `notifyListeners` depois do `dispose` — evita
/// erro quando uma operação assíncrona termina após a tela ter saído.
class SafeChangeNotifier extends ChangeNotifier {
  bool _disposed = false;

  bool get isDisposed => _disposed;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

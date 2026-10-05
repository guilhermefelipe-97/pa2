import 'package:flutter/widgets.dart';

/// Cria o ViewModel uma única vez por tela e o descarta junto com ela.
/// Evita recriar o ViewModel quando o go_router reconstrói a rota
/// (ex.: `refreshListenable` disparando por mudança de auth).
class ViewModelHost<T extends ChangeNotifier> extends StatefulWidget {
  const ViewModelHost({super.key, required this.create, required this.builder});

  final T Function(BuildContext context) create;
  final Widget Function(BuildContext context, T viewModel) builder;

  @override
  State<ViewModelHost<T>> createState() => _ViewModelHostState<T>();
}

class _ViewModelHostState<T extends ChangeNotifier>
    extends State<ViewModelHost<T>> {
  late final T _viewModel = widget.create(context);

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _viewModel);
}

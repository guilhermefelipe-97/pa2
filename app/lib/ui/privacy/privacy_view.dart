import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/privacy_repository.dart';

class PrivacyView extends StatelessWidget {
  const PrivacyView({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthRepository>().currentUserId;
    return Scaffold(
      appBar: AppBar(title: const Text('Modo silencioso')),
      body: uid == null
          ? const SizedBox.shrink()
          : _Preference(key: ValueKey(uid), uid: uid),
    );
  }
}

class _Preference extends StatefulWidget {
  const _Preference({super.key, required this.uid});
  final String uid;
  @override
  State<_Preference> createState() => _PreferenceState();
}

class _PreferenceState extends State<_Preference> {
  bool? value;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  int _loadSequence = 0;
  Future<void> load() async {
    final sequence = ++_loadSequence;
    try {
      final result = await context.read<PrivacyRepository>().silentDefault(
        widget.uid,
      );
      if (mounted && sequence == _loadSequence) {
        setState(() {
          value = result;
          error = null;
        });
      }
    } on Object {
      if (mounted && sequence == _loadSequence) {
        setState(() => error = 'Não foi possível carregar. Tentar novamente');
      }
    }
  }

  Future<void> save(bool next) async {
    if (busy) return;
    _loadSequence++;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await context.read<PrivacyRepository>().setSilentDefault(
        widget.uid,
        next,
      );
      if (mounted) setState(() => value = next);
    } on Object {
      if (mounted) {
        setState(() => error = 'Não foi possível salvar. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(silentScope),
      if (value != null)
        SwitchListTile(
          title: const Text('Usar em futuras avaliações e visitas'),
          value: value!,
          onChanged: busy ? null : save,
        ),
      if (value == null && error == null)
        const Center(child: CircularProgressIndicator()),
      if (error != null)
        TextButton(onPressed: busy ? null : load, child: Text(error!)),
    ],
  );
}

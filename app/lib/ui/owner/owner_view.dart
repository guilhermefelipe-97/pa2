export 'owner_dashboard.dart' show OwnerView;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/owner_repository.dart';
import '../../data/repositories/place_repository.dart';

class OwnershipButton extends StatefulWidget {
  const OwnershipButton({super.key, required this.placeId});
  final String placeId;
  @override
  State<OwnershipButton> createState() => _OwnershipButtonState();
}

class _OwnershipButtonState extends State<OwnershipButton> {
  bool busy = false;
  String? message;
  String? sessionUid;
  @override
  Widget build(BuildContext context) {
    final repository = context.read<OwnerRepository?>();
    if (repository == null) return const SizedBox.shrink();
    final auth = context.watch<AuthRepository>();
    if (sessionUid != auth.currentUserId) {
      sessionUid = auth.currentUserId;
      message = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Este estabelecimento é seu?'),
        const SizedBox(height: 8),
        Text(
          'Solicite o vínculo com este local. A verificação é feita fora do app.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('ownership-request-submit'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.storefront),
          label: const Text(
            'Solicitar titularidade',
            textAlign: TextAlign.center,
          ),
          onPressed: busy
              ? null
              : () async {
                  final uid = context.read<AuthRepository>().currentUserId;
                  if (uid == null) return;
                  final places = context.read<PlaceRepository>();
                  setState(() {
                    busy = true;
                    message = null;
                  });
                  try {
                    await ensurePlaceForSave(
                      places,
                      uid: uid,
                      placeId: widget.placeId,
                    );
                    if (auth.currentUserId != uid) return;
                    final request = await repository.request(
                      uid,
                      widget.placeId,
                    );
                    if (!mounted || auth.currentUserId != uid) return;
                    setState(
                      () => message = switch (request.status) {
                        'pending' =>
                          'Pedido pendente. A verificação ocorre fora do app; não envie documentos pessoais.',
                        'approved' =>
                          'Pedido aprovado. Consulte Meus estabelecimentos.',
                        'revoked' =>
                          'Titularidade revogada. Consulte Meus estabelecimentos.',
                        _ =>
                          'Pedido rejeitado. Consulte Meus estabelecimentos.',
                      },
                    );
                  } on Object {
                    if (mounted && auth.currentUserId == uid) {
                      setState(
                        () => message =
                            'Não foi possível solicitar. Tente novamente.',
                      );
                    }
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
        ),
        if (message != null) ...[
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Text(message!)),
        ],
      ],
    );
  }
}

class OwnershipAction extends StatelessWidget {
  const OwnershipAction({super.key, required this.placeId});
  final String placeId;
  @override
  Widget build(BuildContext context) {
    if (context.read<OwnerRepository?>() == null) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: 'Solicitar titularidade',
      icon: const Icon(Icons.storefront_outlined),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          titleTextStyle: Theme.of(context).textTheme.titleLarge,
          title: const Text('Titularidade do estabelecimento'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: OwnershipButton(placeId: placeId),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }
}

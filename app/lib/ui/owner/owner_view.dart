import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/owner_repository.dart';
import '../../data/repositories/place_repository.dart';
import '../../routing/routes.dart';

class OwnerView extends StatefulWidget {
  const OwnerView({super.key});
  @override
  State<OwnerView> createState() => _OwnerViewState();
}

class _OwnerRow {
  const _OwnerRow(this.request, this.name, this.owned, this.failed);
  final OwnershipRequest request;
  final String name;
  final bool owned;
  final bool failed;
}

class _OwnerViewState extends State<OwnerView> {
  Future<List<_OwnerRow>>? _read;
  String? _uid;
  int _generation = 0;

  Future<List<_OwnerRow>> _load(String uid) async {
    final repository = context.read<OwnerRepository>();
    final places = context.read<PlaceRepository>();
    final requests = await repository.requestsOf(uid);
    final names = await places.getPlaces(requests.map((r) => r.placeId));
    return Future.wait(
      requests.map((r) async {
        try {
          final owner = await repository
              .ownerOf(r.placeId)
              .timeout(ownerLookupTimeout);
          return _OwnerRow(
            r,
            names[r.placeId]?.name ?? 'Estabelecimento',
            owner == uid,
            false,
          );
        } on Object {
          return _OwnerRow(
            r,
            names[r.placeId]?.name ?? 'Estabelecimento',
            false,
            true,
          );
        }
      }),
    );
  }

  void _refresh() => setState(() {
    _generation++;
    _read = null;
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthRepository>();
    if (_uid != auth.currentUserId || _read == null) {
      _uid = auth.currentUserId;
      _generation++;
      _read = _uid == null ? Future.value([]) : _load(_uid!);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus estabelecimentos'),
        actions: [
          IconButton(
            tooltip: 'Atualizar titularidade',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<_OwnerRow>>(
        key: ValueKey('$_uid-$_generation'),
        future: _read,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: TextButton(
                onPressed: _refresh,
                child: const Text('Tentar novamente'),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          if (rows.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Abra a ficha do seu estabelecimento para solicitar titularidade. A verificação é feita fora do app.',
              ),
            );
          }
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return ListTile(
                title: Text(row.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.failed
                          ? 'Não foi possível verificar titularidade'
                          : row.owned
                          ? 'Titularidade verificada'
                          : switch (row.request.status) {
                              'pending' =>
                                'Pedido pendente — sem poderes até a aprovação',
                              'approved' ||
                              'revoked' => 'Titularidade revogada',
                              _ => 'Pedido rejeitado',
                            },
                    ),
                    if (row.owned)
                      TextButton.icon(
                        icon: const Icon(Icons.campaign_outlined),
                        label: const Text('Divulgação'),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Divulgação'),
                            content: const Text(
                              'A contratação de divulgação está indisponível no momento.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Fechar'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (row.request.reason != null)
                      Text(
                        '${row.request.status == 'revoked' ? 'Motivo da aprovação original' : 'Motivo'}: ${row.request.reason}',
                      ),
                    if (row.request.status == 'revoked' &&
                        row.request.revocationReason != null)
                      Text(
                        'Motivo da revogação: ${row.request.revocationReason}',
                      ),
                  ],
                ),
                trailing: row.owned
                    ? TextButton(
                        onPressed: () => context.push(
                          '/meus-estabelecimentos/${Uri.encodeComponent(row.request.placeId)}/avaliacoes',
                        ),
                        child: const Text('Avaliações e respostas'),
                      )
                    : null,
                onTap: () =>
                    context.push(Routes.placeDetail(row.request.placeId)),
              );
            },
          );
        },
      ),
    );
  }
}

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
        TextButton.icon(
          icon: const Icon(Icons.storefront),
          label: const Text(
            'Este estabelecimento é seu? Solicitar titularidade',
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
        if (message != null) Text(message!),
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
          title: const Text('Titularidade do estabelecimento'),
          content: SingleChildScrollView(
            child: OwnershipButton(placeId: placeId),
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

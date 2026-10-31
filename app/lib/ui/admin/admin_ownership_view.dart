import '../core/editorial.dart';
import 'admin_access_view.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../routing/routes.dart';
import 'admin_ownership_view_model.dart';

class AdminOwnershipView extends StatefulWidget {
  const AdminOwnershipView({super.key, required this.viewModel});
  final AdminOwnershipViewModel viewModel;
  @override
  State<AdminOwnershipView> createState() => _AdminOwnershipViewState();
}

class _AdminOwnershipViewState extends State<AdminOwnershipView> {
  final reason = TextEditingController();
  bool verified = false, confirming = false;
  String? session;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> _confirm(bool approve) async {
    final vm = widget.viewModel;
    if (confirming || vm.busy || !vm.access.enabled) return;
    setState(() => confirming = true);
    final generation = vm.access.generation;
    final text = reason.text.trim();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: vm.access,
        builder: (context, _) => AlertDialog(
          title: Text(
            approve ? 'Confirmar aprovação?' : 'Confirmar reprovação?',
          ),
          content: Text(
            vm.access.enabled && generation == vm.access.generation
                ? 'Solicitante: ${vm.request!.applicant}\nIdentificador da conta: ${vm.request!.uid}\nEstabelecimento: ${vm.request!.place}\nIdentificador do local: ${vm.request!.placeId}\n\nO solicitante verá este motivo:\n$text'
                : 'Acesso alterado. Feche esta confirmação.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: vm.access.enabled && generation == vm.access.generation
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => confirming = false);
    if (accepted == true &&
        vm.access.enabled &&
        generation == vm.access.generation) {
      await vm.decide(approve, text);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.viewModel,
    builder: (context, _) {
      final vm = widget.viewModel;
      if (session != vm.access.uid || !vm.access.enabled) {
        session = vm.access.uid;
        reason.clear();
        verified = false;
      }
      final r = vm.request;
      final valid =
          reason.text.trim().isNotEmpty && reason.text.trim().length <= 500;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Solicitações de titularidade'),
          actions: [
            IconButton(
              onPressed: vm.busy || !vm.access.enabled ? null : vm.load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Atualizar',
            ),
          ],
        ),
        body: !vm.access.enabled
            ? AdminAccessView(access: vm.access)
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const EditorialHeading(
                    eyebrow: 'Administração',
                    title: 'Moderação de titularidade',
                  ),
                  if (vm.busy) const LinearProgressIndicator(),
                  if (vm.message != null) Text(vm.message!),
                  if (vm.message != null)
                    TextButton(
                      onPressed: vm.busy ? null : vm.load,
                      child: const Text('Tentar novamente'),
                    ),
                  if (vm.uid == null) ...[
                    if (!vm.busy && vm.requests.isEmpty && vm.message == null)
                      const Text('Nenhuma solicitação pendente'),
                    for (final item in vm.requests)
                      Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: const Icon(Icons.storefront_outlined),
                          title: Text(item.place),
                          subtitle: Text(
                            item.available
                                ? '${item.applicant} · ${_date(item.createdAt)}'
                                : 'Pedido indisponível · Conta: ${item.uid} · Local: ${item.placeId}',
                          ),
                          onTap: !item.available
                              ? null
                              : () async {
                                  await context.push(
                                    Routes.adminRequest(item.uid, item.placeId),
                                  );
                                  if (mounted) vm.load();
                                },
                        ),
                      ),
                    if (vm.cursor != null)
                      TextButton(
                        onPressed: vm.busy ? null : () => vm.load(more: true),
                        child: const Text('Carregar mais'),
                      ),
                  ] else if (r != null) ...[
                    Text(
                      r.place,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      'Solicitante: ${r.applicant}\nIdentificador da conta: ${r.uid}\nData: ${_date(r.createdAt)}\nStatus: ${_status(r.status)}',
                    ),
                    TextButton(
                      onPressed: () => context.push(Routes.person(r.uid)),
                      child: const Text('Abrir perfil do solicitante'),
                    ),
                    TextButton(
                      onPressed: () =>
                          context.push(Routes.placeDetail(r.placeId)),
                      child: const Text('Abrir ficha do local'),
                    ),
                    if (r.reason != null) Text('Motivo: ${r.reason}'),
                    if (r.operator != null)
                      Text(
                        'Decidido por (identificador da conta): ${r.operator}',
                      ),
                    if (r.decidedAt != null)
                      Text('Data da decisão: ${_date(r.decidedAt!)}'),
                    if (r.ownerUid != null)
                      Text(
                        'Este local já possui titular verificado (conta: ${r.ownerUid}). A aprovação está bloqueada; você pode reprovar o pedido.',
                      ),
                    if (r.available &&
                        r.status == 'pending' &&
                        r.uid != vm.access.uid) ...[
                      TextField(
                        controller: reason,
                        maxLength: 500,
                        enabled: !vm.busy && !confirming,
                        decoration: const InputDecoration(
                          labelText:
                              'Motivo visível ao solicitante (obrigatório)',
                          helperText:
                              'Registre método e conclusão. Não inclua documentos ou notas privadas.',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      CheckboxListTile(
                        value: verified,
                        onChanged: vm.busy || confirming
                            ? null
                            : (value) => setState(() => verified = value!),
                        title: const Text(
                          'Verifiquei externamente a identidade e a representação do estabelecimento',
                        ),
                      ),
                      FilledButton(
                        onPressed:
                            valid &&
                                verified &&
                                r.ownerUid == null &&
                                !vm.busy &&
                                !confirming &&
                                !vm.uncertain
                            ? () => _confirm(true)
                            : null,
                        child: const Text('Aprovar'),
                      ),
                      OutlinedButton(
                        onPressed:
                            valid && !vm.busy && !confirming && !vm.uncertain
                            ? () => _confirm(false)
                            : null,
                        child: const Text('Reprovar'),
                      ),
                    ],
                    if (r.uid == vm.access.uid)
                      const Text('Você não pode decidir seu próprio pedido.'),
                  ],
                ],
              ),
      );
    },
  );
}

String _date(DateTime value) {
  final d = value.toLocal();
  String pad(int v) => v.toString().padLeft(2, '0');
  return '${pad(d.day)}/${pad(d.month)}/${d.year} ${pad(d.hour)}:${pad(d.minute)}';
}

String _status(String value) => switch (value) {
  'pending' => 'Pendente',
  'approved' => 'Aprovado',
  'rejected' => 'Reprovado',
  'revoked' => 'Revogado',
  _ => value,
};

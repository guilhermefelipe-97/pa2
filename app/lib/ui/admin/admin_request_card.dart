import 'package:flutter/material.dart';
import '../../domain/models/admin_ownership_request.dart';
import '../feed/widgets/author_avatar.dart';
import '../feed/widgets/place_photo.dart';

class AdminRequestCard extends StatelessWidget {
  const AdminRequestCard({
    super.key,
    required this.request,
    required this.onOpen,
  });
  final AdminOwnershipRequest request;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) {
    final r = request, theme = Theme.of(context);
    final pending = r.status == 'pending';
    final label = switch (r.status) {
      'approved' => 'Aprovado',
      'rejected' => 'Reprovado',
      'revoked' => 'Revogado',
      _ => 'Pendente',
    };
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onOpen,
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: r.location?.photoUrl == null
                        ? const Icon(Icons.storefront_outlined)
                        : PlacePhoto(place: r.location!),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.place,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        if (r.location != null)
                          Text(
                            [
                              r.location!.neighborhood,
                              r.location!.category,
                            ].where((s) => s.isNotEmpty).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer.withValues(
                        alpha: .45,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Divider(color: theme.colorScheme.surfaceContainer),
            const SizedBox(height: 8),
            Row(
              children: [
                AuthorAvatar(id: r.uid, name: r.applicant, radius: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(r.applicant, style: theme.textTheme.bodyMedium),
                ),
                const SizedBox(width: 8),
                Text(
                  '${r.createdAt.day.toString().padLeft(2, '0')}/${r.createdAt.month.toString().padLeft(2, '0')}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: theme.colorScheme.surfaceContainer),
            const SizedBox(height: 8),
            Text(
              !r.available
                  ? 'Pedido indisponível · Conta: ${r.uid} · Local: ${r.placeId}'
                  : pending
                  ? 'Confira a identidade e a representação do estabelecimento antes de registrar a decisão.'
                  : 'Motivo da decisão: ${r.reason ?? 'Consulte os detalhes da solicitação.'}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (pending)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onOpen,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      label: const FittedBox(
                        child: Text('Recusar', maxLines: 1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onOpen,
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.tertiaryContainer,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(
                        Icons.check,
                        size: 18,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                      label: const FittedBox(
                        child: Text('Aprovar', maxLines: 1),
                      ),
                    ),
                  ),
                ],
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Ver decisão'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

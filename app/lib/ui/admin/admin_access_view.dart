import 'package:flutter/material.dart';
import 'admin_access.dart';

class AdminAccessView extends StatelessWidget {
  const AdminAccessView({super.key, required this.access});
  final AdminAccess access;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (access.state == AdminAccessState.loading)
          const CircularProgressIndicator()
        else ...[
          Text(
            access.state == AdminAccessState.error
                ? 'Não foi possível verificar o acesso administrativo'
                : 'Acesso negado',
          ),
          TextButton(
            onPressed: access.retry,
            child: const Text('Revalidar acesso'),
          ),
        ],
      ],
    ),
  );
}

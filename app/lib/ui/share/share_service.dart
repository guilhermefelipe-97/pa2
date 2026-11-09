import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Endereço público do link compartilhado (F21). Leva só o id do local.
const sharedLinkHost = 'naarea-natal.web.app';

String sharedPlaceLink(String placeId) =>
    'https://$sharedLinkHost/l/${Uri.encodeComponent(placeId)}';

/// Folha de compartilhamento do sistema. Interface para os testes.
abstract class ShareService {
  Future<void> shareImage({
    required Uint8List png,
    required String text,
    required String subject,
  });
}

class SystemShareService implements ShareService {
  const SystemShareService();
  @override
  Future<void> shareImage({
    required Uint8List png,
    required String text,
    required String subject,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: subject,
        files: [XFile.fromData(png, mimeType: 'image/png', name: 'naarea.png')],
        fileNameOverrides: const ['naarea.png'],
      ),
    );
  }
}

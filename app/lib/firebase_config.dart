import 'package:firebase_core/firebase_core.dart';

/// Projeto usado nos emuladores. Precisa bater com `.firebaserc` (default) e
/// com o seed; o prefixo `demo-` garante que nada saia para a nuvem.
const String emulatorProjectId = 'demo-naarea';

/// No modo emulador troca só o projectId: o emulador separa os dados por
/// projeto, e com o id real o app leria um namespace diferente do seed.
FirebaseOptions firebaseOptionsFor(FirebaseOptions options, {required bool useEmulator}) {
  return useEmulator ? options.copyWith(projectId: emulatorProjectId) : options;
}

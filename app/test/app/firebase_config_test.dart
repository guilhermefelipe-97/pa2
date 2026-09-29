import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/firebase_config.dart';

const _prod = FirebaseOptions(
  apiKey: 'key',
  appId: 'app',
  messagingSenderId: 'sender',
  projectId: 'naarea-natal',
);

void main() {
  test('modo emulador usa o projeto demo, o mesmo do seed e dos emuladores', () {
    final options = firebaseOptionsFor(_prod, useEmulator: true);

    expect(options.projectId, emulatorProjectId);
    expect(emulatorProjectId, 'demo-naarea');
    expect(options.apiKey, _prod.apiKey);
    expect(options.appId, _prod.appId);
  });

  test('fora do emulador mantém o projeto real', () {
    expect(firebaseOptionsFor(_prod, useEmulator: false).projectId, 'naarea-natal');
  });
}

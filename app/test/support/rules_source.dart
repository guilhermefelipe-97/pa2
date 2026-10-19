import 'dart:convert';
import 'dart:io';

/// Raiz do pacote `naarea`, lida do `package_config.json` do pacote (o
/// mesmo que resolve os imports `package:naarea/...`), procurado a partir
/// do diretório atual para cima: funciona rodando o teste de qualquer
/// pasta dentro do projeto.
Directory naareaPackageRoot() {
  var dir = Directory.current.absolute;
  while (true) {
    final config = File('${dir.path}/.dart_tool/package_config.json');
    if (config.existsSync()) {
      final json = jsonDecode(config.readAsStringSync()) as Map;
      for (final p in json['packages'] as List) {
        if (p['name'] == 'naarea') {
          final root = config.uri.resolve(p['rootUri'] as String);
          return Directory.fromUri(root);
        }
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('package_config.json do naarea não encontrado');
    }
    dir = parent;
  }
}

/// `firebase/firestore.rules`, a partir da raiz do pacote (`app/`).
String readFirestoreRules() {
  final root = naareaPackageRoot().uri;
  return File.fromUri(
    root.resolve('../firebase/firestore.rules'),
  ).readAsStringSync();
}

/// Remove comentários `// ...` das Rules (até o fim da linha), para que um
/// `}` ou um nome em comentário não confunda as buscas.
String stripRulesComments(String rules) =>
    rules.replaceAll(RegExp(r'//[^\n]*'), '');

/// Corpo da `function name(...) { ... }` das Rules, sem comentários, com as
/// chaves balanceadas (um `}` interno não corta o corpo). `null` se a função
/// não existe.
String? rulesFunctionBody(String rules, String name) {
  final source = stripRulesComments(rules);
  final head = RegExp(
    r'function\s+' + RegExp.escape(name) + r'\s*\([^)]*\)\s*\{',
  ).firstMatch(source);
  if (head == null) return null;
  var depth = 1;
  for (var i = head.end; i < source.length; i++) {
    final c = source[i];
    if (c == '{') depth++;
    if (c == '}' && --depth == 0) return source.substring(head.end, i);
  }
  return null;
}

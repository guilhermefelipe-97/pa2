/// Hash determinístico (não depende de execução/plataforma, ao contrário de
/// `String.hashCode`), para escolher cores estáveis por texto.
int stableHash(String s) =>
    s.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff);

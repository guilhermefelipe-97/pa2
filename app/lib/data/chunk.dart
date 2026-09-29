/// Divide [items] em lotes de no máximo [size] (ex.: limite 30 do `whereIn`).
List<List<T>> chunked<T>(List<T> items, int size) {
  if (size <= 0) throw ArgumentError.value(size, 'size', 'deve ser > 0');
  return [
    for (var i = 0; i < items.length; i += size)
      items.sublist(i, i + size > items.length ? items.length : i + size),
  ];
}

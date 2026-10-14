final RegExp _uuidFormat = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// `true` se [value] tem o formato UUID 8-4-4-4-12 (hex). Serve para barrar um
/// identificador vindo do cliente antes de ele chegar a um `::uuid` do SQL, que
/// viraria erro 500 em vez de entrada inválida.
bool isUuidFormat(String value) => _uuidFormat.hasMatch(value);

/// El id de una ruta hecha en el aparato: un UUIDv7 definitivo, sin `local-` (04/11/2026).
final unUuidV7 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

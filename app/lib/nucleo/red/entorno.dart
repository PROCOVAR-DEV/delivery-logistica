/// Las tres URL, por `--dart-define`. Nunca en el codigo y nunca en el APK
/// como constante editable.
///
/// Van separadas porque son tres servicios distintos y uno puede mudarse sin
/// los otros: `auth` es de toda Procovar, `api` y `sync` son del reparto.
abstract final class Entorno {
  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://reparto.procovar.cloud/api',
  );

  static const syncUrl = String.fromEnvironment(
    'SYNC_URL',
    defaultValue: 'https://reparto.procovar.cloud/sync',
  );

  static const authUrlPorDefecto = 'https://auth.procovar.cloud';

  /// `AUTH_URL`. **Vacío = el de producción**: `--dart-define=AUTH_URL=` explícitamente
  /// vacío no usa el `defaultValue` (da `''`), y entonces «el inicio de Accesos» sería
  /// `/`, o sea la propia Reparto: la pantalla de «no tienes permiso» se mandaría a sí
  /// misma cada 3 s en la web.
  static String get authUrl => authUrlDe(
    const String.fromEnvironment('AUTH_URL', defaultValue: authUrlPorDefecto),
  );

  /// La regla de [authUrl] sobre el valor suelto, para poder probarla (un
  /// `String.fromEnvironment` es constante de compilación).
  static String authUrlDe(String valor) =>
      valor.trim().isEmpty ? authUrlPorDefecto : valor;

  /// `true` cuando las tres estan puestas a mano. Sirve para que el arranque
  /// avise en vez de intentar hablar con un dominio que no es.
  static bool get configurado =>
      apiUrl.isNotEmpty && syncUrl.isNotEmpty && authUrl.isNotEmpty;
}

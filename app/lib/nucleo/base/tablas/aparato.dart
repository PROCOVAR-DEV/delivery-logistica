// Las tablas que son SOLO del aparato. No suben nunca y no las conoce el
// servidor: son el andamio que sostiene «guardar aqui y subir por detras».

import 'package:drift/drift.dart';

/// En que quedo un apunte de la cola.
///
/// `rechazado` es un estado FINAL: no se reintenta y no se borra. El servidor
/// dijo que no por algo y eso tiene que quedar a la vista con su motivo y su
/// hora (regla 6). Un apunte que desaparece solo es trabajo perdido que nadie
/// sabe que perdio.
///
/// `descartado` ES LA DECISION DE UNA PERSONA, y es un estado y no un borrado
/// por lo que paso el 29/09/2026. Jose, mirando el cajon de entregar el dia:
/// «los errores se acumulan y nunca se borran, se mantienen aunque se hayan
/// borrado las cosas y solucionado».
///
/// Y el boton de «Descartar» estaba puesto y borraba de verdad. Lo que fallaba
/// era lo de despues: al borrar el apunte, la fila que ese apunte iba a subir
/// se quedaba **sin ningun apunte vivo**, que es exactamente la definicion de
/// huerfana (`nucleo/sincro/huerfanos.dart`). El ciclo la veia colgada, la
/// volvia a encolar, el servidor volvia a decir que no y reaparecia en la
/// bandeja. Descartar y esperar cinco minutos devolvia el mismo rechazo.
///
/// Guardandolo como estado en vez de borrarlo, la decision **se queda escrita**:
/// no sale en la bandeja, no cuenta como sin subir, y lo huerfano lo ve como
/// «esto ya se decidio» y no lo vuelve a encolar. Sigue siendo, ademas, la unica
/// constancia de algo que no llego a pasar, que es lo que pide la regla 6.
enum EstadoApunte { pendiente, aplicado, rechazado, descartado }

/// LA COLA DE SALIDA.
///
/// El orden lo da `orden`, un autoincremento de la base, y NUNCA la hora: un
/// reloj que se mueve —se cambia a mano, se va con la bateria, salta de zona—
/// no puede reordenar el trabajo del dia (caso S3).
@DataClassName('Apunte')
class Apuntes extends Table {
  IntColumn get orden => integer().autoIncrement()();

  /// ULID, la pone el aparato, una por apunte. Es la idempotencia: si la subida
  /// se corto DESPUES de que el servidor guardara, el reintento devuelve
  /// `repetido` y no se duplica (caso S5).
  TextColumn get clave => text().unique()();

  /// La hora del APARATO, escrita al encolar y NO tocada al subir. Lo que se
  /// marca a las cuatro llega como las cuatro, aunque suba a las siete
  /// (regla 7, caso S2).
  DateTimeColumn get hechoAt => dateTime()();

  TextColumn get metodo => text()();
  TextColumn get ruta => text()();

  /// El cuerpo, como JSON en texto. Se guarda serializado porque tiene que poder
  /// REESCRIBIRSE cuando un `local-…` se convierte en un id de verdad.
  TextColumn get cuerpo => text()();

  /// `local-…` si este apunte CREA algo. Es la bisagra de la sustitucion (§2.2.5).
  TextColumn get provisional => text().nullable()();

  TextColumn get estado =>
      textEnum<EstadoApunte>().withDefault(const Constant('pendiente'))();
  TextColumn get motivo => text().nullable()();
  DateTimeColumn get resueltoAt => dateTime().nullable()();
  IntColumn get intentos => integer().withDefault(const Constant(0))();
}

/// `local-9f3a` → `cm2x…`. Queda como rastro: sirve para entender un registro
/// viejo y para no volver a sustituir lo ya sustituido.
@DataClassName('Equivalencia')
class Equivalencias extends Table {
  TextColumn get provisional => text()();

  /// El id de verdad. En Dart se llama `idReal` y en SQL `real`: `real` a secas
  /// choca con `Table.real`, el constructor de columnas de Drift.
  TextColumn get idReal => text().named('real')();

  DateTimeColumn get at => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {provisional};
}

/// De que hora son estos datos, por coleccion (§2.5).
@DataClassName('FilaFrescura')
class Frescura extends Table {
  TextColumn get coleccion => text()();
  DateTimeColumn get bajadaAt => dateTime().nullable()();

  /// La marca del servidor, TAL CUAL vino, en texto.
  ///
  /// No se parsea ni se recalcula: `hasta` lo pone el servidor y un `DateTime`
  /// de ida y vuelta puede perder precision. Lo unico que hacemos con ella es
  /// devolversela en el siguiente `?desde=`.
  TextColumn get hasta => text().nullable()();

  /// `true` si la ultima bajada fue la carga inicial completa.
  BoolColumn get completa => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {coleccion};
}

/// Sucursal mirada, moneda, idioma. Del aparato, no de la persona.
@DataClassName('Preferencia')
class Preferencias extends Table {
  TextColumn get clave => text()();
  TextColumn get valor => text()();

  @override
  Set<Column<Object>> get primaryKey => {clave};
}

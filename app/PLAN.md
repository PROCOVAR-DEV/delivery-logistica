# Plan de construcción — `reparto-app` (Flutter, web + APK del mismo código)

Pliego: `../docs/pantallas.md`, `../docs/identidad.md`, `../docs/sincronizacion.md`,
`../docs/contratos-api.md`, `../docs/reglas-negocio.md`, `../docs/pruebas.md` y las 8 reglas
de `README.md`. Este documento **no vuelve a decidir nada de eso**: dice cómo se construye.

Terminado = **da los mismos números que la pantalla equivalente de Next**. Las dos en pie a
la vez y se comparan. `../../delivery` no se toca.

> **ESTE DOCUMENTO ES EL PLAN DE PARTIDA Y HAY UNA COSA QUE YA NO ES ASÍ.** Lo de la web
> con **OPFS** y con `drift_worker.js` —§«Por qué Drift, y qué pasa en web», y el `web/`
> del árbol de aquí abajo— se cambió el 16/09/2026: **la base de la web es EN MEMORIA**,
> y el 24/09/2026 se quitaron el worker, su compilado y la guarda que lo exigía. Una copia
> en el navegador sólo puede mentir, y lo hizo: guardó una cola, la cola se atascó y el
> tablero se negó a bajar durante hora y media. Lo que manda es
> `app/lib/nucleo/base/conexion/conexion_web.dart` y el §1 de `../CLAUDE.md`; lo de aquí
> se deja escrito para saber de dónde se venía.

---

## 0 · Las decisiones, en cuatro líneas

| Qué | Qué se usa | Por qué en una frase |
|---|---|---|
| Estado | **Riverpod** (`flutter_riverpod` + `riverpod_generator`) | la fuente de verdad es la base local, no el widget; se prueba sin pintar nada y se invalida por sucursal |
| Base local | **Drift** (`drift` + `sqlite3_flutter_libs` + `drift/wasm`) | el **mismo Dart y el mismo SQL** en Android y en web, y en web es SQLite de verdad sobre WASM+OPFS |
| Red | **Dio** con interceptores propios | hace falta un interceptor con candado, no un `http.get` |
| Rutas de pantalla | **go_router** | 7 rutas planas con armazón compartido y URL de verdad en web (los filtros van en la URL) |
| Impreso | **`pdf` + `printing`** | vista previa, imprimir y compartir, en los dos destinos |
| Mapas | **`flutter_map`** + `latlong2` | sin clave de API, funciona sin baldosas y los puntos los ponemos nosotros |
| Sesión | `flutter_secure_storage` (APK) / cookie (web) | lo dice `identidad.md`: la APK no lleva ninguna clave dentro |

---

## 1 · Estructura del proyecto

```
app/
├─ pubspec.yaml
├─ analysis_options.yaml         flutter_lints + riverpod_lint + custom_lint
├─ build.yaml                    drift_dev + riverpod_generator + json_serializable
├─ PLAN.md                       este fichero
├─ README.md                     las 8 reglas (ya está)
├─ assets/
│   └─ fuentes/                  Roboto-Regular.ttf y Roboto-Bold.ttf — para el PDF,
│                                EMBEBIDAS: nada de PdfGoogleFonts, que baja por red
├─ web/
│   ├─ index.html
│   ├─ sqlite3.wasm              del paquete `sqlite3` (release que toque)
│   └─ drift_worker.js           compilado de web/drift_worker.dart
├─ android/                      minSdk 23 (lo pide sqlite3_flutter_libs)
├─ lib/
│   ├─ main.dart                 runApp(ProviderScope(child: RepartoApp()))
│   ├─ app.dart                  RepartoApp — MaterialApp.router, tema, Textos
│   ├─ arranque/
│   │   └─ arranque.dart         Arranque: abre la base, lee la sesión, intenta RENOVAR
│   │                            (no valida el token de acceso), registra el aparato
│   ├─ nucleo/                   LAS PIEZAS TRANSVERSALES — §2
│   │   ├─ base/                 Drift
│   │   │   ├─ base.dart         @DriftDatabase class BaseLocal
│   │   │   ├─ tablas/           orders.dart, routes.dart, customers.dart, products.dart,
│   │   │   │                    vehicles.dart, branches.dart, warehouses.dart,
│   │   │   │                    settings.dart, order_items.dart,
│   │   │   │                    apuntes.dart, equivalencias.dart, frescura.dart,
│   │   │   │                    preferencias.dart
│   │   │   ├─ conexion/         conexion.dart (export condicional)
│   │   │   │                    conexion_nativa.dart | conexion_web.dart | conexion_stub.dart
│   │   │   └─ consultas/        consultas_pedidos.dart, consultas_rutas.dart, …
│   │   ├─ cola/
│   │   │   ├─ cola_salida.dart      ColaDeSalida — encolar, leer FIFO, resolver
│   │   │   ├─ apunte.dart           Apunte, EstadoApunte
│   │   │   └─ provisionales.dart    Provisionales — local-… → id de verdad
│   │   ├─ red/
│   │   │   ├─ cliente_api.dart      ClienteApi (Dio + interceptores)
│   │   │   ├─ interceptor_sesion.dart
│   │   │   ├─ fallos.dart           FalloDeRed | Rechazo(codigo, mensaje) | SesionMuerta
│   │   │   └─ entorno.dart          Entorno.apiUrl / syncUrl / authUrl (--dart-define)
│   │   ├─ identidad/
│   │   │   ├─ sesion.dart           Sesion {token, refresh, sub, sucursalId, roles}
│   │   │   ├─ renovador.dart        Renovador — EL CANDADO
│   │   │   ├─ almacen_sesion.dart   AlmacenDeSesion (interfaz)
│   │   │   │                        almacen_sesion_nativo.dart | _web.dart
│   │   │   └─ identidad_provider.dart
│   │   ├─ frescura/
│   │   │   ├─ frescura.dart         RegistroDeFrescura
│   │   │   └─ reloj_de_datos.dart   RelojDeDatos (el widget de la barra) + SinDescargar
│   │   ├─ sincro/
│   │   │   ├─ sincronizador.dart    Sincronizador.ciclo(): renovar → subir → bajar
│   │   │   ├─ bajada.dart           Bajada (diferencias, `truncado`, `quitados`)
│   │   │   └─ subida.dart           Subida (lotes, resultados apunte a apunte)
│   │   ├─ formato/
│   │   │   ├─ dinero.dart           Dinero.enMoneda(usd, tasa) — USD/CUP
│   │   │   ├─ peso.dart, distancia.dart
│   │   │   └─ fechas.dart           DateFormat('es'), el equivalente de toLocaleString('es')
│   │   ├─ geo/
│   │   │   └─ geo.dart              haversineKm, vecinoMasCercano, tramos — calcado de
│   │   │                            reglas-negocio §1
│   │   └─ registro/registro.dart    Registro.info/aviso/fallo
│   ├─ diseno/                   el kit, calcado de pantallas.md §9
│   │   ├─ cajon.dart            Cajon — SIEMPRE cajón, nunca AlertDialog (§9.2)
│   │   ├─ selector.dart         Selector con buscador desde 4 opciones (§9.6)
│   │   ├─ paginacion.dart       Paginacion (§9.7)
│   │   ├─ insignia.dart, tarjeta.dart, estado_vacio.dart, cargando.dart
│   │   ├─ tabla_ancha.dart      tabla con su propio scroll horizontal
│   │   └─ colores.dart          ámbar / verde / azul / índigo / gris del pliego
│   ├─ navegacion/
│   │   ├─ rutas.dart            go_router: las 7 + /login
│   │   ├─ armazon.dart          Armazon (barra lateral + barra superior)
│   │   ├─ barra_lateral.dart    Sidebar — 6 entradas, Reportes NO está (§8.1)
│   │   └─ barra_superior.dart   Navbar — sucursal, idioma, moneda, avatar, RelojDeDatos
│   ├─ pantallas/                una carpeta por pantalla, siempre con las mismas 3
│   │   ├─ panel/     {datos/, estado/, vista/}
│   │   ├─ pedidos/   {datos/, estado/, vista/}
│   │   ├─ rutas/     {datos/, estado/, vista/}
│   │   ├─ clientes/  {datos/, estado/, vista/}
│   │   ├─ vehiculos/ {datos/, estado/, vista/}
│   │   ├─ almacenes/ {datos/, estado/, vista/}
│   │   └─ reportes/  {datos/, estado/, vista/}
│   ├─ impresion/
│   │   ├─ pre_despacho.dart         pdfPreDespacho(HojaPreDespacho)
│   │   ├─ post_despacho.dart        pdfPostDespacho(HojaPostDespacho)
│   │   ├─ armar_post_despacho.dart  armarPostDespacho(...) — la cuenta, sin PDF
│   │   ├─ hoja.dart                 los datos de entrada, sin Flutter dentro
│   │   └─ vista_previa.dart         VistaPreviaPdf (cajón + Imprimir + Compartir + Cerrar)
│   ├─ mapas/
│   │   ├─ mapa.dart                 Mapa (flutter_map, baldosas OSM)
│   │   ├─ mapa_sin_baldosas.dart    el mismo dibujo sin red
│   │   └─ geocodificar.dart         Nominatim + parseCoordInput
│   └─ excel/
│       └─ reporte_xlsx.dart         las 3 hojas de Reportes
├─ test/
│   ├─ nucleo/                   base, cola, renovador, sincro, geo, formato
│   ├─ pantallas/                widget + golden por pantalla
│   ├─ impresion/                golden de PDF y la cuenta del post-despacho
│   ├─ i18n/claves_test.dart     es y en tienen las MISMAS claves
│   ├─ paridad/                  compara contra la de Next (§5)
│   └─ apoyo/                    ApiFalsa, baseDePrueba(), sembrar()
└─ integration_test/
    ├─ dia_sin_conexion_test.dart
    ├─ sesion_test.dart
    └─ pantallas_test.dart
```

**Dentro de `pantallas/<x>/`, siempre lo mismo y siempre así:**

- `datos/` — el repositorio. **Lee de la base local, nunca de la red.** Es quien traduce
  los filtros del pliego a SQL de Drift.
- `estado/` — los providers de Riverpod. Filtros, selección, paginación.
- `vista/` — widgets. Sin lógica de negocio y sin `dio` a la vista.

### Por qué Riverpod

- La regla 2 («nunca esperar al servidor») obliga a que **la pantalla mire la base local**,
  no la respuesta de una petición. Riverpod hace eso con `StreamProvider` sobre una
  consulta de Drift (`watch()`): se guarda en la base, la consulta emite, la pantalla se
  repinta. Sin `setState`, sin refrescos a mano y sin esperar a nadie.
- El pliego pide algo literal: *«al cambiar de sucursal se invalidan todas las consultas
  (no se recarga la página)»*. Eso en Riverpod es `ref.invalidate(...)` o, mejor,
  `ref.watch(sucursalProvider)` dentro de cada provider: al cambiar la sucursal se
  reconstruyen solos. Es exactamente la semántica de las claves de caché de React Query
  que tiene hoy la de Next, así que se traslada uno a uno.
- `AsyncValue` da los tres estados que el pliego pinta (`Cargando...`, dato, error) **sin
  perder el dato viejo mientras refresca** (`AsyncValue.isRefreshing`), que es lo que el
  pliego llama el giro de `actualizando…` en la barra superior.
- Se prueba sin widgets: `ProviderContainer(overrides: [...])` en un test de `dart test`.

Se descarta BLoC porque aquí el 90 % del estado **no son eventos, son consultas**, y un
bloc por pantalla con 9 filtros son 9 eventos y 9 copias del estado escritos a mano.

### Por qué Drift, y qué pasa en web

**Drift es la única opción que corre el mismo código en los dos destinos.**

- **Android (APK):** `sqlite3_flutter_libs` embebe SQLite en el APK y `drift_flutter`
  abre el fichero en el directorio de la aplicación, en un **isolate aparte**, así que las
  consultas gordas no traban la interfaz.
- **Web:** no hay SQLite nativo — pero **sí hay SQLite**: se compila a WebAssembly.
  `WasmDatabase.open(...)` carga `sqlite3.wasm` en un worker (`drift_worker.js`) y guarda
  el fichero en **OPFS** (Origin Private File System), que es almacenamiento de verdad,
  persistente y del origen. Si el navegador no da OPFS, cae a IndexedDB, que también
  persiste. **El mismo `.dart`, las mismas tablas, el mismo SQL.**

```dart
// lib/nucleo/base/conexion/conexion.dart
export 'conexion_stub.dart'
    if (dart.library.io) 'conexion_nativa.dart'
    if (dart.library.js_interop) 'conexion_web.dart';
```

```dart
// conexion_web.dart
Future<QueryExecutor> abrirConexion() async {
  final r = await WasmDatabase.open(
    databaseName: 'reparto',
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );
  if (r.missingFeatures.isNotEmpty) Registro.aviso('almacenamiento degradado: ${r.missingFeatures}');
  AlmacenamientoFragil.marcar(r.chosenImplementation == WasmStorageImplementation.inMemory);
  return r.resolvedExecutor;
}
```

**Lo que hay que saber de la web y no se puede descubrir a mitad de camino:**

1. `chosenImplementation == inMemory` significa **que al recargar se pierde todo**. En ese
   caso la aplicación **lo dice**, no lo esconde: aviso permanente en la barra, literal
   nuevo `Este navegador no guarda nada: al cerrar la pestaña se pierde lo que no se haya
   subido.` Pasa en Safari en ventana privada y con las cookies de terceros a cero.
2. Hay que pedir `navigator.storage.persist()` al arrancar, o el navegador puede desalojar
   la base cuando le falte disco.
3. `sqlite3.wasm` y `drift_worker.js` **son ficheros del despliegue**: si Dokploy sirve la
   carpeta `build/web` y falta uno, la aplicación arranca y la base no. Va en la lista de
   comprobación del despliegue.
4. La web no es el destino del día sin conexión —eso es la APK— pero **se comporta igual**:
   misma cola, misma frescura, mismos datos locales.

Se descartan: `sqflite` (no hay web), `hive`/`isar` (sin consultas relacionales: los 9
filtros de Pedidos acabarían en Dart recorriendo doce mil pedidos, y el soporte web de Isar
no está para producción), `objectbox` (sin web).

### Las dependencias, con su nombre real

Se añaden con `flutter pub add <nombre>` —que fija la versión del día— y se **pinta la
versión exacta en `pubspec.yaml`**: una APK que se compila distinto en dos máquinas no se
puede depurar.

```yaml
dependencies:
  flutter_riverpod:        # estado
  riverpod_annotation:
  go_router:               # navegación, y la URL de verdad en web
  drift:                   # base local
  drift_flutter:           #   abre el fichero en Android, en un isolate
  sqlite3_flutter_libs:    #   SQLite embebido en el APK (minSdk 23)
  sqlite3:                 #   de aquí sale web/sqlite3.wasm
  path_provider:
  dio:                     # red
  flutter_secure_storage:  # el par de tokens, SÓLO en la APK
  synchronized:            # el Lock del candado de renovación
  ulid:                    # las claves de idempotencia (01J8…)
  uuid:                    # los id provisionales local-…
  intl:                    # números y fechas en 'es'
  flutter_localizations: {sdk: flutter}
  pdf:                     # el pre-despacho y el post-despacho
  printing:                #   vista previa, imprimir y compartir, web y Android
  flutter_map:             # mapas, sin clave de API
  latlong2:
  flutter_map_cache:       #   baldosas que se quedan de la mañana
  dio_cache_interceptor:
  excel:                   # las 3 hojas de Reportes
  file_saver:              #   guardar el .xlsx en los dos destinos
  url_launcher:            # Abrir en Google Maps, ver mapa
  connectivity_plus:       # PISTA de que hay red, nunca la verdad
  device_info_plus:        # el nombre del aparato para POST /sync/aparato
  package_info_plus:
  collection:
  web:                     # nada de dart:html

dev_dependencies:
  build_runner:
  drift_dev:
  riverpod_generator:
  riverpod_lint:
  custom_lint:
  json_serializable:
  json_annotation:
  flutter_lints:
  mocktail:
  http_mock_adapter:       # el servidor falso para los tests de red
  integration_test: {sdk: flutter}
```

**Lo que NO entra, y por qué:** `google_maps_flutter` (clave de API y no pinta sin red),
`sqflite` (no hay web), `isar`/`hive` (sin consultas relacionales), `firebase_*` (nada de
esto sale de Procovar), `http` suelto (hace falta interceptor).

---

## 2 · Las cinco piezas transversales

Van **antes que cualquier pantalla**. Ninguna pantalla se empieza sin las cinco en pie,
porque todas las siete dependen de las cinco y arreglarlas después significa reescribir las
siete.

### 2.1 · La base local — `nucleo/base/`

`BaseLocal` (`@DriftDatabase`), `schemaVersion` empieza en 1. **Las tablas del dominio son
las del esquema del servidor** (`../api/db/migrations/00001_init.sql`), con los mismos
nombres de columna, para que la bajada sea un `insertOnConflictUpdate` y nada más:
`orders`, `order_items`, `routes`, `customers`, `products`, `vehicles`, `branches`,
`warehouses`, `settings`, `currencies`, `vehicle_types`.

Más cuatro que **son sólo del aparato** y no suben nunca:

```dart
class Apuntes extends Table {                  // la cola — §2.2
  IntColumn get orden => integer().autoIncrement()();
  TextColumn get clave => text().unique()();           // ULID, idempotencia
  DateTimeColumn get hechoAt => dateTime()();          // la hora del APARATO
  TextColumn get metodo => text()();
  TextColumn get ruta => text()();
  TextColumn get cuerpo => text()();                   // JSON
  TextColumn get provisional => text().nullable()();   // local-… si CREA algo
  TextColumn get estado => textEnum<EstadoApunte>()(); // pendiente|aplicado|rechazado
  TextColumn get motivo => text().nullable()();
  DateTimeColumn get resueltoAt => dateTime().nullable()();
  IntColumn get intentos => integer().withDefault(const Constant(0))();
}

class Equivalencias extends Table {            // local-9f3a → cm2x…
  TextColumn get provisional => text()();
  TextColumn get real => text()();
  DateTimeColumn get at => dateTime()();
  @override Set<Column> get primaryKey => {provisional};
}

class Frescura extends Table {                 // de qué hora son estos datos — §2.5
  TextColumn get coleccion => text()();        // orders|routes|customers|…
  DateTimeColumn get bajadaAt => dateTime().nullable()();
  TextColumn get hasta => text().nullable()(); // la marca del servidor, TAL CUAL
  BoolColumn get completa => boolean().withDefault(const Constant(false))();
  @override Set<Column> get primaryKey => {coleccion};
}

class Preferencias extends Table {             // sucursal mirada, moneda, idioma
  TextColumn get clave => text()();
  TextColumn get valor => text()();
  @override Set<Column> get primaryKey => {clave};
}
```

Reglas de la pieza:

- **`hasta` se guarda como vino, en texto.** No se parsea ni se recalcula: el servidor
  manda (`sincronizacion.md`), y un `DateTime` de ida y vuelta puede perder precisión.
- **`quitados` se aplica de verdad:** `delete where id in (...)`. Sin eso la lista local
  sólo crece.
- **Borrado al cerrar sesión:** `BaseLocal.borrarTodoLoDelDominio()` vacía dominio +
  frescura + preferencias y **deja la cola intacta** hasta que la persona conteste al aviso
  (regla 8 y caso I7).
- Migraciones con `MigrationStrategy` y **pruebas de migración desde el primer día**
  (`drift_dev schema dump` + `verify`), porque una APK instalada no se puede «recrear».

**Cómo se prueba.** Automática: `test/nucleo/base/` con `NativeDatabase.memory()` —
alta/baja/consulta de cada tabla, `quitados` borra, `borrarTodoLoDelDominio` no toca
`apuntes`. Y `test/nucleo/base/migracion_test.dart` con los volcados de esquema.
A mano: en Chrome, DevTools → Application → **comprobar que sale OPFS y no «in memory»**;
recargar con F5 y que los datos siguen; en el teléfono, `adb shell run-as … ls` y que el
`.sqlite` existe.

### 2.2 · La cola de salida — `nucleo/cola/`

Es la pieza que hace verdad la regla 2: *toda acción se guarda en el aparato y se pinta
como hecha*.

```dart
class ColaDeSalida {
  Future<String> encolar({           // devuelve la clave
    required String metodo, required String ruta,
    required Map<String, Object?> cuerpo, String? provisional,
  });
  Stream<List<Apunte>> pendientes();
  Stream<List<Apunte>> rechazados();              // para la bandeja, §6
  Future<void> resolver(String clave, ResultadoApunte r);
}
```

Las siete cosas que tiene que cumplir, todas del protocolo:

1. **FIFO de verdad.** El orden es `orden` (autoincremento de la base), **nunca la hora**.
   Un reloj que se mueve no puede reordenar el trabajo (caso S3).
2. **`clave` = ULID** (`package:ulid`), la pone el aparato, una por apunte. Es la
   idempotencia: si la subida se cortó después de que el servidor guardara, el reintento
   devuelve `repetido` y no se duplica (caso S5).
3. **`hechoAt` es la hora del aparato**, se escribe al encolar y no se toca al subir
   (regla 7, caso S2).
4. **Se sube en UN solo trabajador**, secuencial, en un lote. Veinte apuntes no son veinte
   peticiones en paralelo: es una `POST /sync/subida` con los veinte dentro. Esto es medio
   caso I1.
5. **Identificadores provisionales.** Al encolar algo que crea, se genera
   `local-<8 hex>` y se escribe ya en la base local para que la pantalla lo enseñe. Cuando
   el apunte sube y vuelve con `id`, en **una sola transacción**:
   `Provisionales.sustituir(prov, real)` → escribe en `equivalencias`, reescribe `ruta` y
   `cuerpo` de **todos los apuntes pendientes de más atrás**, y actualiza las filas locales
   (`routes.id`, `orders.route_id`, `orders.ultima_ruta_id`). Si esto falla, el cierre de
   la tarde se va a `/api/routes/local-9f3a/results` y se pierde justo después de subir
   (caso S4).
6. **`rechazado` no se reintenta y no se borra.** Se queda con `motivo` y `resueltoAt` y
   sale en la bandeja de rechazos. Regla 6 (caso S6).
7. **`aplicado` se conserva 7 días** y luego se poda. Borrarlo al momento deja sin rastro
   una subida que el usuario jura que hizo.

**Cómo se prueba.** Automática: `test/nucleo/cola/cola_test.dart` — orden con relojes
desordenados; doble `encolar` con la misma clave; `resolver` con `repetido`; y
`provisionales_test.dart`: encolar crear-ruta + cerrar-ruta, resolver la primera, y
comprobar que la segunda **ya no menciona `local-`** ni en la ruta ni en el cuerpo ni en la
base. A mano: armar una ruta en avión, ver que sale en la lista al instante con su código,
y mirar la bandeja de rechazos con un cierre rechazado a propósito.

### 2.3 · El cliente de API — `nucleo/red/`

`ClienteApi` envuelve **un** `Dio` por destino (`api`, `sync`, `auth`), con las URL por
`--dart-define=API_URL=…`.

```dart
class ClienteApi {
  Future<T> pedir<T>(String ruta, {Map<String,Object?>? params});  // GET
  Future<T> mandar<T>(String metodo, String ruta, Object? cuerpo); // el resto
}
```

Interceptores, **en este orden**:

1. `InterceptorSesion` — pone `Authorization: Bearer <token>` (APK) o
   `withCredentials` (web, cookie). Añade `x-sucursal-id` cuando el Super Admin está
   mirando una. En un `401` llama al `Renovador` **una vez** y reintenta el envío una vez;
   si el segundo también es 401 → `SesionMuerta`.
2. `InterceptorFallos` — traduce a los tres tipos de `fallos.dart`, que es la regla 5
   escrita en código:

   | Lo que pasa | Tipo | Qué hace la aplicación |
   |---|---|---|
   | 200 | — | dentro |
   | 401 (tras renovar) | `SesionMuerta` | limpia y a la pantalla de acceso |
   | 4xx que no es 401 | `Rechazo(codigo, mensaje)` | **se enseña el mensaje literal del servidor** |
   | red, timeout, 5xx | `FalloDeRed` | **CONSERVA los tokens** y se reintenta luego |

3. `InterceptorRegistro` — sólo en depuración.

- Tiempos: `connectTimeout` 10 s, `receiveTimeout` 30 s (la primera bajada de una sucursal
  grande por la conexión de allá es lenta; para eso existe `truncado`).
- Reintento con espera creciente (1 s, 4 s, 15 s, 60 s) **sólo para `FalloDeRed`**. Un
  `Rechazo` no se reintenta jamás.
- **`connectivity_plus` es una pista, no la verdad.** La verdad es si la petición salió.
  Se usa sólo para disparar el ciclo antes, no para decidir si intentarlo.
- Los mensajes de error del servidor son **literales y en español** (`contratos-api.md`,
  apéndice): se pintan tal cual vienen, sin envolver en «Ha ocurrido un error».

**Cómo se prueba.** Automática: `test/nucleo/red/` con `http_mock_adapter` — un 500 no
borra tokens; un 401 renueva y reintenta una vez; un 409 sale con su texto literal
(`3 de los 8 pedidos ya están en otra ruta. Vuelve a elegirlos.`). A mano: con el servidor
apagado, la aplicación sigue navegando y no salta al login.

### 2.4 · La identidad, con el candado — `nucleo/identidad/`

La regla que si falla deja a diez personas fuera con el trabajo del día dentro.

```dart
class Renovador {
  Renovador(this._crudo, this._almacen);
  final Dio _crudo;                 // SIN InterceptorSesion: renovar no se renueva a sí mismo
  final AlmacenDeSesion _almacen;
  final _candado = Lock();          // package:synchronized

  Future<Sesion> renovar(Sesion vista) =>
    _candado.synchronized(() async {            // ← EL CANDADO, PRIMERA LÍNEA
      final actual = await _almacen.leer();
      if (actual == null) throw SesionMuerta();
      // Otro ya renovó mientras esperábamos: se REUTILIZA su resultado.
      if (actual.refresh != vista.refresh) return actual;
      try {
        final par = await _crudo.post('/refresh', data: {'refresh': actual.refresh});
        final nueva = Sesion.deJson(par.data);
        await _almacen.guardar(nueva);          // el refresh se sustituye ENTERO
        return nueva;
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) { await _almacen.borrar(); throw SesionMuerta(); }
        rethrow;                                // red o 5xx: los tokens SE QUEDAN
      }
    });                                          // synchronized suelta el candado pase lo que pase
}
```

- **Una sola renovación en vuelo** (regla 3). El candado va desde la primera línea. Quien
  llega tarde **no lanza la suya con el mismo refresh**: compara el refresh que traía con
  el guardado y, si cambió, devuelve el nuevo. Las dos mitades hacen falta: sólo con el
  `Lock` habría veinte renovaciones **en fila**, que para el servidor es reutilización
  igual y revoca todas las sesiones de la cuenta.
- **El refresh es de un solo uso y se sustituye entero.** Nunca se guarda el viejo.
- **Al arrancar no se comprueba el token de acceso:** se intenta `renovar()` directamente
  (`identidad.md`). Si no hay red, se entra con lo guardado.
- **Dónde se guarda:**
  - APK → `flutter_secure_storage` (Keystore / `EncryptedSharedPreferences`).
  - Web → **no se guarda nada**: el login único de auth deja su cookie y Dio va con
    `withCredentials: true`. Hace falta que la aplicación y la API salgan bajo
    `*.procovar.cloud` para que la cookie valga (`SameSite=Lax`), o `SameSite=None; Secure`
    con CORS por lista blanca. **Esto se cierra con auth antes de escribir la pantalla de
    acceso.**
- **Para entrar hace falta conexión** y no se intenta lo contrario (regla 1). Sin red y sin
  sesión guardada: `Para entrar la primera vez hace falta conexión.` (literal nuevo), no un
  error de red (caso I4).
- **Al cerrar sesión se borra lo local** (regla 8), y si la cola tiene pendientes se
  **pregunta antes** (caso I7).

**Cómo se prueba.** Automática, y es el test más importante del proyecto:
`test/nucleo/identidad/candado_test.dart` — **20 peticiones simultáneas que reciben 401 y
el servidor falso cuenta cuántas veces le pidieron `/refresh`: tiene que ser 1** (caso I1).
Más: 401 en el refresh → `SesionMuerta` y almacén vacío; 500 en el refresh → excepción y
**los tokens siguen ahí** (caso I6); refresh reutilizado → el mensaje del servidor llega.
A mano: en el teléfono, modo avión con 20 apuntes encolados, quitar el avión y mirar el
registro del servidor: **una sola** renovación, y después la cola sube (casos I1, I2).

### 2.5 · El indicador de «de qué hora son estos datos» — `nucleo/frescura/`

Caso S8 del guion: *arriba, siempre*. Sin esto, una pantalla con datos de anteayer es
indistinguible de una al día, y ese es el modo de fallo que nadie nota.

- `RegistroDeFrescura.marcar(coleccion, hasta, bajadaAt)` lo escribe la bajada, por
  colección.
- `RelojDeDatos` vive en la barra superior, **siempre visible en las 7 pantallas**:
  - < 1 h: `Datos de las 7:42` en gris.
  - 1 h – 24 h: `Datos de hace 5 h` en gris.
  - > 24 h: `Datos del martes — hace 2 días` en **ámbar**.
  - Nunca: `Sin descargar todavía` en ámbar.
  - Subiendo o bajando: el giro y `actualizando…` (literal del pliego, §8.2).
  - Con pendientes en la cola: `<n> sin subir`, pulsable → bandeja de rechazos/pendientes.
- `SinDescargar` es el **estado vacío de una colección que nunca se bajó**, y no es el
  mismo que «no hay nada»: `Esta pantalla no se ha descargado todavía. Con conexión baja
  sola.` (literal nuevo). Caso S7: **una lista vacía ahí es un fallo**.

**Cómo se prueba.** Automática: `test/nucleo/frescura/reloj_test.dart` con el reloj
inyectado, los cinco tramos; y un widget test de que una colección sin fila de frescura
pinta `SinDescargar` y no la lista vacía. A mano: bajar, poner el teléfono en avión, dejarlo
un día, abrir: tiene que decir ámbar y la hora de ayer.

---

## 3 · Las 7 pantallas, en orden de valor

**El orden.** Primero Pedidos, porque es lectura pura y levanta de una vez todo lo que las
demás reutilizan (filtros, paginación, cajón, tabla que se esconde por anchura, alcance por
sucursal) sin arriesgar ni una escritura. Después Rutas, que es **donde está el valor** y
donde vive el día sin conexión, pero necesita las piezas que deja Pedidos. Panel va tercero
porque una vez hay pedidos locales se calcula casi solo. Vehículos antes que Almacenes
porque sin un vehículo con capacidad no se arma ninguna ruta. Almacenes quinto: se toca una
vez por sucursal y escribe en Accesos, que es en línea sí o sí. Clientes sexto, consulta
pura. Reportes último: ni siquiera está en el menú.

**Criterio de terminado, el mismo en las siete:** *da lo mismo que la pantalla equivalente
de Next* — mismas columnas, mismas etiquetas literales, mismos valores por defecto, misma
paginación y **los mismos números** con la misma base.

---

### 3.1 · Pedidos — `/orders` · `pantallas/pedidos/`

**Qué muestra.** El catálogo espejado de PEDIDO con los 9 filtros, la tabla de 12 columnas,
el detalle en cajón y los dos pre-despachos (el de lo marcado y el de lo filtrado).
Pliego: `pantallas.md` §2.

**Qué necesita de la API.** `GET /api/orders` (50 por página, lo fija el servidor),
`GET /api/orders?resumen=1&porPagina=1&…` (sólo al abrir el desplegable; > 5000 →
`resumen: null`), `GET /api/orders/facetas` (caché 10 min).

**Sin conexión, qué sí.** Todo lo de lectura: la lista, los 9 filtros, el orden local de la
página, el detalle, la selección y **los dos pre-despachos**. La consulta va a Drift con el
mismo `WHERE` de `contratos-api.md` §«Filtros compartidos»; el pre-despacho de lo filtrado
se suma en SQL local (`GROUP BY` sobre `order_items`) y **no tiene el tope de 5000**,
porque en el aparato sólo está su sucursal. Las facetas salen de `SELECT municipio,
count(*) … GROUP BY`.

**Sin conexión, qué no.** Nada: esta pantalla no escribe. Lo único que cambia es el
`RelojDeDatos` y que pedidos de hoy que aún no bajaron no están.

**Piezas nuevas que deja para las demás:** `TablaPedidos` (con el escondite por anchura:
`Sucursal`/`Vehículo` < 1536, `Ruta` < 1280, `Artículos`/`Factura` < 1024, `Entrega` < 768),
`FilaPedido`, `InsigniaFactura`, `InsigniaReparto`, `CajonDetallePedido`,
`TarjetaPreDespacho`.

**Cuidado con:** `Precio` es `pedidoCosto`, **no** `price`. Y el estado de reparto lo manda
`resultado` de la parada, **no** el estado de la ruta.

**Cómo se prueba.**
- Automática: `test/pantallas/pedidos/filtros_test.dart` — los 9 filtros contra una base
  sembrada, uno a uno y los 9 juntos, comparando el total contra el número esperado;
  `orden_local_test.dart` (los 6 órdenes ordenan **sólo la página**);
  `predespacho_test.dart` (suma de empaques/unidades/kg contra un caso a mano);
  golden a 390 / 834 / 1440 px comprobando **qué columnas hay en cada uno**.
- Paridad: casos **P9** y **P10** de `pruebas.md` — la misma lista sin filtros y con los 9,
  contra la de Next: el total y los 10 primeros en orden.
- A mano: la franja azul del arranque acotado con su texto literal; `Ver todos los pedidos`
  la quita; cambiar la sucursal en la barra **no recarga** y cambia los números; con 12 000
  pedidos la pantalla no se queda esperando.

---

### 3.2 · Rutas — `/routes` · `pantallas/rutas/`

Es tres pantallas en una y se construye en ese orden: **lista y detalle** → **asistente de
4 pasos** → **cierre parada por parada**. Pliego: `pantallas.md` §3 y §9.1.

**Qué muestra.** Las tres pestañas con su contador (`Activas` = `planned`, `En curso` =
`in_progress`, `Historial` = `completed`), los filtros de cliente, la agrupación por
sucursal cuando hay más de una, 20 por página, y a la derecha el detalle con el mapa, el
enlace de Google Maps y los botones de estado.

**Qué necesita de la API.** `GET /api/routes`, `GET /api/vehicles`, `GET /api/almacenes`,
`GET /api/branches`, `GET /api/orders/available` (tope 2000, `factura=cuadra` siempre);
y de escritura `POST /api/routes`, `PATCH /api/routes/<id>`, `DELETE /api/routes/<id>`,
`POST /api/routes/<id>/results`.

**Sin conexión, qué sí — y esto es el corazón del proyecto.**

| Acción | Sin red | Cómo |
|---|---|---|
| Ver lista, filtrar, paginar | sí | consulta local |
| Ver detalle, paradas, carga total | sí | consulta local |
| **Armar una ruta** | **sí** | id `local-…`, código de ruta generado en el aparato, **km, peso y precio calculados en el aparato** con `Geo` (haversine + vecino más cercano, calcado de `reglas-negocio.md` §1 y §15.8), apunte `POST /api/routes` a la cola |
| `Iniciar ruta` / `Marcar como completada` | sí | se escribe local + apunte `PATCH` |
| `Eliminar` (no completadas) | sí | local + apunte `DELETE` |
| **Cerrar parada por parada** | **sí** | local + apunte `POST …/results` |
| Imprimir pre-despacho y post-despacho | sí | PDF generado en el aparato — §4.1 |

**Sin conexión, qué no.** El mapa se queda **sin baldosas** (los puntos y el recorrido sí);
`Abrir en Google Maps` y `copiar enlace` quedan deshabilitados con el motivo a la vista; y
los rechazos del servidor (`<n> de los <total> pedidos ya están en otra ruta…`) **llegan
tarde**, al subir, y salen en la bandeja de rechazos con su hora y su motivo — nunca se
descartan (regla 6, caso S6).

**Lo que se valida en el aparato, sin preguntar a nadie** (para que el rechazo tardío sea la
excepción y no lo normal): peso contra capacidad, el pedido no está ya en otra ruta *según
lo local*, `factura=cuadra`, y que hay punto de partida con coordenadas. Los mensajes son
**los literales del servidor** (`pantallas.md` §3, «Errores del servidor»), para que un
rechazo local y uno remoto se lean igual.

**El código de ruta sin conexión.** Se genera en el aparato con el mismo formato que
`generateRouteCode()` (`reglas-negocio.md` §15.5) más un sufijo del aparato, para que dos
sucursales sin red no lo repitan. **Al aplicarse en el servidor manda el del servidor** y la
fila local se reescribe con la respuesta.

**Cómo se prueba.**
- Automática: `test/pantallas/rutas/armado_test.dart` — orden de visita, km (las **dos**
  medidas: con y sin regreso), peso y precio contra un caso fijado a mano;
  `rechazos_test.dart` — los 6 mensajes literales; `cierre_test.dart` — marcar, desmarcar
  pulsando dos veces, `Todas: Entregado`, y que **lo no entregado suelta `routeId` pero
  conserva `ultimaRutaId`**; golden de la lista y del asistente a 390 / 1440.
- Paridad: **P4** (misma ruta con los mismos 8 pedidos: orden, km, peso, precio), **P5**
  (sobrepeso, mensaje literal), **P6** (pedido ya en otra ruta, mensaje literal).
- Integración: **S4** — armar sin red, cerrar sin red, subir las dos: el cierre va a la
  ruta de verdad. **S3** — marcar `entregado`, corregir a `devuelto`, subir: queda
  `devuelto`.
- A mano: en el teléfono, el asistente de 4 pasos entero en avión, con el pre-despacho
  lateral sumando en vivo y la barra de capacidad cambiando de color en 80 % y 100 %.

---

### 3.3 · Panel — `/dashboard` · `pantallas/panel/`

**Qué muestra.** Las 4 tarjetas, «Pendiente por sucursal» y «Acciones Rápidas».
Pliego: `pantallas.md` §1.

**Qué necesita de la API.** `GET /api/dashboard`.

**Sin conexión, qué sí.** **Todo**, y calculado en local: es la misma definición de
«repartible» (`routeId = null` **y** `endLat` no nulo **y** `facturaEstado ∈ {igual,
cambiado}`) sobre la base del aparato, más `entregadosHoy` desde las 00:00 **con la hora del
aparato**. Se implementa **una sola vez**, en `ConsultasPanel`, y el cliente en línea
compara su resultado con el del servidor: si difieren, hay un fallo de definición y se
registra.

**Sin conexión, qué no.** Nada. La única diferencia es que un Super Admin sin red sólo suma
las sucursales que tenga bajadas, y eso lo dice el `RelojDeDatos`.

**Cómo se prueba.** Automática: `test/pantallas/panel/cifras_test.dart` — un juego de 30
pedidos sembrados con las 6 combinaciones límite (sin ruta pero sin `endLat`, con factura
`cambiado`, archivado, entregado ayer a las 23:59 y hoy a las 00:01) y las 7 cifras
comprobadas una a una. Paridad: `GET /api/dashboard` contra las cifras locales, campo por
campo. A mano: que `Pedidos sin ruta` se pinta ámbar con > 0 y primario con 0, y que los
tres enlaces van a `/routes`, `/reports`, `/vehicles`.

---

### 3.4 · Vehículos — `/vehicles` · `pantallas/vehiculos/`

**Qué muestra.** La rejilla de tarjetas (1/2/3 columnas), la ficha en cajón `lg` con sus 8
campos, el cajón `md` de tipos y el ayudante del costo por km. 25 por página, cambiable a
50/100. Pliego: `pantallas.md` §5.

**Qué necesita de la API.** `GET /api/vehicles`, `GET /api/settings`,
`POST/PATCH/DELETE /api/vehicles`, `PUT /api/settings` (tipos).

**Sin conexión, qué sí.** Ver, buscar, paginar. Crear, editar, `Marcar disponible`,
`Usar para domicilio` y eliminar: todo local + apunte. El ayudante del costo por km es
aritmética pura (`costo_km = cobroCUP / (2 × km × tasa)`, tasa por defecto 320) y funciona
siempre.

**Sin conexión, qué no.** La tasa CUP/USD que viene de Accesos: se usa **la última bajada**
y se dice de cuándo es. Y `Eliminar` sigue sin confirmación (es lo que hace la de Next), lo
cual sin red significa que el rechazo —si el vehículo tiene rutas— llega tarde: sale en la
bandeja.

**Ojo:** «sólo un vehículo por sucursal para el domicilio» lo impide la base del servidor
(índice único). En local hay que hacer lo mismo **en la misma transacción**: marcar uno
desmarca los demás de esa sucursal, o la pantalla enseña dos marcados hasta la próxima
bajada.

**Cómo se prueba.** Automática: `ficha_test.dart` — los defectos exactos (`truck`, 1000 kg,
`available`); heredar el costo/km al elegir tipo; el ayudante con `180000 CUP / 72 km / 320`
y el `$/km` resultante; `Usar para domicilio` desmarca al anterior de la sucursal.
A mano: los tres estados con su color, y el eje de edición del guion: **abrir una ficha y
guardar sin tocar nada tiene que dejarla igual**.

---

### 3.5 · Almacenes — `/warehouses` · `pantallas/almacenes/`

**Qué muestra.** Selector de sucursal y de almacén, la lista con estrella/`sin punto`/
`inactivo`, y el editor en cajón `lg` con dirección autocompletada y mapa.
Pliego: `pantallas.md` §6.

**Qué necesita de la API.** `GET /api/almacenes` y `PUT /api/almacenes`
(`{codigo, almacenes:[...]}` — **la lista completa de la sucursal**, nunca el almacén
suelto).

**Sin conexión, qué sí.** Ver lo bajado. Editar nombre, principal, activo y **coordenadas
escritas a mano** (`parseCoordInput`, «19.83, -75.82»), con apunte a la cola.

**Sin conexión, qué no.** El **autocompletado de dirección** y la geocodificación inversa
(Nominatim, red): el campo queda con su texto y el mapa sin baldosas. Y la confirmación
`Guardado en Accesos.` **no se puede dar sin red**: sin conexión el mensaje es
`Guardado aquí. Se manda a Accesos en cuanto haya conexión.` (literal nuevo) — decirle a
alguien que se guardó en Accesos cuando no salió del teléfono es mentir en la pantalla.

**Cómo se prueba.** Automática: `principal_test.dart` — marcar uno desmarca los demás; el
cuerpo del `PUT` lleva la lista entera; `Le falta el nombre.` deshabilita Guardar;
`parseCoordInput` con los formatos del pliego. A mano: los 6 mensajes de error literales de
Accesos, y que un almacén `sin punto` avisa de que desde ahí no se cotiza.

---

### 3.6 · Clientes — `/customers` · `pantallas/clientes/`

**Qué muestra.** La cartera geolocalizada con 6 filtros, 4 columnas, 50 por página y **dos**
juegos de controles de paginación (arriba y al pie). Pliego: `pantallas.md` §4.

**Qué necesita de la API.** `GET /api/customers` con `q, municipio, zona, vendedor,
telefono, kmMax, origen, pagina`.

**Sin conexión, qué sí.** Todo. Incluida la distancia: **es haversine desde el almacén
principal de la sucursal en curso, a dos decimales**, y eso se calcula en el aparato con
`Geo.haversineKm`. El filtro `kmMax` también.

**Sin conexión, qué no.** Nada; no escribe.

**Ojo con la anchura:** en pantallas estrechas **se desplaza la tabla, no la página**
(mínimo 736 px). Es `TablaAncha` del kit, y es el mismo bicho que las tablas de
pre-despacho (§11 del pliego).

**Cómo se prueba.** Automática: `distancia_test.dart` — 5 clientes con coordenadas conocidas
y sus km a dos decimales contra un cálculo a mano; `filtros_test.dart` con los 6; golden a
390 px comprobando que **se desplaza la tabla y no la página**.
Paridad: el total y los km de los 10 primeros contra la de Next. A mano: los tres estados
vacíos, que son tres textos distintos y se confunden con facilidad.

---

### 3.7 · Reportes — `/reports` · `pantallas/reportes/`

**Qué muestra.** Filtros (desde/hasta/vehículo), tres pestañas y la exportación a Excel.
**No está en el menú**: se llega por URL y desde las acciones rápidas del Panel.
Pliego: `pantallas.md` §7.

**Qué necesita de la API.** `GET /api/reports?from=&to=&vehicleId=` y `GET /api/vehicles`.

**Sin conexión, qué sí.** Se puede calcular en local con lo bajado, **pero sólo hasta donde
llegue lo bajado**. Se pinta con el `RelojDeDatos` en ámbar y el aviso
`Cuadrado con los datos del aparato, del <fecha>. Con conexión sale el del servidor.`
(literal nuevo). El Excel se genera igual: es aritmética.

**Sin conexión, qué no.** Nada más. Es la pantalla menos crítica del conjunto y así se trata.

**Ingreso de un pedido = `price` si lo tiene, si no `pedidoCosto`.** Está escrito en el
pliego y es el número que más fácil se equivoca.

**Cómo se prueba.** Automática: `resumen_test.dart` — las 4 cifras y `Top vehículos`;
`xlsx_test.dart` — el fichero tiene **tres** hojas con esos nombres exactos, las cabeceras
literales con la moneda dentro, importes a 2 decimales y pesos a 1.
Paridad: `GET /api/reports` con el mismo rango, las 4 cifras y la fila de totales.
A mano: abrir el `.xlsx` en LibreOffice y en el móvil.

---

## 4 · Lo que NO se traslada tal cual

### 4.1 · Lo impreso: de HTML a PDF — `lib/impresion/`

**Cómo está hoy:** una ventana de 900×700 con HTML escrito a mano, que **no** lanza el
diálogo de impresión: la hoja se revisa y se imprime desde su propio botón. En Flutter no
hay ventana nueva ni impresora del navegador en Android, así que **se genera el PDF**.

**Con qué:** `pdf` (construir) + `printing` (previsualizar, imprimir, compartir). Funciona
en los dos destinos: en web `Printing.layoutPdf` abre el diálogo del navegador, en Android
va al servicio de impresión del sistema y `Printing.sharePdf` lo manda por WhatsApp, que es
lo que de verdad va a pasar en el patio de un almacén.

```dart
Future<Uint8List> pdfPreDespacho(HojaPreDespacho h, {required DateTime impresoEn});
Future<Uint8List> pdfPostDespacho(HojaPostDespacho h, {required DateTime impresoEn});
```

**Reglas de traslado, una por una:**

| En Next | En Flutter |
|---|---|
| ventana 900×700 sin diálogo | `VistaPreviaPdf` en un `Cajon` `xl` con `PdfPreview` |
| botones flotantes `Imprimir` / `Cerrar`, que no se imprimen | acciones del cajón, **fuera del PDF**; se añade `Compartir` |
| 24 px en pantalla / **12 mm al imprimir** | sólo queda lo de imprimir: `PdfPageFormat.a4.copyWith(marginAll: 12 * PdfPageFormat.mm)` |
| tipografía del sistema, 13 px / 1.4 | **Roboto embebida desde `assets/fuentes/`** — `PdfGoogleFonts` baja por red y esto tiene que salir sin red. 13 px ≈ **9.75 pt**, interlineado 1.4 |
| columna vacía de 70 px / 78 px para marcar a mano | ancho fijo `18.5 mm` / `20.6 mm` (70/96 y 78/96 de pulgada) con `pw.FixedColumnWidth` |
| `toLocaleString('es')` en la cabecera | `DateFormat('d/M/y, H:mm:ss', 'es')` — **es punto de paridad**: se compara con lo que imprime la de Next |
| escapar `& < > "` | no hace falta: el PDF no es markup. **Se quita, no se copia.** |

**La cuenta va aparte del papel.** `armarPostDespacho()` (`lib/impresion/armar_post_despacho.dart`)
es Dart puro, sin `pdf` ni Flutter dentro, calcado de `reglas-negocio.md` §12: el número de
una línea son sus **`packs`** y si no los trae sus **`quantity`**, nunca cero; `queda` =
**todo lo que no se entregó**, incluido lo que nadie marcó; sólo salen los productos con
`queda > 0`; el pie suma **las filas mostradas**. Así se prueba sin abrir un PDF, y el mismo
resultado alimenta la vista previa en vivo `Queda en el camión` del cierre.

**Cómo se prueba.** Automática: `test/impresion/armar_post_despacho_test.dart` — el caso del
pliego con paradas sin marcar, un producto entregado entero (no sale) y el orden por `queda`
descendente y luego por nombre; `test/impresion/pdf_golden_test.dart` — el PDF se rasteriza
con `Printing.raster` y se compara contra un golden (una hoja de cada). Paridad: **P7** —
el post-despacho de la misma ruta, columnas y totales al lado de los de Next.
A mano: imprimir las dos en una impresora de verdad y **medir que la columna de marcar a
mano da para escribir un número**; y compartirlas por WhatsApp desde el teléfono.

### 4.2 · Los mapas — `lib/mapas/`

**Cómo está hoy:** componentes de mapa del navegador con baldosas de red y un enlace a
Google Maps.

**Con qué:** `flutter_map` + `latlong2`, baldosas de OpenStreetMap
(`userAgentPackageName: 'cloud.procovar.reparto'`). **No `google_maps_flutter`**: pide clave
de API, en web carga el SDK de JS y **no pinta nada sin red**, que aquí es la mitad del día.

Los cuatro usos del pliego y qué pasa con cada uno:

| Uso | Con red | Sin red |
|---|---|---|
| Detalle de pedido: `Recorrido`, 220 px, almacén → cliente | baldosas + 2 marcadores + línea | `MapaSinBaldosas`: fondo neutro, los 2 puntos, la línea y la escala. Los **puntos son los de verdad** |
| Detalle de ruta: partida (verde) · paradas (azul) · regreso (naranja) | igual, con la leyenda | igual, sin baldosas |
| Asistente paso 2: el almacén, 220 px | igual | igual |
| Editor de almacén: elegir el punto | baldosas + autocompletado Nominatim | **sin autocompletado**; se escribe `lat, lng` con `parseCoordInput` |

- **Caché de baldosas** (`flutter_map_cache` + `dio_cache_interceptor`) para que lo que se
  miró por la mañana siga por la tarde. **Nada de descargar zonas enteras por adelantado**:
  la política de uso de las baldosas de OSM lo prohíbe, y con diez aparatos no hace falta.
  Si algún día hace falta, se sirven baldosas propias y se cambia sólo el `urlTemplate`.
- `Abrir en Google Maps` y `copiar enlace` se quedan como están (`url_launcher` +
  `Clipboard`), con el aviso literal de las 25 paradas y **deshabilitados sin red** con el
  motivo a la vista, nunca en silencio. `copiar enlace` pasa a `copiado` 2,5 s, igual.
- Las distancias **no las da el mapa**: las calcula `Geo.haversineKm`, que es lo que hace la
  de Next. El mapa sólo dibuja.

**Cómo se prueba.** Automática: golden de `MapaSinBaldosas` con 1, 2 y 12 puntos (la línea
y el encuadre); `geocodificar_test.dart` con las respuestas de Nominatim guardadas y los
formatos de `parseCoordInput`. A mano: en avión, abrir el detalle de una ruta y **que se ve
el recorrido**; y que el enlace de Google Maps abre la aplicación de Google Maps en el
teléfono, no el navegador.

### 4.3 · Los textos — ~~`lib/nucleo/i18n/`~~ **NO SE HIZO. Se deshizo el 24/09/2026.**

> **Esta sección está muerta y se deja escrita para que nadie la retome creyendo
> que es un pendiente.** Se llegó a hacer —305 claves en `app_es.arb`, otras 305
> en `app_en.arb`, la clase `Textos` de `gen_l10n`, `l10n.yaml` y las
> delegaciones en `app.dart`—, y quedó **enchufada a una sola pantalla** de las
> cuarenta y pico: `lib/impresion/vista_previa.dart`. Todo el resto de la
> interfaz siempre fueron literales en español a pelo; no había `locale:`, ni
> provider, ni forma de cambiar de idioma. Las ocho sucursales son de Cuba y
> nadie ha pedido inglés, así que era código muerto que las pruebas daban por
> vivo, que es peor que no tenerlo.
>
> **Jose decidió el 24/09/2026 quitarlo entero.** El porqué y lo único que
> sobrevive —`flutter_localizations`, por las delegaciones de Material: sin ellas
> los cinco calendarios de la aplicación salen en inglés— está en
> `lib/idioma.dart`, con su guarda en `test/idioma_test.dart`. De las tres
> pruebas de textos se salvó lo que no miraba la traducción: los literales de las
> hojas impresas, hoy en `test/impresion/literales_de_las_hojas_test.dart`.
>
> Lo de abajo es el plan original, tal como se escribió.


**Cómo está hoy:** diccionarios `es`/`en` de next-intl, anidados por espacios de nombre.

**Con qué:** `flutter_localizations` + **`gen_l10n`** con ficheros ARB.

```yaml
# l10n.yaml
arb-dir: lib/nucleo/i18n/arb
template-arb-file: app_es.arb
output-localization-file: textos.dart
output-class: Textos
nullable-getter: false
```

**Las cinco reglas del traslado:**

1. **`es` es la verdad.** Cada cadena se copia **literal del pliego**, con sus tildes, sus
   comillas angulares y sus puntos. Una coma cambiada rompe el criterio de terminado.
2. **ARB es plano: los espacios de nombre se aplastan** con el nombre de la pantalla
   delante. `orders.filters.title` → `pedidosFiltrosTitulo`. Sin excepciones, o en tres
   semanas hay dos claves para el mismo texto.
3. **Nada de pluralizar con ICU lo que en el pliego está escrito `pedido(s)`.** La de Next
   escribe `<n> pedido(s) elegidos` con el `(s)` dentro; si aquí se pone un `plural{}` de
   ICU el texto deja de ser idéntico al patrón. Se usa ICU **sólo** donde el pliego ya
   distinga singular y plural.
4. **Los números y las fechas no son textos:** van por `intl` con el locale, no dentro de
   la cadena. `initializeDateFormatting('es')` en el arranque.
5. **Los literales nuevos se marcan.** Los que esta aplicación necesita y la de Next no
   tiene (los de sin conexión, los de frescura, el del almacenamiento frágil) llevan el
   prefijo `nuevo…` en la clave y una línea en `@description` diciendo por qué existen.
   Así se sabe siempre qué se comparó con Next y qué no.

**Ojo con el idioma en la barra:** se oculta por debajo de 640 px (§11), sucursal y moneda
no. Y el `RouteSummaryCard` del pliego (§9.3) tiene las etiquetas **en inglés y sin
traducir**; como hoy no lo usa ninguna pantalla, **no se hace**, y si algún día se reutiliza
es con las etiquetas en español.

**Cómo se prueba.** Automática: `test/i18n/claves_test.dart` — `es` y `en` tienen
exactamente las mismas claves (falla el test si falta una); `literales_test.dart` — un
puñado de textos críticos comparados carácter a carácter contra una copia del pliego
(la franja azul de Pedidos, la cabecera del cierre, los 6 errores del armado).
A mano: recorrer las 7 pantallas en `en` buscando textos que se quedaron en español.

---

## 5 · Cómo se prueba, en conjunto

Cada ficha de arriba ya lleva lo suyo. Esto es lo que las cruza.

| Clase | Dónde | Con qué | Cuándo corre |
|---|---|---|---|
| Unidad | `test/nucleo/` | `flutter_test` + `NativeDatabase.memory()` + `mocktail` | en cada guardado |
| Widget y golden | `test/pantallas/` | `matchesGoldenFile` a 390 / 834 / 1440 px | en cada guardado |
| API falsa | `test/apoyo/api_falsa.dart` | `http_mock_adapter` | — |
| Paridad con Next | `test/paridad/` | `dart test`, con `PATRON_URL`, `NUEVA_URL` y un token; **se salta si no están** | a mano, antes de dar algo por bueno |
| Integración | `integration_test/` | `flutter test integration_test -d <aparato>` | antes de cada APK |
| A mano | el guion de `../docs/pruebas.md` | `/qa-como-usuario` | antes de encender |

**Regla que manda sobre todo lo demás** (`pruebas.md`): *un caso que no se ejecutó es
PENDIENTE, nunca «pasa»*. Y nada de «funciona correctamente» sin el dato al lado.

### 5.1 · La prueba que no puede faltar: el día entero sin conexión

Es el caso **S1** y **no se puede automatizar entera**, porque apagar un teléfono no lo hace
un test. Se parte en dos mitades y **las dos son obligatorias**.

**La mitad automática** — `integration_test/dia_sin_conexion_test.dart`, en un aparato real:

```
 1. con red      entrar, que baje el día, anotar cuántos pedidos y la marca `hasta`
 2. sin red      CERRAR la base y volver a abrirla (es lo que pasa al reabrir la
                 aplicación): los pedidos siguen y la marca también
 3. sin red      armar una ruta con 8 pedidos → sale con id local-… y su código
 4. sin red      cerrar esa ruta: 5 entregados, 2 devueltos con motivo, 1 sin marcar
 5. sin red      cerrar y reabrir la base OTRA VEZ: las 8 marcas siguen
 6. sin red      comprobar la cola: 3 apuntes, en orden, con la hora del aparato
 7. con red      un ciclo: UNA renovación, la subida devuelve los 3 aplicados
 8.              el apunte del cierre YA NO dice local-… : dice el id de verdad
```

**La mitad a mano, en un teléfono de verdad, y sin saltarse los pasos 2 y 6** — que son los
que distinguen «guarda en memoria» de «vive en el aparato»:

```
 1. con red   abrir, entrar, que baje el día
 2. sin red   CERRAR la aplicación del todo (deslizar fuera) y volver a abrirla   ← aquí se rompe
 3. sin red   armar una ruta desde la lista de pedidos
 4. sin red   imprimir el pre-despacho (vista previa + compartir)
 5. sin red   cerrar la ruta parada por parada, con motivos
 6. sin red   APAGAR el teléfono y encenderlo                                      ← y aquí
 7. sin red   comprobar que sigue TODO lo marcado, y que el reloj de datos dice de
              cuándo son
 8. con red   quitar el avión y no tocar nada: tiene que subir solo
```

Evidencia que hay que pegar en el informe: el número de pedidos en cada paso, el código de
la ruta, las 8 marcas, y del registro del servidor **cuántas veces se pidió `/refresh`**.
Si no es una, el caso falla aunque todo lo demás salga.

### 5.2 · Antes de dar cualquier cosa por buena

- `flutter analyze` limpio y `flutter test` entero.
- **Compila lo que se despliega: web Y APK.** `flutter build web --release` y
  `flutter build apk --release`. Una de las dos rota es la mitad del proyecto caída.
- En web, comprobar en la consola que la base **no** cayó a `inMemory`.
- Los casos de paridad que toquen a lo que se cambió, con su evidencia literal.
- `git status` limpio y lo sembrado dado de baja.

---

## 6 · Orden de trabajo

Lo que va en la misma ola se puede hacer **a la vez y por personas distintas**. Pasar de ola
requiere que la anterior esté entera.

```
Ola 0  ── esqueleto ───────────────────────────────────────────────  (nadie más empieza)
         pubspec, analysis_options, build.yaml, tema,
         go_router con las 7 rutas vacías, Armazon + BarraLateral + BarraSuperior,
         web/index.html con sqlite3.wasm y drift_worker.js en su sitio
                                  │
      ┌───────────────────────────┼───────────────────────────┐
      │                           │                           │
Ola 1 A) BASE LOCAL          B) RED + IDENTIDAD          C) KIT + i18n + FORMATO
      §2.1 y §2.5            §2.3 y §2.4                  diseno/, arb, Dinero,
      tablas, migraciones,   ClienteApi, fallos,          Peso, Fechas, Geo
      frescura, RelojDeDatos Renovador + CANDADO          (no depende de nada)
      └───────────────┬───────────────┘                           │
                      │                                           │
Ola 2          D) COLA + SINCRONIZADOR  §2.2                       │
                  apuntes, provisionales, ciclo renovar→subir→bajar│
                      └─────────────────┬─────────────────────────┘
                                        │
      ┌──────────┬──────────┬───────────┼───────────┬──────────┬──────────┐
Ola 3 │ PEDIDOS  │ VEHÍCULOS│ CLIENTES  │ REPORTES  │ IMPRESIÓN│  MAPAS   │
      │  §3.1    │   §3.4   │   §3.6    │   §3.7    │   §4.1   │   §4.2   │
      └────┬─────┴──────────┴───────────┴───────────┴────┬─────┴────┬─────┘
           │                                             │          │
      ┌────┴───────────────┬──────────────────────────────┴──────────┤
Ola 4 │  RUTAS (lista +    │  PANEL §3.3                 │ ALMACENES §3.5
      │  detalle +         │  (sólo necesita Pedidos)     │ (necesita mapas
      │  asistente) §3.2   │                              │  y geocodificar)
      └────┬───────────────┴──────────────────────────────┴───────────┘
           │
Ola 5  CIERRE DE RUTA + POST-DESPACHO  §3.2 y §4.1
           │
Ola 6  QA: día sin conexión entero, paridad con Next, APK firmada
```

**El camino crítico es uno solo:** `Ola 0 → A+B → D (cola) → Pedidos → Rutas → Cierre`.
Todo lo demás cuelga de él y se puede mover sin retrasar el final.

**Qué se puede hacer en paralelo desde el minuto uno** (no depende de ninguna pieza):
el kit de `diseno/`, los ARB, `Geo`, `Dinero`/`Peso`/`Fechas`, `armarPostDespacho` (es Dart
puro) y los dos PDF (reciben una estructura de datos, no la base).

**Lo que hay que cerrar FUERA de la aplicación y bloquea si llega tarde:**

1. **`POST /token`, `POST /refresh`, `POST /logout` en auth** (`identidad.md`). Sin ellos no
   hay APK. Mientras tanto, la Ola 1-B se desarrolla contra `ApiFalsa` — pero **el candado
   no se da por bueno hasta probarlo contra el auth de verdad**.
2. **Cuánto dura el refresh.** Está «por decidir» en `identidad.md` y marca cuántos días
   puede un aparato estar sin conectarse antes de tener que entrar otra vez.
3. **`/sync/bajada`, `/sync/subida`, `/sync/aparato`, `/sync/estado`.** Ola 2 depende.
4. **La cookie en web**: bajo qué dominio sale la aplicación y con qué `SameSite`. Bloquea
   la pantalla de acceso de la web, no la de la APK.

---

## 7 · Tres cosas que este plan deja abiertas a propósito

1. **El «tablero» de `pruebas.md` §3 no existe en `pantallas.md`.** El guion dice
   *«preparar el tablero: mover pedidos a columnas»* y eso no es ninguna de las 7 pantallas
   del pliego. O es otra forma de llamar al paso 4 del asistente de rutas, o es una pantalla
   que no está escrita. **No se inventa**: se pregunta antes de la Ola 4.
2. **El tope de 5000 del pre-despacho de lo filtrado.** En el servidor tiene sentido; en el
   aparato, donde sólo está una sucursal, no. Se implementa **sin tope local** y el mensaje
   `Son demasiados pedidos para sumarlos…` sólo sale cuando lo dice el servidor. Si en
   paridad esto da números distintos, es porque el aparato tiene menos pedidos, y eso lo
   dice el `RelojDeDatos`.
3. **Las baldosas de OSM** sirven para diez aparatos. Para más, o si hay que precargar
   zonas, hacen falta baldosas propias. El código ya lo deja en una sola línea
   (`urlTemplate`).

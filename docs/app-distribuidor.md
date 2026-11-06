# «Reparto Distribuidor» — la app del repartidor

Segundo APK del **mismo** proyecto Flutter (`app/`): reutiliza Drift, la cola, el sincronizador y el
motor de sesión de Reparto, y enseña solo **Mis rutas → ruta guiada → cierre parada por parada**, sin
conexión, subiendo cuando haya red. El plan acordado con Jose está en `docs/plan-app-distribuidor.md`.

> **El GPS NO está probado en un teléfono real.** Ni el servicio en primer plano, ni la notificación fija,
> ni lo que hace cada fabricante con la batería. Tampoco se ha instalado el APK en un móvil: lo comprobado
> es que compila (debug, con el mapa de relleno) y que lo que no es del teléfono pasa en pruebas.

## 1. Cómo se compila

```bash
# 1. el mapa de Cuba, que va DENTRO del APK (97 MiB, no se commitea):
deploy/preparar-mapa-distribuidor.sh <sha256 que anuncia /api/mapa> [version]
#    -> app/herramientas/distribuidor-assets/cuba-detallado.{pmtiles,json}

# 2. el APK:
cd app
ORG_GRADLE_PROJECT_distribuidor=true flutter build apk --release -t lib/main_distribuidor.dart
```

El APK pesa **~180 MB** por el mapa. Sin `ORG_GRADLE_PROJECT_distribuidor=true` el APK sale como siempre
(no hay `productFlavors`: nada de `--flavor`). Con la variable cambia, en `android/app/build.gradle.kts`:

| | Reparto (de siempre) | Reparto Distribuidor |
|---|---|---|
| `applicationId` | `cloud.procovar.reparto` | `cloud.procovar.reparto.distribuidor` (se instala AL LADO) |
| nombre | Reparto | Reparto Distribuidor |
| enlace que abre | ninguno (el filtro queda con un host inerte) | `https://reparto.procovar.cloud/r/…` |
| mapa | el que se descarga | dentro del APK (assets nativos) |

Si falta el mapa al compilar el del distribuidor, Gradle **falla** con «falta el mapa: ejecuta
deploy/preparar-mapa-distribuidor.sh» (comprobado). El script trae el fichero con `ssh vps-vpn` (desde el PC no
se llama a ningún dominio de Procovar) y aborta si el sha256 no coincide con el anunciado. **No se ha ejecutado.**

La firma es la de siempre (`android/key.properties`). La huella SHA-256 del certificado, para
`assetlinks.json`: `apksigner verify --print-certs app-release.apk` o `keytool -list -v -keystore … -alias …`.

### Versión propia (Jose, 06/11/2026)

«Reparto» y «Reparto Distribuidor» son aplicaciones DISTINTAS y llevan **cada una su versión**, «para poder darle mejor
soporte y mejor control». **Subir una NO obliga a subir la otra.**

| | Reparto | Reparto Distribuidor |
|---|---|---|
| de dónde sale | `app/pubspec.yaml` (`version: 1.0.56+57`) | `app/android/distribuidor.version` (`name=1.0.0`, `code=57`) |
| medido con `aapt2 dump badging` (06/11/2026) | `versionName 1.0.56`, `versionCode 57` | `versionName 1.0.0`, `versionCode 57` |
| qué anuncia `GET /api/version` | `ultima` (`APP_ULTIMA_*`) | `distribuidor` (`APP_DISTRIBUIDOR_*` y `APP_DESCARGA_ANDROID_DISTRIBUIDOR[_BYTES|_SHA256]`) |

* Con `ORG_GRADLE_PROJECT_distribuidor=true`, `build.gradle.kts` toma `versionName`/`versionCode` de `distribuidor.version`
  y NO de `flutter.versionName/Code`; sin la propiedad, Reparto sigue con el pubspec. `code` es **su propia cuenta,
  siempre creciente** (Android solo deja instalar encima un `code` mayor): el chofer ya publicado llegó al 56, así que
  arranca en 57. Se sube +1 en cada APK del distribuidor que se publique.
* Comprobar antes de repartir (el SDK sale de `sdk.dir` en `app/android/local.properties`):

  ```bash
  AAPT2=~/Android/sdk/build-tools/36.0.0/aapt2
  cd app
  ORG_GRADLE_PROJECT_distribuidor=true flutter build apk --release -t lib/main_distribuidor.dart
  $AAPT2 dump badging build/app/outputs/flutter-apk/app-release.apk | head -1   # …distribuidor versionCode='57' versionName='1.0.0'
  flutter build apk --release                                                     # el de Reparto, con el pubspec
  $AAPT2 dump badging build/app/outputs/flutter-apk/app-release.apk | head -1   # …reparto versionCode='57' versionName='1.0.56'
  ```
* **Lo que se ve:** cada llamada de la app del distribuidor lleva `X-App-Version: 1.0.0+57` (`nucleo/red/version_de_la_app.dart`,
  solo en su modo; Reparto no la manda); el servidor la apunta por teléfono y la pestaña «Teléfonos» la enseña como
  «Versión 1.0.0 (57)», con la etiqueta «Desactualizada» si es menor que la `compilacion` anunciada en `distribuidor`
  («Versión desconocida» si el teléfono aún no la declaró).
* **El aviso de versión nueva del chofer** es el mismo del armazón de Reparto (`navegacion/aviso_de_version_nueva.dart`) leyendo
  la clave `distribuidor` (`ComprobadorDeActualizacion(clave:)`, elegida por `modoDistribuidorProvider`) y comparando con SU
  `versionCode`; mismas tres reglas (no se actualiza con trabajo sin subir, nunca se fuerza, web no aplica), sin reintentos,
  y además se vuelve a mirar UNA vez cuando la red pasa de mala a buena si al arrancar no se pudo saber. No sale en la puerta
  («Añadir ruta», sin armazón): sale en cuanto hay rutas.
* Cuando se publique: subir `code`, compilar, y anunciar la misma `compilacion` en `APP_DISTRIBUIDOR_COMPILACION`.

### Lo que SÍ cambia en el APK normal

`geolocator` y los permisos de ubicación están en el manifiesto de `main`, así que **el APK de siempre también
los declara** (ubicación precisa y aproximada, servicio en primer plano de ubicación, notificaciones) y lleva
el código del plugin. **Nunca los pide**: solo `main_distribuidor.dart` enciende el GPS. Y lleva un
`intent-filter` con un host inerte (`sin-enlaces.invalid`) que no abre nada. Si Jose no quiere ni eso, hay que
partir el manifiesto (un `src/distribuidor/` exige `productFlavors`).

## 2. Sin usuario ni contraseña: el enlace de la ruta

Decisión de Jose (04/11/2026): **no hay login ni cuentas de Accesos**. El logístico manda por WhatsApp un
enlace por ruta, `https://reparto.procovar.cloud/r/<token>`.

* Android abre la app con ese enlace (`intent-filter` con `autoVerify`, scheme `https`, host
  `reparto.procovar.cloud`, `pathPrefix /r/`). Flutter lo entrega como ruta `/r/<token>` tanto con la app
  cerrada (ruta inicial, `main_distribuidor.dart` → `enlaceDeEntrada`) como abierta (`pushRouteInformation` →
  go_router). **No se usa `app_links`**: no hace falta con el *deep linking* de Flutter y evita otra dependencia.
  *Pendiente de probar en un teléfono con WhatsApp de verdad.*
* **Agregar ruta a mano** (respaldo si abrir el enlace falla): campo donde pegar el enlace completo o solo el
  código, con su explicación; está en el menú y en «Mis rutas» (con y sin rutas).
* `dispositivoId` (UUIDv7) lo genera la app la primera vez (preferencias del aparato); `secreto` lo da el servidor
  al reclamar el primer enlace. `POST /api/d/reclamar` `{token, dispositivoId, nombre, secreto?}` SIN
  `Authorization` → `{acceso, secreto?, expira, rutaId, sucursal}`. Errores con sus palabras: 403
  `ruta_de_otro_dispositivo`, 404 `enlace_no_valido`, 410 `enlace_revocado`, `ruta_cerrada`.
* Cada enlace nuevo se SUMA a las rutas del teléfono; con red, reclamar es lo único que la exige.
* Con el `acceso` (JWT, rol DISTRIBUIDOR) funciona el MISMO motor de siempre: `/sync/cambios`, la cola por
  `/sync/subida`, `POST /routes/{id}/results`, `PATCH /routes/{id}` y `POST /api/track`.
* En el `Sesion` guardado (almacén seguro de siempre): `sub` = dispositivoId, `refresh` = **el secreto**,
  `token` = el acceso. La base local es del dispositivo.

### Vehículo, distribuidor y desvinculación

El enlace trae vehículo y distribuidor: `POST /api/d/reclamar` devuelve además `vinculoId`, `vehiculoId`,
`vehiculo {id,nombre,placa,tipo}` y `distribuidor {id,nombre}` (si la ruta lo tiene). La app los guarda en las
preferencias de su base (`VinculoDelTelefono`) y los enseña en «Mis rutas» («Triciclo-Juan (P-77) · Juan»).
Errores nuevos de reclamar (se enseña el `mensaje` del servidor): 403 `vehiculo_de_otro_dispositivo`,
403 `dispositivo_de_otro_vehiculo`, 409 `ruta_sin_vehiculo`.

**Desvinculado.** Cualquier llamada (rutas, sync, results, track, renovar) puede contestar 403
`dispositivo_desvinculado`. Se detecta en el interceptor de `ClienteApi` (`alDesvincular`), en el renovador del
dispositivo y en la segunda cerradura de `Subida._aplicar` (el sync convierte el 4xx en un rechazo dentro de un 200:
se busca `dispositivo_desvinculado` o «fue desvinculado» en el motivo). La app se **vacía**
(`Desvinculador`): borra todas las tablas de la base local (rutas, paradas, marcas, historial, puntos GPS, cola,
vínculo, preferencias) y el acceso, y **conserva solo el id de dispositivo y el secreto** (en las preferencias de la
base neutra). Vuelve a «Agregar ruta» con «Este teléfono fue desvinculado de su vehículo. Pide a tu logístico un
enlace nuevo.» y, si había algo sin enviar, **una vez** cuántas marcas, cambios de ruta y puntos de GPS se descartaron.
Un enlace nuevo funciona con el mismo id y el mismo secreto (es el mismo teléfono para el servidor). El mapa del APK
no se toca. *Supuesto:* el motivo del rechazo que el sync devuelve dentro de un 200 contiene la marca o la frase; si
el sync lo redacta distinto, el 403 directo de la API (renovar, `/api/track`, `results` en vivo) sigue funcionando.

### La sesión no se cierra sola (punto 8 del encargo)

Antes (Accesos): token de acceso de 15 min y refresh de 30 días de un solo uso; pasados esos 30 días, o con un
401 al renovar, la sesión moría y se volvía a la puerta (`Renovador`, `Portero.murio`). Sin red nunca muere: se
entra con lo guardado.

Ahora: `RenovadorDeDispositivo` (hereda de `Renovador`, así el interceptor, el ciclo y el arranque no cambian):

* **al arrancar** renueva solo si al acceso le quedan **menos de 30 días** (`Renovador.alArrancar`, nuevo);
* **ante un 401** de una llamada normal renueva siempre, con `POST /api/d/renovar` `{dispositivoId, secreto}`
  → `{acceso, expira}`;
* el **secreto no cambia** al renovar (no es de un solo uso); solo si el servidor contesta 401 al renovar
  (dispositivo revocado) se borra la sesión y se vuelve a «Agregar ruta».

**Lo que falta pedir** (otra sesión): `/api/d/reclamar` y `/api/d/renovar` en la API, el claim `dispositivo` en el
JWT, el acceso de meses y el alcance de `/sync/cambios` por dispositivo; y la página `/r/<token>` con
`/.well-known/assetlinks.json` (`package_name = cloud.procovar.reparto.distribuidor`).

## 3. Lo que hace la app

* **Mis rutas**: `PantallaRutas` en *modo distribuidor* (`modoDistribuidorProvider`, un `override` en
  `main_distribuidor.dart`; por defecto `false` y Reparto no cambia). Sin «+ Nueva Ruta», filtros, «Eliminar»,
  «Quitar de ruta», reordenar, pre-despacho, importes, WhatsApp ni compartir. Pestañas: Planificadas, En curso,
  Historial (la cancelada cuenta como historial).
* **Ruta guiada** (`distribuidor/ruta_guiada.dart`): el propio distribuidor INICIA la ruta; la app enseña SIEMPRE la
  parada de ahora (la primera sin resultado por `stop_order`) con factura, cliente, teléfono, dirección, notas,
  productos con su cantidad en empaques, el cronómetro de la parada y el de la ruta, «Navegar a esta parada»
  (`https://www.google.com/maps/dir/?api=1&destination=lat,lng&travelmode=driving`) y «Llamar al cliente».
  Varias rutas en curso a la vez: cada tarjeta dice su siguiente parada.
* **Marcar**: «Entregado» (con «Cobrado» sí/no) o «No entregada» (viaja como `devuelto`; el **motivo es
  obligatorio**). Cada marca guarda la **hora del aparato**; en el cuerpo de `POST /routes/{id}/results` viajan
  `cobrado` (boolean) y `hora` (ISO UTC) por parada. La app no sabe importes de factura: lo único de dinero es ese
  «cobrado» (decisión A). Se guarda en `cobros_de_entrega` (tabla aparte: la bajada reescribe la fila del pedido).
* **Estado visible de cada parada (issue 26 de Amado, 06/11/2026).** Una sola función, `estadoDeParada(resultado,
  cobroEntrega)` (`app/lib/diseno/estado_de_parada.dart`), y una sola etiqueta, `EtiquetaDeEstadoDeParada` (color +
  borde + icono + texto, sin relleno): Pendiente · Entregada · cobrada · Entregada · sin cobrar · Entregada (cobro sin
  anotar) · No entregada (con el motivo) · Cancelada. El cobro es `cobros_de_entrega` (lo marcado aquí, antes de
  subir) y, si no hay, `orders.cobro_entrega` (esquema local 18, baja del servidor). La ruta guiada enseña TODAS las
  paradas con su etiqueta (`distribuidor/paradas_de_la_ruta.dart`). Los mandos de la parada van con `temaDeLaCalle`
  (7:1 de contraste, letra 16, 48 px).
* **La ruta se completa SOLA** al marcar la última (`GuiaDeRuta.marcar` → `completar`); offline queda en la cola
  *detrás* de los resultados. Con una sola parada sin marcar, no.
* **Cancelar la ruta** (cajón con motivo obligatorio): `PATCH /routes/{id}` `{"status":"cancelled","motivo":…}`.
  Solo si no hay ninguna entregada (el aparato lo dice antes con las mismas palabras que el servidor).
* **Historial** (`distribuidor/vista_historial.dart`, de la base local): fecha, paradas, entregadas / no
  entregadas / cobradas, salida, fin, duración; «Enviada» o «Pendiente de enviar» (cola de apuntes + GPS); y
  «Revisada ✓» / «Pendiente de revisión de logística» según `revisadaAt` (columna nueva `routes.revisada_at`). Al abrir
  una ruta: sus paradas con lo que marcó y a qué hora. Las rutas completadas se quedan en el móvil.
* **Aviso de ubicación** la primera vez («Reparto registra tu ubicación mientras haces una ruta, para un mejor
  trabajo», «Aceptar»): se guarda quién y cuándo en las preferencias del aparato. «Ahora no» deja trabajar sin GPS
  y vuelve a preguntar la próxima vez.

## 4. El GPS

`geolocator` 14.0.1 (la 14.0.2+ choca con `nm`/`connectivity_plus`). UN solo flujo para todas las rutas en curso,
con servicio en primer plano de Android y notificación fija «Reparto: ruta en curso»; se enciende con la primera ruta
en curso (y el aviso aceptado) y se apaga cuando no queda ninguna. Constantes en `gps/ajustes_de_gps.dart`
(30 s / 30 m; en Android el servicio aplica **las dos a la vez**, así que parado en un almacén no hay puntos: la
llegada la da el punto `parada`).

* Tabla local `puntos_gps` (esquema 17): id UUIDv7, `ruta_ids` (las rutas en curso en ese instante), lat, lng,
  precisión, velocidad, rumbo, hora del APARATO, evento `inicio`/`parada`/`fin`, pedido, subido. Cada marca de
  parada guarda un punto `parada`+pedido; `inicio`/`fin` al iniciar/completar/cancelar. Sin posición reciente no
  se inventa el punto.
* Subida tras la cola de apuntes (`CicloDeSincronizacion.despuesDeSubir`), lotes ≤ 200, `POST /api/track`
  `{"puntos":[…]}`, idempotente por id; un fallo se reintenta y no pierde nada.
* Retención local: a los 90 días se podan los puntos **ya subidos**; los no subidos **no se borran nunca**.
* El distribuidor no ve el recorrido ni el estado de la subida del GPS. Sin permiso lo dice con palabras
  («la oficina no verá tu recorrido…») y se trabaja igual.
* Límites: no probado en un teléfono; hay móviles que matan el servicio (hay que quitar la optimización de batería
  a la app); sin permiso de notificaciones (Android 13+) la notificación del servicio puede no verse y no se pide
  (no hay `permission_handler`); sin señal GPS en almacenes no hay puntos.

## 5. El mapa dentro del APK

Los assets nativos de Android (`herramientas/distribuidor-assets/`, solo con `distribuidor=true`) llevan
`cuba-detallado.pmtiles` y `cuba-detallado.json`. En el primer arranque, SIN RED y sin cargar 97 MB en memoria,
`MapaIncluido.kt` copia el asset por trozos a `cuba-detallado.pmtiles.parcial`, Dart comprueba el sha256 y solo
entonces renombra y escribe el `.json` con el mismo formato que la descarga (`PaqueteGuardado`): el resto del
código lo ve como «descargado». Reanuda si se mata la app; si ya está y cuadra, no hace nada; si el APK trae otra
versión, la reemplaza. Pantalla «Preparando el mapa de Cuba… (una sola vez)». La app **nunca** ofrece bajar mapa y el
mapa no sale a la red (ni teselas ni OSRM: `distribuidor/mapa/solo_local.dart`).

## 6. Qué queda por hacer / por probar

* Instalar el APK en un teléfono: GPS, servicio en primer plano, apertura del enlace desde WhatsApp, copia del mapa.
* Ejecutar `deploy/preparar-mapa-distribuidor.sh` y compilar el release de verdad.
* El servidor: ver §2 («Lo que falta pedir»); `revisadaAt` en la ruta; `cobrado`/`hora` en `results`; el motivo
  de cancelar (`motivo`) es un campo extra que el servidor puede ignorar.
* Publicación del segundo APK y su canal (`APP_DESCARGA_ANDROID_DISTRIBUIDOR_*`, plan §6).

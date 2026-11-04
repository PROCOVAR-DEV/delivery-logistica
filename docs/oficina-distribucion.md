# La oficina y la distribución: pantallas nuevas y contrato del servidor

Rama `feat/oficina-distribucion`. Hace de la app de Reparto de la oficina (web, Windows y APK de los logísticos) la contraparte de la
app del distribuidor (`docs/plan-app-distribuidor.md`, `docs/roadmap-distribucion.md`, frente «Reparto — aplicación de la oficina»).

**Todo esto es EN VIVO contra el servidor**, también en la APK y en Windows: el enlace de cada ruta, el GPS y la revisión viven en el
servidor, no en la copia del aparato. Sin red la pantalla lo dice con su motivo («Sin conexión con el servidor.») y no finge. No se toca
Drift ni el sincronizador. Son pantallas de la oficina (logístico, administrador, super admin, desarrollador) como el resto de Rutas; el
cerrojo es el del servidor (403) y no hay roles escritos en la app. En la app del distribuidor no se montan.

Código: `app/lib/pantallas/distribucion/` (`datos/modelos.dart`, `datos/api_distribucion.dart`, `vista/…`). Pruebas:
`app/test/pantallas/distribucion/`.

## Pantallas

| # | Dónde | Qué hace |
|---|---|---|
| 1 | Rutas → detalle de la ruta, bajo el mapa | **Enviar a distribuidor**: WhatsApp / Compartir / Copiar. Crea u obtiene el enlace (`POST`, siempre al pulsar) y manda: «Tu ruta RT-001 · nombre · fecha · 3 paradas:» + el enlace en su línea + «Necesitas la app Reparto Distribuidor; si no la tienes, el enlace te dice cómo instalarla.» Sustituye al enlace de Google Maps y a la lista de facturas por parada (borrados). |
| 2 | Mismo bloque | **Estado del enlace**: «Sin enlace» / «Sin reclamar» / «Asignada a <teléfono> el <fecha>», y **Soltar y mandar a otro teléfono** (pide confirmación; manda `renovar:true`). Una ruta `local-…` (armada sin red) o cerrada no se puede enviar y lo dice. |
| 3 | Rutas → detalle, botón **Recorrido real** (solo si hay puntos) | Cajón con: salida, llegada, duración total, km por la traza del GPS, paradas marcadas; mapa (el croquis de siempre con calles si hay red o paquete) con la traza morada y las paradas numeradas; por parada: hora real, resultado, cobro, nota, tiempo desde la anterior y tiempo en la parada (desde que el GPS pasó a menos de 75 m hasta que se marcó), y aviso si la marca se hizo a más de 250 m de su punto. Estados vacíos: cargando, sin puntos, sin red (con «Reintentar»), traza recortada. |
| 4 | Vehículos → tarjeta → **Historial** | Cajón con las rutas del vehículo (más reciente primero): fecha, quién las hizo, paradas / entregadas / devueltas / cobradas, km, duración, salida y llegada; al tocar una con GPS, su Recorrido real. |
| 5 | Menú → **Distribución** → «Dónde están» | Mapa con el último punto de cada distribuidor con ruta en curso, hace cuánto lo mandó y **aviso en ámbar pasados 10 minutos**. Se refresca solo cada 30 s y con «Actualizar». |
| 6 | Mismo menú → «Por revisar (n)» y el detalle de una ruta completada | «Pendiente de revisión» / «Revisada ✓ por <quién> el <fecha>» y botón **Confirmar revisión**. Lista filtrable (Pendientes / Revisadas / Todas + buscador por código, distribuidor o vehículo); al tocar una fila, su revisión y su recorrido juntos. |
| 7 | Vehículos → ficha → **Lo lleva**; asistente de Nueva ruta | Selector del distribuidor por defecto del vehículo. Al elegir vehículo en el asistente se propone ese distribuidor (si es de la sucursal y está en activo), con la frase «Propuesto porque suele llevar este vehículo.». |

## Contrato esperado del servidor

Paths relativos a `/api`. Todos solo para quien no es distribuidor.

```
POST /routes/{id}/enlace        {"renovar":true?}  -> 200/201 {"token","url","creadoAt","estado":"sin_reclamar"|"reclamado",
                                                              "dispositivoId"?,"dispositivo"?,"reclamadoAt"?}
                                                      409 = la ruta ya está cerrada (se enseña su frase literal)
GET  /routes/{id}/enlace        -> lo mismo, o {"estado":"sin_enlace"}
GET  /routes/{id}/track         -> {"ruta":{id,codigo,nombre,estado,inicio,fin,distribuidorId,distribuidor,vehiculoId,vehiculo},
                                    "puntos":[{id,lat,lng,precision,velocidad,rumbo,hora,evento,pedidoId}],
                                    "paradas":[{pedidoId,factura,cliente,lat,lng,orden,resultado,resultadoAt,nota,
                                                cobroEntrega,cobroEntregaAt}], "truncado":bool}
GET  /vehicles/{id}/historial   -> {"vehiculoId","rutas":[{id,codigo,nombre,estado,fecha,inicio,fin,km,distribuidorId,distribuidor,
                                    paradas,entregadas,devueltas,cobradas,puntos}]}
GET  /tracking/ahora            -> {"distribuidores":[{distribuidorId,distribuidor,lat,lng,hora,recibidoAt,velocidad,rutaIds}]}
GET  /routes                    -> la lista de siempre; cada ruta lleva además "revisadaAt" (nulo = pendiente) y "revisadaPor"
POST /routes/{id}/revision      {"confirmar":true} -> 200 la ruta con revisadaAt/revisadaPor
GET/POST/PATCH /vehicles        aceptan y devuelven "distribuidorId" (quién lo lleva por defecto)
```

Decisiones de lectura que el servidor debe respetar:

* **Horas**: ISO 8601 (con `Z` o con desfase). `hora`/`resultadoAt` son las del aparato; `recibidoAt` es cuando llegó al servidor y es
  lo que cuenta para «hace cuánto mandó su punto».
* **`revisadaAt`**: si la clave NO viene, la ruta no pasa por revisión y no se pinta nada. Si viene (aunque sea `null`) y la ruta está
  `completed`, es «pendiente de revisión». Para que las rutas viejas no salgan todas pendientes, el servidor debe omitir la clave (o
  fecharlas) en las que no cerró un distribuidor.
* **`cobroEntrega`**: `cobrado` / `no_cobrado` / nulo (sin anotar). **`resultado`**: `entregado`, `devuelto`, `no_entregada`; otro valor se
  enseña tal cual con la primera en mayúscula.
* **`PATCH /vehicles/{id}`**: la app solo manda `distribuidorId` cuando pudo leer quién lo llevaba; si no pudo, omite la clave (no manda
  un `null` que lo borre). Con la clave a `null` quiere decir «nadie en particular».

## Lo que NO hace (a propósito) y por qué

* **Nada en Drift ni en el sincronizador**: la copia local de la flota y de las rutas no trae `distribuidorId` ni `revisadaAt`. Se leen
  en vivo. Cuando el sync los lleve, se podrá mostrar sin red.
* **La propuesta del distribuidor al armar** solo está en el asistente de Nueva ruta, no en el cajón de zona del Tablero (ahí el camión
  lo reparte el algoritmo al armar). Sin red no se propone nada.
* **No se publica ni se despliega nada**; la web, la APK y Windows quedan para el visto bueno de Jose (roadmap, tareas 8-11).

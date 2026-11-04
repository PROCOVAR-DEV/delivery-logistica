# Plan: la aplicación del distribuidor y el control de la distribución

Pedido de Jose (04/11/2026): una aplicación para el distribuidor —el que va en el vehículo— que trabaje sin conexión, con su
sincronizador, que le diga en cada punto qué factura, qué productos y cantidades dejar y qué cobrar, que complete la ruta sola, y
que la **administración** vea dónde estuvo cada distribuidor en cada ruta (GPS del móvil), qué movimientos hizo y cuánto se demoró.
El distribuidor **no** ve nada de ese seguimiento.

> Google Maps no admite notas por parada en el enlace (comprobado con el enlace de verdad, 04/11/2026), por eso se hace una app
> propia en vez de seguir empujando información por Maps. La 1.0.53 ya manda al chofer, por mensaje, la factura y los productos de
> cada parada en el orden de Maps; esta app es lo que lo sustituye.

## 0. Lo que hay hoy (leído de producción el 04/11/2026, solo lectura)

**Distribuidores** (`distribuidores`: solo `id, branch_id, nombre, activo`; no hay vínculo con ninguna persona de Accesos):

| Sucursal | Distribuidores | Vehículos |
|---|---|---|
| La Habana | Angel, Augusto, Felix, Juan, Kensy, Sander | Triciclo-Augusto, Triciclo- Felix, Triciclo-Juan, Fulgon-Vladimir, Fulgon-tropicalcarga, Camion |
| Santiago | Jorge Perez Perez, Julian La Rosa Rios, Oberlandis Torres Torres, Wilson Columbie, Yasmany Banos Perez | Triciclo-J, Triciclo_L, Triciclo_Y, Camion 10T, Camion 7,5T, Camion 8T |
| Las demás | ninguno | un «Vehiculo XX» genérico cada una (Camagüey: «10 T») |

- El nombre de los triciclos lleva al distribuidor (Triciclo-Augusto, -Felix, -Juan; Triciclo-J/L/Y), pero **no hay vínculo real**: una
  ruta guarda `vehicle_id` y `distribuidor_id` por separado. Los camiones y fulgones no se pueden emparejar por el nombre.
- Rutas con distribuidor en 30 días: 17; **7 sin distribuidor** (el campo es opcional y se deja vacío).
- Usuarios en Accesos: 10 roles, **ninguno** de distribuidor, y ningún usuario con el nombre de un distribuidor. Logísticos: Maikel
  (Santiago) y «Logistico test» (La Habana).
- **Lo que hay que cobrar:** Reparto solo sabe el **domicilio** (`pedido_costo`, `factura_domicilio`). El total de la factura y si
  está pagada viven en Ventra y no llegan a Reparto. «Cobrar» hoy = el domicilio.
- **Horas reales:** hoy `resultado_at` de varias facturas es la MISMA hora (las marca el logístico de golpe al cerrar), así que no se
  sabe cuándo se entregó cada una ni cuánto tardó. La app del distribuidor lo arregla: cada marca lleva la hora del aparato.

## 1. Quién es quién (Accesos y Reparto)

1. **Rol `DISTRIBUIDOR` en Accesos** (`src/rbac/system-roles.ts`: al FINAL de `SYSTEM_ROLE_NAMES` para no mover el escalafón; llaves
   `delivery.entrar`, `reparto.read`, `reparto.complete`, `ruta.read`, `vehiculo.read`; nada de `crm.entrar`, ni de armar/gestionar).
   Se siembra al arrancar Accesos; luego los permisos se editan en Roles y permisos. Tests de `rbac/__tests__` y la lista de roles de
   `procovar/CLAUDE.md` («Son DIEZ» pasa a ONCE).
2. **Un usuario por distribuidor** (creado en Accesos con rol `DISTRIBUIDOR` y su sucursal). Lista propuesta: 11 usuarios (6 La Habana +
   5 Santiago). Los crea Jose desde el dashboard de Accesos (yo no creo cuentas).
3. **Vínculo usuario ↔ distribuidor** (lo que no existe): columna `distribuidores.persona_id` (el `sub` del token, texto) con índice
   único, y un selector en la pantalla Distribuidores para asignarlo.
4. **Vínculo vehículo ↔ distribuidor**: columna `vehicles.distribuidor_id` (quién lo lleva por defecto) y selector en Vehículos. Al
   armar una ruta con ese camión se propone su distribuidor (arregla las rutas «sin distribuidor»).

## 2. Seguridad en el servidor (lo primero y lo más delicado)

Hoy cualquiera con `delivery.entrar` hereda todo lo que puede el logístico de su sucursal. Un distribuidor tiene que fallar **cerrado**:

1. El alcance gana una dimensión nueva: el distribuidor de la sesión (resuelto por `persona_id`). Sin fila en `distribuidores` →
   403, nunca «ve toda la sucursal».
2. **Lista blanca por rol** en el enrutador: a un `DISTRIBUIDOR` solo se le dejan `GET /api/sync/cambios` y `/api/sync/cuadre`
   (acotados), `GET /api/routes` y `/{id}`, `POST /api/routes/{id}/results`, `PATCH /api/routes/{id}` solo con `status`, el envío del
   GPS (`POST /api/routes/{id}/track`) y lo de sesión/versión. Todo lo demás, 403 (tablero, pedidos, clientes, vehículos, ajustes,
   informes, conduces, armar y borrar).
3. El SQL acota por distribuidor en rutas, paradas, pedidos de esas rutas (por `COALESCE(route_id, ultima_ruta_id)`, que un devuelto
   suelta `route_id`), renglones, vehículo y su propio distribuidor; también las lápidas y el cuadre diario, o un pedido que salió de la
   ruta no se limpia nunca. No se le bajan clientes (no hay `customer_id` en `orders`: se usan los datos de la propia factura),
   productos ni tablero.
4. La lista de roles de la API (`auth`) y la del sync (`identidad`) están atadas por `docs/roles-de-reparto.casos.json`: se tocan juntas.
5. Pruebas de extremo a extremo (`api/e2e`, contra la API y el sync reales): un distribuidor no ve ni toca rutas ajenas, no llama a
   ningún endpoint fuera de la lista, y no puede reasignarse la ruta ni cambiar de camión.

## 3. La aplicación del distribuidor («Reparto Distribuidor»)

Segundo APK del **mismo** proyecto Flutter (reutiliza Drift, la cola, el sync y el login; no se copia nada):
`lib/main_distribuidor.dart`, `applicationId` con sufijo `.distribuidor` activado por variable de entorno (sin ella, el APK de
siempre sale idéntico), nombre «Reparto Distribuidor».

- **Mis rutas** (solo las suyas, hoy y pendientes) → detalle → paradas en el orden de visita. Se esconden armar, borrar, reordenar,
  tablero, vehículos, pedidos…
- **Por parada, bien visible**: factura, cliente, teléfono, dirección, **productos con cantidad (empaques)**, **lo que hay que
  cobrar** (el domicilio; ver decisión A) y las notas.
- **Navegar a esta parada** (Google Maps solo a ese punto) y «Llamar al cliente».
- **Marcar cada parada**: entregado / devuelto / no estaba, con nota, y **hora real del aparato**. Offline; sube por detrás.
- **La ruta se completa sola** cuando todas las paradas tienen resultado (sin que el logístico lo haga). Iniciar la ruta lo hace él.
- Aviso si falta el permiso de ubicación («la oficina no podrá ver tu recorrido»), pero sin impedirle trabajar.

## 4. El GPS (solo lo ve la administración)

- **Captura**: mientras la ruta está «en curso», servicio en primer plano de Android con notificación fija («Reparto: ruta en
  curso»), un punto cada ~20 s o 30 m. No se sigue fuera de la ruta. Permisos: ubicación precisa, servicio en primer plano de
  ubicación y notificaciones; no se pide ubicación en segundo plano salvo que haga falta.
- **Local primero**: tabla `puntos_gps` en Drift (id UUIDv7, ruta, lat, lng, precisión, velocidad, rumbo, hora del aparato, evento
  `inicio` | `parada` | `fin`, pedido, subido). Cada marca de parada guarda un punto con su evento.
- **Subida por lotes** cuando hay red (hasta 200 puntos): `POST /api/routes/{id}/track`, idempotente por `id`. Si falla, se reintenta:
  no se pierde nada.
- **Servidor**: tabla `route_tracks` (índice por ruta y hora) y lectura `GET /api/routes/{id}/track` **prohibida** a `DISTRIBUIDOR`.
  Retención propuesta: 90 días (luego se poda).
- Volumen: ~1.400 puntos por ruta de 8 h; despreciable.
- **Límites que hay que decir claro**: no está probado en un teléfono real hasta que se instale; algunos móviles matan el servicio
  para ahorrar batería (hay que pedir que se quite la optimización de batería); sin señal de GPS dentro de almacenes no hay puntos.

## 5. La parte de administración (lo que ven el logístico, el administrador y arriba)

Dentro de la aplicación de Reparto de siempre (web, escritorio y APK), solo para roles de oficina:

1. **Recorrido real de la ruta**: pestaña en el detalle con el mapa, la traza del GPS, cada parada con su hora de llegada, el tiempo en
   la parada y los tiempos entre paradas; paradas marcadas lejos de su punto (se marcó sin estar allí); tiempo total, km reales
   frente a los planificados, tiempo parado y a qué hora salió y llegó.
2. **Distribuidor**: sus rutas, paradas por hora, tiempo medio por parada, km, hora de inicio y fin, entregas y devueltos.
3. **Dónde están ahora**: mapa con el último punto de cada distribuidor con ruta en curso y hace cuánto lo mandó; aviso si pasan
   N minutos sin señal.
4. En Distribuidores y Vehículos: asignar usuario y vehículo.

## 6. Publicación

- Segundo canal de descarga: variables propias (`APP_DESCARGA_ANDROID_DISTRIBUIDOR_*`), `/api/version` que las sirva y una tarjeta
  nueva en el portal. `deploy/publicar-apk.sh` asume UN solo APK y su limpieza borraría el del otro: se parametriza por prefijo.
- El aviso «versión nueva» de cada app lee su propio anuncio (si no, uno se actualizaría al APK del otro).

## 7. Orden de trabajo y estado

| # | Pieza | Depende de | Estado |
|---|---|---|---|
| 1 | Servidor: `persona_id`, `vehicles.distribuidor_id`, alcance, lista blanca, SQL acotado, pruebas e2e | — | por empezar |
| 2 | Accesos: rol `DISTRIBUIDOR` (código, tests; despliegue con visto bueno) | — | por empezar |
| 3 | App del distribuidor (entrada, mis rutas, parada con cobro, completar sola, navegar) | 1 | por empezar |
| 4 | GPS: captura, tabla local, subida, `route_tracks` | 1, 3 | por empezar |
| 5 | Administración: recorrido real, distribuidor, dónde están | 4 | por empezar |
| 6 | Publicación del segundo APK y portal; usuarios creados por Jose | 1–3 | por empezar |

Nada de esto se publica hasta que las piezas 1–3 estén probadas de punta a punta contra la API y el sync reales.

## 8. Decisiones de Jose

- **A. Qué cobra el distribuidor**: solo el domicilio (lo que Reparto sabe hoy), o también el importe de la factura (haría falta
  traerlo de Ventra).
- **B. GPS**: solo con la ruta en curso (propuesto) o durante toda la jornada.
- **C. Vínculos**: confirmar quién lleva cada camión y fulgón (los triciclos se deducen por el nombre; los camiones no).
- **D. Retención del GPS**: 90 días propuestos.
- **E. Quién ve el seguimiento**: LOGISTICO, ADMINISTRADOR, SUPER ADMIN y DESARROLLADOR de la sucursal (propuesto).
- **F. Avisar a los distribuidores** de que la app registra su posición durante la ruta (la notificación fija ya lo muestra).

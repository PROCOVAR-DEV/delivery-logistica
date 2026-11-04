# Plan: la aplicación del distribuidor y el control de la distribución

**Modelo final (Jose, 04/11/2026): SIN cuentas, SIN login.** El distribuidor trabaja con un **enlace por ruta** que le manda el logístico
por WhatsApp. Este documento sustituye al plan inicial, que partía de usuarios de Accesos (ese camino se aparcó: la rama
`feat/usuarios-de-distribuidor` de Accesos ya no se usa). El estado y los porcentajes viven en `docs/roadmap-distribucion.md`; el
detalle de la app, en `docs/app-distribuidor.md`, y el de las pantallas de la oficina, en `docs/oficina-distribucion.md`.

## 1. Cómo funciona

1. El logístico arma la ruta **con vehículo** (y, si quiere, distribuidor) y pulsa **«Enviar a distribuidor»**. Reparto crea UN enlace vivo
   `https://reparto.procovar.cloud/r/<código>` y lo comparte por WhatsApp. Ya no se manda el enlace de Google Maps.
2. El distribuidor lo toca. Si tiene la app **Reparto Distribuidor**, Android la abre (App Links verificados con
   `/.well-known/assetlinks.json`). Si no la tiene, la página `/r/<código>` le dice que hay que instalarla y le da la descarga. Si el enlace
   no abre la app, en la app existe **«Agregar ruta a mano»**: pega el enlace o solo el código (la parte final del enlace).
3. La app **reclama** la ruta (`POST /api/d/reclamar`): se identifica con un id de teléfono (UUIDv7) y un secreto que da el servidor la
   primera vez. Una ruta queda en UN teléfono; un teléfono acumula las rutas de SU vehículo. El servidor devuelve la ruta, el vehículo y
   el distribuidor, y un acceso (JWT de 180 días firmado por Reparto, rol `DISTRIBUIDOR`) que se renueva con el secreto.
4. **El teléfono queda vinculado al vehículo** de la ruta (uno a uno). Otro teléfono, o otro vehículo, da 403 hasta que la oficina
   **desvincule** (Reparto > Vehículos). Al desvincular, el teléfono pierde el acceso (403 `dispositivo_desvinculado`), la app se **vacía**
   y las rutas abiertas quedan libres con su enlace revocado. **El servidor no borra nada**: rutas cerradas, puntos de GPS y los vínculos
   quedan con el id del dispositivo, para el histórico.
5. Trabaja **sin conexión**: la app trae el mapa detallado de Cuba dentro del APK (no baja nada) y sube lo que hizo cuando vuelve la red.

## 2. Lo que hace el distribuidor
- Ruta guiada: siguiente parada, qué entregar (factura, cliente, dirección, teléfono, productos y cantidades), cronómetros, varias rutas a la vez.
- Cada parada: **Entregado** (con **cobrado sí/no**, no importes) o **No entregada con motivo obligatorio**. Guarda la hora real del aparato.
- La ruta se completa sola al marcar la última; puede cancelarla solo si no hay ninguna entregada.
- Historial propio (90 días en el teléfono; lo no enviado no se borra jamás) y estado de revisión.
- **GPS solo con la ruta en curso**, con aviso de consentimiento y notificación fija; primero local, sube por lotes (un flujo para todas
  las rutas en curso). El distribuidor **nunca** ve el seguimiento.

## 3. Lo que hace la oficina (LOGISTICO, ADMINISTRADOR, SUPER ADMIN, DESARROLLADOR)
- Estado del enlace por ruta, soltar y mandar a otro teléfono.
- Recorrido real de la ruta (traza, horas, tiempo en cada parada, cobro), historial **por vehículo**, **dónde están ahora**.
- **Revisión (la segunda llave):** la logística confirma las rutas completadas por el distribuidor. Lo cerrado desde la oficina cuenta como
  revisado.
- Vínculo vehículo ↔ teléfono (ver, desvincular con motivo, historia) y vehículo ↔ distribuidor por defecto.

## 4. Seguridad en el servidor
- Lista blanca **cerrada por defecto** para el rol `DISTRIBUIDOR` (API y sync): solo sus rutas (por teléfono) y lo mínimo para trabajarlas;
  lo demás es 403 `no_es_para_el_distribuidor`. Quien lleve ese rol queda acotado aunque tenga otros.
- El alcance sale del teléfono resuelto en el servidor (vínculo vivo), nunca de lo que mande el cliente. Falla cerrado.
- El enlace es una capacidad de un solo uso por teléfono; reclamar es atómico. `renovar:true` lo revoca y da otro.
- Tracking (GPS) visible solo para los roles de oficina.

## 5. Publicación
Un solo despliegue al terminar todo (migraciones 00032 a 00035, API, sync, web, y el rol `DISTRIBUIDOR` en Accesos), con el visto bueno de
Jose. Segundo APK con `applicationId cloud.procovar.reparto.distribuidor`, mapa dentro y descarga en
`archivos.procovar.cloud/reparto/apk/reparto-distribuidor-ultimo.apk` (el alias que enlaza la página `/r/`). La prueba en teléfono real
(enlace desde WhatsApp, GPS, sin conexión, mapa) la hace Jose.

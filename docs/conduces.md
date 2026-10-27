# Conduces (super factura) — especificación

**Decisión de Jose (21 y 27/10/2026).** La unidad de Reparto es la FACTURA. Un **conduce** es lo que sale con el camión
y puede juntar varias facturas del mismo cliente en UNA parada: el logístico las junta a mano, **la primera que marca es
la PRINCIPAL** (la que crea el conduce y dice a qué cliente y a qué punto va dedicado). Es una agrupación MANUAL; el
espejo nunca junta facturas (eso se quitó el 22/10 porque ocultaba facturas canceladas).

Texto de la pestaña (literal): «Un conduce es lo que sale con el camión y puede juntar varias facturas; la primera que
marques es la que lo crea y dice a qué cliente va dedicado.»

## Modelo

- `orders.conduce_principal_id uuid NULL` (migración 00029, aditiva). **NULL** = la fila es una factura normal o es
  la PRINCIPAL de un conduce. **No NULL** = es MIEMBRO y apunta a su principal. Sin cadenas: una principal nunca es
  miembro y un miembro nunca es principal (lo vigila un `CHECK`/trigger y los endpoints). `ON DELETE SET NULL`.
  Índice parcial sobre `conduce_principal_id`.
- Una factura sigue siendo UNA FILA con su número, su folio, su estado y su resultado: **el conduce no mezcla ni
  suma datos en la principal** (el espejo reescribe cada fila desde su factura y pisaría lo acumulado). Los totales se
  suman por las filas de la ruta.
- **Un conduce es UNA PARADA**: la que representa la principal. Los miembros «van con ella».

## Reglas

1. **Crear** `POST /api/conduces` `{ "principalId": uuid, "ids": [uuid, …] }`: `ids` (≥1, sin repetir, sin la
   principal) son los miembros. Todas de la MISMA sucursal (la del alcance de quien llama; nunca de un parámetro),
   ninguna en una ruta ni con resultado ni entregada ni archivada/anulada, ninguna ya miembro ni principal de otro
   conduce (la principal SÍ puede ser ya principal: añadir miembros a un conduce existente), y **el mismo cliente**
   (mismo `customer_name` normalizado o mismo código de cliente si lo hay): no se juntan facturas de clientes distintos.
   Rechazos con motivo literal y 409/422 según corresponda (ver `docs/contratos-api.md`, «Conduces»).
2. **Deshacer** `DELETE /api/conduces/{principalId}`: todos los miembros vuelven a ser facturas sueltas
   (`conduce_principal_id = NULL`). Solo si NINGUNA (principal ni miembros) va en ruta o tiene resultado.
   `DELETE /api/conduces/{principalId}/miembros/{id}` saca UN miembro (misma condición).
3. **Visibilidad.** Los miembros NO aparecen como filas propias en: Facturas (lista y contadores), «Sin colocar»,
   «disponibles» del asistente de rutas, tablero (tarjetas), Panel, armado y colocar. Se ven como parte de su principal:
   la fila/tarjeta de la principal dice «Conduce 47313 + 47314» (números unidos, la principal primero) y su detalle
   enseña la lista de facturas del conduce. **Toda consulta de lista y su contador se atan con la misma regla** (ver
   CLAUDE.md §3-bis: una lista y su contador se atan con una prueba, no con un comentario).
4. **Armar ruta / colocar en zona / tablero**: se elige la principal; el servidor y los dos armados locales mueven
   **la principal Y todos sus miembros** (`route_id`, `ultima_ruta_id`, zona/columna según corresponda); el miembro
   no recibe `stop_order` propio (o lo hereda sin crear parada: decide el agente, pero `ListarParadasDeRuta` y el
   «n paradas» cuentan UNA por conduce). Quitar la principal de una ruta quita a los miembros. El peso, el importe y el
   domicilio de la ruta suman a TODAS las filas del conduce (los totales ya salen de las filas con `route_id`).
5. **Cierre de la ruta.** El resultado (entregado, devuelto, cancelado), la nota y la hora que se marcan sobre la
   principal se APLICAN IGUAL A SUS MIEMBROS (servidor y base local), cada fila con su propio `resultado*`. Cada
   factura miembro avisa a PEDIDO POR SEPARADO (`alcance.AvisoDeLaEntrega` ya avisa por factura: un conduce de 3
   facturas son 3 avisos). La hoja del cierre enseña UNA parada por conduce con sus facturas debajo.
6. **Pre-despacho / «Por producto y factura»**: usa los renglones de TODAS las filas del conduce (cada renglón ya
   guarda su `factura_numero`, así que sale una fila por factura sin tocar nada más).
7. **Espejo.** No cambia de identidad ni agrupa. Si una factura MIEMBRO se cancela (Ventra deja de mandarla) se saca
   del conduce y se retira como cualquier otra; si se cancela la PRINCIPAL, los miembros se liberan (quedan sueltos,
   NO se destruye nada) y el conduce desaparece. Una principal/miembro que ya va en una ruta NO completada y se
   cancela: se quita de la ruta como hoy (`AnularEntregasEnRuta`); si era la principal, sus miembros salen de la ruta
   con ella y quedan sueltos.
8. **Sin conexión (APK y escritorio).** Crear y deshacer conduce son apuntes de la cola del aparato (una forma más en
   la lista blanca del sincronizador: `POST /conduces`, `DELETE /conduces/{id}` y `DELETE /conduces/{id}/miembros/{id}`),
   con aplicación optimista en la base local. Las reglas de arriba se comprueban también en local; el servidor manda.
   Si el servidor rechaza el apunte, queda en la bandeja con su motivo literal (regla de la casa: nada se descarta en
   silencio).
9. **Bajada.** Los miembros BAJAN al aparato (con `conducePrincipalId`) para que trabaje sin conexión; el aparato los
   oculta según la regla 3. Esquema local 16 (columna nueva, creada solo si falta; rebaja una vez por aparato, como
   `folio` y `factura_numero`).

## Pantalla (app)

- **Pestaña «Conduces»** en la pantalla Facturas (junto a la lista actual, con el patrón de pestañas del proyecto):
  arriba el texto literal de arriba; debajo, los conduces existentes (principal + miembros, cliente, peso, estado) con
  «Deshacer conduce» y «Sacar» por miembro, y el botón «Crear conduce».
- **Crear**: desde la lista de Facturas se marcan varias (barra de selección existente) y «Crear conduce» las junta;
  **la primera marcada es la principal** (el orden de marcado se conserva y se dice en el cajón de confirmación: «La
  principal será 47313 (Hector Luis…). Las demás irán con ella»). Cajón, no modal; botones sin fondo con icono;
  `BotonPrincipal` para lo principal. Con facturas de clientes distintos el cajón lo dice y no deja crear.
- La fila/tarjeta de una principal enseña «Conduce 47313 + 47314» y su peso y domicilio SUMADOS (de la principal y sus
  miembros); el detalle lista las facturas y deja «Deshacer conduce» (si no van en ruta).
- Lo que ya va en ruta o está entregado no se junta ni se deshace (el botón se apaga y dice por qué).

## Lo que NO es

- No es el «conduce» de Amado de antes (el número de operación de la factura, `orders.operation_number`): ese sigue
  igual, y para una factura suelta es su número.
- No es una agrupación automática por pedido ni por cliente: solo la hace una persona.
- No se mezclan sucursales ni clientes.

## Servidor: lo que quedó decidido al implementarlo (27/10/2026)

El contrato exacto (JSON y motivos literales) está en `docs/contratos-api.md`, «Conduces». Lo que afina esta especificación:

- **Trigger, no CHECK**: `conduce_sin_cadenas` (BEFORE INSERT/UPDATE) impide cadenas y mezclar sucursales; `conduce_al_archivar`
  saca del conduce a una factura que PEDIDO archiva (y suelta a los miembros de una principal archivada).
- **El miembro no tiene parada ni `stop_order`, `segment_km` ni `price`**, pero SÍ `route_id`/`ultima_ruta_id` de la ruta de su
  principal (así los totales de la ruta los suman solos). **La parada que sirve el servidor** (`orders[]` de una ruta) es la de la
  principal con el `weight`, el `price` y el `pedidoCosto` del conduce entero, y todos los renglones. `paradas_sin_cotizar` cuenta
  paradas (un conduce está sin cotizar sólo si ninguna de sus facturas trae costo). **El aparato puede hacer lo mismo**: no hace falta
  un `stop_order` para el miembro.
- **El cierre se manda SOBRE LA PRINCIPAL**; el servidor lo aplica a los miembros y avisa por cada factura. Un `orderId` de miembro
  en la hoja del cierre se rechaza con el motivo literal de «Esa factura va dentro del conduce…» (por eso la app NO debe subir
  resultados de miembros: subirá uno por conduce; cada aparato aplica el cascadeo en su base local). `aplicados[].miembros` los nombra.
- **«El mismo cliente»**: `customerName` en minúsculas, con los espacios colapsados (`trim` + un solo espacio entre palabras);
  sin plegar tildes. La app tiene que usar EXACTAMENTE esa regla para que local y servidor coincidan.
- **Deshacer/sacar** exigen que NINGUNA fila del conduce vaya en una ruta ni tenga resultado. `DELETE /api/conduces/{x}` con una
  factura que no encabeza ningún conduce es `404`; con un miembro, `409` («deshaz ese»).
- **Crear** devuelve TODOS los miembros del conduce después (no sólo los nuevos), por número de factura. Un miembro pierde su
  tarjeta de zona del tablero al entrar en un conduce.
- **Visibilidad**: la decisión de cada consulta (excluye miembros sí/no y por qué) está atada en
  `api/internal/store/conduces_visibilidad_test.go`. Los miembros SÍ bajan en la bajada (`conducePrincipalId`).
- **Cancelaciones (regla 7)**: una cancelación que llega con la principal y un miembro en la misma tanda no rompe nada; el miembro
  sobreviviente queda suelto y fuera de la ruta.
- **Búsqueda (27/10/2026)**: `q` de Facturas encuentra un conduce por el número de CUALQUIERA de sus facturas (la fila que sale es
  la principal; lo ata `TestMotorReal_Conduces_LaBusquedaEncuentraAlConducePorUnMiembro`). `GET /api/orders` trae `conduce.facturas` para que la fila diga «Conduce 47313 + 47314».

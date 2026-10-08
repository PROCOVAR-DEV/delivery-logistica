# El tablero de preparación

**Pantalla nueva. No existe en `delivery`.** La pidió Jose el 14/09/2026 y el apunte está en
`~/Notas/Procovar/Pendiente/Delivery.md`.

Lo de abajo es lo que hay que construir, no lo que hay. Las tablas están en
`api/db/migrations/00002_tablero.sql` y las consultas en `api/db/queries/tablero.sql`.

---

## 1 · Qué es

Entre «me han llegado 180 pedidos» y «sale este camión con estas 14 paradas» hay un trabajo
que hoy se hace en la cabeza del logístico y en un papel: **agrupar por zona**.

En Santiago reparten **por distrito**. El logístico va poniendo en cada columna los pedidos
que van a esa zona, y cuando una columna está llena —o cuando ya no cabe más en el camión—
de ahí sale una ruta. Eso es todo el tablero: **columnas que él pone, tarjetas que él
arrastra.**

**Las columnas no son del sistema, son suyas.** Cada sucursal divide su territorio a su
manera: Santiago por distritos, otra por carreteras, otra por barrios de toda la vida que no
están en ningún mapa. Un catálogo fijo de zonas sería inventarse una geografía que sólo
sirve en un sitio, y la primera vez que no encajara, el logístico volvería al papel. Por eso
las columnas se crean, se renombran, se reordenan y se borran desde la pantalla.

**Y no sustituye al armador de rutas de siempre.** El armador sigue donde está y sigue
funcionando: marcar pedidos en una lista y darle a «Nueva Ruta». El tablero es el paso de
antes, el del día entero, y es opcional. Quien no lo use no pierde nada.

## 2 · Para quién

El **logístico de la sucursal**, uno por sucursal, que es quien tiene el día entero por
delante y quien conoce las calles.

**No hay tablero de todas las sucursales.** El Super Admin lo ve, pero eligiendo una: las
columnas son de una sucursal y la cercanía se mide desde el almacén de una sucursal. Un
tablero con las diez mezcladas ordenaría los pedidos de Holguín por su distancia al almacén
de Santiago. Si no hay sucursal elegida, la pantalla pide que se elija y no enseña nada —no
enseña «todo», que es lo que parecería razonable y sería lo peor.

## 3 · Qué muestra

Dos mitades, y la de la izquierda es la que importa.

```
┌────────────────────────┬──────────────────────────────────────────────────────┐
│  SIN COLOCAR (128)     │  Centro (12)   Vista Alegre (9)   Carretera (4)  [+] │
│  ──────────────────    │  ───────────   ─────────────────  ─────────────      │
│  ▸ 0,4 km  SC06…1257   │  ▸ SC06…0912   ▸ SC06…3341        ▸ SC06…7781        │
│  ▸ 0,9 km  SC06…0431   │  ▸ SC06…1102   ▸ SC06…2290        ▸ SC06…6650        │
│  ▸ 1,2 km  SC06…8890   │  ▸ …           ▸ …                ▸ …                │
│  ▸ 1,2 km  SC06…2214   │  480 kg · 62 $  310 kg · 41 $      1 210 kg ⚠ 41 $   │
│  ▸ 3,7 km  …           │  Camión: F-350  Camión: —          Camión: Ford 600  │
└────────────────────────┴──────────────────────────────────────────────────────┘
```

### La mitad izquierda — los pedidos sin colocar

**Ordenados por cercanía al almacén de su sucursal, el más cerca primero.** Es la segunda
mitad del encargo y no es un adorno:

> Es como se decide qué se reparte hoy cuando no cabe todo. Lo que está cerca sale igual,
> porque cuesta poco; lo que está lejos espera al día en que haya suficiente para ese lado.
> Por fecha —que es como sale en `/api/orders/available`— esa decisión no se puede tomar.

Cada tarjeta trae: kilómetros al almacén, número de operación, cliente, dirección de
entrega, peso, costo del domicilio (`pedido_costo`, el que puso Entrega) y municipio.

**Qué entra en «Sin colocar» — 07/10/2026 (Amado, incidencias 2 y 6).** Además de lo de
siempre (de PEDIDO, sin ruta, con punto de entrega, con domicilio), el pedido tiene que
traer **el domicilio cobrado** (`factura_domicilio > 0` en la factura) y **cotizado en
Entrega** (`pedido_costo` no nulo; un cero **sí** es un precio puesto). Sin eso la tarjeta
**ni se ofrece**, y si se intenta colocar igualmente (arrastrar, o «Mandar a una zona» desde
Pedidos) se rechaza con un mensaje claro: `No se puede asociar al tablero: la factura no
tiene un cobro de domicilio registrado.` / `No se puede asociar al tablero: primero cotiza
el domicilio del pedido.` (más `Ese pedido ya se entregó` y `Ese pedido ya está en una
ruta`). Colocar **no mira** el estado de la factura: «Sin colocar» ofrece `igual` y
`cambiado` (la `cambiado` con su marca roja desde la 1.0.29; hasta la 1.0.28 era ámbar), y la que no cuadra la descarta después
**armar la zona** (`cambió en la factura`, igual que `la factura no tiene domicilio
cobrado` y `domicilio sin cotizar`). El caso que lo motivó: sin las dos condiciones el
tablero ofrecía tarjetas que el servidor devolvía con un 409, y con los datos reales del
07/10/2026 de 1.914 pedidos repartibles sólo 29 cumplían las tres cosas (64 con domicilio
cobrado, 33 cotizados). Sin señal el aparato dice el mismo «no» **al momento** (con las
mismas palabras que el servidor) y no horas después, desde la bandeja de rechazados. El
contador y la lista tienen que decir lo mismo: lo ata una prueba (CLAUDE.md §3-bis), no
este párrafo.

Filtros de la mitad izquierda: día del pedido, búsqueda libre (la misma caja de la lista de
pedidos: cliente, operación, dirección, municipio, vendedor y el **contenido de los
renglones** — «¿qué pedidos llevan malta?»), municipio, vendedor y un corte por kilómetros.

### La mitad derecha — las columnas

Cada columna enseña su nombre, cuántos pedidos lleva, **el peso total**, el costo total de
domicilios y el camión previsto, si se eligió uno. Las tarjetas dentro van en el orden en
que el logístico las dejó, que es el orden de visita que él propone.

Los totales los da la base, no la suma de lo pintado. La pantalla pagina y el camión no: con
60 pedidos puestos, sumar lo que se ve en el móvil da el peso de los 20 primeros y el aviso
de que no cabe no aparecería nunca.

### De dónde sale la distancia

Del **almacén principal de la sucursal**, en línea recta (haversine, R = 6371 km). Es
exactamente la misma medida de `order.segment_km` y la misma con la que Entrega cobra el
domicilio; tener dos medidas distintas de «cuán lejos está este cliente» es peor que tener
una aproximada.

El almacén **vive en Accesos, no en esta base**, y no se copia: un almacén copiado se separa
del de verdad en cuanto alguien mueve unas coordenadas allá, y con esas coordenadas se mide
lo que se le cobra al cliente. Quien sirve el tablero lo resuelve igual que
`/api/quote/home-delivery`:

1. el primer almacén con `principal = true` **y** coordenadas;
2. si no hay, el primero con coordenadas, principal o no;
3. **si no hay ninguno con coordenadas, no hay tablero**: `409 «<Sucursal> no tiene ningún
   almacén con coordenadas»`. No se ordena por un punto inventado ni por las coordenadas de
   la sucursal, que no son el sitio del que sale la mercancía.

Las coordenadas resueltas se pasan a la consulta (`origen_lat`, `origen_lng`) y la base
ordena. Ordenar 1.700 filas en Go para quedarse con 200 es bajar el municipio entero por la
conexión de allá para tirar el 95%.

## 4 · Cómo se usa

| Gesto | Qué pasa |
|---|---|
| Arrastrar de «sin colocar» a una columna | El pedido queda colocado en esa columna, en la posición donde se soltó. Desaparece de la izquierda. |
| Arrastrar de una columna a otra | Cambia de columna. **Es la misma orden**: soltar una tarjeta es decir «este pedido va aquí», venga de donde venga. |
| Arrastrar dentro de la misma columna | Cambia el orden de visita propuesto. |
| Arrastrar de vuelta a la izquierda | Vuelve a «sin colocar» y la lista lo recoloca solo por cercanía. |
| «+» al final de las columnas | Crea una columna. Va al final; el nombre lo pone la persona. |
| Arrastrar la cabecera de una columna | Reordena las columnas. |
| Menú de la columna | Renombrar · elegir camión · vaciar · mover todo a otra columna · borrar · **armar la ruta**. |

**Un pedido está en una columna o en ninguna, nunca en dos.** No lo sostiene una
comprobación de la aplicación: lo sostiene la clave primaria de `board_placements`, que
**es** el pedido.

## 5 · Cómo sale una ruta de una columna

Es el mismo armado de siempre (`POST /api/routes`), con la columna como universo en vez de
una lista de casillas marcadas:

1. Se piden los pedidos de la columna **que todavía se pueden repartir**, en su orden
   (`PedidosDeColumnaParaArmarRuta`). Esa consulta **es la validación**, no una lectura
   previa a ella: si vuelven menos de los que hay puestos, alguien se los llevó entre que se
   pintó el tablero y se pulsó el botón, y de ahí sale el `409 «N de los M pedidos ya están
   en otra ruta»`.
2. Se descartan los que no cuadran con la factura, **nombrándolos**: quién falla y por qué
   («cambió en la factura» / «sin cotejar»). Una columna de doce que produce una ruta de
   nueve sin explicación es la manera más rápida de que el logístico deje de fiarse.
3. El origen es el almacén; el camión, el previsto de la columna si lo hay.
4. **El orden de visita.** El logístico ya propuso uno arrastrando, y él conoce las calles
   de su distrito; el vecino más próximo no. Por defecto **se respeta su orden** y la ruta
   nace con `optimized = false`; hay un botón de «reordenar por cercanía» que aplica el
   greedy de siempre. Lo que no puede pasar es que el orden que él puso se pierda sin que
   nadie se lo diga — por eso `posicion` viaja hasta el armador.
5. Se crea la ruta, se enganchan las paradas y **se vacían las tarjetas de esa columna**
   (`QuitarDelTableroLosDeRuta`), todo en la misma transacción. La columna se queda: el
   distrito sigue existiendo mañana. Lo que se vacía es lo que llevaba dentro hoy.
6. Lo de siempre a partir de ahí: aviso de cambio `rutas`, y `despachado` a PEDIDO de fondo.

Si la columna se queda sin ningún pedido repartible, no se crea una ruta vacía: `409` con la
lista de por qué se cayó cada uno.

**Armar sin señal (APK/escritorio), desde la 1.0.29: la misma regla que el servidor.** Hasta
la 1.0.28 el aparato armaba con todo lo que no llevara una marca grave, y el servidor
descartaba después lo que el aparato ya había subido al camión (domicilio sin cobrar, sin
cotizar y `cambiado`). Ahora la tarjeta entra sólo si es `igual`, con `factura_domicilio > 0`
y `pedido_costo` no nulo (y no entregada); lo demás se **descarta y se nombra** por su
conduce (el número de operación de la factura) con el mismo motivo que daría el servidor:
`Archivado en PEDIDO`, `Ya va en otra ruta`, `Sin cotejar`, `Sin factura`, `Cambió en la
factura` (las cinco son las marcas de la tarjeta, con mayúscula inicial), `ya se entregó`,
`la factura no tiene domicilio cobrado`, `domicilio sin cotizar` (las dos últimas, idénticas a
`docs/armado-rechazado.casos.json`), por ese orden de prioridad (`TarjetaPedido.motivoDeNoSubir`).
**Si ninguna cumple, no se arma la ruta** (`La columna no tiene ningún pedido que se pueda
repartir hoy` y debajo la lista). Si algunas sí y otras no, la ruta se arma con las buenas, las
descartadas se quedan puestas en la zona y marcadas, y una franja roja de 6 s —en la web,
la APK y el escritorio— dice `Ruta armada de «<zona>», pero <n> pedidos no entraron:` y una
línea `<conduce> · <cliente>: <motivo>` por cada una. En la web se le suman las que cuente
el servidor en `descartados`, sin repetir las que el aparato ya nombró.

**Reasignar un devuelto es un intento nuevo (1.0.29).** Un pedido devuelto o cancelado que se
engancha a otra ruta entra **sin el resultado anterior**: el aparato deja a `NULL` `resultado`,
`resultado_at`, `resultado_nota` y `delivered_at` (el servidor hace lo mismo al engancharlo,
`EngancharPedidoARuta`); `ultima_ruta_id` se conserva, porque dice en qué camión viajó. Un
entregado nunca llega ahí: se descarta con `ya se entregó`.

### 5-bis · La lista de pedidos del cuerpo (18/09/2026)

El cuerpo acepta, **opcionalmente**, `pedidoIds` (o `orderIds`, se admiten los dos nombres):
los pedidos que el aparato decidió que iban en esa ruta.

**Por qué.** Una ruta armada sin señal sube horas después. Sin esa lista, el servidor la
arma con *lo que él tenga puesto en esa zona en el instante en que le llega el apunte*, que
para entonces puede ser otra cosa —la web siguió moviendo tarjetas—. Y entonces: la ruta
nace sin un pedido que el repartidor ya entregó, el resultado de esa parada se rechaza al
cerrar, y el pedido se queda suelto en el tablero para que la web lo meta en **otro camión**.

**Cómo se comporta:**

- **Si no viene** (las APK instaladas antes del 28/09/2026 no la mandan): todo igual que
  antes, se arma con lo que haya puesto. El campo no puede volverse obligatorio sin dejar sin
  armar rutas a los aparatos que ya están en la calle.
- **Si viene**: la ruta lleva **exactamente** lo que el aparato eligió y que todavía puede
  ir, y la respuesta **dice la diferencia** en `descartados`:
  - lo que él eligió y ya no está en la zona → `motivo:"ya no estaba en esa zona cuando
    llegó tu apunte"`. **Es el que su repartidor puede llevar entregado**, así que el
    `queHacer` avisa de mirarlo antes de que salga en otra ruta;
  - lo que hay ahora en la zona y él no eligió → `motivo:"lo pusieron en la zona después de
    que armaras"`. No sube a ese camión y la tarjeta se queda puesta.
- **La lista sólo QUITA, nunca añade**: un id de otra sucursal, o de un pedido que ya va en
  otra ruta, no entra por venir escrito en el cuerpo. El universo sigue siendo la columna.
- **`"pedidoIds": []` es un `400`**, no «arma con todo»: una lista vacía es un cuerpo mal
  formado, y armar entonces con lo que haya es justo el fallo que esto viene a tapar.

**Y quién la manda (28/09/2026).** Esto estuvo escrito y sin usar diez días: la aplicación
encolaba sólo `{nombre, vehiculoId, optimizar, deliveryDate}`, con un comentario al lado
diciendo que la lista sí viajaba. Desde hoy la manda `RepositorioTablero.armarRuta`, **por
los dos caminos** —el POST en vivo de la web y el apunte que encola la APK, que comparten
cuerpo—, en el orden que puso el logístico. Lo ata
`app/test/pantallas/tablero/armar_ruta_test.dart` comparando el cuerpo entero.

### 5-ter · Los `descartados` llegan hasta una persona (28/09/2026)

Que el servidor lo diga no basta: hasta hoy nadie lo leía, y por eso lo de arriba pudo estar
diez días sin usarse sin que saltara nada. El camino entero, de punta a punta:

1. `reparto-api` los escribe en el `201` de armar la zona (`DescartadoSalida`);
2. el sincronizador los **reenvía tal cual** dentro del resultado de ese apunte
   (`sync/internal/sincro/subida.go`, `resultado.descartados`, con `omitempty`);
3. la cola del aparato los guarda en el `motivo` del apunte **aplicado** —no rechazado: el
   apunte entró, y ofrecer «reintentar» ahí armaría una segunda ruta—
   (`ColaDeSalida.resolver`);
4. la franja de estado lo dice en ámbar en las siete pantallas, y el cajón de entregar el
   día lo cuenta entero: el pedido con su folio y su cliente, el motivo y qué hacer.

Se queda a la vista hasta que una persona lo da por leído, y **la poda de los siete días no
se lo lleva** mientras siga sin leer. Sale sólo cuando de verdad se cayó alguien: un aviso
que sale en cada armado deja de leerse.

## 6 · Sin conexión

El tablero es **lo que más sentido tiene sin red** de toda la aplicación: preparar es mover
cosas de sitio, y es justo lo que el logístico hace durante el día, que es cuando no tiene
señal. No hay «modo sin conexión» que encender: se guarda en el aparato y se sube por
detrás, igual que el resto (`sincronizacion.md`).

**Se ve y se hace igual que con red:**

- las columnas, las tarjetas puestas y su orden;
- los pedidos sin colocar **ordenados por cercanía** — el aparato repite la misma fórmula
  con el almacén que bajó por la mañana (`warehouses` viene en la bajada); no depende de
  preguntarle a nadie;
- el peso por columna y el aviso de que no cabe en el camión;
- crear, renombrar, reordenar y borrar columnas;
- **armar la ruta** de una columna, con identificador provisional (`local-…`), imprimir el
  despacho y cerrarla por la tarde.

**No se ve, y hay que decirlo en la pantalla:**

- que **otra persona** se haya llevado un pedido a otra ruta (el Super Admin, o el armador
  de siempre desde otro aparato);
- el cotejo de factura nuevo: un pedido que se facturó hace una hora sigue enseñándose como
  estaba esta mañana;
- que PEDIDO haya archivado un pedido desde entonces;
- pedidos **nuevos**: la mitad izquierda es la foto de la última bajada.

Por eso arriba va la hora de la última bajada, con todas las letras: «visto por última vez a
las 9:14». Un tablero que parece vivo y lleva seis horas congelado es peor que uno que
avisa.

**Los rechazos llegan tarde y no se pierden.** Colocar un pedido que ya se llevó otra ruta
se rechaza al subir, no al arrastrar, y ese rechazo queda a la vista con su motivo y su hora
hasta que una persona decida. No se reintenta y no se borra solo.

**Los conflictos casi no existen** por lo mismo que en el resto: un logístico por sucursal,
y las columnas son de la sucursal. La excepción sigue siendo el Super Admin.

## 7 · Los casos que duelen

### 7.1 · Dos pedidos del mismo cliente

**Son dos tarjetas y se quedan dos tarjetas.** No se agrupan, no se funden, no se avisa de
nada.

Ya se decidió en otro sitio de la casa y aquí vale igual: **el sufijo del folio es nuestro**
— X-2992 y X-2992-2 son dos pedidos distintos, con sus renglones, su peso y su costo de
domicilio cada uno. Juntarlos porque coincide el cliente es repetir el error de julio: dos
facturas, un solo bulto cargado.

Lo que sí hace la pantalla es **ponerlas juntas**: al ordenar por cercanía caen seguidas
(mismos kilómetros) y la tarjeta marca discretamente «2 pedidos de este cliente hoy», para
que el logístico los meta en la misma columna a propósito y no por casualidad. El desempate
del orden es la fecha y luego el id, para que no bailen entre dos llamadas mientras se está
arrastrando.

### 7.2 · Un pedido se factura mientras está colocado

Pasa a diario: se coloca a las nueve y a las once PEDIDO lo coteja contra Ventra.

**La tarjeta se queda donde está y se marca. Nunca se quita sola.** Quitar una tarjeta que
dejó de servir es hacer desaparecer el trabajo de alguien sin decírselo: el logístico
volvería a la columna, vería once paradas donde puso doce y no tendría manera de saber cuál
falta ni por qué. Por eso `ListarPedidosColocados` **no lleva** las condiciones de
«repartible» en su `WHERE` y devuelve `factura_estado`, `archivado`, `route_id` y
`resultado` crudos: la tarjeta se marca, no se esconde.

Los cuatro desenlaces:

| Quedó en | Qué significa | Qué hace el tablero |
|---|---|---|
| `igual` | cuadra | nada, es lo normal |
| `cambiado` | se facturó distinto de como se pidió | **se marca** en rojo (1.0.29; hasta la 1.0.28, ámbar) y se queda en la columna, pero **ya no sube a la ruta** (07/10/2026: «en el camión sólo sube lo que cuadra con la factura»). Al armar la zona sale en `descartados` con `cambió en la factura`. Antes se repartía con las líneas de la factura y se avisaba de que el peso ya no era el mismo |
| `sin_factura` | no hay nada que llevar | se marca en rojo: hoy no sale |
| `NULL` | **no se sabe** | se marca en rojo. No es «cuadra». Con un NULL colado se armó una ruta sin facturar el 2/09 |

El contador de arriba los cuenta por separado (`AvisosDelTablero`) porque se arreglan de
maneras distintas, y un número único obligaría a abrir las doce columnas para saber cuál de
las tres es.

### 7.3 · Una columna con más peso del que cabe en el camión

**Se avisa, no se impide.**

La columna enseña su peso y, si tiene camión previsto, se pinta el aviso cuando lo pasa
(`excede_camion`). Sin camión previsto el aviso es **NULL, que no es `false`**: significa
que todavía no se sabe, y pintar «cabe» cuando nadie ha dicho en qué va es peor que no
pintar nada.

No se impide por tres razones, en este orden:

1. **El tablero es un borrador.** Se pasa de peso durante media mañana y luego se parte en
   dos columnas; una pantalla que no deja soltar la tarjeta número trece obliga a preparar
   el día en el orden que le conviene a la aplicación.
2. **El camión previsto es una intención.** A media mañana no se sabe cuál va a ir; el
   camión de verdad se elige al armar la ruta.
3. **La capacidad ya se comprueba donde importa**, al armar, y allí sigue avisando igual.

La salida natural es «partir la columna»: se crea «Vista Alegre 2» y se arrastra lo que
sobra. Por eso mover en bloque de una columna a otra (`MoverPedidosDeColumna`) existe y
respeta el orden relativo.

**Qué camiones ofrece «Camión previsto» (1.0.29).** Los **activos**. El que está en el taller
(`maintenance`) **sale, con `EN EL TALLER` en ámbar y un icono de llave, y se puede elegir**:
aviso, no bloqueo (decisión de Jose del 28/09/2026; la 1.0.28 lo había quitado por error y
se restauró, porque una sucursal con un solo camión olvidado en el taller se quedaría sin
poder armar ni una zona). El **inactivo** no se ofrece nunca. Sin ninguno activo:
`Esta sucursal no tiene vehículos activos en este aparato.`

### 7.4 · Al día siguiente, con lo que quedó sin repartir

**No se borra nada por la noche. Lo que quedó puesto, puesto sigue.**

No hay barrido nocturno y no lo va a haber: el tablero vive en un aparato que a las nueve de
la noche está apagado y sin señal, así que no hay quien lo dispare. Y aunque lo hubiera,
vaciar el tablero de madrugada es tirar el trabajo de ayer — el logístico que dejó tres
columnas preparadas para primera hora se las encuentra vacías.

Cómo se vacía entonces: **solo, a medida que salen las rutas.** Cada ruta armada se lleva
sus tarjetas. Lo que queda en las columnas al final del día es exactamente lo que no salió,
y eso es lo primero que hay que ver a la mañana siguiente.

Lo que sí cambia por la mañana es la mitad izquierda, que trae los pedidos nuevos de la
bajada, ya ordenados por cercanía entre los de ayer.

**El caso del devuelto.** Un pedido que volvió en el camión suelta su `route_id` al cerrar
la ruta y reaparece en «sin colocar» —**no vuelve a su columna**: su tarjeta se fue cuando
salió la ruta—. Es lo correcto: volvió por algo (el cliente no estaba, la dirección no era),
y darlo por bueno en la zona de ayer es repetir el viaje. Vuelve a la izquierda, con sus
kilómetros, y el logístico decide.

### 7.5 · El pedido desaparece del servidor estando colocado

Se archivó en PEDIDO (borrado blando) y la bajada lo trae en `quitados`.

Hay que distinguir dos cosas que no son lo mismo:

- **Archivado (`archivado = true`), que es lo que pasa casi siempre.** La fila del pedido
  sigue en esta base; lo único que cambia es la marca. **La tarjeta se queda y se marca**
  «archivado en PEDIDO», igual que en 7.2, y se cuenta en el aviso de arriba. El logístico
  la quita él, cuando la ve. No hace falta ningún mecanismo nuevo.

- **La fila se borra de verdad** (`quitados` del espejo, una limpieza del histórico, un
  `DELETE`). Aquí la colocación **no puede sobrevivir**: una tarjeta apuntando a un pedido
  que no existe es una parada fantasma que la ruta cargaría sin renglones. Por eso
  `board_placements.order_id` tiene `ON DELETE CASCADE` — y es la única cascada del tablero.

  Pero la cascada es silenciosa, y eso es lo que hay que tapar en la pantalla: el aparato ya
  sabe **qué** desapareció, porque la bajada se lo dijo por su nombre en `quitados`. Con esa
  lista se avisa: «2 pedidos que tenías puestos ya no están en PEDIDO: SC06…1257 (Centro),
  SC06…0431 (Carretera)», con el número de operación y la columna de la que salieron. Se
  avisa **una vez**, con lo que se sabía de ellos antes de que se fueran.

  La regla es la misma de todo el proyecto: la base impide que quede basura; la pantalla
  impide que el trabajo desaparezca en silencio.

### 7.6 · Borrar una columna que tiene pedidos dentro

**La base se niega.** `board_placements.column_id` es `ON DELETE RESTRICT`, no cascade.

Con cascade, las tarjetas volverían a «sin colocar» sin decir nada, y quien borró «Centro»
creyendo que estaba vacía se entera al día siguiente, cuando a la ruta le faltan ocho
paradas. Con RESTRICT, el contrato está obligado a preguntar qué se hace con lo de dentro:

```
DELETE /api/board/columns/<id>            → 409 {"error":"«Centro» tiene 8 pedidos puestos",
                                                  "pedidos": 8}
DELETE /api/board/columns/<id>?vaciar=1   → las tarjetas vuelven a «sin colocar», y se borra
DELETE /api/board/columns/<id>?destino=<id> → las tarjetas se van a la otra columna, detrás
                                              de lo que ya haya y en su orden, y se borra
```

Se pregunta con `ContarPedidosEnColumna` para poder decir «tiene 8 pedidos puestos» en vez
de devolverle a la persona el error de clave ajena de Postgres, que no entiende nadie.

### 7.6-bis · Borrar la ruta que salió de una columna — 07/10/2026 (Amado, incidencia 3)

Antes, borrar una ruta hecha con «Armar la ruta de esta zona» soltaba los pedidos y **el
tablero quedaba limpio**: la relación factura–columna se perdía y había que volver a
crear y repartir todo. Ahora **cada factura vuelve a su columna y a su posición**: al armar
la zona el servidor guarda de dónde salió cada parada (`board_route_origins`) y al borrar
la ruta —o al quitar **una sola parada** de una ruta planificada con «Quitar de ruta»— las
devuelve. Si la columna ya no existe, el pedido queda en «sin colocar». Una ruta armada a
mano no restaura nada, y una **completada** es histórico y no se borra.

**El límite sin señal (APK/escritorio).** Ese origen vive en el servidor y la bajada no lo
trae, así que el aparato **no sabe de qué columna salió** cada factura. Mientras el borrado
no ha subido (o ha subido y el tablero no ha bajado), esas facturas salen en **«Sin
colocar»** y no en su columna; la pregunta de borrado lo dice («Mientras tanto, sin señal,
salen en «Sin colocar»») y no nombra ninguna zona que no tiene. En la web el borrado es
inmediato y el tablero ya las enseña en su columna. Cuando suba el borrado y baje el
tablero, cada una aparece donde estaba. Quitar de ruta, borrar ruta y el tablero se avisan
en vivo (`rutas`, `pedidos`, `tablero`).

### 7.7 · Dos aparatos sobre el mismo tablero

Con un logístico por sucursal no pasa. Cuando pasa —el Super Admin, o el logístico con el
móvil y el portátil a la vez— el criterio es **el último que llega manda para la colocación**
(`ON CONFLICT (order_id) DO UPDATE`: soltar la tarjeta es decir dónde va, y la última palabra
es la última) **y la base manda para lo que ya no se puede deshacer**: si el pedido se subió
a una ruta, `route_id IS NULL` falla y la colocación se rechaza con su motivo.

Lo que no se hace es arbitrar entre dos posiciones dentro de una columna. Es un orden
propuesto por una persona: que gane el último no le cuesta nada a nadie.

---

## 8 · Los contratos

Todos con **auth de usuario** (`401 {"error":"Unauthorized"}`) y **alcance por sucursal**,
que aquí es seguridad y va dentro del SQL. `branchId` es **obligatorio** en las lecturas: el
alcance manda y `branchId` estrecha, nunca amplía.

| Ruta | Qué hace |
|---|---|
| `GET /api/board` | El tablero entero: columnas con totales, tarjetas puestas, avisos, y la primera página de sin colocar. **Una sola ida y vuelta**, porque la conexión de allá no da para cinco |
| `GET /api/board/unplaced` | Sólo la mitad izquierda, para paginar y filtrar sin recargar el resto |
| `POST /api/board/columns` | Crea una columna. Va al final; la posición la calcula la base |
| `PATCH /api/board/columns/[id]` | Renombrar y elegir camión |
| `PUT /api/board/columns/orden` | Reordena el tablero: llega la lista de ids en el orden nuevo, **una sola sentencia** |
| `DELETE /api/board/columns/[id]` | Con `?vaciar=1` o `?destino=<id>`; sin ninguno y con pedidos dentro, `409` (§7.6) |
| `PUT /api/board/placements/[pedidoId]` | Colocar o mover: `{columnaId, posicion}` |
| `DELETE /api/board/placements/[pedidoId]` | Devolver a «sin colocar» |
| `POST /api/board/columns/[id]/route` | Armar la ruta de la columna (§5) |

`GET /api/board` devuelve además el almacén que se usó de origen y la hora de la bajada, que
es lo que la pantalla necesita para poder decir desde dónde está midiendo.

Errores propios, literales:

| Situación | Respuesta |
|---|---|
| La sucursal no tiene almacén con coordenadas | `409 {"error":"<Sucursal> no tiene ningún almacén con coordenadas"}` |
| Columna con pedidos y sin decir qué hacer | `409 {"error":"«<nombre>» tiene N pedidos puestos","pedidos":N}` |
| Colocar un pedido que ya va en una ruta | `409 {"error":"Ese pedido ya está en una ruta"}` |
| Colocar un pedido que YA SE ENTREGÓ | `409 {"error":"Ese pedido ya se entregó"}` — se mira ANTES que la ruta: un entregado conserva su `route_id`, y decir «ya está en una ruta» manda a esperar a que se cierre un camión que puede que ya no exista |
| Armar la zona con una tarjeta ya entregada | `201`, y la tarjeta sale en `descartados` con `motivo:"ya se entregó"`. No bloquea la zona |
| Colocar un pedido de otra sucursal | `404 {"error":"Ese pedido no existe o no es de tu sucursal"}` — se contesta lo MISMO que si no existiera: decir «existe pero no es tuyo» ya es contar algo de otra sucursal |
| Tocar una zona que ya no está —o con un id que no es un uuid— | `404 {"error":"Esa zona del tablero ya no existe"}` |
| Pedir el tablero de una sucursal que no es tuya | `404 {"error":"Esa sucursal no existe o no es tuya"}` |
| Armar una columna sin nada repartible | `409` con la lista de por qué se cayó cada uno |
| Dos columnas con el mismo nombre | `409 {"error":"Ya hay una columna «<nombre>» en este tablero"}` |

## 9 · Lo que toca fuera del tablero

- **La sincronización** gana dos conjuntos en `cambios`: `boardColumns` y `boardPlacements`,
  con sus `puestos` y sus `quitados`, igual que los demás. Las dos tablas llevan `updated_at`
  con trigger desde el primer día, que es lo que hace posible la bajada por diferencias.
- **Los apuntes de la cola** son los de la tabla de arriba. Una columna creada sin conexión
  usa identificador provisional (`local-…`) y el aparato tiene que **sustituirlo en todo lo
  que quedara en la cola detrás** — si no, las doce colocaciones que van después irían a una
  columna que no existe en ningún sitio, y se perderían justo después de haberse subido.
- **El armador de siempre no cambia.** Un pedido colocado en el tablero sigue saliendo en
  `/api/orders/available`: el tablero es un plan, no una reserva. Si el armador de siempre se
  lo lleva, la tarjeta se queda marcada «en otra ruta» (§7.2) hasta que alguien la quite.
- **Nada de `board_*` se le cuenta a PEDIDO.** Preparar no es un estado del pedido: es
  trabajo interno del reparto. El primer aviso a PEDIDO sigue siendo `despachado`, al armar
  la ruta.

## 10 · Lo que queda por decidir

- **Si el orden del logístico gana al greedy por defecto.** Aquí se propone que sí (§5), y
  se pregunta antes de escribir el armador.
- **Sugerir columna.** Con el municipio y los kilómetros se podría proponer dónde cae cada
  pedido nuevo. **No en la primera versión**: primero hay que ver qué columnas se inventa la
  gente de verdad. Una sugerencia que falla la mitad de las veces es peor que ninguna,
  porque hay que deshacerla.
- **Si un pedido `cambiado` debería avisar más fuerte** que un marcador en la tarjeta, ahora
  que se sabe que el peso de la columna deja de ser el que era.

---

> **Comprobado**: el esquema de `00002_tablero.sql` y las 19 consultas de `tablero.sql` pasan
> por el analizador de Postgres de sqlc (`sqlc compile`), que resuelve cada tabla, cada
> columna y cada función contra el catálogo de las dos migraciones. `sqlc generate` escribe
> `internal/store/sqlc/tablero.sql.go` y `go build ./internal/store/...` y `go vet` pasan
> limpios sobre lo generado.
>
> **Lo que eso NO comprueba** es que el servidor acepte la migración al aplicarla de verdad
> —las restricciones diferidas y el `ON DELETE RESTRICT` no se ejercitan hasta que hay
> filas—. Falta correrla contra un Postgres:
>
> ```
> docker run --rm -d --name pg -e POSTGRES_PASSWORD=x -e POSTGRES_DB=reparto postgres:16-alpine
> docker exec -i pg psql -U postgres -d reparto -v ON_ERROR_STOP=1 < api/db/migrations/00001_init.sql
> docker exec -i pg psql -U postgres -d reparto -v ON_ERROR_STOP=1 < api/db/migrations/00002_tablero.sql
> ```
>
> En este equipo sigue sin poderse: el demonio de docker no acepta a este usuario
> (`permission denied ... /var/run/docker.sock`), igual que el 14/09 con `00001`.

## 10 · Por qué estos «no está» van en español

Hasta el 29/09/2026 las catorce puertas del tablero contestaban `httpx.MsgNotFound`, o sea
literalmente **«Not found»**. Y son justo las puertas por las que sube un apunte armado sin
señal: el sincronizador reenvía el cuerpo del 4xx tal cual (`sync/internal/reparto/
reparto.go`, `motivoDe`), así que ese texto viajaba entero hasta la bandeja del teléfono de
quien reparte — en inglés, sin decir qué era lo que no estaba y sin decir qué hacer.

La constante de `httpx` **no se tocó**: está inventariada como literal del contrato de
`/api/vehicles/[id]` y cambiarla rompe a quien la compara. Lo que cambió es lo que dicen
estas puertas, que son las que lee una persona.

Lo que más dice de esto: al cambiarlo **no falló ni una prueba de las que había**. Nadie
vigilaba el texto que lee quien reparte. Ahora sí, en
`api/internal/api/los_no_esta_se_leen_en_espanol_test.go`, que comprueba además que una
zona de otra sucursal conteste **exactamente lo mismo** que una que no existe.

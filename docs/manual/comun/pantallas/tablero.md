# Tablero

**Para qué sirve:** es donde se arma el día. A la izquierda todos los pedidos que
hay por repartir; a la derecha las zonas del territorio. Se reparten los pedidos
por zonas, y de cada zona sale una ruta.

**Así arma Jose el día: por zonas, y la ruta sale de una zona entera con su
camión.** Es el camino principal.

**Recuerda:** el tablero es **de una sucursal**. Hace falta elegir una; no hay
tablero de «todas».

---

## Las dos mitades

- **Izquierda: «Sin colocar (308)»** — los pedidos que todavía no están en ninguna
  zona. El número cuenta **pedidos**. Sólo salen los que tienen **el domicilio cobrado
  en la factura** y, si el vendedor lo marcó, **ya cotizado en Entrega** (ver
  [Qué se puede colocar](#qué-se-puede-colocar-en-una-zona)).
- **Derecha: las zonas** — «Centro», «Vista Alegre», «Carretera»… Las pones tú,
  con los nombres que se usen en tu sucursal.

En pantalla grande (a partir de 900 px de ancho) se ven las dos a la vez. En el
teléfono se ve una página cada vez y se pasa deslizando: primero «Sin colocar»,
después una página por zona, y al final «Nueva columna».

---

## La barra de arriba del tablero

- **La sucursal y desde qué almacén se mide**: «Granma · desde Bayamo (Granma)».
  Si hay más de un almacén, se toca y se elige. Elegir uno que **no** es el de por
  defecto pone **primero** sus pedidos en «Sin colocar» (ver «El orden de la lista»).
- **De cuándo es la copia** (sólo APK y escritorio): «Visto por última vez a las
  10:41».
- **Los contadores de avisos**, que cuentan **pedidos ya colocados** en alguna
  zona y sólo salen si hay alguno:
  - «3 archivados en PEDIDO» (rojo)
  - «2 ya en otra ruta» (rojo)
  - «5 sin factura o sin cotejar» (rojo)
  - «1 cambiaron en la factura» (ámbar: es un aviso, esos pedidos sí salen con lo
    facturado)
- **El botón de refrescar**, con el rótulo **«Traer lo del servidor»**.

### El tablero se niega a refrescar si tienes algo sin subir

Y lo dice:

> «No se actualiza: hay 1 cambio sin subir. Se sube primero y después se trae —
> así no se pierde nada.»

No es un fallo. Es para que lo de allá no pise lo que hiciste aquí. Sube primero.

---

## Buscar y filtrar la mitad izquierda

- **El buscador** dice «Cliente, operación, factura, dirección, artículo…» y **filtra al
  escribir**, sin darle a Intro.
- **El embudo** abre los filtros:
  - **«Día del pedido»**
  - **«Municipio»** (por defecto «Todos»)
  - **«Vendedor»** (por defecto «Todos»)
  - **«Hasta cuántos km del almacén»** (por defecto «Sin tope»). Se aplica al
    salir del campo o con Intro.
  - **«Cobro del domicilio»**: «Todos» · «Con cobro» · «Sin cobro»
  - **«Quitar todos los filtros»**

Cuando hay filtros puestos, el embudo lleva un punto.

### El orden de la lista

**De la factura más vieja a la más reciente.** Lo primero que ves es lo que lleva más
tiempo esperando. Un pedido que no tiene fecha de ningún tipo va al final. Es el orden
cuando arriba está el almacén de por defecto (el principal), que es como abre el tablero.

**Con otro almacén elegido arriba, primero los suyos.** Si tocas la cabecera y eliges,
por ejemplo, «AURORA», la lista enseña **todos** los pedidos igual, pero **primero los que
salen de AURORA, del más cercano al más lejano** (los mismos kilómetros de la tarjeta), y
**después todos los demás** de la factura más vieja a la más reciente. Así se prepara la
zona de ese almacén sin buscar entre los de los otros.

- **Qué pedidos son «de ese almacén»**: los que PEDIDO manda con ese almacén de salida.
  Un pedido que sale de dos almacenes va con el que pone más artículos.
- **Para volver al orden de siempre**, se vuelve a elegir arriba el almacén de por defecto.
- Si el almacén elegido **no tiene código en Accesos**, no se sabe qué pedidos salen de
  él: se miden los kilómetros desde él, pero la lista se queda en el orden de siempre.
- El número de «Sin colocar» no cambia: el orden no esconde a nadie.

### La lista sale acotada a 200

Si hay más, lo dice: **«Se ven 200 de 308.»** y al lado el botón **«Ver 108 más»**,
que sube el tope de 200 en 200. Lo que queda fuera son las facturas más recientes (con
un almacén elegido, las más recientes de los otros almacenes).

---

## Qué se ve en cada tarjeta de pedido

De arriba abajo:

1. **Los kilómetros al almacén** si está sin colocar («0,4 km»), o **su número de
   orden** si ya está en una zona («3.»). A la derecha, el número de operación.
   Si el pedido no tiene coordenadas, en vez de los km pone **«sin ubicar»**.
2. **El número de factura**, que es el título de la tarjeta, lo más grande:
   `Factura 1024237`. Es el de la factura de Ventra y **no es el número de
   operación** de la derecha. Si son varias, van todas (`Factura 47061, 47062`) y
   saltan de línea si no caben. Si el pedido todavía no tiene número de factura, en
   su sitio pone **«Sin número de factura»**, en gris.
3. **El cliente**, debajo, en negrita y del tamaño de la dirección.
4. **La dirección.**
5. **Una línea de datos** separada por puntos: peso, costo del domicilio,
   municipio, y los km si ya está colocada. Por ejemplo:
   `12 kg · 0,04 USD · Songo-La Maya · 3,7 km`
   Si el pedido no tiene costo, en su sitio no sale nada.
6. **Las marcas**, si las tiene: «Archivado en PEDIDO», «Ya va en otra ruta»,
   «Sin cotejar» y «Sin factura» (las cuatro en rojo), y «Cambió en la factura» (en
   ámbar). Ver [Las reglas del reparto](../las-reglas-del-reparto.md). **Las cuatro
   rojas no entran en la ruta**. La ámbar sí: sólo avisa de que al camión va lo
   facturado y no lo que se pidió.
7. **Si el cliente repite hoy**: «2 pedidos de este cliente hoy». **Las tarjetas
   no se juntan**: sólo se avisa, para que los metas en la misma zona a propósito.

---

## Qué se ve en la cabecera de cada zona

```
Vista Alegre (9)                           ⋮
1.210 kg / 1.000 kg · 41,00 USD      (!) no cabe
Camión: F-350                          sin subir
desde PV-STGO
```

- **«Vista Alegre (9)»** — el nombre y cuántos pedidos lleva.
- **«1.210 kg / 1.000 kg»** — lo que pesa la zona **y la capacidad del camión**
  previsto. Sin camión sólo sale el peso.
- **«41,00 USD»** — lo que suman los domicilios de esa zona.
- **«no cabe»** en ámbar cuando el peso pasa de la capacidad del camión. **Es un
  aviso, no un bloqueo**: la ruta se puede armar igual.
- **«Camión: F-350»** o **«Camión: —»**.
- **«sin subir»** o **«rechazada»** en ámbar, cuando esa zona tiene trabajo que no
  ha llegado al servidor.
- **«desde PV-STGO»** — el almacén del que sale la ruta de esa zona (su **punto de
  salida**) y desde el que se miden los km de sus pedidos. Si el punto elegido ya no
  sirve, en su lugar sale el motivo en ámbar, por ejemplo «AURORA está dado de baja en
  Accesos».

**Las zonas van agrupadas por su punto de salida**: primero las que salen del almacén
principal y después, almacén por almacén, las demás. En pantalla grande hay un hueco de
más entre un grupo y el siguiente. Dentro de cada grupo, el orden de siempre.

---

## Cómo se mueve un pedido a una zona

**En pantalla grande hay dos maneras:**

1. **Arrastrar la tarjeta.** Con ratón, se arrastra del tirón. Con el dedo, hay
   que **mantener pulsado medio segundo** antes de levantarla.
   - Soltarla **sobre otra tarjeta** la pone en ese sitio del orden.
   - Soltarla en el hueco de abajo o **sobre la cabecera** la pone la última.
   - Soltarla en la mitad izquierda la devuelve a «sin colocar».
   - Soltarla donde ya estaba **no hace nada**.
2. **Tocar la tarjeta** y elegir la zona en el cajón que se abre.

**En el teléfono no se arrastra.** Sólo se toca la tarjeta. Es a propósito: las
dos mitades no caben a la vez y el arrastre se comía el desplazamiento de la
lista.

### El cajón de mover una tarjeta

Al tocar una tarjeta se abre con:

- El detalle del pedido: dirección, municipio, teléfono, vendedor, **la factura y
  cuándo se facturó** (`Factura 1024237 · facturada el 12/10/2026`, o «Sin número de
  factura»), y la línea de peso, km y costo: `12,5 kg · 3,7 km · $0.04`.
- Los artículos (hasta cuatro, y luego «y 3 artículo(s) más»), con las cantidades
  **en empaques primero**: `MALTA GUAJIRA 330 ML BLISTER 6U · 20 empaques · 120 uds`. El
  empaque (el blíster, la caja, la paca) es como se carga y se transporta; las unidades
  van detrás y solo salen cuando se pueden afirmar.
- Las marcas del pedido, si las tiene.
- Si ya está colocada: **«Subir una posición»**, **«Bajar una posición»** y
  **«Devolver a sin colocar»**.
- La lista de zonas: **«Colocar en «Centro»»**, con «12 pedidos · 480 kg» debajo.

Si todavía no hay zonas:

> «Todavía no hay ninguna columna. Créala con el «+» del tablero y ponle el nombre
> de la zona.»

---

## Qué se puede colocar en una zona

A una zona sólo se coloca una factura **con el domicilio cobrado** (y **cotizado**, si
el vendedor marcó domicilio). Son las mismas condiciones de la lista de disponibles de
Rutas, y se piden por una razón: el domicilio es un servicio que se cobra, y una zona
entera no se debe preparar con facturas que luego la ruta no va a aceptar.

1. **Domicilio cobrado**: la factura trae un importe de domicilio **mayor que cero**.
   Es lo que dice que el pedido va a domicilio, aunque el vendedor no marcara la
   casilla.
2. **Domicilio cotizado, si el vendedor lo marcó**: Entrega ya le puso el costo. Si no
   lo marcó, no se pide: Entrega sólo cotiza los marcados.
3. **Que no se haya entregado ya ni vaya en otra ruta.**

Lo que no cumple **no sale en «Sin colocar»**. Y si se intenta colocar igualmente
—arrastrándolo, o desde «Mandar a una zona» en Pedidos—, **se rechaza con un mensaje
claro** y la tarjeta se queda donde estaba:

| Mensaje | Qué pasa |
|---|---|
| «No se puede asociar al tablero: la factura no tiene un cobro de domicilio registrado.» | La factura no cobró domicilio |
| «No se puede asociar al tablero: primero cotiza el domicilio del pedido.» | El vendedor marcó domicilio y Entrega todavía no le puso costo |
| «Ese pedido ya se entregó» | Ya se repartió |
| «Ese pedido ya está en una ruta» | Se lo llevó otra ruta |

**Es lo mismo con señal y sin ella.** En la APK y el escritorio el aparato lo dice en
el momento, antes de colocar, para que el «no» no te llegue horas después a la
bandeja de rechazados con la zona ya preparada.

**La factura que «Cambió» se coloca y sube.** Sale en «Sin colocar» con su marca
ámbar, y al armar la ruta **entra** como cualquier otra: al camión va lo facturado, no
lo que se pidió. La marca se queda para que se vea.

Si te falta un pedido que esperabas, probablemente es éste el motivo: **no se ha
cobrado el domicilio en la factura, o el vendedor lo marcó y Entrega no lo ha
cotizado**. Se arregla cobrando o cotizando en Entrega, no aquí.

---

## Crear y gestionar una zona

- **Crearla**: el recuadro con el `+` al final de la tira dice **«Columna»**; en el
  teléfono el botón se llama **«Nueva columna»**. Pide el **«Nombre de la zona»**,
  con el ejemplo «Centro, Vista Alegre, Carretera…», y se guarda con **«Guardar»**
  o con Intro.
- **El menú de la zona** se abre con el **⋮** («Opciones de la columna») y lleva:
  1. **«Renombrar»**
  2. **«Camión previsto»** — debajo el camión elegido, o **«Sin elegir»**
  3. **«Punto de salida»** — debajo el almacén del que sale la zona, por ejemplo
     «El principal: PV-STGO» o «AURORA»
  4. **«Vaciar»** — «Las tarjetas vuelven a «sin colocar»»
  5. **«Mover todo a otra columna»**
  6. **«Borrar la columna»**
  7. Y abajo, separado: **«Armar la ruta de esta zona»**

### «Camión previsto»

Es **lo primero que hay que poner en una zona**, porque sin camión no se arma su
ruta.

- La primera opción siempre es **«Sin camión»**.
- Cada camión sale con su capacidad y su matrícula: «1.000 kg · P-123456».
- Un camión en el taller sale con **«EN EL TALLER»** en ámbar, y **se puede elegir
  igual**: es aviso, no bloqueo (ver [Vehículos](vehiculos.md)).
- **Un camión «Inactivo» no sale nunca.** Si un camión no te sale, mira allí por qué.
- Si la sucursal no tiene ninguno que se pueda ofrecer, lo dice: «Esta sucursal no
  tiene vehículos activos en este aparato.»
- Si el camión que ya tenía la zona se dio de baja después, la zona lo sigue
  nombrando, pero **al armar la ruta el servidor no lo acepta**: «El vehículo está
  inactivo y no se puede asignar a una ruta.» Elige otro en «Camión previsto».

### «Punto de salida»

De qué almacén sale la ruta de la zona. Así cada zona queda preparada para su punto
y no hay que cambiar el almacén de arriba cada vez.

- **«El principal»** es lo de siempre: el almacén que Accesos marca como principal.
- Debajo, los almacenes **de esa sucursal**. Los que no tienen la ubicación puesta
  salen apagados con «sin ubicación configurada» y no se pueden elegir.
- Una zona **nueva** nace con el almacén que esté elegido arriba; si no se eligió
  ninguno, con el principal.
- Al **armar la ruta** de la zona, la ruta sale de ese almacén, y los km de cada
  parada se miden desde él. Si el almacén se dio de baja o perdió la ubicación, **no
  se arma desde el principal sin avisar**: dice «La zona «Centro» no puede salir de su
  punto de salida: … Elige otro en «Punto de salida».»
- Funciona igual sin señal en la APK y el escritorio (se sube después); en la web se
  guarda en el momento y, si el servidor dice que no, sale su motivo.

### Borrar una zona

Hay dos diálogos distintos:

- **Zona vacía** — «La zona se va del tablero. No hay ningún pedido dentro, así que
  no se pierde trabajo del día, pero la zona hay que volver a crearla a mano con su
  nombre.» Botones: **«Sí, borrar «Centro»»** y **«No, dejarla»**.
- **Zona con pedidos** — «**«Centro» tiene 8 pedidos puestos**. ¿Qué se hace con
  ellos?» y dos salidas: **«Devolverlos a «sin colocar» y borrar»** o **«Mandarlos
  a otra columna y borrar»**.

**No se puede borrar una zona con pedidos sin decidir antes qué pasa con ellos.**

---

## Armar la ruta de una zona

Botón **«Armar la ruta de esta zona»**, abajo del menú de la zona. Mientras
trabaja dice **«Armando…»**; si falló, el botón pasa a **«Volver a intentarlo»**.

**Si sale bien:** aparece la franja «Ruta armada con lo que se puede repartir de
«Centro».» y **la aplicación salta sola a Rutas**, a la pestaña «Planificadas», con
la ruta nueva ya elegida.

**Lo que entra en la ruta:** sólo los pedidos de esa zona que se pueden repartir, con
**la misma regla que usa el servidor**, **con señal y sin ella**: facturados (también
los que «Cambió en la factura», que suben con lo facturado), con el **domicilio
cobrado** en la factura y, si el vendedor lo marcó, **cotizado** en Entrega. Los demás
se **descartan**: **se quedan puestos en la zona y
marcados**, y la aplicación los nombra por su conduce (ver
[Si la ruta sale con menos pedidos](#si-la-ruta-sale-con-menos-pedidos)). No
desaparece el trabajo de nadie.

**El orden que va en la ruta es el que dejaste en la zona.** La aplicación no lo
reordena. Ya armada, se puede cambiar en Rutas → «Ver paradas» (arrastrando o con
«Ordenar por cercanía»).

### Si borras la ruta, las facturas vuelven a su zona

Una ruta armada desde una zona se acuerda de dónde salió. Si la **eliminas** (en
Rutas, sólo mientras no esté completada), **las facturas vuelven a la zona** del
tablero: no se pierde la relación y no hay que volver a crear la zona ni a repartir los
pedidos. Lo mismo si quitas **una sola parada** con «Quitar de ruta»: esa factura
vuelve a su zona.

- **En la web** pasa al instante.
- **En la APK y el escritorio, sin señal**, hasta que suba el borrado y baje el
  tablero esas facturas **salen en «Sin colocar»** y no en su zona. Con señal se
  colocan solas donde estaban.

Una ruta **completada** es histórico y no se borra, así que sus facturas no vuelven.

### Los dos «no» del armado

**1. La zona no tiene camión.** No se arma, y el cajón **se queda abierto** para
que le pongas el camión ahí mismo:

> **La zona «Centro» no tiene camión previsto, y sin camión no se arma su ruta**
>
> - Elige el camión en «Camión previsto», en las opciones de la zona, y vuelve a
>   armar.
> - Sin camión no hay capacidad contra la que medir la carga ni costo por km con
>   el que cotizar el domicilio: la ruta saldría con su peso y su importe sin nada
>   con que contrastarlos.

**2. No hay nada repartible en la zona.** Si **ningún** pedido de la zona cumple, **no se
arma la ruta**, y se dice por qué:

> «La columna no tiene ningún pedido que se pueda repartir hoy»

Y debajo, uno por uno, por qué se cayó cada pedido. Cada uno sale por su conduce (el
número de operación de la factura):

```
PTB25-261005-1480 · DAYLIS PÉREZ: Ya va en otra ruta
PTB25-261005-1502 · ANA MARTÍNEZ: Sin factura
PTB25-261005-1511 · LUIS PÉREZ: la factura no tiene domicilio cobrado
PTB25-261005-1523 · MARTA CRUZ: domicilio sin cotizar
```

Los motivos posibles, por este orden de prioridad: «Archivado en PEDIDO», «Ya va en otra
ruta», «Sin cotejar», «Sin factura» (las cuatro son las marcas rojas de la tarjeta), «ya
se entregó», «la factura no tiene domicilio cobrado» y «domicilio sin cotizar» (sólo si
el vendedor marcó domicilio). Son los mismos con señal y sin ella. «Cambió en la
factura» ya no descarta: ese pedido entra.

### Si la ruta sale con menos pedidos

Si **algunos** pedidos cumplen y otros no, la ruta **sí se arma**, con los que cumplen,
y una franja roja lo dice en cuanto llegas a Rutas, con el conduce y el motivo de cada
pedido que se quedó fuera:

> Ruta armada de «Centro», pero 2 pedidos no entraron:
> PTB25-261005-1511 · LUIS PÉREZ: la factura no tiene domicilio cobrado
> PTB25-261005-1523 · MARTA CRUZ: domicilio sin cotizar

(Con uno solo dice «pero 1 pedido no entró». La franja se queda unos seis segundos:
léela antes de que se vaya; los pedidos siguen marcados en la zona.) Esos pedidos **siguen en su zona**, marcados;
se arreglan donde dice el motivo (cobrando o cotizando en Entrega, o en PEDIDO) y se
vuelve a armar. Cuando no se cae ninguno, la franja es la de siempre: «Ruta armada con lo
que se puede repartir de «Centro».»

**Esto ya no depende de la señal.** Antes, sin señal, el aparato armaba con más
pedidos de los que luego aceptaba el servidor, y la misma zona salía distinta con
conexión que sin ella. Ahora el teléfono y el escritorio aplican la misma regla que el
servidor, en el momento.

---

## Los avisos del tablero

| Aviso | Qué significa |
|---|---|
| «Elige una sucursal para ver su tablero» | El tablero es de una sucursal |
| «Santiago de Cuba no tiene ningún almacén con coordenadas» | No hay desde dónde medir. Se arregla en Almacenes |
| «Los almacenes todavía no han llegado a este aparato…» | No es que falten: es que no han bajado. Vuelve a intentarlo |
| «No se pudo guardar en este aparato, así que este movimiento NO se ha hecho. Suele ser que no queda espacio: libera sitio en el teléfono y vuelve a intentarlo.» | El aparato no pudo escribir. **El movimiento no se hizo** |
| «Tablero al día con el servidor.» | Refrescó bien |
| «No se trajo nada: no hay conexión con el servidor. Se sigue con lo que hay en este aparato.» | Sin señal. Lo que hay sigue sirviendo |
| «3 pedidos que tenías puestos ya no están en PEDIDO: SC06-1257 (Centro)…» | Los dieron de baja allá. Se dice con su zona y hay un botón «Entendido» |

### Estados vacíos

- Izquierda sin filtros: «No queda ningún pedido por colocar.»
- Izquierda con filtros: «Ningún pedido con estos filtros.»
- Zona vacía: «Todavía no hay nada en esta zona»; mientras arrastras encima,
  **«Suelta aquí»**.
- Tablero sin ninguna zona: «**Las zonas las pones tú.** Cada sucursal divide su
  territorio a su manera: por distritos, por carreteras o por barrios de toda la
  vida. Crea la primera columna con el «+».»

---

## Lo que el Tablero NO hace

- **No sugiere en qué zona va cada pedido.** Las zonas y el reparto los pones tú.
- **No reordena los pedidos por cercanía.** El orden que pones es el que va.
- **No esconde un pedido que dejó de servir**: lo marca.
- **No junta dos pedidos del mismo cliente**: sólo avisa.
- **No se vacía solo por la noche.** Se vacía a medida que salen las rutas, y la
  zona se queda para el día siguiente.
- **No deja que un pedido esté en dos zonas a la vez.**
- **No edita el pedido**: ni cliente, ni dirección, ni peso, ni el costo del
  domicilio.
- **No se puede arrastrar en el teléfono**, ni reordenar zonas desde ahí. Las zonas
  se reordenan arrastrando su cabecera, y eso sólo se puede en pantalla grande.

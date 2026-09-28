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
  zona. El número cuenta **pedidos**.
- **Derecha: las zonas** — «Centro», «Vista Alegre», «Carretera»… Las pones tú,
  con los nombres que se usen en tu sucursal.

En pantalla grande (a partir de 900 px de ancho) se ven las dos a la vez. En el
teléfono se ve una página cada vez y se pasa deslizando: primero «Sin colocar»,
después una página por zona, y al final «Nueva columna».

---

## La barra de arriba del tablero

- **La sucursal y desde qué almacén se mide**: «Granma · desde Bayamo (Granma)».
  Si hay más de un almacén, se toca y se elige.
- **De cuándo es la copia** (sólo APK y escritorio): «Visto por última vez a las
  10:41».
- **Los contadores de avisos**, que cuentan **pedidos ya colocados** en alguna
  zona y sólo salen si hay alguno:
  - «3 archivados en PEDIDO» (rojo)
  - «2 ya en otra ruta» (rojo)
  - «5 sin factura o sin cotejar» (rojo)
  - «1 cambiaron en la factura» (ámbar)
- **El botón de refrescar**, con el rótulo **«Traer lo del servidor»**.

### El tablero se niega a refrescar si tienes algo sin subir

Y lo dice:

> «No se actualiza: hay 1 cambio sin subir. Se sube primero y después se trae —
> así no se pierde nada.»

No es un fallo. Es para que lo de allá no pise lo que hiciste aquí. Sube primero.

---

## Buscar y filtrar la mitad izquierda

- **El buscador** dice «Cliente, operación, dirección, artículo…» y **filtra al
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

### La lista sale acotada a 200

Si hay más, lo dice: **«Se ven 200 de 308.»** y al lado el botón **«Ver 108 más»**,
que sube el tope de 200 en 200.

---

## Qué se ve en cada tarjeta de pedido

De arriba abajo:

1. **Los kilómetros al almacén** si está sin colocar («0,4 km»), o **su número de
   orden** si ya está en una zona («3.»). A la derecha, el número de operación.
   Si el pedido no tiene coordenadas, en vez de los km pone **«sin ubicar»**.
2. **El cliente.**
3. **La dirección.**
4. **Una línea de datos** separada por puntos: peso, costo del domicilio,
   municipio, y los km si ya está colocada. Por ejemplo:
   `12 kg · 0,04 USD · Songo-La Maya · 3,7 km`
   Si el pedido no tiene costo, en su sitio no sale nada.
5. **Las marcas**, si las tiene: «Archivado en PEDIDO», «Ya va en otra ruta»,
   «Sin cotejar», «Sin factura» (las cuatro en rojo) y «Cambió en la factura» (en
   ámbar). Ver [Las reglas del reparto](../las-reglas-del-reparto.md).
6. **Si el cliente repite hoy**: «2 pedidos de este cliente hoy». **Las tarjetas
   no se juntan**: sólo se avisa, para que los metas en la misma zona a propósito.

---

## Qué se ve en la cabecera de cada zona

```
Vista Alegre (9)                           ⋮
1.210 kg / 1.000 kg · 41,00 USD      (!) no cabe
Camión: F-350                          sin subir
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

- El detalle del pedido: dirección, municipio, teléfono, vendedor, y la línea de
  peso, km y costo: `12,5 kg · 3,7 km · $0.04`.
- Los artículos (hasta cuatro, y luego «y 3 artículo(s) más»).
- Las marcas del pedido, si las tiene.
- Si ya está colocada: **«Subir una posición»**, **«Bajar una posición»** y
  **«Devolver a sin colocar»**.
- La lista de zonas: **«Colocar en «Centro»»**, con «12 pedidos · 480 kg» debajo.

Si todavía no hay zonas:

> «Todavía no hay ninguna columna. Créala con el «+» del tablero y ponle el nombre
> de la zona.»

---

## Crear y gestionar una zona

- **Crearla**: el recuadro con el `+` al final de la tira dice **«Columna»**; en el
  teléfono el botón se llama **«Nueva columna»**. Pide el **«Nombre de la zona»**,
  con el ejemplo «Centro, Vista Alegre, Carretera…», y se guarda con **«Guardar»**
  o con Intro.
- **El menú de la zona** se abre con el **⋮** («Opciones de la columna») y lleva:
  1. **«Renombrar»**
  2. **«Camión previsto»** — debajo el camión elegido, o **«Sin elegir»**
  3. **«Vaciar»** — «Las tarjetas vuelven a «sin colocar»»
  4. **«Mover todo a otra columna»**
  5. **«Borrar la columna»**
  6. Y abajo, separado: **«Armar la ruta de esta zona»**

### «Camión previsto»

Es **lo primero que hay que poner en una zona**, porque sin camión no se arma su
ruta.

- La primera opción siempre es **«Sin camión»**.
- Cada camión sale con su capacidad y su matrícula: «1.000 kg · P-123456».
- Un camión en el taller sale con **«EN EL TALLER»** en ámbar, y **se puede elegir
  igual**: es aviso, no bloqueo.
- Si la sucursal no tiene ningún camión bajado en el aparato, lo dice: «Esta
  sucursal no tiene ningún vehículo en este aparato.»

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

**Lo que entra en la ruta:** sólo los pedidos repartibles de esa zona. Los que no
se pueden repartir **se quedan puestos en la zona y marcados**. No desaparece el
trabajo de nadie.

**El orden que va en la ruta es el que dejaste en la zona.** La aplicación no lo
reordena.

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

**2. No hay nada repartible en la zona.**

> «La columna no tiene ningún pedido que se pueda repartir hoy»

Y debajo, uno por uno, por qué se cayó cada pedido:

```
SC06-1257 · DAYLIS PÉREZ: Ya va en otra ruta
X-2992 · ANA MARTÍNEZ: Sin cotejar
```

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

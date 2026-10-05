# Panel

**Para qué sirve:** es la foto del día. Se abre por la mañana para saber cuánto
queda por repartir, cuántos camiones están fuera y si falta algo por configurar.

**Dónde está:** primera entrada del menú.

**Recuerda:** todo lo que ves es **de la sucursal que tengas puesta arriba**.

---

## Lo que hay en la pantalla, de arriba abajo

1. **Paso a paso de la configuración** — sólo si falta algo.
2. **Estado del día** — la banda de traer y entregar. **No existe en la web.**
3. **Las cuatro cifras.**
4. **«Pendiente por sucursal»** y **«Acciones Rápidas»**, uno al lado del otro en
   pantalla grande y uno debajo del otro en el teléfono.

---

## Las cuatro cifras

| Tarjeta | Qué cuenta |
|---|---|
| **«Pedidos sin ruta»** | **Pedidos** que hoy pueden subir a un camión y todavía no están en ninguna ruta. Debajo, el peso: «1.240 kg por mover» |
| **«Rutas en marcha»** | **Rutas que salieron.** Las planificadas no entran aquí |
| **«Entregados hoy»** | **Pedidos** marcados como entregados desde las 00:00 de hoy |
| **«Vehículos»** | «3 / 8», y debajo «en ruta / total». El de la izquierda son camiones en una ruta en curso |

Detalles que hay que saber:

- **«Pedidos sin ruta»** cuenta los pedidos que tienen coordenadas de entrega y
  están facturados (cuadre o haya cambiado). Un pedido sin coordenadas no entra.
- **«Entregados hoy»** usa el **reloj del aparato**, no el del servidor. Si el
  reloj del teléfono está mal, este número está mal.
- **«Vehículos»** saca el camión de la **ruta**, no del pedido.
- Mientras carga, las cuatro se pintan **con ceros**, no con una rueda. Si acabas
  de abrir la pantalla, espera un segundo antes de creerte un cero.

Los kilos de esta pantalla van **redondeados y sin decimales**: «860 kg».

### «Pedidos sin ruta» del Panel no es «Sin colocar» del Tablero

Son dos preguntas parecidas con dos respuestas distintas, y **no tienen por qué
coincidir**. El Tablero pide además que el pedido venga de PEDIDO, que requiera
domicilio y que **no esté ya puesto en ninguna zona**.

Con los datos del 25/09/2026 la diferencia en Santiago era de 183 pedidos. No es
un fallo.

---

## «Pendiente por sucursal»

Una fila por sucursal, con su peso y su número de pedidos, **ordenadas de más a
menos pedidos**. Son los mismos pedidos que cuenta «Pedidos sin ruta».

- Un pedido sin sucursal se agrupa bajo **«Sin sucursal»**.
- Si no queda nada, dice: **«No queda nada sin ruta.»**

Al pie, separado por una línea: **«Domicilios cobrados»** con su importe.

**Cuidado con ese importe:** suma el costo de domicilio de **todos** los pedidos
de la sucursal, no sólo de los que quedan sin ruta. No se puede comparar con la
lista de arriba.

---

## «Acciones Rápidas»

Tres atajos:

| Botón | A dónde lleva |
|---|---|
| **«Planificar Rutas»** | Rutas |
| **«Ver Reportes»** | Reportes |
| **«Gestionar Flota»** | Vehículos |

---

## «Paso a paso» de la configuración

**El paso a paso de verdad, con quién hace cada cosa y qué se pide a quién, está en
[Dejar una sucursal lista para trabajar](../puesta-en-marcha.md).** Aquí sólo está
qué es cada cosa de la pantalla.

Sale **sólo cuando falta algo** y el aparato ya tiene datos bajados. Son cuatro
pasos, **en orden: cada uno necesita el anterior**.

El título cambia según cuántas sucursales tengas puestas arriba:

- Con **una**: **«Falta configurar esta sucursal»**.
- Con **varias**: **«Faltan cosas por configurar en 6 de las 8 sucursales»**.

Y la línea de debajo del título también:

- Con una: «Sin esto no se puede armar una ruta. Van en este orden: cada uno necesita
  el anterior.»
- Con varias: «Un paso sólo está hecho cuando lo está en TODAS las sucursales que
  estás mirando. Van en este orden: cada uno necesita el anterior.»

Cada paso lleva delante su número sobre el total: **«1/4»**, **«2/4»**… **y no se
renumeran al tacharlos**: el paso 3 de ayer sigue siendo el 3 hoy.

| Paso | Para qué sirve | Qué se rompe sin él | Se arregla |
|---|---|---|---|
| **«El punto de partida de la sucursal»** | Es el sitio desde el que se mide la distancia hasta cada cliente | «esos domicilios se quedan sin cotizar y los pedidos salen sin precio» | **No aquí.** Lo deja hecho quien da de alta la sucursal. Pídelo a administración |
| **«Al menos un vehículo»** | Es el camión al que se le carga la ruta del día | No se puede terminar el paso 3 del asistente de rutas, y una zona del tablero no puede llevar camión | Botón **«Agregar el primer vehículo»** |
| **«Al menos un almacén con su punto puesto»** | De ahí sale lo que se le cobra al cliente por el domicilio, y de ahí arranca el camión | Se cobra desde el sitio equivocado. Un almacén sin coordenadas tampoco sirve | Botón **«Poner el almacén»** |
| **«La tasa de cambio de la sucursal»** | Pasa los importes de USD a CUP | Los importes sólo se ven en USD | **No aquí.** La mantiene Accesos, que la trae de Entrega |

A la derecha del título, cuántos van: «2 de 4».

**Con varias sucursales a la vista, un paso sólo está hecho cuando lo está en
TODAS.** Y te dice en cuáles falta: «Falta en 2 de las 8 sucursales: Granma y Las
Tunas.» Con más de tres, sólo dice cuántas.

Si un paso **no se ha podido mirar** porque esa parte no bajó, lo dice y no lo da
por malo:

> «Este aparato no lo ha descargado todavía, así que no se sabe si falta. Se
> arregla trayendo el día, no dando nada de alta.»

**En la web**, donde no hay día que traer, ese mismo estado se dice así:

> «Esto no se pudo traer, así que no se sabe si falta. No es que no esté dado de
> alta: es que no llegó. Prueba a recargar y, si sigue igual, avisa a la oficina.»

**El color los separa, y hay que mirarlo**: **ámbar = falta y hay que hacerlo**;
**azul = todavía no se sabe**. Un paso azul **no se arregla dando nada de alta**.

Y cuando lo único pendiente es que baje, **el título también cambia** y no acusa a
nadie: **«Falta por traer parte de la configuración»**, **«Todavía está bajando la
configuración»** o **«No se pudo traer la configuración»**.

**Si el recuadro no sale, la sucursal está lista.** No hay ninguna pantalla que diga
«todo correcto»: el paso a paso sólo se pinta cuando falta algo.

---

## «Estado del día» — sólo en la APK y en el escritorio

La banda que gobierna traer y entregar. Sus siete estados:

| Dice | Botón | Qué significa |
|---|---|---|
| **«Todo al día»** | — | Los datos son de ahora y no queda nada sin enviar |
| **«Traer el día»** | «Traer el día» | Hay que cargar lo del día |
| **«Tienes trabajo sin enviar»** | «Enviar datos (23)» | 23 apuntes están sólo en este aparato |
| **«Trabajando sin conexión»** | — | Puedes seguir: todo se guarda aquí y sube solo |
| **«Trayendo datos...»** | — | En marcha. «No cierres la pantalla hasta que acabe.» |
| **«Enviando datos...»** | — | Igual |
| **«Hay trabajo que no va a subir solo»** | — | **Aviso serio.** Ver abajo |

### «Hay trabajo que no va a subir solo»

Es el aviso más importante de esta banda. Quiere decir:

> «Está sólo en este aparato y no le queda ningún apunte que lo suba. No cierres
> sesión ni borres esta copia: avisa a la oficina para que lo rehagan.»

No es «todavía no ha subido». Es «**no va a subir**». Avisa antes de cerrar
sesión o de desinstalar nada.

Al lado se lee de qué hora son los datos y cuántos quedan: «datos de las 8:14 ·
23 sin subir».

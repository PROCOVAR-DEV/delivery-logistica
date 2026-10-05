# Cómo se trabaja un día

Éste es el hilo. Todo lo demás cuelga de aquí.

Los pasos son los mismos en los tres sitios; lo que cambia es **el paso 0** y **lo
que pasa al final del día**. Para los pasos concretos de tu aparato:
[web](../web/1-el-dia-en-la-web.md) · [APK](../apk/2-el-dia-en-el-telefono.md) ·
[escritorio](../escritorio/2-el-dia-en-el-escritorio.md).

---

## Paso 0 — Traer el día (sólo APK y escritorio)

**Donde haya señal**, antes de bajar al almacén. En la web este paso no existe: los
datos están siempre en vivo.

Franja de arriba o Panel, botón **«Traer el día»**.

> «Cárgalo donde haya señal y llévatelo: el día entero se trabaja sin conexión.»

Al terminar dice qué te llevas: «308 pedidos · 1.842 clientes · 129 productos», con
sus líneas, y «Y lo de siempre: vehículos, sucursales, almacenes y ajustes».

**Si falta algo, lo dice con nombre y con qué se rompe sin ello.** Entonces:

> «Busca señal y vuelve a darle al botón. Lo que ya bajó se queda.»

---

## Paso 1 — Entrar y mirar la sucursal

Entra con tu usuario de Procovar. **Para entrar hace falta conexión; una vez
dentro, no.**

Y lo primero: **mira arriba qué sucursal pone**. Todas las pantallas enseñan lo de
esa sucursal. Si tienes uno de los cinco roles de una sola sucursal, ya está puesta
y no se cambia.

---

## Paso 2 — El Panel: cómo viene el día

De un vistazo:

- **«Pedidos sin ruta»** y debajo cuántos kilos hay por mover.
- **«Rutas en marcha»** — los camiones que están fuera.
- **«Entregados hoy»**.
- **«Vehículos»** — «3 / 8» en ruta sobre el total.

Si sale el **«Paso a paso»**, hay algo de configuración sin terminar y **no vas a
poder armar una ruta**. Míralo antes de seguir: te dice qué falta, en qué sucursales
y dónde se arregla. Las cuatro cosas, en orden y con quién hace cada una, están en
[Dejar una sucursal lista para trabajar](puesta-en-marcha.md).

Y **«Pendiente por sucursal»** te dice por dónde empezar: las sucursales salen
ordenadas de más a menos pedidos pendientes.

---

## Paso 3 — El Tablero: armar las zonas

Éste es el camino principal. **Así arma Jose el día: por zonas.**

1. **Comprueba arriba desde qué almacén se mide** («Granma · desde Bayamo
   (Granma)»). Ese punto decide los kilómetros de cada tarjeta y lo que se cobra.
2. **Mira los avisos rojos**, si los hay: «3 archivados en PEDIDO», «2 ya en otra
   ruta». Son pedidos ya colocados que hoy no salen.
3. **Filtra la izquierda** si te conviene: por municipio, por vendedor, por día o
   por «Hasta cuántos km del almacén».
4. **Crea las zonas** con el botón **«Nueva columna»** (lleva un `+`): «Centro»,
   «Vista Alegre», «Carretera»… **Los nombres de tu sucursal, no los de nadie más.**
   Con el tablero vacío la propia pantalla te lo dice: «**Las zonas las pones tú.**
   Cada sucursal divide su territorio a su manera: por distritos, por carreteras o
   por barrios de toda la vida. Crea la primera columna con el «+».»

   **Las zonas se quedan puestas.** No hay que crearlas cada mañana: se vacían a
   medida que salen sus rutas y se vuelven a llenar.
5. **Ponle el camión a cada zona**: **⋮ → «Camión previsto»**. **Hazlo ahora**, no al
   final: sin camión la zona no arma ruta.
6. **Reparte los pedidos.** Arrastrando en pantalla grande, o tocando la tarjeta y
   eligiendo la zona en el teléfono.
7. **Mira la cabecera de cada zona** mientras repartes: «1.210 kg / 1.000 kg · 41,00
   USD». Si aparece **«no cabe»** en ámbar, esa carga pasa de lo que aguanta el
   camión. Es un aviso, no un bloqueo: la ruta se arma igual, pero alguien va a tener
   que dejar algo en el almacén.

**Ejemplo:** tienes 102 pedidos sin colocar en Santiago. Arrastras los de Vista
Alegre a esa zona y su cabecera queda en «3 pedidos · 516 kg · Camión: F-350». Ya
está lista para armar.

---

## Paso 4 — Armar la ruta

**⋮ → «Armar la ruta de esta zona»**.

- **El orden que va es el que dejaste tú.** La aplicación no lo reordena.
- **Sólo entran los pedidos repartibles.** Los que no, se quedan en la zona,
  marcados con su motivo. No desaparece nada.
- Si sale bien: «Ruta armada con lo que se puede repartir de «Centro».» y **la
  aplicación salta sola a Rutas**, pestaña «Planificadas», con la ruta ya abierta.

La ruta se llamará **`RT-20260928-004`**: el prefijo, la fecha y el número de orden
dentro del día.

**Sin señal** (APK y escritorio) la ruta nace con un nombre provisional como
`local-3df93810` y **se convierte en su `RT-…` en cuanto suba**.

### Si no quieres armar por zonas

En Rutas hay **«+ Nueva Ruta»**, un asistente de cuatro pasos: **«Sucursal»**,
**«Salida»**, **«Vehículo»** y **«Pedidos»**. Es el camino largo, y sirve cuando la
ruta no sale de una zona entera.

---

## Paso 5 — Sacar el pre-despacho e iniciar la ruta

**Antes de que salga el camión**, saca el pre-despacho: es la hoja del almacén, con
lo que hay que sacar de cada producto, sus empaques y su peso, y una columna
**«Sacado»** en blanco para ir marcando.

Sale del **paso 4 del asistente**, con **«Ver e imprimir»**.

Luego, en el detalle de la ruta: **«Iniciar ruta»**.

- La ruta pasa a **«En curso»**.
- **El camión queda ocupado** (hasta ahora no lo estaba).
- La vista salta sola a la pestaña «En curso».

Y mándale al chófer el recorrido: en el bloque **«Recorrido»**, **«WhatsApp»** o
**«Copiar»**. El mensaje lleva el código, las paradas, los kilómetros, el camión, la
fecha y el enlace de Google Maps.

---

## Paso 6 — Marcar las entregas

Durante el reparto, en el detalle de la ruta: **«Cierre (3)»** — el número son las
paradas que quedan sin marcar.

Por cada parada, tres botones: **«Entregado»**, **«Devuelto»** y **«Cancelado»**.

- Si marcas devuelto o cancelado, **escribe el motivo**. El campo lo pide con un
  ejemplo: «¿Por qué volvió? (el cliente cerró, no lo quiso, no había nadie…)». Es
  opcional, pero es lo único que le explica a la oficina qué pasó.
- **Pulsar dos veces el mismo botón desmarca**, para corregir un dedazo.
- Arriba hay atajos: **«Todas: Entregado / Devuelto / Cancelado»**.

Abajo, en vivo, **«Queda en el camión»** te dice qué debe quedar arriba: «MALTA
GUAJIRA ×36». Si dice **«Nada: se entregó todo lo que salió»**, el camión vuelve
vacío.

**Esto se puede hacer sin señal, entero.**

Y guarda: **«Guardar 5 marcada(s)»**.

> «Cierre guardado. En PEDIDO cada pedido ya dice si se entregó o volvió.»

---

## Paso 7 — Cerrar la ruta

**«Marcar como completada»**.

Si quedan paradas sin marcar, **te abre el cierre primero**, y avisa:

> «Lo que dejes sin marcar se da por no entregado y cuenta como que sigue en el
> camión.»

Al completarla:

- La ruta pasa al **«Historial»**.
- **El camión queda libre.**
- Los pedidos no entregados **vuelven a estar disponibles** para mañana.

**Y saca el post-despacho** antes de descargar el camión: es la hoja de «Tiene que
quedar en el camión», con una columna **«Bajó»** en blanco para contar a mano, y la
sección **«De quién es lo que vuelve»**.

**Una ruta completada no se puede corregir aquí.** El cierre pasa a solo lectura:
«Para corregir algo, hay que hacerlo en PEDIDO.»

---

## Paso 8 — Entregar el día (sólo APK y escritorio)

Al volver, **con señal**: franja de arriba o Panel, **«Entregar el día»**.

En realidad **casi nunca hace falta pulsarlo**: en cuanto vuelve la señal sube solo,
en unos segundos. Se pulsa para asegurarse.

Al terminar: **«Todo entregado»**, o «Quedan 2 sin subir» con qué hacer.

**No te vayas a casa con la franja diciendo «23 sin subir».** Mientras no suba,
para los demás ese trabajo no existe.

---

## Al día siguiente

Lo que quedó sin repartir **sigue ahí**: los pedidos no entregados soltaron su ruta
y vuelven a estar disponibles.

**Las zonas del Tablero se quedan.** No se borran por la noche, y no hace falta
volver a crearlas: se vacían a medida que salen sus rutas y se vuelven a llenar.

---

## Lo que no es de todos los días, pero toca

Esto no entra en el hilo de la mañana. Es el trabajo que aparece cuando algo cambia,
y cada tarea está escrita por su cuenta en **[Busca tu tarea](tareas.md)**.

| Cuándo | Qué hay que hacer | Empieza en |
|---|---|---|
| Entra un camión nuevo, o se cambia uno | [Dar de alta un camión](tareas.md#vehículos--necesita-conexión-siempre-también-en-el-teléfono) y, si es el que pone el precio del domicilio, decirlo | **Vehículos** |
| Un camión se va al taller | Marcarlo, **con el motivo en «Notas»**. Y si llevaba una ruta abierta, **eso no la cierra**: hay que rearmarla con otro camión | **Vehículos** |
| Se muda el almacén, o se abre otro | Poner su punto, y decidir cuál es el **«Principal»** | **Almacenes** |
| Se retira un almacén | Quitarlo — y **avisar a quien tenga la aplicación en el teléfono para que traiga el día**, o ese día cobra desde un sitio que ya no existe | **Almacenes** |
| Cambia la tasa de cambio | **No se toca aquí.** Se pide a administración, se arregla en Accesos y baja sola con el día | **Panel** |
| Se abre una sucursal | Las cuatro cosas, en orden: [Dejar una sucursal lista para trabajar](puesta-en-marcha.md) | **Panel** |
| Cambia el territorio | Renombrar, vaciar, mover o borrar zonas del tablero | **Tablero** |
| Hay que cuadrar lo repartido | Sacar el informe y exportarlo | **Reportes** |
| Un aparato lleva días sin subir | Mirar quién es y llamarle | **Sincronización** (sólo escritorio) |
| Sale una versión nueva | **Primero subir lo que haya, después instalar.** La aplicación ni te deja al revés | la franja de arriba |

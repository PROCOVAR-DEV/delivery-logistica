# Tareas sueltas

**La mayoría se hacen igual que en la web**, porque se manejan con ratón y con las
dos mitades a la vista. Para no repetirlo, aquí está lo que **es igual** (con su
enlace) y, detallado, **lo que cambia**.

---

## Igual que en la web

Estas tareas se hacen exactamente igual. Cada una está explicada paso a paso en el
manual de la web:

- [Buscar un pedido](../web/2-tareas.md#buscar-un-pedido)
- [Filtrar y ordenar la lista de pedidos](../web/2-tareas.md#filtrar-y-ordenar-la-lista-de-pedidos)
- [Mandar varios pedidos a una zona de golpe](../web/2-tareas.md#mandar-varios-pedidos-a-una-zona-de-golpe)
- [Ver el detalle de un pedido](../web/2-tareas.md#ver-el-detalle-de-un-pedido)
- [Renombrar, vaciar o borrar una zona](../web/2-tareas.md#renombrar-vaciar-o-borrar-una-zona)
- [Armar una ruta sin usar el Tablero](../web/2-tareas.md#armar-una-ruta-sin-usar-el-tablero)
- [Filtrar la lista de rutas](../web/2-tareas.md#filtrar-la-lista-de-rutas)
- [Eliminar una ruta](../web/2-tareas.md#eliminar-una-ruta)
- [Sacar un pedido de una ruta](../web/2-tareas.md#sacar-un-pedido-de-una-ruta)
- [Consultar un cliente](../web/2-tareas.md#consultar-un-cliente)
- [Dar de alta un camión](../web/2-tareas.md#dar-de-alta-un-camión)
- [Decir qué camión calcula el domicilio](../web/2-tareas.md#decir-qué-camión-calcula-el-domicilio)
- [Marcar un camión en el taller](../web/2-tareas.md#marcar-un-camión-en-el-taller)
- [Dar de baja un camión](../web/2-tareas.md#dar-de-baja-un-camión)
- [Dejar un camión inactivo](../web/2-tareas.md#dejar-un-camión-inactivo)
- [Definir los tipos de camión y su costo por km](../web/2-tareas.md#definir-los-tipos-de-camión-y-su-costo-por-km)
- [Cambiar el camión de una ruta](../web/2-tareas.md#cambiar-el-camión-de-una-ruta)
- [Poner o corregir un almacén](../web/2-tareas.md#poner-o-corregir-un-almacén)
- [Cambiar cuál es el almacén principal](../web/2-tareas.md#cambiar-cuál-es-el-almacén-principal)
- [Quitar un almacén de la sucursal](../web/2-tareas.md#quitar-un-almacén-de-la-sucursal)
- [Cambiar entre USD y CUP](../web/2-tareas.md#cambiar-entre-usd-y-cup)
- [Ir a otra aplicación de la casa](../web/2-tareas.md#ir-a-otra-aplicación-de-la-casa)

**Y la puesta en marcha de una sucursal** —las cuatro cosas que hay que dejar
configuradas antes de poder armar una ruta— es la misma en los tres sitios: [Dejar
una sucursal lista para trabajar](../comun/puesta-en-marcha.md).

**Dos avisos al leerlas:** donde digan «recarga la página», aquí no hay página que
recargar; y **Vehículos y Almacenes necesitan conexión también aquí** (no hay cola
para ellos).

---

## Lo que cambia en el escritorio

### Traer el día a mano
<!-- tarea -->

**Empieza en:** la franja de arriba, desde cualquier pantalla.

1. **Clic en la franja de arriba**, en cualquier sitio.
   <!-- señala: franja-de-estado -->
2. **Clic en «Traer el día»**. <!-- señala: traer-el-dia-traer -->

**En la web esto no existe.** Aquí es el gesto que hace que todo lo demás funcione
sin red.

Si el botón está apagado, el motivo sale al lado: **«Sin conexión con el servidor»**
o **«Los datos ya son de ahora mismo»**.

### Entregar el día a mano
<!-- tarea -->

**Empieza en:** la franja de arriba, desde cualquier pantalla.

1. **Clic en la franja**, o directamente en el botón **«23 sin subir»**.
   <!-- señala: franja-entregar-el-dia -->
2. **Clic en «Entregar el día»**. <!-- señala: entregar-el-dia-entregar -->

Si está apagado: **«Trae el día primero: no se envía nada sin tener lo de ahora»**.

### Ver qué aparato lleva sin subir
<!-- tarea -->

**Empieza en:** **Menú → «Sincronización»**.

**Esta pantalla no existe en la web.**

1. **Menú → «Sincronización»**. <!-- señala: menu-sincronizacion -->
2. Arriba, las cuatro cifras: **«Sin subir nunca»**, **«Más de un día sin subir»**
   («Estos son los de llamar»), **«Apuntes pendientes»** y **«Rechazados sin
   atender»**. <!-- señala: sincronizacion-cifras -->
3. Debajo, la tabla **«Aparatos»**, **ordenada por el que lleva más sin subir**. El
   borde de cada fila es rojo (más de 24 h o nunca), ámbar (más de 8 h) o verde.
   <!-- señala: sincronizacion-aparatos -->
4. Y la bandeja **«Rechazados sin atender (4)»**, con el motivo literal del servidor,
   quién, cuándo se hizo y cuándo se rechazó.
   <!-- señala: sincronizacion-bandeja -->

**Desde aquí sólo se miran.** Los botones de **«Reintentar»** y **«Descartar»** están
en el cajón de «Entregar el día», que enseña los rechazos **de este** ordenador.

**Y necesita conexión**: se lee del servidor cada vez y no guarda copia.

### Resolver un rechazo
<!-- tarea -->

**Empieza en:** la franja de arriba, desde cualquier pantalla.

1. **Clic en la franja** → botón de la nube con la flecha hacia arriba.
   <!-- señala: franja-entregar-el-dia -->
2. Baja hasta **«Rechazados, esperando a una persona»**.
   <!-- señala: entregar-el-dia-bandeja -->
3. **Lee el motivo**, con las palabras del servidor.
   <!-- señala: entregar-el-dia-rechazo -->
4. **«Reintentar»** si el motivo ya no se da; **«Descartar»** si ese cambio ya no tiene
   sentido (**se pierde**). <!-- señala: rechazo-reintentar -->

### Descargar el mapa de Cuba
<!-- tarea -->

**Empieza en:** **Menú → «Mapa de Cuba sin conexión»**.

**Esta pantalla no existe en la web.**

1. **Menú → «Mapa de Cuba sin conexión»**. <!-- señala: menu-mapa -->
2. **Clic en «Completo, con calles — 49,2 MB»**. <!-- señala: mapa-bajar -->

Y si el mapa se ve mal, baja hasta **«Si el mapa se ve mal»** y usa **«Volver a bajar
«Completo, con calles»»**. **Nunca desinstales la aplicación para arreglar el mapa:
se llevaría el trabajo que no haya subido.**

### Exportar el Excel
<!-- tarea -->

**Empieza en:** **Menú → «Reportes»**.

Igual que en la web hasta el botón, pero **el final es distinto**: aquí **se guarda en
la carpeta de descargas** y te dice la ruta:

> «Excel guardado en /home/jose/Descargas/reporte-procovar-2026-09-28.xlsx»

**No se abre ningún cajón de compartir** (en Linux compartir ficheros no existe).

### Mandarle la ruta al chófer
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

Los botones son los mismos —**«Abrir en Google Maps»**, **«WhatsApp»**,
**«Compartir»**, **«Copiar»**— pero en el escritorio **«Compartir» puede no ofrecer
nada**, y la aplicación lo dice:

> «Este aparato no ofreció ningún modo de compartir. Con «Copiar» el enlace queda en el
> portapapeles.»

**Usa «Copiar»** y pégalo donde quieras.

### Actualizar la aplicación
<!-- tarea -->

**Empieza en:** la franja de arriba, desde cualquier pantalla.

**En la web basta con recargar. Aquí se instala a mano.**

1. **Antes de nada, sube lo que tengas.** Si hay trabajo sin subir, ni te lo ofrece:

   > **Hay una versión nueva, pero antes hay que subir el trabajo** — Te quedan 3 cosas
   > por subir. Instalar ahora puede llevárselas: primero sube, después actualiza.

2. Con la cola vacía, la franja dice **«Hay una versión nueva: 1.0.7»**.
3. **Clic en «Cómo instalarla»**. <!-- señala: franja-version-nueva -->
4. Lee qué va a pasar: «Son 74 MB. Se abre el navegador y se descarga el fichero. La
   descarga no toca esta aplicación: lo que tengas dentro sigue aquí mientras no
   instales.»
5. **Clic en «Descargar»** (el botón se apaga después del primer clic).
   <!-- señala: cajon-descargar-al-navegador -->
6. Instálalo encima cuando puedas: «No hace falta que sea ahora: la versión de ahora
   sigue funcionando.»

---

## Lo que el escritorio NO tiene y la web sí

**La pantalla «Canal con PEDIDO».** No es que esté escondida: en el escritorio y en
el teléfono **no existe**, no se registra siquiera. En la web la ven en el menú sólo
`DESARROLLADOR` y `SUPER ADMIN`.

Si tienes que mirar cómo va el canal, **ábrelo en el navegador**, no aquí.

# El día, de principio a fin

Cada paso dice **dónde hacer clic** y **qué tienes que ver después**.

---

# 1. Traer el día

**Con conexión, antes de empezar** (y obligatoriamente antes si vas a quedarte sin
red).

1. **Mira la franja de arriba.** Si pone **«Datos de hace 9 h»** o **«Datos del martes
   — hace 3 días»** en ámbar, hay que traer el día.
2. **Haz clic en la franja**, en cualquier sitio. Se abre el cajón **«Traer el
   día»**.
3. **Clic en «Traer el día»**.
4. El botón pasa a **«Trayendo el día...»** y te va diciendo por dónde va:
   «Comprobando la sesión…», «Pidiendo los cambios…», «Pedidos…», «Clientes…»,
   «Productos…».
5. Al terminar, **«Ya lo tienes»** y debajo qué te llevas:

   ```
   Esto es lo que te llevas ahora mismo
   308 pedidos · 1.842 clientes · 129 productos
   con 4.912 líneas
   Y lo de siempre: vehículos, sucursales, almacenes y ajustes.
   ```

6. Cierra el cajón. **La franja tiene que poner «Datos de las 8:14»** en gris.

### Si el botón está apagado

El motivo sale al lado:

- **«Sin conexión con el servidor»** — sin red no hay nada que traer.
- **«Los datos ya son de ahora mismo»** — ya está hecho.

### Si falta algo

No dice «error»: dice **qué falta** («Falta el catálogo de productos») y **qué se
rompe sin eso**. Y al final:

> «Busca señal y vuelve a darle al botón. **Lo que ya bajó se queda.**»

### Si dice «El servidor no mandó todo»

> «La bajada se quedó a medias: … Lo que hay en el aparato está incompleto **aunque
> las cifras de abajo parezcan normales**.»

**Vuelve a darle antes de armar nada, y antes de sacar ningún informe.**

---

# 2. Mirar cómo viene el día: el Panel

1. En el **menú de la izquierda**, clic en **«Panel»**.
2. **Comprueba la sucursal** arriba a la derecha: «Santiago (STG)». Todas las
   pantallas enseñan lo de esa sucursal.
3. Las cuatro cifras: **«Pedidos sin ruta»** (con «1.240 kg por mover» debajo),
   **«Rutas en marcha»**, **«Entregados hoy»** y **«Vehículos»** («3 / 8»).
4. Abajo, **«Pendiente por sucursal»** (ordenada de más a menos) y **«Acciones
   Rápidas»**.

### Si arriba sale «Falta configurar esta sucursal»

**Léelo antes de seguir: sin eso no vas a poder armar una ruta.** Dos de los cuatro
pasos tienen botón y dos no:

| Falta | Qué hacer |
|---|---|
| **«Al menos un vehículo»** | **«Agregar el primer vehículo»** |
| **«Al menos un almacén con su punto puesto»** | **«Poner el almacén»** |
| **«El punto de partida de la sucursal»** | No se pone aquí. Pídelo a administración |
| **«La tasa de cambio de la sucursal»** | No se pone aquí. La mantiene Accesos |

Si un paso no se ha podido comprobar porque esa parte no bajó, te lo dice y **no lo
da por malo**:

> «Este aparato no lo ha descargado todavía, así que no se sabe si falta. **Se arregla
> trayendo el día**, no dando nada de alta.»

---

# 3. Armar las zonas en el Tablero

1. **Menú → «Tablero».**
2. **Ves las dos mitades a la vez**: a la izquierda **«Sin colocar (308)»**, a la
   derecha la tira de zonas.
3. **Comprueba arriba desde dónde se mide**: **«Granma · desde Bayamo (Granma)»**. Con
   más de un almacén sale una flechita ▾: clic y elige.
4. **Mira de cuándo es tu copia**, al lado: **«Visto por última vez a las 10:41»**.
5. **Mira los avisos rojos** si los hay: «3 archivados en PEDIDO», «2 ya en otra
   ruta».

## 3.1 Crear una zona
<!-- tarea -->

**Empieza en:** **Menú → «Tablero»**.

1. Al final de la tira, **clic en el recuadro con el `+` que pone «Columna»**.
   <!-- señala: tablero-nueva-zona -->
   - **Aquí no hay carrusel que pasar**: «Sin colocar» y la tira de zonas están las
     dos a la vista, como en la web.
2. Escribe el **«Nombre de la zona»** («Centro, Vista Alegre, Carretera…»).
   <!-- señala: tablero-nombre-de-la-zona -->
3. **«Guardar»**, o intro. <!-- señala: tablero-guardar-la-zona -->

## 3.2 Ponerle el camión a la zona — HAZLO AHORA
<!-- tarea -->

**Empieza en:** **Menú → «Tablero»**.

**Sin camión la zona no arma ruta.**

1. **Clic en el ⋮** de la cabecera de la zona («Opciones de la columna»).
   <!-- señala: tablero-menu-de-la-zona -->
2. **Clic en «Camión previsto»**. Debajo pone el camión, o **«Sin elegir»**.
   <!-- señala: tablero-camion-previsto -->
3. **Clic en el camión** que va a llevar esa zona.
   <!-- señala: tablero-elegir-camion -->
   - La primera opción es **«Sin camión»**; cada camión sale con su capacidad y su
     matrícula: **«1.000 kg · P-123456»**.
   - La cabecera pasa a poner **«Camión: F-350»**.

Un camión con **«EN EL TALLER»** en ámbar **se puede elegir igual**: es aviso, no
bloqueo.

**Si dice «Esta sucursal no tiene ningún vehículo en este aparato»**, con conexión ve
a **«Vehículos»** y dalo de alta; baja con la siguiente sincronización.

## 3.3 Repartir los pedidos — arrastrando
<!-- tarea -->

**Empieza en:** **Menú → «Tablero»**.

**Aquí se arrastra con el ratón, del tirón.** En el teléfono no se arrastra: se toca
cada tarjeta y se elige la zona en el cajón.

1. **Clic en el embudo** para acotar la mitad izquierda.
   <!-- señala: tablero-sin-colocar-filtros -->
   - Abre **«Día del pedido»**, **«Municipio»**, **«Vendedor»**, **«Hasta cuántos km
     del almacén»** (se aplica al salir del campo o con intro) y **«Cobro del
     domicilio»**.
2. O usa **el buscador** («Cliente, operación, dirección, artículo…»), que **filtra
   mientras escribes**. <!-- señala: tablero-sin-colocar-buscar -->
   - Si pone **«Se ven 200 de 308.»**, clic en **«Ver 108 más»**.
3. **Agarra la tarjeta con el ratón**, arrástrala hasta la zona señalada y
   **suéltala allí**, sin interrumpir el gesto.
   <!-- señala: tablero-tarjeta-de-pedido -->
   <!-- señala: tablero-zona-donde-soltar -->
   - Sobre otra tarjeta: la pone en ese sitio del orden.
   - En el hueco de abajo o **sobre la cabecera**: la pone la última.
   - En la mitad izquierda: la devuelve a «sin colocar».
   - Donde ya estaba: **no hace nada**.
   - Si la zona está vacía, mientras arrastras encima verás **«Suelta aquí»**.
4. **Si prefieres no arrastrar**, clic en la tarjeta.
   <!-- señala: tablero-tarjeta-de-pedido -->
5. En el cajón, baja hasta la lista de zonas y **clic en «Colocar en «Centro»»**.
   <!-- señala: tablero-colocar-en-la-zona -->
   - Ahí están también **«Subir una posición»**, **«Bajar una posición»** y
     **«Devolver a sin colocar»**.

### Qué mirar mientras repartes

```
Vista Alegre (9)                       ⋮
1.210 kg / 1.000 kg · 41,00 USD   (!) no cabe
Camión: F-350                       sin subir
```

- **«1.210 kg / 1.000 kg»** — lo que llevas **y lo que aguanta el camión**.
- **«no cabe»** en ámbar: te has pasado. La ruta se arma igual, pero alguien dejará
  algo en el almacén.
- **«sin subir»** o **«rechazada»** en ámbar: esa zona tiene trabajo que no ha llegado
  al servidor.

### Las marcas de los pedidos

- **«Archivado en PEDIDO»**, **«Ya va en otra ruta»**, **«Sin cotejar»**, **«Sin
  factura»** — hoy **no salen**.
- **«Cambió en la factura»** en ámbar — **sí sale**, pero el peso ya no es el que era.
- **«sin ubicar»** — sin coordenadas de entrega: **no puede ir en una ruta**.
- **«2 pedidos de este cliente hoy»** — son dos de verdad. **No se juntan.**

## 3.4 Reordenar las zonas
<!-- tarea -->

**Empieza en:** **Menú → «Tablero»**.

**Esto sólo se puede en pantalla grande**, aquí y en la web. En el teléfono no hay
forma: las zonas van una por página y no hay dónde soltar.

Necesitas **al menos dos zonas**. Si sólo tienes una, crea otra antes de empezar.

1. **Agarra la cabecera de la primera zona** —donde está su nombre y su peso—,
   arrástrala hasta la **segunda zona** y **suéltala allí**, sin interrumpir el gesto.
   La primera pasa a la posición de la segunda. Pulsa **«Ya está»** después de soltar.
   <!-- señala: tablero-cabecera-de-la-zona -->
   <!-- señala: tablero-segunda-zona-donde-soltar -->

---

# 4. Armar la ruta
<!-- tarea -->

**Empieza en:** **Menú → «Tablero»**.

1. **Clic en el ⋮** de la zona. <!-- señala: tablero-menu-de-la-zona -->
2. Baja del todo y **clic en «Armar la ruta de esta zona»**.
   <!-- señala: tablero-armar-la-ruta -->
   - El botón pasa a **«Armando…»**.
   - Si sale bien: **«Ruta armada con lo que se puede repartir de «Centro».»** y **la
     aplicación salta sola a Rutas**, pestaña «Planificadas», con la ruta ya elegida.

### Si sale un recuadro rojo: «no tiene camión previsto»

> «La zona «Centro» no tiene camión previsto, y sin camión no se arma su ruta»

**El cajón NO se cierra.** Clic ahí mismo en **«Camión previsto»**, elige, y luego
**«Volver a intentarlo»**.

### Si dice «La columna no tiene ningún pedido que se pueda repartir hoy»

Debajo te lista por qué se cayó cada uno:

```
SC06-1257 · DAYLIS PÉREZ: Ya va en otra ruta
X-2992 · ANA MARTÍNEZ: Sin cotejar
```

### El nombre de la ruta

Con conexión nace con su código: **`RT-20260928-004`**.

**Sin conexión** nace como **`local-3df93810`** y **se convierte en su `RT-…` en
cuanto suba**. Es normal y no hay que hacer nada.

---

# 5. Sacar el pre-despacho
<!-- tarea -->

**Empieza en:** **Menú → «Pedidos»**.

1. **Filtra** para dejar los de tu ruta — por **«Municipio»**, por ejemplo.
   <!-- señala: pedidos-filtro-municipio -->
2. **Marca los pedidos** con la casilla de la cabecera («Elegir todos los de esta
   página»), o con la de cada uno. <!-- señala: pedidos-marcar-todos -->
   - Aparece la franja azul **«7 pedido(s) elegidos»**.
3. **Clic en el botón del pre-despacho** (icono de caja). Se abre el cajón con el
   resumen: <!-- señala: pedidos-pre-despacho-de-lo-filtrado -->

   ```
   15 producto(s) · 10197 empaques · ≥ 17318.8 kg (462 renglones sin peso)
   ```

   **El `≥` no es un error:** pesa **por lo menos** eso; hay 462 renglones sin peso
   conocido. Con eso se carga el camión; lo que no se puede es firmar el peso exacto.

   - **Clic en «Ver e imprimir»** para la **«Hoja de pre-despacho»**, con su columna
     **«Sacado»** en blanco.

---

# 6. Iniciar la ruta y mandársela al chófer
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

1. **Clic en la tarjeta de tu ruta.** Ves **la lista a la izquierda y el detalle a la
   derecha**: no hay cajón que abrir, como en el teléfono.
   <!-- señala: rutas-tarjeta-de-ruta -->
   - Comprueba la línea de datos:

   ```
   Planificada · 68.0 km (incl. regreso) · 516 kg · $5212.78 · Camión 1 · P-001 ·
   libre · 28/9/2026 · Carga total: 3
   ```

2. **Clic en «Ver paradas (3)»** si quieres repasar el orden antes de salir.
   <!-- señala: rutas-ver-paradas -->
3. **Clic en «Iniciar ruta»**. <!-- señala: rutas-iniciar -->
   - Pasa a **«En curso»**, **el camión queda ocupado**, y la vista salta a esa
     pestaña.

## Mandarle el recorrido
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

1. Baja hasta **«Recorrido»** y **clic en «Abrir en Google Maps»** para verlo tú.
   <!-- señala: rutas-abrir-en-google-maps -->
2. **Clic en «WhatsApp»** para mandárselo al chófer. <!-- señala: rutas-whatsapp -->
3. **«Compartir»**, si lo quieres por otro sitio. <!-- señala: rutas-compartir -->
4. O **«Copiar»**, y lo pegas tú. <!-- señala: rutas-copiar -->

**Esto necesita conexión.**

Si copias: **«Copiado. Ya se puede pegar en un chat.»**

En Linux, **«Compartir» puede no ofrecer nada**, y la aplicación lo dice: «Este
aparato no ofreció ningún modo de compartir. Con «Copiar» el enlace queda en el
portapapeles.» **Usa «Copiar».**

---

# 7. Marcar las entregas
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

**Los estados se marcan sólo al completar la ruta. Antes no hay un cierre editable.**

**Esto funciona entero sin conexión.**

1. En la pestaña **«En curso»**, **clic en la ruta**.
   <!-- señala: rutas-tarjeta-de-ruta -->
2. **Clic en «Marcar como completada»**. Aquí se abre la hoja para marcar los estados.
   <!-- señala: rutas-completar -->
3. Por cada parada, **clic en «Entregado»**, **«Devuelto»** o **«Cancelado»**.
   <!-- señala: rutas-resultado-de-la-parada -->
   - Si marcas devuelto o cancelado, **escribe el motivo** en el campo que aparece.
   - **Volver a hacer clic en el mismo botón lo desmarca.**
   - Si la ruta entera fue igual, arriba hay atajos: **«Todas:»** y los tres botones.
   - Baja hasta **«Queda en el camión»**, que se recalcula con cada marca: **«Nada: se
     entregó todo lo que salió.»** o la lista, **«MALTA GUAJIRA ×36»**.
4. **Clic en «Guardar y completar»**. <!-- señala: rutas-guardar-el-cierre -->

Al confirmar, la ruta pasa al Historial y el camión queda libre.

**Si dejas paradas sin marcar:** «3 sin marcar · cuentan como que siguen en el
camión».

**Si sales sin guardar**, el botón pasa a **«Salir sin guardar (3 sin guardar)»**. No
te bloquea, pero te lo dice.

---

# 8. Cerrar la ruta
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

1. **Clic en «Marcar como completada»**. <!-- señala: rutas-completar -->
   - **Siempre abre primero la hoja de estados**, aunque hubiera marcas anteriores:

   > «Lo que dejes sin marcar se da por no entregado y cuenta como que sigue en el
   > camión.»

2. Márcalas y **clic en «Guardar y completar»**. Revisa las marcas antes de confirmar. <!-- señala: rutas-guardar-el-cierre -->
   - **La ruta se va al «Historial»**, el camión queda libre, y los pedidos no
     entregados **vuelven a estar disponibles**.

## Sacar el post-despacho
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

1. Abre la ruta en **«Historial»**. <!-- señala: rutas-tarjeta-de-ruta -->
2. **Clic en «Ver cierre»**. <!-- señala: rutas-cierre -->
3. Abajo, **clic en «Post-despacho»**: «8 entregadas · 2 devueltas · 1 canceladas · 1
   sin marcar». <!-- señala: rutas-post-despacho -->
   - Lleva **«Tiene que quedar en el camión»** (con la columna **«Bajó»** en blanco
     para contar a mano) y **«De quién es lo que vuelve»**.

**Una ruta completada ya no se toca.** El cierre pasa a sólo lectura: «Para corregir
algo, hay que hacerlo en PEDIDO.»

---

# 9. Entregar el día

**Con conexión.**

1. **Mira la franja.** Si pone **«23 sin subir»** en ámbar, tienes trabajo aquí que no
   ha llegado al servidor.
2. **Casi nunca hace falta hacer nada**: en cuanto vuelve la red sube solo, en unos
   segundos. Espera y mira otra vez.
3. Para asegurarte, **clic en «23 sin subir»** (o clic en la franja y luego en el botón
   de la nube con la flecha hacia arriba).
4. **Clic en «Entregar el día»** (o **«Entregar lo que queda»**).
5. Te va diciendo: «Subiendo lo que hiciste…», «Subido. Ahora trayendo lo nuevo...».
6. Al terminar: **«Todo entregado»**, y la franja pasa a **«Todo al día»**.

### Si el botón está apagado

- **«Sin conexión con el servidor»** — no hay red.
- **«Trae el día primero: no se envía nada sin tener lo de ahora»** — trae el día y
  vuelve. Es a propósito.

---

# 10. Cuadrar la caja
<!-- tarea -->

**Empieza en:** **Menú → «Reportes»**.

1. **Menú → «Reportes».** <!-- señala: menu-reportes -->
2. **Lee lo que dice encima de las pestañas**: «Cuadrado con los datos del aparato, del
   28/9/2026, 10:36. Con conexión sale el del servidor.»
   **Si sale el aviso ámbar de que los datos tienen más de un día, esto no sirve para
   cerrar.** Trae el día primero. <!-- señala: informes-advertencia -->
3. Pon **«Desde»**, **«Hasta»** y, si quieres, un **«Vehículo»**.
   <!-- señala: informes-desde -->
4. Mira **«Resumen»**, **«Por Vehículo»** y **«Detalle de Órdenes»**.
   <!-- señala: informes-pestanas -->
5. **Clic en «Exportar a Excel»**. Mientras lo arma dice **«Armando el Excel...»** y
   al terminar te dice **dónde lo dejó**: <!-- señala: informes-exportar -->

   > «Excel guardado en /home/jose/Descargas/reporte-procovar-2026-09-28.xlsx»

**En el escritorio el fichero se guarda en la carpeta de descargas**, no se abre
ningún cajón de compartir (en Linux eso no existe).

---

# 11. Antes de apagar

1. **La franja dice «Todo al día».** Si dice «23 sin subir», conéctate y espera.
2. **No sale «Sólo en este aparato: …»** en la franja. Si sale, eso **no va a subir
   solo**: avisa a la oficina.
3. **No cierres sesión con trabajo sin subir.** Si lo haces, te avisa:

   > **Queda trabajo sin subir** — Hay 3 apuntes sin subir al servidor. Salir NO los
   > borra: se quedan en este aparato hasta que vuelvas a entrar. Pero nadie los ve
   > hasta que suban. Si puedes, conecta y espera.

   Clic en **«Me quedo»**, conecta, y sal después.

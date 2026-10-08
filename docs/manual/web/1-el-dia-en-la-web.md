# El día, de principio a fin

Esto es el día entero, paso a paso. Cada paso dice **dónde hacer clic** y **qué
tienes que ver después**.

---

# 1. Entrar

1. Abre el navegador y entra en **reparto.procovar.cloud**.
2. Normalmente **no tienes que escribir nada**: la página te lleva sola al acceso
   único de Procovar y verás «Entrando con tu cuenta de Procovar…».
3. Si ya estabas dentro en otra aplicación de la casa, entras directo.
4. **Si el acceso único falla**, sale el formulario con **«Usuario o correo»** y
   **«Contraseña»**, y el botón **«Entrar»**.

### Si sale un recuadro ámbar

> **No se pudo entrar con tu cuenta de Procovar.**

Debajo está el motivo. Los más comunes:

| Motivo | Qué hacer |
|---|---|
| **«El servidor del reparto no contesta. La página cargó, así que conexión hay…»** | Haz clic en **«Volver a intentarlo»**. Si sigue, avisa a la oficina |
| **«No se pudo conectar con Accesos. Vuelve a probar en un momento…»** | Lo mismo |
| **«El acceso con la cuenta de Procovar todavía no está configurado en este servidor.»** | Avisa a quien lleva el sistema |
| **«La vuelta desde Accesos llegó incompleta. Vuelve a probar.»** | **«Volver a intentarlo»** |

### Si dice que el navegador no guarda la sesión

> «Puede ser una ventana privada o el navegador con los datos del sitio bloqueados.
> Ábrelo en una ventana normal y vuelve a entrar.»

Ciérralo y ábrelo en una ventana normal.

---

# 2. Comprobar la sucursal
<!-- tarea -->

**Empieza en:** la barra de arriba, desde cualquier pantalla.

**Esto es lo primero, todos los días.**

1. Mira **arriba a la derecha**, a la izquierda de tu avatar. Hay una pastilla con la
   sucursal: **«Santiago (STG)»**. <!-- señala: barra-sucursal -->
2. Si no es la que quieres y tu rol te lo permite, **haz clic en ella** y elige de la
   lista. La primera opción es **«Todas las sucursales (8)»**.
   <!-- señala: barra-elegir-sucursal -->

**Todas las pantallas enseñan lo de esa sucursal.** Si un pedido «no aparece», casi
siempre es esto.

Sólo `DESARROLLADOR` y `SUPER ADMIN` pueden cambiarla. Los otros cinco roles tienen
la suya fija, y no es un fallo.

**Al lado está el selector de moneda**, **«USD»** o **«CUP»**. La opción de CUP lleva
la tasa: «1 USD = 320 · del 9/9/2026». Si esa sucursal no tiene tasa, **no se ofrece
CUP** y la pastilla se queda en ámbar poniendo «USD».

---

# 3. Mirar cómo viene el día: el Panel

1. En el **menú de la izquierda**, haz clic en **«Panel»**.
2. Mira las cuatro cifras de arriba:
   - **«Pedidos sin ruta»**, y debajo «1.240 kg por mover»
   - **«Rutas en marcha»** — los camiones que están fuera ahora mismo
   - **«Entregados hoy»**
   - **«Vehículos»**, «3 / 8» (en ruta sobre el total)
3. Abajo a la izquierda, **«Pendiente por sucursal»**: una fila por sucursal con su
   peso y sus pedidos, **ordenadas de más a menos**. Por ahí se empieza.
4. Abajo a la derecha, **«Acciones Rápidas»**: **«Planificar Rutas»**, **«Ver
   Reportes»** y **«Gestionar Flota»**.

### Si arriba sale «Falta configurar esta sucursal»

**Léelo antes de seguir: sin eso no vas a poder armar una ruta.**

Te dice cuántos pasos van («2 de 4») y qué falta. Dos de ellos tienen botón y dos
no:

| Falta | Qué hacer |
|---|---|
| **«Al menos un vehículo»** | Clic en **«Agregar el primer vehículo»** |
| **«Al menos un almacén con su punto puesto»** | Clic en **«Poner el almacén»** |
| **«El punto de partida de la sucursal»** | **No se pone aquí.** «Pídelo a administración y baja solo con el día.» |
| **«La tasa de cambio de la sucursal»** | **No se pone aquí.** «La mantiene Accesos, que la trae de Entrega.» |

Con varias sucursales a la vista, un paso sólo cuenta como hecho **si lo está en
todas**, y te dice en cuáles falta: «Falta en 2 de las 8 sucursales: Granma y Las
Tunas.»

---

# 4. Armar las zonas en el Tablero

**Éste es el trabajo del día. Así se arma: por zonas, y de cada zona sale una
ruta.**

1. En el **menú de la izquierda**, clic en **«Tablero»**.
2. **En la web ves las dos mitades a la vez**: a la izquierda **«Sin colocar (308)»**
   y a la derecha la tira de zonas.
3. **Comprueba arriba desde dónde se mide**: **«Granma · desde Bayamo (Granma)»**. Si
   hay más de un almacén sale una flechita ▾: haz clic y elige. Ese punto decide los
   kilómetros de cada tarjeta y lo que se cobra.
4. **Mira los avisos rojos** si los hay: «3 archivados en PEDIDO», «2 ya en otra
   ruta», «5 sin factura o sin cotejar». Son pedidos **ya colocados** que hoy no
   salen.

## 4.1 Crear una zona
<!-- tarea -->

**Empieza en:** **Menú → «Tablero»**.

1. Al final de la tira de zonas, a la derecha, **haz clic en el recuadro con un `+`
   que pone «Columna»**. <!-- señala: tablero-nueva-zona -->
   - Se abre un cajón **«Nueva columna»** con el campo **«Nombre de la zona»** y el
     ejemplo «Centro, Vista Alegre, Carretera…».
   - **Aquí no hay carrusel que pasar**: «Sin colocar» y la tira de zonas están las
     dos a la vista.
2. **Escribe el nombre de tu zona** en «Nombre de la zona».
   <!-- señala: tablero-nombre-de-la-zona -->
3. **Haz clic en «Guardar»** (o dale a intro). La zona aparece en la tira.
   <!-- señala: tablero-guardar-la-zona -->

Si ya existe: **«Ya hay una columna «Centro» en este tablero»**.

## 4.2 Ponerle el camión a la zona — HAZLO AHORA
<!-- tarea -->

**Empieza en:** **Menú → «Tablero»**.

**Sin camión la zona no arma ruta.** Hazlo antes de repartir los pedidos.

1. En la cabecera de la zona, arriba a la derecha, **haz clic en el icono de tres
   puntos ⋮** («Opciones de la columna»). <!-- señala: tablero-menu-de-la-zona -->
2. Se abre un cajón con el nombre de la zona. **Haz clic en «Camión previsto»**.
   Debajo pone el camión, o **«Sin elegir»**.
   <!-- señala: tablero-camion-previsto -->
3. **Haz clic en el camión** que va a llevar esa zona.
   <!-- señala: tablero-elegir-camion -->
   - La primera opción es **«Sin camión»**; cada camión sale con su capacidad y su
     matrícula: **«1.000 kg · P-123456»**.
   - La cabecera de la zona pasa a poner **«Camión: F-350»**.

**Sólo salen los camiones activos y fuera del taller.** Un camión «Inactivo» (dado de
baja) o en mantenimiento no se ofrece para rutas nuevas; si no te sale, mira su
tarjeta en **Menú → «Vehículos»**.

## 4.3 Repartir los pedidos — arrastrando
<!-- tarea -->

**Empieza en:** **Menú → «Tablero»**.

**En la web se arrastra con el ratón, del tirón.** No se va tocando tarjeta por
tarjeta: eso es el teléfono, que no tiene las dos mitades a la vez.

1. **Haz clic en el icono del embudo** para acotar lo que vas a repartir.
   <!-- señala: tablero-sin-colocar-filtros -->
   - Los filtros son **«Día del pedido»**, **«Municipio»**, **«Vendedor»**, **«Hasta
     cuántos km del almacén»** (se aplica al salir del campo o con intro) y **«Cobro
     del domicilio»**. Para quitarlos, **«Quitar todos los filtros»**.
2. O usa **el buscador**, que dice «Cliente, operación, dirección, artículo…» y
   **filtra mientras escribes**. <!-- señala: tablero-sin-colocar-buscar -->
   - Si pone **«Se ven 200 de 308.»**, haz clic en **«Ver 108 más»**.
3. **Agarra la tarjeta del pedido** en la mitad izquierda, arrástrala hasta la zona
   señalada de la derecha y **suéltala allí**, sin interrumpir el gesto.
   <!-- señala: tablero-tarjeta-de-pedido -->
   <!-- señala: tablero-zona-donde-soltar -->
   - Suéltala **sobre otra tarjeta** para ponerla en ese sitio del orden.
   - Suéltala en **el hueco de abajo** o **sobre la cabecera** para ponerla la última.
   - Suéltala **en la mitad izquierda** para devolverla a «sin colocar».
   - Soltarla donde ya estaba **no hace nada**.
   - Si la zona está vacía, mientras arrastras encima verás **«Suelta aquí»**.
4. **Si prefieres no arrastrar**, haz clic en la tarjeta.
   <!-- señala: tablero-tarjeta-de-pedido -->
   - Se abre el mismo cajón del pedido que en el teléfono.
5. En ese cajón, baja hasta la lista de zonas y **haz clic en «Colocar en «Centro»»**.
   <!-- señala: tablero-colocar-en-la-zona -->
   - Ahí mismo están **«Subir una posición»**, **«Bajar una posición»** y **«Devolver
     a sin colocar»**, que en el teléfono son la única vía.

### Qué mirar mientras repartes

La cabecera de cada zona:

```
Vista Alegre (9)                       ⋮
1.210 kg / 1.000 kg · 41,00 USD   (!) no cabe
Camión: F-350
```

- **«1.210 kg / 1.000 kg»** — lo que llevas **y lo que aguanta el camión**.
- **«no cabe»** en ámbar: te has pasado. La ruta se arma igual, pero alguien va a
  tener que dejar algo. Saca pedidos o cambia de camión.

### Las marcas de los pedidos

- **«Archivado en PEDIDO»**, **«Ya va en otra ruta»**, **«Sin cotejar»**, **«Sin
  factura»** — hoy **no salen**. Los puedes dejar puestos: no entrarán en la ruta y te
  lo dirá.
- **«Cambió en la factura»** en ámbar — **tampoco sale**: en el camión sólo sube lo que
  cuadra con la factura. La ruta lo descartará con «cambió en la factura».
- **Sin domicilio cobrado o sin cotizar** — esos pedidos **ni salen en «Sin colocar»**, y
  si intentas colocarlos te lo rechaza con su motivo («No se puede asociar al tablero:
  la factura no tiene un cobro de domicilio registrado.» / «…primero cotiza el domicilio
  del pedido.»). Ver [Tablero](../comun/pantallas/tablero.md#qué-se-puede-colocar-en-una-zona).
- **«sin ubicar»** en vez de los kilómetros — ese pedido no tiene coordenadas de
  entrega y **no puede ir en una ruta**.
- **«2 pedidos de este cliente hoy»** — son dos pedidos de verdad. **La aplicación no
  los junta.** Ponlos en la misma zona a propósito.

## 4.4 Reordenar las zonas
<!-- tarea -->

**Empieza en:** **Menú → «Tablero»**.

**Esto sólo se puede en pantalla grande**, aquí y en el escritorio. En el teléfono no
hay forma: las zonas van una por página y no hay dónde soltar.

Necesitas **al menos dos zonas**. Si sólo tienes una, crea otra antes de empezar.

1. **Agarra la cabecera de la primera zona** —donde está su nombre y su peso—,
   arrástrala hasta la **segunda zona** y **suéltala allí**, sin interrumpir el gesto.
   La primera pasa a la posición de la segunda. Pulsa **«Ya está»** después de soltar.
   <!-- señala: tablero-cabecera-de-la-zona -->
   <!-- señala: tablero-segunda-zona-donde-soltar -->

---

# 5. Armar la ruta
<!-- tarea -->

**Empieza en:** **Menú → «Tablero»**.

1. **Clic en el ⋮** de la cabecera de la zona.
   <!-- señala: tablero-menu-de-la-zona -->
2. Baja del todo en el cajón y **haz clic en «Armar la ruta de esta zona»**.
   <!-- señala: tablero-armar-la-ruta -->
   - El botón pasa a **«Armando…»**.
   - Si sale bien: una franja dice **«Ruta armada con lo que se puede repartir de
     «Centro».»** y **la aplicación salta sola a Rutas**, pestaña
     **«Planificadas»**, con la ruta ya elegida.

**En la web la ruta la crea el servidor al momento**, así que ya nace con su código
de verdad: **`RT-20260928-004`**.

### Si sale un recuadro rojo: «no tiene camión previsto»

> «La zona «Centro» no tiene camión previsto, y sin camión no se arma su ruta»

**El cajón NO se cierra.** Haz clic ahí mismo en **«Camión previsto»**, elige el
camión, y después en **«Volver a intentarlo»**.

### Si dice «La columna no tiene ningún pedido que se pueda repartir hoy»

Debajo te lista, uno a uno, por qué se cayó cada pedido:

```
PTB25-261005-1480 · DAYLIS PÉREZ: Ya va en otra ruta
PTB25-261005-1502 · ANA MARTÍNEZ: cambió en la factura
PTB25-261005-1511 · LUIS PÉREZ: la factura no tiene domicilio cobrado
PTB25-261005-1523 · MARTA CRUZ: domicilio sin cotizar
```

Cada pedido sale por su **conduce** (el número de operación de la factura).

### Qué entra y qué no

**Sólo entran los pedidos repartibles** (facturados que cuadran, con el domicilio
cobrado y cotizado). Los que no, **se quedan en la zona y marcados**. No desaparece
nada.

**Si luego borras la ruta, las facturas vuelven a su zona** al instante (en la web no
hay espera): no hay que volver a crear la zona ni repartir de nuevo.

**El orden que dejaste es el que va.** La aplicación no lo reordena.

---

# 6. Sacar el pre-despacho
<!-- tarea -->

**Empieza en:** **Menú → «Pedidos»**.

Es la hoja del almacén: **qué hay que sacar de cada producto**.

1. **Filtra** para dejar los de tu ruta — por **«Municipio»**, por ejemplo.
   <!-- señala: pedidos-filtro-municipio -->
2. **Marca los pedidos**: clic en la casilla de la cabecera («Elegir todos los de esta
   página»), o en la de cada uno. <!-- señala: pedidos-marcar-todos -->
   - Aparece una franja azul: **«7 pedido(s) elegidos»**.
3. **Clic en el botón del pre-despacho** (el del icono de caja). Se abre el cajón
   **«Pre-despacho»** con el resumen arriba:
   <!-- señala: pedidos-pre-despacho-de-lo-filtrado -->

   ```
   15 producto(s) · 10197 empaques · ≥ 17318.8 kg (462 renglones sin peso)
   ```

   **Ese `≥` no es un error.** Quiere decir «pesa **por lo menos** esto»: hay 462
   renglones sin peso conocido. Con eso se carga el camión; lo que no se puede es
   firmar que ése es el peso exacto.
   - Debajo, la tabla **«Producto» | «Empaques» | «Unidades» | «kg»** y los cuatro
     totales.
   - **Clic en «Ver e imprimir»**: se abre la **«Hoja de pre-despacho»** con el PDF,
     con su columna **«Sacado»** en blanco.

**También puedes sacarlo de lo filtrado sin marcar nada**: hay un botón
**«Pre-despacho»** en la misma fila que las fechas. **La suma se hace al pulsarlo.**

---

# 7. Iniciar la ruta y mandársela al chófer
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

1. **Haz clic en la tarjeta de tu ruta.** En la web **la lista va a la izquierda y el
   detalle a la derecha**: no hay cajón que abrir, como en el teléfono.
   <!-- señala: rutas-tarjeta-de-ruta -->
   - Comprueba la línea de datos del detalle:

   ```
   Planificada · 68.0 km (incl. regreso) · 516 kg · $5212.78 · Camión 1 · P-001 ·
   libre · 28/9/2026 · Carga total: 3
   ```

2. **Clic en «Ver paradas (3)»** si quieres repasar el orden antes de salir.
   <!-- señala: rutas-ver-paradas -->
3. **Clic en «Iniciar ruta»**. <!-- señala: rutas-iniciar -->
   - La ruta pasa a **«En curso»**, **el camión queda ocupado**, y la vista **salta
     sola a la pestaña «En curso»**.

## Mandarle el recorrido al chófer
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

1. Baja hasta el bloque **«Recorrido»** y **clic en «WhatsApp»** para mandárselo al
   chófer. <!-- señala: rutas-whatsapp -->
2. O **«Copiar»**, si prefieres pegarlo tú. <!-- señala: rutas-copiar -->

Sale un mensaje así:

   ```
   Ruta RT-20260928-001 — Reparto Vista
   3 paradas · 68.0 km (incl. regreso) · Camión 1 (P-001) · 28/9/2026
   https://www.google.com/maps/dir/?api=1&origin=...
   ```

Si copias, verás: **«Copiado. Ya se puede pegar en un chat.»**

### Si dice «Google admite 25 paradas: 3 paradas quedan fuera»

El enlace no admite más. Las tres últimas hay que decírselas aparte.

---

# 8. Seguir la ruta y marcar las entregas
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

Los estados se marcan **al pulsar «Marcar como completada»**, al terminar el reparto.
Antes no hay un cierre editable. **Desde la web se hace igual que en el teléfono**.

1. En la pestaña **«En curso»**, **haz clic en tu ruta**.
   <!-- señala: rutas-tarjeta-de-ruta -->
2. **Clic en «Marcar como completada»**. Aquí se abre la hoja para marcar los estados.
   <!-- señala: rutas-completar -->
3. Por cada parada, **clic en uno de los tres botones**: **«Entregado»**,
   **«Devuelto»** o **«Cancelado»**.
   <!-- señala: rutas-resultado-de-la-parada -->
   - Si marcas devuelto o cancelado, **escribe el motivo** en el campo que aparece:
     «¿Por qué volvió? (el cliente cerró, no lo quiso, no había nadie…)».
   - **Volver a hacer clic en el mismo botón lo desmarca**, por si te equivocas.
   - Baja hasta **«Queda en el camión»**: se recalcula con cada marca.
4. **Clic en «Guardar y completar»**. <!-- señala: rutas-guardar-el-cierre -->

Al confirmar, la ruta pasa al Historial y el camión queda libre.

**Si el servidor guarda unas paradas y rechaza otras**, lo guardado vale: el aviso, en
la franja de abajo, dice el motivo («Se guardaron 1 de las 2 paradas de esta hoja. 1 no
se pudieron guardar: … (ese pedido no va en esta ruta).») y la ruta se puede completar.
Si no se guardó **ninguna**, no se completa. Cada parada lleva su **conduce**
(«Conduce: PTB25-261005-1480»), el número de operación de la factura, para encontrarla.

---

# 9. Cerrar la ruta
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

1. En el detalle, **clic en «Marcar como completada»**.
   <!-- señala: rutas-completar -->
   - **Siempre abre primero la hoja de estados**, aunque hubiera marcas anteriores:

   > «Antes de dar la ruta por completada: ¿cómo acabó cada parada? Lo que dejes sin
   > marcar se da por no entregado y cuenta como que sigue en el camión.»

2. Márcalas y **clic en «Guardar y completar»**. Revisa las marcas antes de confirmar. <!-- señala: rutas-guardar-el-cierre -->
   - **La ruta se va al «Historial»**, el camión queda libre, y los pedidos no
     entregados **vuelven a estar disponibles**.

## Sacar el post-despacho
<!-- tarea -->

**Empieza en:** **Menú → «Rutas»**.

1. Abre la ruta en la pestaña **«Historial»**.
   <!-- señala: rutas-tarjeta-de-ruta -->
2. **Clic en «Ver cierre»**. <!-- señala: rutas-cierre -->
3. Abajo, **clic en «Post-despacho»**. <!-- señala: rutas-post-despacho -->
   - Sale la hoja con **«8 entregadas · 2 devueltas · 1 canceladas · 1 sin marcar»**,
     la sección **«Tiene que quedar en el camión»** con su columna **«Bajó»** en
     blanco, y **«De quién es lo que vuelve»**.

## Una ruta completada ya no se toca

El botón es **«Ver cierre»** y es **sólo lectura**: sin botones de resultado y sin
botón de guardar.

> «La ruta ya está completada: así acabó cada parada. **Para corregir algo, hay que
> hacerlo en PEDIDO.**»

---

# 10. Cuadrar la caja
<!-- tarea -->

**Empieza en:** **Menú → «Reportes»**.

1. **Menú → «Reportes».** <!-- señala: menu-reportes -->
2. **Lee lo que dice encima de las pestañas**: «Cuadrado con lo último que bajó, de
   las 10:36.» <!-- señala: informes-advertencia -->
   - **Si sale el aviso ámbar de que los datos tienen más de un día**, el informe no
     cuadra y no sirve para cerrar. Aquí **no se arregla conectándose** —ya lo
     estás—: «Recarga la página y, si sigue igual, avisa a la oficina.»
3. Pon **«Desde»**, **«Hasta»** y, si quieres, un **«Vehículo»**.
   <!-- señala: informes-desde -->
4. Mira las tres pestañas: **«Resumen»**, **«Por Vehículo»** y **«Detalle de
   Órdenes»**. <!-- señala: informes-pestanas -->
5. **Clic en «Exportar a Excel»**. El navegador lo descarga: **«Se descargó
   reporte-procovar-2026-09-28.xlsx»**. <!-- señala: informes-exportar -->

**Si sale «— (3 sin cotizar)» en vez de un total, no es un fallo**: faltan importes y
no se suma lo que no se sabe. Debajo te dice cuántos: «Faltan cotizar 3 órdenes: sin
ellas no hay total.»

---

# 11. Al terminar

En la web **no hay nada que subir**: todo lo que hiciste ya está en el servidor.

Lo único que hay que mirar: **si en algún momento te salió un aviso de que el
servidor rechazó un cambio, resuélvelo antes de irte.** En la web esos cambios **no
se quedan en cola**: si cierras la pestaña, se pierden.

Y al cerrar sesión, si queda algo sin guardar:

> **Hay cambios sin guardar** — Hay 3 cambios que no llegaron al servidor. Si sales
> ahora se pierden. Vuelve a intentarlo desde la pantalla donde los hiciste.

Haz clic en **«Me quedo»**, arréglalo, y sal después.

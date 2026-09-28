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

**Esto es lo primero, todos los días.**

1. Mira **arriba a la derecha**, a la izquierda de tu avatar. Hay una pastilla con la
   sucursal: **«Santiago (STG)»**.
2. Si no es la que quieres y tu rol te lo permite, **haz clic en ella** y elige de la
   lista. La primera opción es **«Todas las sucursales (8)»**.

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

1. Al final de la tira de zonas, a la derecha, hay un recuadro con un `+` que pone
   **«Columna»**. **Haz clic.**
2. Se abre un cajón **«Nueva columna»** con el campo **«Nombre de la zona»** y el
   ejemplo «Centro, Vista Alegre, Carretera…».
3. Escribe el nombre y **haz clic en «Guardar»** (o dale a intro).
4. La zona aparece en la tira.

Si ya existe: **«Ya hay una columna «Centro» en este tablero»**.

## 4.2 Ponerle el camión a la zona — HAZLO AHORA

**Sin camión la zona no arma ruta.** Hazlo antes de repartir los pedidos.

1. En la cabecera de la zona, arriba a la derecha, **haz clic en el icono de tres
   puntos ⋮** («Opciones de la columna»).
2. Se abre un cajón con el nombre de la zona. **Haz clic en «Camión previsto»**.
   Debajo pone el camión, o **«Sin elegir»**.
3. Elige de la lista. La primera opción es **«Sin camión»**; cada camión sale con su
   capacidad y su matrícula: **«1.000 kg · P-123456»**.
4. La cabecera de la zona pasa a poner **«Camión: F-350»**.

Un camión en el taller sale con **«EN EL TALLER»** en ámbar. **Se puede elegir
igual**: es aviso, no bloqueo.

## 4.3 Repartir los pedidos — arrastrando

**En la web se arrastra con el ratón, del tirón.**

1. En la mitad izquierda, **acota lo que vas a repartir**:
   - **El buscador** dice «Cliente, operación, dirección, artículo…» y **filtra
     mientras escribes**.
   - **El icono del embudo** abre los filtros: **«Día del pedido»**, **«Municipio»**,
     **«Vendedor»**, **«Hasta cuántos km del almacén»** (se aplica al salir del campo o
     con intro) y **«Cobro del domicilio»**. Para quitarlos, **«Quitar todos los
     filtros»**.
   - Si pone **«Se ven 200 de 308.»**, haz clic en **«Ver 108 más»**.
2. **Arrastra la tarjeta** desde la izquierda hasta la zona de la derecha:
   - Suéltala **sobre otra tarjeta** para ponerla en ese sitio del orden.
   - Suéltala en **el hueco de abajo** o **sobre la cabecera** para ponerla la última.
   - Suéltala **en la mitad izquierda** para devolverla a «sin colocar».
   - Soltarla donde ya estaba **no hace nada**.
3. Si la zona está vacía, mientras arrastras encima verás **«Suelta aquí»**.

**También puedes hacer clic en la tarjeta** y elegir la zona en el cajón que se abre,
si prefieres no arrastrar.

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
- **«Cambió en la factura»** en ámbar — **sí sale**, pero el peso de la zona ya no es
  el que era.
- **«sin ubicar»** en vez de los kilómetros — ese pedido no tiene coordenadas de
  entrega y **no puede ir en una ruta**.
- **«2 pedidos de este cliente hoy»** — son dos pedidos de verdad. **La aplicación no
  los junta.** Ponlos en la misma zona a propósito.

## 4.4 Reordenar las zonas

**Arrastra la cabecera de una zona** sobre otra: se cambian de sitio. Esto sólo se
puede en pantalla grande.

---

# 5. Armar la ruta

1. **Clic en el ⋮** de la cabecera de la zona.
2. Baja del todo en el cajón y **haz clic en «Armar la ruta de esta zona»**.
3. El botón pasa a **«Armando…»**.
4. Si sale bien: una franja dice **«Ruta armada con lo que se puede repartir de
   «Centro».»** y **la aplicación salta sola a Rutas**, pestaña **«Planificadas»**, con
   la ruta ya elegida.

**En la web la ruta la crea el servidor al momento**, así que ya nace con su código
de verdad: **`RT-20260928-004`**.

### Si sale un recuadro rojo: «no tiene camión previsto»

> «La zona «Centro» no tiene camión previsto, y sin camión no se arma su ruta»

**El cajón NO se cierra.** Haz clic ahí mismo en **«Camión previsto»**, elige el
camión, y después en **«Volver a intentarlo»**.

### Si dice «La columna no tiene ningún pedido que se pueda repartir hoy»

Debajo te lista, uno a uno, por qué se cayó cada pedido:

```
SC06-1257 · DAYLIS PÉREZ: Ya va en otra ruta
X-2992 · ANA MARTÍNEZ: Sin cotejar
```

### Qué entra y qué no

**Sólo entran los pedidos repartibles.** Los que no, **se quedan en la zona y
marcados**. No desaparece nada.

**El orden que dejaste es el que va.** La aplicación no lo reordena.

---

# 6. Sacar el pre-despacho

Es la hoja del almacén: **qué hay que sacar de cada producto**.

1. **Menú → «Pedidos».**
2. **Filtra** para dejar los de tu ruta.
3. **Marca los pedidos**: clic en la casilla de cada uno, o en la casilla de la
   cabecera («Elegir todos los de esta página»).
4. Aparece una franja azul: **«7 pedido(s) elegidos»**.
5. **Clic en el botón del pre-despacho** (el del icono de caja).
6. Se abre el cajón **«Pre-despacho»** con el resumen arriba:

   ```
   15 producto(s) · 10197 empaques · ≥ 17318.8 kg (462 renglones sin peso)
   ```

   **Ese `≥` no es un error.** Quiere decir «pesa **por lo menos** esto»: hay 462
   renglones sin peso conocido. Con eso se carga el camión; lo que no se puede es
   firmar que ése es el peso exacto.
7. Debajo, la tabla **«Producto» | «Empaques» | «Unidades» | «kg»** y los cuatro
   totales.
8. **Clic en «Ver e imprimir»**. Se abre la **«Hoja de pre-despacho»** con el PDF, con
   su columna **«Sacado»** en blanco.

**También puedes sacarlo de lo filtrado sin marcar nada**: hay un botón
**«Pre-despacho»** en la misma fila que las fechas. **La suma se hace al pulsarlo.**

---

# 7. Iniciar la ruta y mandársela al chófer

1. **Menú → «Rutas».**
2. **En la web ves la lista a la izquierda y el detalle a la derecha.** Haz clic en la
   tarjeta de tu ruta.
3. Comprueba la línea de datos del detalle:

   ```
   Planificada · 68.0 km (incl. regreso) · 516 kg · $5212.78 · Camión 1 · P-001 ·
   libre · 28/9/2026 · Carga total: 3
   ```

4. **Clic en «Iniciar ruta»**.
5. La ruta pasa a **«En curso»**, **el camión queda ocupado**, y la vista **salta sola
   a la pestaña «En curso»**.

## Mandarle el recorrido al chófer

1. Baja hasta el bloque **«Recorrido»**.
2. **Clic en «WhatsApp»**, o en **«Copiar»** para pegarlo tú.
3. Sale un mensaje así:

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

Lo normal es que las entregas las marque el repartidor desde el teléfono. **Desde la
web se puede hacer igual**, y en directo: lo que marque él lo ves tú.

1. **Menú → «Rutas»**, pestaña **«En curso»**.
2. Clic en la ruta.
3. **Clic en «Cierre (3)»**. El número son las paradas sin marcar.
4. Por cada parada, **clic en uno de los tres botones**: **«Entregado»**,
   **«Devuelto»** o **«Cancelado»**.
5. Si marcas devuelto o cancelado, **escribe el motivo** en el campo que aparece: «¿Por
   qué volvió? (el cliente cerró, no lo quiso, no había nadie…)».
6. **Volver a hacer clic en el mismo botón lo desmarca**, por si te equivocas.
7. Baja hasta **«Queda en el camión»**: se recalcula con cada marca.
8. **Clic en «Guardar 5 marcada(s)»**.

Verás: **«Cierre guardado. En PEDIDO cada pedido ya dice si se entregó o volvió.»**

---

# 9. Cerrar la ruta

1. En el detalle, **clic en «Marcar como completada»**.
2. Si quedan paradas sin marcar, **te abre el cierre primero**:

   > «Antes de dar la ruta por completada: ¿cómo acabó cada parada? Lo que dejes sin
   > marcar se da por no entregado y cuenta como que sigue en el camión.»

   Márcalas y **clic en «Guardar y completar»**.
3. **La ruta se va al «Historial»**, el camión queda libre, y los pedidos no
   entregados **vuelven a estar disponibles**.

## Sacar el post-despacho

1. Abre la ruta en la pestaña **«Historial»**.
2. **Clic en «Ver cierre»**.
3. Abajo, **clic en «Post-despacho»**.
4. Sale la hoja con **«8 entregadas · 2 devueltas · 1 canceladas · 1 sin marcar»**,
   la sección **«Tiene que quedar en el camión»** con su columna **«Bajó»** en blanco,
   y **«De quién es lo que vuelve»**.

## Una ruta completada ya no se toca

El botón es **«Ver cierre»** y es **sólo lectura**: sin botones de resultado y sin
botón de guardar.

> «La ruta ya está completada: así acabó cada parada. **Para corregir algo, hay que
> hacerlo en PEDIDO.**»

---

# 10. Cuadrar la caja

1. **Menú → «Reportes».**
2. **Lee lo que dice encima de las pestañas**: «Cuadrado con lo último que bajó, de
   las 10:36.»
3. Pon **«Desde»**, **«Hasta»** y, si quieres, un **«Vehículo»**.
4. Mira las tres pestañas: **«Resumen»**, **«Por Vehículo»** y **«Detalle de
   Órdenes»**.
5. **Clic en «Exportar a Excel»**. El navegador lo descarga: **«Se descargó
   reporte-procovar-2026-09-28.xlsx»**.

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

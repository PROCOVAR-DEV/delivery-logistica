> # SÓLO PARA ADMINISTRACIÓN — NO ES PARTE DE LOS MANUALES DE USO
>
> Esta pantalla **no la ve casi nadie**: sólo `DESARROLLADOR` y `SUPER ADMIN`. No sale
> en el menú del logístico, ni en el del repartidor, ni en el del administrador de una
> sucursal, y no debe salir en los manuales que ellos leen.
>
> Jose, 28/09/2026: «ese no lo documentes q es para administracion y es un webhook y solo
> lo puedo ver yo si quieres ponlo pero q solo lo pueda ver yo».
>
> Por eso este fichero vive aparte y **ninguno de los tres manuales enlaza aquí**. Si
> alguien añade un enlace desde `apk/`, `web/`, `escritorio/` o `comun/`, lo está sacando
> del sitio donde Jose lo puso.

# Canal con PEDIDO

**Para qué sirve:** saber si el reparto y PEDIDO se están hablando. Contesta tres
preguntas: **¿respira el canal?**, **¿llega lo que sale?**, **¿se escribe lo que
entra?**

**Dónde está:** **sólo en la web**, y en el menú **sólo para `DESARROLLADOR` y
`SUPER ADMIN`**. Los otros cinco roles no la ven. En la APK y en el escritorio no
existe.

Las palabras están puestas a propósito iguales que en la pantalla equivalente de
PEDIDO —*esperando*, *sin terminar*, *el más viejo*, *último aviso*— para poder
comparar las dos sin traducir nada.

---

## Mirar cómo va el canal con PEDIDO
<!-- tarea -->

**Empieza en:** **Menú → «Canal con PEDIDO»**. **Sólo en la web, y sólo para
`DESARROLLADOR` y `SUPER ADMIN`.**

1. Mira **«El canal con PEDIDO»**, arriba: contesta si el canal respira.
   <!-- señala: canal-respira -->
2. Baja a **«Saliendo»**: lo que el reparto le cuenta a PEDIDO.
   <!-- señala: canal-saliendo -->
3. Y a **«Entrando»**: lo que PEDIDO le cuenta al reparto.
   <!-- señala: canal-entrando -->
4. Si hay algo en **«Sin terminar»**, mira su motivo antes de reintentar nada.
   <!-- señala: canal-sin-terminar -->

## «El canal con PEDIDO»

Tres datos:

- **«Último aviso recibido»** — cuánto hace que entró algo
- **«Última tanda enviada»** — cuánto hace que salió algo
- **«Escritos hoy»** — cuántos

Los tiempos se escriben así: **«nunca»** (que no es lo mismo que «hace mucho»),
«hace 40 s», «hace 6 min», «hace 3 h», «hace 4 días».

**Si algo lleva más de 10 minutos esperando a salir, sale en rojo:**

> «Atascado: hay algo esperando desde hace 6 h. Con el canal sano no pasa de unos
> segundos.»

---

## «Saliendo · lo que el reparto le cuenta a PEDIDO»

Tres datos:

- **«Esperando»** — avisos nuestros que aún no han salido
- **«El más viejo»** — de cuándo es el más antiguo sin mandar. **Éste es el número
  que dice si está atascado**
- **«Rechazados por PEDIDO»** — llegaron perfectamente y PEDIDO dijo que no. **No
  se reintentan**: es una bandeja que alguien tiene que mirar

Debajo, hasta ocho tandas:

```
hace 3 min · 12 avisos · 12 aceptados · HTTP 200 · 148 ms
hace 2 h · 8 avisos · 5 aceptados · 3 no · HTTP 200 · 210 ms
```

Con el motivo de PEDIDO debajo, si lo hay. La línea sale **en rojo** cuando la
respuesta no fue buena.

Si no ha salido ninguna: «Todavía no ha salido ninguna tanda.»

---

## «Entrando · lo que PEDIDO le cuenta al reparto»

```
hace 1 min · por el webhook · 1 avisos · 1 llevaron a algo · 42 ms
```

Los avisos entran por **tres puertas distintas**, y se dicen con palabras:

- **«por el webhook»** — PEDIDO avisa de uno en uno
- **«por la cola»**
- **«por el lote del espejo»** — tandas de 200

**«Sin efecto» no se pinta en rojo**, a propósito: un aviso repetido, o uno que un
borrado posterior anuló, es el sistema haciendo lo correcto, no un fallo.

Si no ha entrado ninguna:

> «Todavía no ha entrado ninguna tanda. Si PEDIDO está avisando y esto sigue vacío,
> mira que el grupo de lectura exista.»

---

## «Sin terminar · 6»

Sale sólo si hay alguno.

> «Lo que no llegó a PEDIDO. Los rechazados NO se reintentan: repetir lo mismo da lo
> mismo, así que se quedan aquí hasta que alguien decida.»

Cada línea:

```
hace 4 h · X-2992 · entregado · rechazado · 3 intentos
```

Y el motivo debajo. Hay **dos situaciones y no son lo mismo**:

- **«pendiente»** — no se pudo ni preguntar. **Se reintenta solo.**
- **«rechazado»** — PEDIDO dijo que no. **No se reintenta.** Sale en rojo.

---

## Los botones y los errores

- **«Volver a mirar»** es el único botón. La pantalla **también se repinta sola**
  cuando el servidor avisa de un cambio: no está preguntando cada rato.
- Si no te toca verla: **«Esta pantalla es del desarrollador.»**
- Cualquier otro fallo: **«No se pudo leer cómo va el canal.»**

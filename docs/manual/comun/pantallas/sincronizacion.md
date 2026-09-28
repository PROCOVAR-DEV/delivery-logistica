# Sincronización

**Para qué sirve:** ver **qué aparato lleva sin subir**, qué le queda pendiente y
qué se le rechazó. Es la pantalla de quien lleva la oficina, no la del repartidor.

**Dónde está:** en el menú **sólo en la APK y en el escritorio**.

En la web la pantalla existe pero no hace nada, y lo dice:

> **Esto es de la aplicación, no de la web**
>
> La sincronización es de la aplicación de Android y de la de escritorio, que son
> las que se quedan sin señal y guardan el trabajo hasta poder subirlo. En el
> navegador no hay ni aparato ni cola: cada cosa que se hace se guarda en el
> servidor al momento, y lo que el servidor rechace se dice ahí mismo, con su
> motivo.

---

## La cabecera

> «Qué aparato lleva sin subir, qué le queda pendiente y qué se le rechazó. Se lee
> del servidor cada vez: aquí no se guarda copia.»

Botón **«Actualizar»**, y debajo: «Leído del servidor a las 9:12.»

Como **se lee del servidor cada vez**, sin señal no hay nada que enseñar, y te lo
dice:

> «Sin conexión: no se puede saber quién lleva sin subir. Esta pantalla se lee del
> servidor y no guarda copia en el aparato, así que no hay nada viejo que enseñar.
> Vuelve a intentarlo cuando haya red.»

---

## Las cuatro cifras de arriba

| Cifra | Debajo | Qué cuenta |
|---|---|---|
| **«Sin subir nunca»** | «Dados de alta y sin una sola subida» | Aparatos que no han subido **jamás**. En rojo si hay alguno |
| **«Más de un día sin subir»** | «Estos son los de llamar» | Aparatos con 24 horas o más sin subir |
| **«Apuntes pendientes»** | «Trabajo hecho que sigue en los teléfonos» | Todo lo que está en cola, sumando todos los aparatos |
| **«Rechazados sin atender»** | «Esperando a que una persona decida» | Rechazos que siguen sin decidir |

---

## La tabla «Aparatos»

Columnas: **«Sin subir» | «Aparato» | «Persona» | «Sucursal» | «Última subida» |
«Pendientes» | «Rechazados»**.

**«Sin subir» va la primera a propósito**, porque es la que se mira. Sus textos:

- **«Nunca ha subido»** (rojo) — no es «lleva cero horas», es que no ha subido
  nunca
- **«Hace menos de una hora»**
- **«Hace 1 hora»** / **«Hace 9 horas»**
- **«Hace 1 día»** / **«Hace 3 días»**

**Las horas las cuenta el servidor**, no el ordenador desde el que miras.

El borde izquierdo de cada fila lleva un color:

- **rojo con nube tachada** — nunca subió
- **rojo con triángulo** — más de 24 horas
- **ámbar** — más de 8 horas. Una jornada: cerró el día y se fue a casa sin subir
- **verde** — al día

El aparato sale por su nombre, o como «Aparato a3f91c02» si no se le puso ninguno.

**El orden es el del servidor: el que lleva más sin subir sale primero.** No se
reordena.

Si no hay ninguno: «No hay ningún aparato dado de alta todavía.»

---

## La bandeja de rechazados

Tarjeta **«Rechazados sin atender (4)»**. Si está vacía:

> «No hay nada rechazado esperando. Lo que se rechace sale aquí con su motivo y su
> hora, y no se va solo.»

Cada rechazo lleva cuatro cosas:

1. **El motivo, con las palabras del servidor**, tal cual. Por ejemplo: «3 de los 8
   pedidos ya están en otra ruta. Vuelve a elegirlos.»
2. **Quién**: «Aparato a3f91c02 · Yunier Pérez · Santiago»
3. **Las dos horas**: «hecho 23/9/2026, 17:02 · rechazado 24/9/2026, 8:11». Son dos
   porque la primera es la del **aparato** —cuándo se hizo de verdad, quizá sin
   señal— y la segunda la del **servidor**.
4. **Qué se intentaba**: «POST /api/routes/7f3a/results»

### Qué se puede hacer con un rechazo desde aquí

**Mirarlo.** Desde esta pantalla no se reintenta ni se descarta, porque aquí se ven
los rechazos de **todos los aparatos**, y el rechazo de otro no se toca desde aquí.

**Los botones «Reintentar» y «Descartar» están en el cajón de «Entregar el día»**,
que enseña los rechazos de **ese** aparato.

Y la regla que no cambia: **un rechazo no se reintenta solo y no se borra solo.**
Se queda a la vista con su motivo hasta que una persona decida.

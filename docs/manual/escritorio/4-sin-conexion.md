# Trabajar sin conexión

El escritorio se comporta **igual que el teléfono**: guarda el día dentro y aguanta
la jornada entera sin red.

El detalle completo, con la lista de lo que se puede y lo que no, está en
**[Trabajar sin señal (APK)](../apk/4-sin-senal.md)**. Aquí va lo mismo en corto y
lo que cambia en el ordenador.

---

## Cómo saber que estás sin conexión

**La franja de arriba te lo dice en medio segundo:**

1. El icono pasa a ser una **nube tachada**.
2. Aparece **«Sin conexión»** en ámbar, **delante** de la hora.
3. La franja entera se pone en ámbar.

Al volver la red se quita **en menos de un segundo**, sola.

Y el Panel:

> **Trabajando sin conexión** — No hay conexión con el servidor. Puedes seguir
> trabajando: todo se guarda aquí y sube solo cuando vuelva la señal.

---

## Lo que SÍ puedes hacer sin conexión

El camino entero del día: ver el Panel, armar zonas, ponerles camión, colocar
pedidos, **armar la ruta**, **iniciarla**, **marcar las entregas con su motivo**,
**completarla**, eliminarla, ver y sacar los PDF del pre-despacho y el
post-despacho, consultar Pedidos, Clientes y Reportes.

El mapa de la ruta se dibuja igual: **las paradas, su orden y el recorrido**. Si
descargaste el mapa de Cuba, además con calles de fondo.

---

## Lo que NO puedes hacer sin conexión

| No se puede | Por qué |
|---|---|
| **Entrar** | «Para entrar hace falta conexión. Una vez dentro, no.» |
| **«Abrir en Google Maps»** y mandar el enlace | Necesita la red |
| **Vehículos**: dar de alta, editar, borrar | Se configuran con conexión |
| **Almacenes**: crear, editar, borrar | Viven en Accesos |
| **Buscar una dirección** en Almacenes | Pero **hacer clic en el mapa y escribir las coordenadas sí funcionan** |
| **Sincronización** | Se lee del servidor cada vez |
| **Traer el día** y **Entregar el día** | Los dos hablan con el servidor |
| **El fondo de calles del mapa**, si no lo descargaste | Las teselas vienen del servidor |

---

## Qué pasa al volver la conexión

**Sube solo, en unos segundos, sin tocar nada.** Una ruta armada sin red como
`local-3df93810` **pasa a llamarse `RT-20260928-004`** al subir, y la franja pasa de
«2 sin subir» a **«Todo al día»**.

Y con red, la aplicación **se pone al día sola cada 5 minutos**.

El orden en que lo hace es siempre: **comprobar la sesión → subir lo tuyo → bajar lo
nuevo.** Primero sube y después baja, para que lo de allá no pise lo que acabas de
hacer.

---

## Lo único distinto del escritorio: la sesión

**En el teléfono la sesión se guarda siempre. En algunos ordenadores con Linux, no.**

Si al entrar viste esto:

> «Para entrar hace falta conexión, y **en este aparato hará falta cada vez que abras
> la aplicación**.»

entonces **no cierres la aplicación si te vas a quedar sin red**. Déjala abierta: el
día se sigue trabajando igual, pero no vas a poder volver a entrar sin conexión.

Ver [La primera vez](1-la-primera-vez.md#lee-esta-frase-antes-de-nada).

---

## Qué se puede perder, y qué no

**Lo único que se puede perder es lo que no ha subido.** Y no se pierde por sí solo:

- **Cerrar la aplicación no borra nada.**
- **Cerrar sesión no borra la cola.** Te lo avisa: «Salir NO los borra: se quedan en
  este aparato hasta que vuelvas a entrar.»
- **Desinstalar la aplicación SÍ se lo lleva todo.**

---

## El aviso que hay que tomarse en serio

> **Hay trabajo que no va a subir solo** — Está sólo en este aparato y no le queda
> ningún apunte que lo suba. No cierres sesión ni borres esta copia: avisa a la
> oficina para que lo rehagan.

En la franja sale como **«Sólo en este aparato: 1 ruta, 2 vehículos»**.

**No es «todavía no ha subido». Es «no va a subir».** Conéctate, y lo que siga
saliendo ahí después **hay que volver a hacerlo con conexión** — las zonas del tablero
suben solas, pero las rutas, los vehículos y los almacenes no.

**Y cuando ya lo hayas rehecho, quita el aviso.** Abre «Entregar el día», busca ese
mismo recuadro ámbar y pulsa **«Dar por perdido: 1 ruta»**; confirma con **«Sí, darlo
por perdido»**. No borra nada del equipo: lo que se quita es el aviso. Paso a paso en
[Cuando algo sale mal](../comun/cuando-algo-sale-mal.md).

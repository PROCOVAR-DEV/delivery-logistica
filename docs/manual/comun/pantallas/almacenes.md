# Almacenes

**Para qué sirve:** poner el punto desde el que arranca el camión y desde el que se
mide cada domicilio.

Debajo del título:

> «El punto desde el que se mide cada domicilio. Un almacén sin coordenadas no
> sirve para cotizar: la distancia se mide desde aquí.»

**Esta pantalla necesita conexión.** Los almacenes viven en Accesos; aquí no se
guarda nada en el aparato.

---

## La lista

Un renglón por almacén. Lleva una **estrella** si es el principal, y debajo del
nombre, separado por puntos, lo que le falta:

```
Calle 5 nº 12 · sin punto · inactivo
```

- **«sin dirección»** si no tiene dirección escrita.
- **«sin punto»** si no tiene coordenadas. **Desde ése no se puede medir.**
- **«inactivo»** si está apagado.

Si el almacén no tiene nombre, sale como **«(sin nombre)»**.

Arriba, el selector de sucursal (sólo si hay más de una), con cuántos almacenes
tiene cada una o **«sin almacenes»**. Y el botón **«Nuevo almacén»**.

---

## Los campos de un almacén

- **El nombre.** Si falta: «Le falta el nombre.» en rojo, y no se puede guardar.
- **«Principal»** — un chip. «Desde éste se mide cuando nadie dice cuál».
- **«Activo» / «Inactivo»** — otro chip.
- **La papelera («Quitar»)**, sólo en uno que ya existe.

Y la sección **«Dónde está»**:

> «Tres formas de poner el punto: buscar la dirección, pulsar en el mapa, o
> escribir las coordenadas. Escribirlas a mano funciona siempre, también sin
> conexión.»

- **«Dirección»** con el botón **«Buscar»**. Hacen falta al menos 4 letras.
- **«Coordenadas»**, con el ejemplo «19.83, -75.82».
- **El mapa**, que se puede pulsar.

Al pie: **«Cerrar»** y **«Guardar»**.

---

## Las tres formas de poner el punto

1. **Escribir la dirección y pulsar «Buscar»** — pregunta a un servicio de mapas.
   **Necesita señal.**
2. **Escribir las coordenadas a mano** en la caja «Coordenadas». **Funciona
   siempre, también sin conexión.** Vale la coma, el punto y coma o un espacio
   como separador.
3. **Pulsar en el mapa** — **también funciona sin señal**. Lo único que necesita
   red es traer después el nombre de la calle.

**Las tres escriben en la misma caja de coordenadas, y lo que se guarda es lo que
pone ahí.** Puedes usar una y corregir a mano.

Si la sucursal ya tiene otro almacén con punto, el mapa se abre por ahí. Si no, se
abre centrado en Cuba.

### Qué te dice al buscar

- **«Encontrado «Bayamo, Granma». Punto puesto en 20.38, -76.64; míralo en el mapa
  antes de guardar.»**
- **«No se encontró esa dirección. Prueba con menos detalle, o púlsalo en el mapa,
  o escribe las coordenadas a mano.»**
- **«Escribe al menos 4 letras para poder buscar.»**
- Sin red: **«Sin conexión no se puede buscar una dirección: no se preguntó a nadie
  y el punto se ha quedado como estaba. Púlsalo en el mapa o escribe las
  coordenadas a mano — esa vía funciona siempre.»**

### Qué te dice al pulsar en el mapa

- **«Punto puesto en 20.02470, -75.82190.»**
- Si ya tenías una dirección escrita, **no te la pisa**: te la ofrece. «El mapa dice
  que ahí es «Calle Martí».» con un botón **«Usar ésa»**.
- **«Punto puesto en … Ese sitio no tiene dirección con nombre: escríbela tú.»**
- Sin red: **«Punto puesto en … Sin conexión no se pudo traer la dirección:
  escríbela tú.»**

Y debajo del mapa, según haya cargado el fondo o no:

- «Pulsa en el mapa para poner el punto. Dos dedos (o el ratón) mueven el mapa.»
- «El fondo del mapa no ha cargado: sin señal se dibuja sólo si está descargado el
  mapa de Cuba. **Pulsar en el mapa pone el punto igual, y escribir las coordenadas
  también.**»

---

## Las reglas

- **Sólo puede haber un principal.** Al marcar uno, los demás se desmarcan.
- **Un almacén sin punto se puede guardar**, pero se te avisa antes: «Sin
  coordenadas: desde éste no se puede medir el domicilio.»
- **Al quitar uno se pregunta en un cajón**, igual que al borrar una zona del
  tablero o un camión: **«Borrar «Almacén Central»»**, con **«Sí, borrar «Almacén
  Central»»** y **«No, dejarlo»**. Cerrar el cajón sin contestar —la ✕, tocar
  fuera, Escape— es **No**.

  Y dice qué se pierde, porque no se deshace: se guarda la lista de la sucursal
  **sin él**, así que desaparece para todo el mundo; deja de poder medirse desde
  ahí (los pedidos que lo traen puesto pasan a medirse desde el principal de la
  sucursal, y si era el último con punto los domicilios de esa sucursal salen sin
  precio); los teléfonos que ya lo bajaron siguen midiendo desde él hasta la
  próxima vez que tengan red, así que cada entrega de ese día se cobra mal y no se
  ve hasta cuadrar la caja; y volver a ponerlo es darlo de alta a mano.

---

## Los avisos al guardar

- Bien: **«Guardado en Accesos.»**
- Sin conexión: **«Sin conexión: no se guardó nada en Accesos. Los almacenes se
  configuran con conexión; inténtalo otra vez cuando haya red.»**
- Si Accesos dice que no, el motivo sale **tal cual**, sin envolver.

---

## Los avisos al cargar

Si no carga la lista:

> «No se pudieron traer los almacenes de Accesos. Lo de abajo está vacío por eso,
> no porque no haya ninguno.»

Y en la APK y el escritorio, debajo, lo que sí tienes:

> «El aparato tiene 3 almacén(es) de la última bajada: desde ésos se sigue midiendo
> el domicilio aunque esta pantalla no cargue.»

### La franja de la última bajada (APK y escritorio)

> «Los almacenes son los de la última vez que hubo red: 28/9/2026, 7:14. Accesos no
> avisa de los que se retiran, así que este aparato no puede enterarse hasta la
> próxima bajada. Desde el almacén se mide lo que se le cobra por el domicilio: si
> sobra uno, cada entrega del día se cobra mal y no se ve hasta cuadrar la caja.»

Va en gris si la copia es de hoy y **en ámbar si tiene más de un día**. **En la web
no sale.**

---

## Si la sucursal no tiene ninguno

> **Sin almacenes en Granma**
>
> El almacén es el sitio del que sale el camión y desde el que se mide la distancia
> hasta cada cliente. Lleva su dirección y su punto en el mapa.
>
> Sin ninguno no hay desde dónde medir: los domicilios de esta sucursal salen sin
> precio y el asistente de rutas no pasa del punto de partida.

Con el botón **«Nuevo almacén»**.

Y si no sale ninguna sucursal:

> **No hay ninguna sucursal a la vista con código en Accesos.**
>
> Los almacenes son de la sucursal, y la sucursal se reconoce por su código (STG,
> HAB, CAM…). Sin ese código no hay a quién preguntarle por sus almacenes.
>
> Se arregla en Accesos, poniéndole el código a la sucursal. Si te debería salir
> alguna, pídelo a administración.

Aquí **no hay botón**, porque esto no se arregla en esta pantalla.

---

## Lo que Almacenes NO hace

- **No funciona sin conexión.**
- **No autocompleta la dirección mientras escribes.** Se busca **con el botón**, a
  propósito, para que el punto no se mueva solo.
- **No pone el punto de partida de la sucursal.** Eso es otra cosa, y lo deja hecho
  quien da de alta la sucursal.

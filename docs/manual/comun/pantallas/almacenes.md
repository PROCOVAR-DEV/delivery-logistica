# Almacenes

**Para qué sirve:** ver el punto desde el que arranca el camión y desde el que se
mide cada domicilio. **Es una pantalla de solo lectura**: los almacenes se editan
en el CRM.

Debajo del título:

> «El punto desde el que se mide cada domicilio. Un almacén sin coordenadas no
> sirve para cotizar: la distancia se mide desde aquí.»

Y, fijo debajo, el aviso:

> «Los almacenes se editan en el CRM. Aquí solo se consultan.»

Al lado sale el enlace **«Abrir el CRM»**, que lleva a la pantalla de almacenes del CRM
(`https://crm.procovar.cloud/catalogos/almacenes`), donde se corrigen.

**Esta pantalla necesita conexión.** Los almacenes se piden al servidor; aquí no se
guarda nada en el aparato.

---

## La lista

Un renglón por almacén. Lleva una **estrella** si es el principal, y debajo del
nombre, separado por puntos, lo que se sabe de él:

```
Calle 5 nº 12 · 20.02470, -75.82190 · código C1 · principal
```

- **«sin dirección»** si no tiene dirección escrita.
- Las **coordenadas**, o **«sin punto»** si no las tiene. **Desde un almacén sin
  punto no se puede medir.**
- **«código X»**, o **«sin código»**.
- **«principal»** si es el principal.
- **«inactivo»** si está apagado.

Si el almacén no tiene nombre, sale como **«(sin nombre)»**.

Arriba, el selector de sucursal (sólo si hay más de una), con cuántos almacenes
tiene cada una o **«sin almacenes»**.

**No hay nada que pulsar en un renglón** ni botones de crear, editar, borrar, marcar
principal o activar: para cambiar un almacén se va al CRM.

---

## Se repinta sola

Cuando alguien cambia un almacén en el CRM, el servidor avisa y la pantalla vuelve a
pedir la lista sin que hagas nada. No hace falta recargar.

---

## Los avisos al cargar

Si no carga la lista:

> «No se pudieron traer los almacenes de Accesos. Lo de abajo está vacío por eso,
> no porque no haya ninguno.»

Sin conexión, **en la APK y el escritorio**: **«Sin conexión. Los almacenes se piden
al servidor y ahora no hay con qué traerlos. Vuelve a intentarlo cuando haya red.»**

Sin conexión, **en la web**: **«Accesos no contesta. La página cargó, así que
conexión hay: los almacenes se piden al servidor y ahora mismo no responde. Prueba
otra vez y, si sigue igual, avisa a la oficina.»** No es el mismo texto a propósito:
mandar a mirar la señal a quien está en la oficina es mandarlo a mirar donde no es.

Si el servidor dice que no, el motivo sale **tal cual**, sin envolver.

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
>
> Esta sucursal no tiene ninguno: sus domicilios no se pueden cotizar. Se dan de
> alta en el CRM.

Sin botón: aquí no se dan de alta.

Y si no sale ninguna sucursal:

> **No hay ninguna sucursal a la vista con código en Accesos.**
>
> Los almacenes son de la sucursal, y la sucursal se reconoce por su código (STG,
> HAB, CAM…). Sin ese código no hay a quién preguntarle por sus almacenes.
>
> Se arregla en Accesos, poniéndole el código a la sucursal. Si te debería salir
> alguna, pídelo a administración.

Aquí **tampoco hay botón**, porque esto no se arregla en esta pantalla.

---

## Lo que Almacenes NO hace

- **No crea, edita ni borra almacenes.** Eso se hace en el CRM.
- **No funciona sin conexión.**
- **No pone el punto de partida de la sucursal.** Eso es otra cosa, y lo deja hecho
  quien da de alta la sucursal.

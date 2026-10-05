# Vehículos

**Para qué sirve:** es la flota. Qué camiones hay, cuánto carga cada uno, qué
cuesta su kilómetro y cuál está hoy en la calle.

Debajo del título: «Gestiona tu flota. El costo por kilómetro de cada tipo de
camión se pone en «Tipos de vehículo», aquí al lado.»

**Importante: esta pantalla necesita conexión.** No hay cola ni copia en el
aparato: si no sale, no se guarda, y se dice.

---

## La flota de un vistazo

Cuatro pastillas arriba, y **se pueden pulsar para filtrar** (volver a pulsarlas
quita el filtro):

- **«Libres»** (verde)
- **«En ruta»** (azul)
- **«Con ruta planificada»** (ámbar)
- **«Mantenimiento»** (ámbar) — **sólo sale si hay alguno**. Un «Mantenimiento 0»
  no se enseña.

Cuentan **sobre la flota entera**, no sobre lo que estés buscando ni sobre la
página.

---

## Los cuatro estados de un camión

| Insignia | Qué significa |
|---|---|
| **«Disponible»** (verde) | No tiene ninguna ruta abierta. Libre de verdad |
| **«Con ruta»** (ámbar) | Tiene una ruta **planificada**: comprometido, pero aún no ha salido |
| **«En ruta»** (azul) | Tiene una ruta **en curso**: está fuera ahora mismo |
| **«Mantenimiento»** (ámbar) | Está en el taller |

**Los tres primeros no los escribe nadie: salen de las rutas del camión.** El
único que se pone a mano es «Mantenimiento», porque un camión en el taller no
tiene ruta, igual que uno libre.

Si el taller y una ruta abierta se contradicen, **gana el taller** en la insignia,
y justo debajo se explica con el nombre de la ruta.

---

## Qué se ve en cada tarjeta

- El **nombre** y debajo la **placa**.
- La **insignia de estado** a la derecha.
- El **tipo** del camión.
- **«Cálculo domicilio · $1.65/km»** si es el que se usa para calcular el
  domicilio. Si no lo es, en su sitio sale el botón **«Usar para domicilio»**.
- Dos cajas: **«Capacidad»** («1000 kg») y **«Rutas»** (cuántas lleva).
- Si tiene ruta abierta, una caja de color: **«Ruta activa»** (en curso) o **«Ruta
  planificada»**.
- **«12 órdenes asignadas»**.
- Las notas, si las tiene.

### Los dos avisos de la tarjeta

**Cuando el estado guardado miente:**

> «El estado guardado dice «en uso» y no lleva ninguna ruta abierta. Márcalo
> disponible: hasta entonces sale como ocupado al elegir camión.»

Se arregla con el botón **«Marcar disponible»**.

**Cuando está en el taller y lleva una ruta abierta:**

> «Está en el taller y lleva la ruta R-0412 abierta. O vuelve a estar disponible, o
> esa ruta la tiene que llevar otro camión: mandarlo al taller no la cierra, porque
> una ruta cerrada es una ruta repartida.»

### Los botones

- **«Marcar disponible»** — sólo si el estado guardado dice que está ocupado
- **«Editar»**
- **«Eliminar»** — **pregunta antes, en un cajón** (ver abajo)

### Al eliminar, pregunta antes

Se abre un cajón titulado **«Borrar «Camión 1»»**, igual que al borrar una zona del
tablero o un almacén, y dice **qué se pierde**:

> «El camión se va de la flota. Las rutas y los pedidos que lo llevaban puesto NO se
> borran —el histórico de lo repartido se queda— pero se quedan sin camión, y hay que
> ponerles otro. Y el camión hay que volver a darlo de alta a mano, con su placa, su
> capacidad y su costo por km.»

Con **«Sí, borrar «Camión 1»»** y **«No, dejarlo»**. **Cerrar el cajón sin
contestar —la ✕, tocar fuera, Escape— es No.**

---

## La ficha de un vehículo

Se abre con **«Agregar Vehículo»** o con **«Editar»**.

| Campo | Ejemplo o valor por defecto |
|---|---|
| **«Nombre del Vehículo *»** | «Ej: Camión #1, Furgoneta Azul». Obligatorio |
| **«Tipo»** | Desplegable. Al elegir uno, **hereda su costo por km** |
| **«Placa (opcional)»** | «ABC-1234». Se pasa a mayúsculas solo |
| **«Capacidad Máx. (kg)»** | 1000 |
| **«Estado del vehículo»** | «Disponible» |
| **«Costo por km (USD)»** | «1.65» |
| **«Usar este vehículo para calcular el domicilio»** | Desmarcada. «Solo un vehículo por TIPO.» |
| **«Notas (opcional)»** | Texto libre |

### El desplegable «Estado del vehículo» sólo tiene DOS opciones

**«Disponible»** y **«En mantenimiento»**. **«En ruta» no está, a propósito**: se
deduce de las rutas y no se escribe a mano.

Si el camión está cogido por el despacho de una ruta, el desplegable sale sin nada
marcado, con la pista «Ocupado por el despacho de una ruta», y esta explicación:

> «Ahora mismo lo tiene cogido el despacho de una ruta. Eso no se elige aquí: se
> quita cerrando o cambiando esa ruta…»

Y al marcarlo en mantenimiento:

> «En el taller: no se le puede dar ruta hasta que vuelva. Escribe el motivo en
> Notas, aquí abajo — es lo único que le dice al de al lado por qué no puede contar
> con él. Marcarlo NO cierra la ruta que ya tuviera abierta.»

### El ayudante del costo por km

Plegable, se llama **«¿No sabes el costo por km?»**. Se le dice **«El camionero
cobra (CUP)»** (por ejemplo 180000) y **«hasta ___ km (ida)»** (por ejemplo 72), y
con **«Calcular»** te da «= $3.91/km».

La cuenta es: **lo que cobra, dividido entre el doble de los kilómetros** (ida y
vuelta) **y entre la tasa**. La nota lo dice: «Tipo de cambio: 320 CUP/USD. Se
divide entre 2×km (ida y vuelta).»

**El ayudante rellena el campo, no lo propone.** Y si le falta un dato, no lo
toca.

---

## «Tipos de vehículo»

Botón arriba, abre un cajón:

> «Define cada tipo con su costo por km por defecto. Al crear un vehículo de ese
> tipo se hereda el costo/km (editable por vehículo).»

Cada fila tiene **«Nombre»** y **«Costo/km (USD)»**, con una papelera («Quitar»).
Abajo, **«Agregar tipo»**, y al pie **«Cancelar»** y **«Guardar»**.

Las filas **sin nombre no se guardan**.

### Un costo por km VACÍO no es lo mismo que CERO

Esto importa, y mucho:

- **Vacío** quiere decir **«todavía no se sabe»**. Es un hueco que se ve y se
  rellena.
- **Cero** quiere decir **«el kilómetro es gratis»**, y eso se propaga al precio
  del domicilio. Un número creíble y equivocado.

**Si no sabes el costo, déjalo vacío. Nunca pongas cero.**

Lo mismo en el Excel de Reportes: un importe que no se sabe deja la celda vacía,
nunca en cero.

---

## Los avisos

Al guardar bien: «Vehículo agregado.» · «Vehículo actualizado.» · «Vehículo
eliminado.» · «Vehículo marcado como disponible.» · «Se usará este vehículo para
calcular el domicilio.» · «Tipos guardados.»

Sin conexión, **y no dice lo mismo en los tres sitios, a propósito**: mandar a mirar
la señal a quien está sentado en la oficina es mandarlo a mirar donde no es.

En la APK y el escritorio:

> «Sin conexión: no se guardó nada. Los vehículos se configuran con conexión;
> inténtalo otra vez cuando haya red.»

En la web:

> «Sin conexión con el servidor: no se guardó nada. La página cargó, así que conexión
> hay: el que no contesta es el servidor. Prueba otra vez y, si sigue igual, avisa a
> la oficina.»

**Lo que no cambia en ninguno: no se guardó nada.**

Si el servidor contesta algo raro:

> «No se pudo guardar y no se sabe por qué: el servidor contestó algo que esta
> pantalla no entiende. NO se guardó nada. Vuelve a intentarlo y, si sigue igual,
> avisa a la oficina.»

---

## Si no carga

En la APK y el escritorio, debajo del fallo te dice **qué tienes en el aparato**,
que es lo que de verdad importa para poder trabajar:

> «El aparato tiene 8 vehículo(s) de la última bajada: con ésos se puede armar la
> ruta aunque esta pantalla no cargue.»

O, si no bajó nunca:

> «Este aparato no ha descargado la flota todavía. No es que no haya vehículos: es
> que no están aquí. Baja sola al traer el día desde el Panel.»

---

## Si no hay ningún vehículo

> **Sin vehículos**
>
> Aquí van los camiones con los que se reparte: cuánto carga cada uno, qué cuesta
> su kilómetro y cuál está hoy en ruta.
>
> Mientras no haya ninguno no se puede terminar de armar una ruta —el asistente se
> para en el paso del vehículo— y las columnas del tablero se quedan sin camión.

Con el botón **«Agregar Vehículo»**.

---

## Paginación

Al pie: «Mostrando 1–25 de 63», con un desplegable de **«25 / pág.»**, **«50 /
pág.»** o **«100 / pág.»**, y las flechas «Primera», «Anterior», «Siguiente»,
«Última».

---

## Lo que Vehículos NO hace

- **No funciona sin conexión.** Es la diferencia con Pedidos, Clientes o Rutas.
- **No se marca «En ruta» a mano.**
- **No se le cambia el camión a una ruta ya armada.** Eso no está aquí ni en Rutas:
  hay que eliminar la ruta y volver a armarla.
- **El costo por kilómetro no se pone en la ficha del camión**: sale del **tipo**
  de camión. La ficha lo dice: «El costo por kilómetro no se pone aquí: sale del
  tipo de camión, y se cambia en «Tipos de vehículo».»

  Se cambia en el botón **«Tipos de vehículo»**, en esta misma pantalla.

  > **Hasta el 05/10/2026 las dos pantallas mandaban a una «Configuración» que no
  > existe** — no hay ninguna entrada así en el menú; era un resto del sistema
  > anterior. Lo destapó quien escribía este manual, al tener que explicar dónde
  > se ponen las tarifas. Si alguien te manda a buscar esa pantalla, ya no está:
  > es «Tipos de vehículo».

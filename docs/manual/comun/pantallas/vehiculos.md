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

**Un camión en el taller se sigue ofreciendo para rutas nuevas, con un aviso en ámbar**
(«en el taller») en el asistente «Nueva Ruta» y en el «Camión previsto» del Tablero. Es
aviso, no bloqueo, y es a propósito: una sucursal con un solo camión olvidado en el
taller se quedaría sin poder armar ni una ruta. Lo que **nunca** se ofrece es un camión
«Inactivo».

### «Inactivo» no es un quinto estado

Un camión puede estar **«Disponible» e «Inactivo» a la vez**, y por eso la insignia
**«Inactivo»** sale **aparte**, debajo del nombre y de la insignia de estado (con un
borde y un icono de prohibido, sin relleno). Los estados de arriba dicen **en qué anda
el camión** (libre, con ruta, fuera, en el taller); «Inactivo» dice que **se dio de
baja sin borrarlo**:

- **No se ofrece en rutas nuevas**: ni en el paso «Vehículo» del asistente «Nueva
  Ruta», ni en el «Camión previsto» de una zona del Tablero.
- **Sigue viéndose donde ya tiene historia**: en el filtro «Rutas de un camión», en
  los informes y en las rutas que ya hizo, que siguen diciendo en qué camión fueron.
- **Se puede volver a activar** cuando haga falta, en su ficha (interruptor «Vehículo
  activo»).

Es la salida para un camión que ya se usó: **un camión con rutas —aunque sean del
histórico— no se puede borrar**, se inactiva.

---

## Qué se ve en cada tarjeta

- El **nombre** y debajo la **placa**.
- La **insignia de estado** a la derecha.
- Si el camión está dado de baja, la insignia **«Inactivo»**, debajo.
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

> «El camión se va de la flota y hay que volver a darlo de alta a mano, con su placa,
> su capacidad y su costo por km.
>
> Un camión que ya tiene rutas —aunque sean del histórico— NO se puede borrar: el
> servidor lo rechaza para no perder qué camión hizo cada reparto. Si ese es el caso,
> no lo borres: ábrelo con «Editar» y márcalo como inactivo. Así deja de ofrecerse en
> las rutas nuevas y su historial se queda intacto.»

Con **«Sí, borrar «Camión 1»»** y **«No, dejarlo»**. **Cerrar el cajón sin
contestar —la ✕, tocar fuera, Escape— es No.**

**Sólo se borra un camión que nunca se usó** (sin ninguna ruta, ni siquiera de las
completadas). Si tiene rutas y le das a «Sí», el servidor no lo borra y lo dice:

> «No se puede eliminar este vehículo porque tiene rutas asociadas, incluso
> históricas. Márcalo como inactivo para impedir que se use en nuevas rutas.»

---

## La ficha de un vehículo

Se abre con **«Agregar Vehículo»** o con **«Editar»**.

| Campo | Ejemplo o valor por defecto |
|---|---|
| **«Nombre del Vehículo *»** | «Ej: Camión #1, Furgoneta Azul». Obligatorio |
| **«Vehículo activo»** | Interruptor, **encendido** por defecto. Ver abajo |
| **«Tipo»** | Desplegable. Al elegir uno, **hereda su costo por km** |
| **«Placa (opcional)»** | «ABC-1234». Se pasa a mayúsculas solo |
| **«Capacidad Máx. (kg)»** | 1000 |
| **«Estado del vehículo»** | «Disponible» |
| **«Costo por km (USD)»** | «1.65» |
| **«Usar este vehículo para calcular el domicilio»** | Desmarcada. «Solo un vehículo por TIPO.» |
| **«Notas (opcional)»** | Texto libre |

### El interruptor «Vehículo activo»

Está justo debajo del nombre. Dice, según esté:

- Encendido: «Aparece en los selectores para crear rutas.»
- Apagado: «Se oculta de los selectores de rutas nuevas.»

**Apagarlo es dar el camión de baja sin borrarlo.** Es lo que hay que hacer con un
camión que se vende, se rompe del todo o ya no se usa, pero que **tiene rutas hechas**:
borrarlo está prohibido para que el histórico siga diciendo qué camión repartió cada
cosa. Al guardar («Actualizar»), la tarjeta pasa a llevar la insignia **«Inactivo»**.
Para recuperarlo, vuelve a **«Editar»** y enciéndelo.

**Un camión sin sucursal es de todas** y sólo lo modifican, dan de baja o eliminan un
`SUPER ADMIN` o un `DESARROLLADOR`; los demás roles reciben: «Este vehículo es
compartido por todas las sucursales: sólo un SUPER ADMIN o un DESARROLLADOR puede
modificarlo, darlo de baja o eliminarlo.»

**No confundir con «En mantenimiento».** El mantenimiento es un camión que **va a
volver** (está en el taller): **se ofrece para rutas nuevas, con su aviso en ámbar**, y
al volver se pasa a «Disponible». «Inactivo» es una baja que no cuenta con él y **no se
ofrece nunca**.

### El desplegable «Estado del vehículo» sólo tiene DOS opciones

**«Disponible»** y **«En mantenimiento»**. **«En ruta» no está, a propósito**: se
deduce de las rutas y no se escribe a mano.

Si el camión está cogido por el despacho de una ruta, el desplegable sale sin nada
marcado, con la pista «Ocupado por el despacho de una ruta», y esta explicación:

> «Ahora mismo lo tiene cogido el despacho de una ruta. Eso no se elige aquí: se
> quita cerrando o cambiando esa ruta…»

Y al marcarlo en mantenimiento:

> «En el taller: se puede elegir para una ruta nueva, pero sale marcado con un aviso.
> Escribe el motivo en Notas, aquí abajo — es lo único que le dice al de al lado por qué
> no puede contar con él. Marcarlo NO cierra la ruta que ya tuviera abierta: eso se
> arregla en la tarjeta del camión.»

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
- **No se borra un camión que tiene rutas**, ni siquiera históricas: se pone
  «Inactivo».
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

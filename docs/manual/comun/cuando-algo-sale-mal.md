# Cuando algo sale mal

Busca aquí el aviso que te salió. Cada uno dice qué pasó y qué hacer.

---

## «Un pedido no aparece»

Es la consulta más frecuente, y casi nunca es un fallo. Mira en este orden:

1. **La sucursal de arriba.** Todas las pantallas enseñan lo de esa sucursal. Un
   pedido de Holguín no sale si estás en Santiago.
2. **La franja azul de Pedidos.** Al entrar, Pedidos viene acotado a lo que puede
   subir a un camión. Pulsa **«Ver todos los pedidos»**.
3. **Los filtros.** Si hay alguno puesto, el vacío dice «Ningún pedido cuadra con
   estos filtros.» y hay un botón **«Quitar todos los filtros»**.
4. **Si ya está en una ruta**, no sale entre los disponibles. Búscalo en Rutas.
5. **De cuándo son tus datos** (APK y escritorio). Si la franja de arriba dice
   «Datos de hace 9 h», ese pedido puede haber entrado después. Pulsa la franja y
   trae el día.
6. **Si no tiene coordenadas de entrega**, no entra en el Tablero ni en «Pedidos
   sin ruta». Se ve en Pedidos, marcado.

---

## «Marqué uno como entregado y el Historial está vacío»

**No es un fallo.** «Entregados hoy» cuenta **pedidos**; el Historial de Rutas
cuenta **rutas cerradas**. Un camión en la calle con una parada hecha sale en el
primero y no en el segundo.

El detalle entero está en
[Qué significa cada número](que-significa-cada-numero.md).

---

## «No me deja armar la ruta»

Por orden de probabilidad:

| El aviso | Qué hacer |
|---|---|
| **«La zona «Centro» no tiene camión previsto, y sin camión no se arma su ruta»** | El cajón se queda abierto. Toca **«Camión previsto»** y elige uno. Vuelve a armar |
| **«Se requiere un vehículo para crear la ruta»** | Lo mismo, pero en el asistente: paso 3 |
| **«La columna no tiene ningún pedido que se pueda repartir hoy»** | Debajo te dice por qué se cayó cada uno. Casi siempre es factura |
| **«En una ruta sólo entra lo facturado y que cuadre. 3 no cumplen…»** | Esos pedidos no van hoy. Quítalos y arma con el resto |
| **«2 de los 12 pedidos elegidos no pueden ir en esta ruta: X-2992 (ya va en la ruta RT-20260922-003)…»** | Alguien se te adelantó, o el pedido cambió. Quítalo y vuelve |
| **«Peso total (1250.5 kg) supera la capacidad del vehículo (1000 kg)»** | Saca pedidos o cambia de camión |
| **«Las coordenadas del punto de partida son requeridas»** | La sucursal no tiene almacén con punto. Se arregla en Almacenes |
| **«Esta sucursal no tiene ningún almacén con ubicación»** | Botón **«Poner el almacén»** |
| **«Esta sucursal no tiene ningún vehículo dado de alta»** | Botón **«Agregar el primer vehículo»** |

---

## «No hay conexión»

### En la web

Si la página cargó, **conexión hay**. Lo que no contesta es el servidor, y la
aplicación lo dice así:

> «La página cargó, así que conexión hay: el que no contesta es el servidor. Prueba
> otra vez y, si sigue igual, avisa a la oficina.»

**No vayas a mirar la señal**: no es eso.

**En la web, sin servidor no se puede seguir trabajando.** No hay copia local.

### En la APK y el escritorio

La franja de arriba dice **«Sin conexión»** y se pone en ámbar. Y el Panel:

> «No hay conexión con el servidor. Puedes seguir trabajando: todo se guarda aquí y
> sube solo cuando vuelva la señal.»

**Sigue trabajando.** Puedes armar zonas, armar rutas, iniciarlas y marcar entregas
con su motivo. Todo se guarda y sube solo cuando vuelva la señal, en unos segundos.

**Los dos botones del día se apagan**, y con su motivo escrito al lado: **«Sin
conexión con el servidor»**. Son los dos gestos que hablan con el servidor, así que
sin red no hay ninguno.

### Lo único que NO se puede hacer sin señal

- **Entrar.** «Para entrar hace falta conexión. Una vez dentro, no.»
- **«Abrir en Google Maps»** y mandar el enlace por WhatsApp.
- **Buscar una dirección** en Almacenes (pero poner el punto en el mapa o escribir
  las coordenadas **sí** funciona).
- **Vehículos** y **Almacenes** enteros: se configuran con conexión.
- **Sincronización**: se lee del servidor cada vez.
- **El fondo de calles del mapa**, si no descargaste el mapa de Cuba. Las paradas y
  el recorrido se siguen dibujando.

---

## «Un cambio se rechazó»

Un rechazo **no se reintenta solo y no se borra solo**. Se queda con su motivo hasta
que una persona decida.

### En la web

Te lo dice ahí mismo, con el motivo de verdad: «Ese pedido ya va en otra ruta». Haz
lo que diga y repite el gesto.

### En la APK y el escritorio

Van a la bandeja **«Rechazados, esperando a una persona»**, dentro del cajón de
«Entregar el día»:

> «El servidor dijo que no por algo. No se reintentan solos y no se borran: quedan
> aquí con su motivo hasta que alguien decida.»

Ahí tienes **«Reintentar»** y **«Descartar»**.

La pantalla de **Sincronización** enseña los rechazos de **todos** los aparatos,
pero desde ahí sólo se miran: los botones están en el cajón del aparato.

El motivo más común es **haber trabajado con datos viejos**: el pedido que aquí
salía libre, allá ya entró en otra ruta. Por eso la aplicación pide **traer el día
antes de enviar** y lo dice:

> «Trae el día primero: no se envía nada sin tener lo de ahora»

---

## «Hay trabajo que no va a subir solo»

**Éste es el aviso serio.** Aparece en el Panel y en la franja, y también como
**«Sólo en este aparato: 1 ruta, 2 vehículos»**.

No quiere decir «todavía no ha subido». Quiere decir **«no va a subir»**: está
hecho aquí, no está en el servidor, y **no le queda ningún apunte detrás que lo
suba**.

> «Está sólo en este aparato y no le queda ningún apunte que lo suba. No cierres
> sesión ni borres esta copia: avisa a la oficina para que lo rehagan.»

Qué hacer:

1. **No cierres sesión** y **no desinstales la aplicación**.
2. Conéctate: con señal, el sincronizador vuelve a encolar solo lo que sabe rehacer.
   Las **zonas del tablero** suben solas así, sin que toques nada.
3. **Lo que siga saliendo ahí después de subir, hay que volver a hacerlo con
   conexión.** Las rutas, los vehículos y los almacenes no se rehacen solos.

### Y cuando ya lo has rehecho: quitar el aviso

Una ruta que se quedó aquí y ya rehiciste con conexión **sigue saliendo en ámbar**, y
ese aviso está en las siete pantallas. Para quitarlo:

1. Abre **«Entregar el día»** (la franja de arriba, o el botón del Panel).
2. Busca el recuadro ámbar **«Sólo en este aparato: …»**.
3. Toca **«Dar por perdido: 1 ruta»**.
4. Lee lo que sale y toca **«Sí, darlo por perdido»**. Si te arrepientes,
   **«Dejarlo como está»**.

**No se borra nada del aparato.** Lo que se quita es el aviso; lo que hiciste aquel día
sigue estando para quien pregunte. Y **sólo sale para lo que no se rehace solo**: a una
zona del tablero no te lo ofrece, porque esa va a subir sola.

> Úsalo cuando **ya no haga falta**: la ruta se rehizo en la web, el reparto se cerró a
> mano. Si todavía hace falta, primero rehazlo con conexión.

---

## «Los errores no se van nunca»

Si ves lo mismo una y otra vez en **«Entregar el día»** —lo descartas y a los pocos
minutos está otra vez ahí— **tienes una versión vieja de la aplicación**. Se arregló el
29/09/2026 en la **1.0.15**: descartar borraba el apunte, y al quedarse la zona sin nada
que la subiera el sincronizador la volvía a encolar, el servidor repetía su «no», y el
mismo error volvía a la bandeja.

Actualiza la aplicación. Desde la 1.0.15, lo que descartas se queda descartado.

---

## «El tablero no se actualiza»

> «No se actualiza: hay 1 cambio sin subir. Se sube primero y después se trae — así
> no se pierde nada.»

Es a propósito: si bajara primero, lo del servidor pisaría lo que acabas de hacer.
**Sube primero** (franja de arriba, «Entregar el día») y después refresca.

---

## «El mapa no se descarga»

- **«Todavía no hay ningún mapa colgado para descargar.»** — no hay nada que bajar
  todavía. No es tuyo.
- **«No se pudo preguntar si hay un mapa nuevo. Se mira otro día; lo que ya esté
  descargado sigue funcionando.»**
- **«El servidor anunció 1 nivel más que esta versión de la aplicación no sabe
  leer.»** — hay que actualizar la aplicación.

**Y si el mapa se ve a trozos o mal**, no desinstales nada: abajo del todo, en
«Si el mapa se ve mal», está el botón para volver a bajarlo entero.

Recuerda: **sin el mapa de Cuba se sigue trabajando**. Lo que falta son las calles
de fondo.

---

## «No se pudo guardar en este aparato»

> «No se pudo guardar en este aparato, así que este movimiento NO se ha hecho. Suele
> ser que no queda espacio: libera sitio en el teléfono y vuelve a intentarlo.»

**El movimiento no se hizo.** No es que esté pendiente: no está. Libera espacio y
repítelo.

---

## «La sesión se perdió»

> «Tu sesión se perdió. Los datos que bajaste siguen en el aparato. Para volver a
> entrar hace falta señal; **no es tu contraseña**.»

Busca señal y entra otra vez. **Tu cola sigue entera**, no se pierde nada.

Si pasa a menudo en una red con pérdidas, díselo a la oficina: puede ser otra cosa.

---

## «La bajada volvió a medias»

> «La bajada se quedó a medias: se llegó al tope de tandas y el servidor seguía
> diciendo que queda más. Lo que hay en el aparato está incompleto **aunque las
> cifras de abajo parezcan normales**.»

Eso último es lo importante: **los números se leen bien y están cortos**. Si sale
esto, **los reportes no sirven para cerrar**. Conéctate y deja que termine.

---

## «Faltan datos» al traer el día

El aviso nombra **lo que falta**, no «hubo un error»: «Falta el catálogo de
productos», «Faltan los almacenes y los vehículos», «No bajó nada». Y debajo, **qué
se rompe sin cada cosa**.

Qué hacer:

> «Busca señal y vuelve a darle al botón. Lo que ya bajó se queda.»

No hay que empezar de cero.

---

## «No hay señal» al traer o entregar el día

> «No se intentó nada: el aparato dice que no hay red. Sigues teniendo lo que
> bajaste antes.»

O, al entregar:

> «No se intentó nada: el aparato dice que no hay red. Tu trabajo sigue guardado aquí
> y no se pierde.»

Ojo con un caso de Cuba: **el teléfono puede decir que hay wifi y no salir ni un
paquete**. La aplicación lo detecta mirando si las peticiones llegan, no si el icono
del wifi está encendido. Cuando pasa, dice:

> «Se cortó la conexión a mitad. El aparato puede decir que hay wifi y no salir un
> paquete: eso es esto.»

---

## Cuando lo que ves no cuadra con lo que esperas

Dos cosas que **hoy no son de fiar** y están en arreglo:

1. **El peso del pre-despacho no cambia al cambiar de sucursal.**
2. **Una ruta con dos pedidos del mismo cliente cuenta el peso de uno solo** en su
   cabecera.

Y dos que **sí son correctas** aunque parezcan un fallo:

- **«Pedidos sin ruta» del Panel y «Sin colocar» del Tablero no dan el mismo
  número.** Cuentan cosas distintas.
- **Los kilómetros de las paradas no suman los kilómetros de la ruta.** Son dos
  medidas distintas.

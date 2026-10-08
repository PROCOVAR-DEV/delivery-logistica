# El armazón: lo que está en todas las pantallas

Arriba está la barra superior; debajo, el aviso de versión nueva cuando lo hay; y
debajo, **sólo en la APK y en el escritorio**, la franja de estado. El menú va a la
izquierda en pantalla grande y en un cajón en el teléfono.

---

## La barra superior

De izquierda a derecha:

- **El botón de menú** («Menú») — **sólo en el teléfono**.
- **El título de la pantalla** — sólo en pantalla ancha. En el teléfono no se
  pinta, para que quepan la sucursal, la moneda y el avatar.
- **«actualizando…»** con una rueda, cuando hay algo en vuelo. Sólo en pantalla
  ancha.
- **El selector de sucursal** («Sucursal que se está mirando»).
- **El selector de moneda.**
- **Tu avatar**, que abre el menú de cuenta.

### El selector de sucursal

- Con **una sola** sucursal: una pastilla con su nombre, «Santiago (STG)», y en el
  teléfono sólo el código.
- Con **varias**: la primera opción es **«Todas las sucursales (8)»** («Todas (8)»
  en el teléfono), y luego una por sucursal.

**Sólo `DESARROLLADOR` y `SUPER ADMIN` ven varias.** Los otros cinco roles tienen
la suya y no pueden cambiarla.

**Este selector manda sobre todas las pantallas.** Es lo primero que hay que mirar
cuando algo «no aparece».

### El selector de moneda

**«USD»** y **«CUP»**. La opción de CUP lleva la tasa y de cuándo es: «1 USD = 320
· del 9/9/2026».

**Si esa sucursal no tiene tasa, no se ofrece CUP.** Se queda una pastilla ámbar
que pone **«USD»**, con el motivo dentro. No se convierte con la tasa de otra
sucursal.

Si la tasa es vieja y estás mirando en CUP, sale un reloj en ámbar avisando.

---

## El menú de cuenta

El avatar enseña tu inicial; en pantalla ancha, también tu nombre y tu rol. **Nunca
se enseña el identificador interno.**

Al abrirlo:

1. **«Ir a»** — una baldosa por cada aplicación de la casa, con su nombre y su
   descripción. Se abren fuera. **Si no se pueden leer, la sección simplemente no
   sale**, sin error.
2. **«Cerrar sesión»**, en rojo. Es lo único de este menú que destruye algo.

### Cerrar sesión con trabajo sin subir

Sale un aviso, y **dice cosas distintas según dónde estés**:

**En la web:**

> **Hay cambios sin guardar**
>
> Hay 3 cambios que no llegaron al servidor. Si sales ahora se pierden.
>
> Vuelve a intentarlo desde la pantalla donde los hiciste.

**En la APK y el escritorio:**

> **Queda trabajo sin subir**
>
> Hay 3 apuntes sin subir al servidor. Salir NO los borra: se quedan en este aparato
> hasta que vuelvas a entrar.
>
> Pero nadie los ve hasta que suban. Si puedes, conecta y espera.

Botones: **«Me quedo»** y **«Salir de todos modos»**.

**La diferencia es real:** en la web, salir con cambios sin guardar **los pierde**.
En el aparato, no: se quedan y suben cuando vuelvas a entrar.

---

## El menú de la izquierda

Arriba el logo, **«ProCovar»** y debajo **«Plataforma de Delivery»**.

Las entradas:

| Entrada | Dónde sale |
|---|---|
| **Panel** | Los tres |
| **Tablero** | Los tres |
| **Rutas** | Los tres |
| **Pedidos** | Los tres |
| **Clientes** | Los tres |
| **Vehículos** | Los tres |
| **Almacenes** | Los tres |
| **Reportes** | Los tres |
| **Sincronización** | **Sólo APK y escritorio** |
| **Mapa de Cuba sin conexión** | **Sólo APK y escritorio** |

En el teléfono el menú se cierra solo al elegir una entrada.

---

## La franja de estado — sólo APK y escritorio

**En la web no existe**, porque habla de *tu copia* y de *tu cola*, y en un
navegador no hay ninguna de las dos.

De izquierda a derecha:

1. Un icono: **rueda** si está actualizando, **nube tachada** si no hay conexión,
   **reloj** si todo va bien.
2. **«Sin conexión»** en ámbar, si las peticiones no están llegando. Va **delante**
   de la hora.
3. **De cuándo son los datos:**

| Texto | Cuándo | Color |
|---|---|---|
| **«Sin descargar todavía»** | Nunca se bajó nada | ámbar |
| **«El reloj de este aparato no cuadra»** | El reloj del aparato va por detrás de sus propios datos | ámbar |
| **«Datos de las 10:36»** | Menos de una hora | gris |
| **«Datos de hace 9 h»** | Entre una hora y un día | gris |
| **«Datos del martes — hace 3 días»** | Más de un día | ámbar |

1. **«23 sin subir»**, un botón ámbar, sólo si hay algo. Lleva al cajón de entregar
   el día.
2. Y dos líneas más que sólo salen cuando hay problema:
   - **«Sólo en este aparato: 1 ruta, 2 vehículos»** — trabajo que **nadie va a
     subir** porque ya no le queda ningún apunte detrás. Ver
     [Cuando algo sale mal](../cuando-algo-sale-mal.md).
   - **«Faltan datos por bajar: …»** — la bajada volvió a medias, con el motivo.
3. A la derecha, dos botones: **«Traer el día»** y **«Entregar el día · 23 sin
   subir»**, éste con el número en una insignia.

**La franja entera se puede pulsar** y abre el cajón de traer el día. Así el gesto
está a mano desde cualquier pantalla, sin volver al Panel.

Se pone en **ámbar** cuando los datos tienen más de un día, cuando no hay conexión,
cuando hay trabajo huérfano o cuando la bajada volvió a medias. El resto del tiempo
va en gris, para no pedir la vista sin motivo.

### Por qué «El reloj de este aparato no cuadra» no dice una hora

Porque la hora es justo lo que no vale. Decir «Datos de las 16:40» cuando son las
14:00 es escribir una hora del futuro con cara de dato. Si te sale esto, **ponle la
hora al aparato**: hasta entonces, «Entregados hoy» y todo lo que dependa del día
están mal.

---

## El aviso de versión nueva

Una franja ámbar arriba del todo, **en los tres sitios**. No tapa nada.

**En la web:**

> **Hay una versión nueva**
>
> Esta pestaña lleva abierta desde antes del último cambio. Recarga para tenerlo;
> aquí no hay nada sin guardar que se pueda perder.

Con **«Recargar ahora»** y **«Ahora no»**.

**En la APK y el escritorio, con la cola vacía:**

> **Hay una versión nueva: 1.0.7**

Con **«Cómo instalarla»** y **«Ahora no»**. Al pulsar el primero se abre un cajón
que explica qué va a pasar:

> «Son 78 MB. Se abre el navegador y se descarga el fichero. La descarga no toca
> esta aplicación: lo que tengas dentro sigue aquí mientras no instales.»
>
> «Instálalo con señal y con la cola vacía. No hace falta que sea ahora: la versión
> de ahora sigue funcionando.»

**En la APK y el escritorio, con trabajo sin subir, no se ofrece instalar:**

> **Hay una versión nueva, pero antes hay que subir el trabajo**
>
> Te quedan 3 cosas por subir. Instalar ahora puede llevárselas: primero sube,
> después actualiza.

Y sólo está el botón **«Ahora no»**.

**«Ahora no» no mata el aviso: lo calla 30 minutos y vuelve.** No hay ninguna equis
definitiva, a propósito.

---

## Entrar

La pantalla dice **«Reparto»** y debajo **«Entra con tu usuario de Procovar.»**

Dos campos, **«Usuario o correo»** y **«Contraseña»** (con un ojo para verla), y el
botón **«Entrar»**. Vale también la tecla intro.

**En la web esta pantalla casi nunca se ve**: te lleva sola al acceso único de
Procovar y lo único que aparece es «Entrando con tu cuenta de Procovar…». El
formulario sólo sale si eso falla.

**En la APK y el escritorio**, debajo del botón, una de estas dos frases:

- «Para entrar hace falta conexión. Una vez dentro, no: puedes seguir trabajando el
  día entero sin señal.»
- «Para entrar hace falta conexión, y **en este aparato hará falta cada vez que
  abras la aplicación**.»

**La segunda es un aviso serio**: ese aparato no guarda la sesión, así que cada vez
que cierres la aplicación tendrás que volver a entrar, y para eso hace falta señal.
Avísalo en la oficina antes de irte al almacén.

### Los mensajes de error al entrar

| Mensaje | Qué hacer |
|---|---|
| **«Usuario o contraseña incorrectos.»** | Pruébalo otra vez |
| **«La cuenta no está dada de alta en ninguna sucursal, o la sucursal pedida no es suya.»** | «No es un fallo de la aplicación: tu cuenta entró bien. Pide en la oficina que te den de alta en tu sucursal y vuelve a entrar.» |
| **«tu sucursal MOA no está dada de alta en Reparto: pide en la oficina que la den de alta»** | Entras, pero cada pantalla se niega con esto. Tu cuenta es buena: te asignaron una sucursal que Reparto no tiene (Moa, Palma Soriano…). Pide en la oficina que la den de alta o que te asignen una de las ocho. Ver [Roles y sucursales](../roles-y-sucursales.md#si-tu-sucursal-no-está-dada-de-alta-en-reparto) |
| **«La cuenta está dada de baja.»** | «Pregunta en la oficina» |
| **«Demasiados intentos seguidos. Espera un minuto y vuelve a probar.»** | Esperar un minuto |
| **«Sin conexión con el servidor. Para entrar hace falta conexión; prueba otra vez cuando haya señal.»** | «Comprueba la señal. Lo que ya estaba descargado sigue en el aparato.» |
| **«El servidor de acceso no contesta.»** (web) | «La página cargó, así que conexión hay: el que no contesta es el servidor.» |
| **«El servidor no dejó pasar la petición (403). No es tu contraseña: avisa a la oficina.»** | Avisar a la oficina |

Y si tu sesión se perdió:

> **Tu sesión se perdió.**
>
> Los datos que bajaste siguen en el aparato. Para volver a entrar hace falta señal;
> **no es tu contraseña**.

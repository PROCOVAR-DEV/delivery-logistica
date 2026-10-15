# Identidad

Auth (`auth.procovar.cloud`) sigue mandando en personas, roles y sucursales. Nada de eso se
mueve. Lo que se añade es una puerta de entrada por token, para la APK.

El patrón está resuelto y probado en `call-center-board`, que entra directo contra
AuthCenter desde Flutter. **Se copia la forma, no el código.**

---

## La regla que lo simplifica todo

> **Para entrar hace falta conexión. Una vez dentro, no.**

No hay acceso sin conexión y no se intenta. Quien entró sigue trabajando aunque pase días
sin señal.

Esto no es una limitación, es lo correcto: validar una contraseña contra una copia guardada
en el teléfono significa que dar de baja a alguien no sirve de nada mientras ese aparato no
se conecte. Con esta regla, la baja hace efecto en el momento en que intente entrar.

Y no hay riesgo de perder trabajo. Si la sesión murió, cuando el aparato por fin conecte
**tiene conexión** —o sea, puede volver a entrar— y la cola sube igual. El trabajo nunca se
queda atrapado.

---

## Dos formas de entrar

| Cliente | Cómo | Qué guarda |
|---|---|---|
| **Web** (Flutter) | Login único de auth, como hoy: redirección y vuelta con sesión | Cookie |
| **APK** (Flutter) | Usuario y contraseña contra el endpoint de token | El par, en el almacén seguro del sistema |

### La APK no lleva ninguna clave dentro

Hoy delivery firma cada petición a auth con HMAC y una clave propia de la aplicación. Eso
funciona porque vive en un servidor. **Una APK se descompila**: esa clave dentro del
teléfono deja a cualquiera hacerse pasar por delivery ante auth.

Y hablar con la base de auth directamente sería peor: dos sitios comprobando contraseñas y
dos sitios donde dar de baja a alguien.

La APK manda usuario y contraseña por HTTPS y recibe un par de tokens. No guarda ningún
secreto de aplicación.

---

## Lo que hay que añadir en auth

```
POST /token      usuario + contraseña        → { token, refresh }
POST /refresh    refresh (un solo uso)       → { token, refresh }   ← par NUEVO
POST /logout     refresh                     → revoca
```

El token de acceso lleva dentro el `sub`, la sucursal y los roles, que es lo que la API ya
lee.

---

## Las tres reglas de la sesión

### 1 · El refresh se sustituye entero

Es de un solo uso. Guardar el viejo no es inútil: el servidor lo lee como reutilización y
**revoca todas las sesiones de esa cuenta**.

### 2 · Una sola renovación en vuelo

Quien llegue mientras otra renovación está en curso **espera a esa y reutiliza su
resultado**, en vez de lanzar la suya con el mismo refresh.

> En reparto esto es más peligroso que en cualquier otro sitio de Procovar: **el teléfono
> recupera señal y dispara la cola entera de golpe**. Varias peticiones a la vez, varias
> renovaciones a la vez, y el logístico se queda fuera de todas sus sesiones justo en el
> momento en que iba a subir el trabajo del día.

El candado va desde la primera línea, no después. Y se libera pase lo que pase: una
renovación fallida que dejara el candado puesto impediría cualquier intento posterior.

### 3 · Un 401 mata la sesión. Un fallo de red, no.

```
200        → dentro
401        → sesión muerta: limpiar y a la pantalla de acceso
red o 5xx  → CONSERVAR los tokens y reintentar luego
```

Esta es exactamente la regla del caso sin conexión. Borrar los tokens por una caída pasajera
obliga a entrar otra vez sin motivo — y en la calle eso es quedarse sin aplicación con el
trabajo del día dentro.

---

## Al arrancar

No se comprueba el token de acceso por su cuenta: dura minutos, así que casi siempre estará
caducado al abrir, y eso no significa que la sesión haya muerto. Se intenta **renovar**, que
hace las dos cosas a la vez — si el par sirve devuelve uno nuevo, y si no, no sirve.

Y si no hay red al arrancar, se entra igual con lo guardado. Ver la regla 3.

---

## Al recuperar la señal, el orden

```
1. renovar     ← primero, SI HACE FALTA
2. subir la cola
3. bajar diferencias
```

Ocho horas sin conexión dejan el acceso caducado. Si la cola sale con el viejo, todo
responde 401 y se para.

**«Si hace falta», no «siempre» — 15/10/2026.** El escritorio de Santiago (1.0.35)
renovaba en cada vuelta del ciclo: 142 `POST /refresh` en cinco horas, uno cada 15–60 s.
Cada renovación rota el refresh, y con la conexión de allá una respuesta se perdió: el
reintento llevó el refresh viejo y Accesos le cerró todas las sesiones (regla 1). Ahora el
ciclo renueva sólo si no se sabe cuánto le queda al token o le quedan menos de **5
minutos** (`Renovador.margenParaRenovar`, con el porqué del número). Cuánto le queda **no
se compara con el reloj del aparato**, que puede ir desfasado: se cuenta `exp − iat` (los
dos del servidor) desde la hora del aparato en que se PIDIÓ el par (`Sesion.pedidoA`,
guardada con él). Un reloj que va hacia atrás es «no se sabe» y renueva. El 401
(interceptor y canal de eventos), el aviso de Accesos (`renovarPorAviso`) y el arranque
siguen renovando en el acto. Un cambio de rol se nota igual en ≤ 15 minutos, porque el
token se renueva antes de caducar. Pruebas: `app/test/nucleo/sincro/renovar_solo_si_hace_falta_test.dart`.

---

## Cuánto dura cada token — decidido

| Token | Dura | Por qué ese número |
|---|---|---|
| **Acceso** | **15 minutos** | Va en cada petición y **no se puede revocar**: una vez emitido, vale hasta que caduca. Quince minutos es el mismo valor que usa `call-center-board` y acota la ventana de un token robado a casi nada. Que caduque a media tarde no molesta a nadie: se renueva solo. |
| **Refresh** | **30 días** | Es el número que de verdad importa, y abajo está el razonamiento. |

### Por qué 30 días y no otra cosa

El refresh **se renueva cada vez que se usa**, así que este número no le afecta a quien
coge señal a menudo: un aparato que conecta cada mañana se renueva indefinidamente. Sólo
muerde al que ha estado **todo ese tiempo sin conectarse ni una vez**.

Con eso en la mano, el número se decide entre dos cosas que tiran en sentidos contrarios:

- **Muy corto molesta a quien no tiene la culpa.** Siete días no aguantan una avería de
  línea de dos semanas, ni unas vacaciones, ni una baja. Y el que se queda fuera es
  justamente el que está en el patio de un almacén en Palma, con el trabajo del día en el
  teléfono y sin nadie a quien preguntar. No se pierde nada —cuando conecta puede volver a
  entrar y la cola sube— pero le arruinas la tarde.
- **Muy largo alarga la baja.** Si das de baja a alguien, su aparato sigue funcionando
  hasta que el refresh caduque. Noventa días es demasiado tiempo para eso.

**Treinta días** cubre una ausencia de dos semanas más una racha mala, y deja la ventana de
una baja en un mes.

### Y la baja no se arregla acortando el token

Acortarlo para que las bajas hagan efecto antes es pagar todos los días por un caso que
pasa dos veces al año. Lo que sí lo arregla es que **el sincronizador sabe qué aparatos
hay**: se marca el aparato como dado de baja y a la primera conexión se le cierra la
sesión. Eso es inmediato en cuanto el aparato aparece, que es el único momento en que se le
puede hacer algo de todas formas.

Ver la tabla `aparatos` en `sincronizacion.md`.

---

## Guardar la sesión no es lo mismo que haberla guardado — 15/09/2026

Se probó la aplicación de escritorio compilada: se entró con una cuenta de verdad, se cerró
y se volvió a abrir, y **pidió la contraseña otra vez**. El par estaba escrito en el llavero
del sistema —se leyó el fichero—, así que guardar guardó; lo que falló fue **leerlo al
arrancar**.

La causa, comprobada a mano contra el llavero de este equipo con el propio código de
`flutter_secure_storage_linux` 3.0.3: el plugin escribe el secreto, y el `lookup` de vuelta
—con la misma etiqueta y la misma cuenta— no encuentra nada. Su `SecretSchema.name` apunta
al buffer interno de un `std::string` que se reasigna después (`setLabel`), así que el
atributo `xdg:schema` que queda escrito es basura. **En Linux ese almacén es de sólo
escritura.** En Android (Keystore) no pasa, pero la regla que sale de aquí vale para los
tres destinos:

1. **El almacén no lanza nunca.** `leer()` que falla devuelve `null` y lo deja en el
   registro. Una excepción ahí sube hasta el portero, que la traduce a «no hay sesión» y
   deja a la persona delante de un formulario mudo. Y un `leer()` que falla **no borra**:
   un almacén que hoy no contesta puede contestar mañana, y borrar el par por un fallo del
   sistema es la regla 3 aplicada al disco.
2. **`guardar()` lee de vuelta y dice si quedó.** «La escritura no dio error» y «la sesión
   está guardada» son dos cosas distintas, y la que importa es la segunda.
3. **Si el aparato no guarda, se dice AL ENTRAR.** La pantalla de acceso le pregunta al
   almacén si sirve —una ida y vuelta de verdad, con su propia clave— antes de pedir la
   contraseña, y si no sirve **no escribe la promesa**: en su lugar dice que en este
   aparato hará falta entrar cada vez. O se cumple, o no se promete.
4. **Sin sesión pero con datos en el aparato no es «entra»**: es «tu sesión se perdió y
   hace falta señal». Un formulario mudo deja a esa persona probando su contraseña buena en
   el patio de un almacén, convencida de que se le olvidó.

---

## Al cerrar sesión se CAMBIA DE COPIA, no se borra — 15/09/2026

En el aparato quedan los clientes con sus direcciones y los pedidos del día, y si el
teléfono cambia de manos eso no puede seguir ahí. Hasta el 15/09/2026 la respuesta a eso
era borrar el dominio al salir y **dejar la cola**, a propósito. Con una sola base por
aparato eso daba lo siguiente:

1. A entra, baja lo suyo, trabaja sin señal y le quedan 23 apuntes sin subir.
2. A cierra sesión: sus datos se borran, **sus 23 apuntes se quedan**.
3. Entra B y baja lo suyo.
4. Al haber señal, **los 23 apuntes de A suben con el token de B**.

Trabajo de una sucursal subiendo como si fuera de otra. Y además A se rebajaba sus ocho mil
clientes cada vez que alternaban, por la conexión de allá.

Ahora **cada persona tiene su copia**: su base y su cola, en un fichero por `sub`
(`app/lib/nucleo/base/conexion/nombre.dart`). Salir cambia de copia y quien vuelve
encuentra lo suyo. La cola de cada quien sube con el token de quien la hizo, y la subida lo
comprueba otra vez contra el dueño anotado dentro de la propia base.

**Lo que esto no cierra**: los datos de quien salió siguen en el disco. El borrado de antes
tampoco protegía gran cosa —dejaba la cola entera, con los resultados de entrega y las
notas dentro, y sólo borraba del que se iba, nunca del que no había vuelto— pero el cambio
es real y hay que decirlo. La mitigación es **olvidar a una persona**, un gesto aparte y
explícito que borra su copia entera y avisa antes si tiene trabajo sin subir; no pasa sola
al cerrar sesión, porque cerrar sesión es lo que hacen diez veces al día dos personas que
comparten la tablet, y borrar ahí es tirar el día de alguien sin decírselo. Lo que lo
cerraría de verdad es cifrar cada copia con una clave derivada de la contraseña, y eso
choca con la regla de que sin conexión no se comprueba ninguna contraseña. Queda escrito
para el día que se decida.

---

## Dónde guarda cada destino, y por qué el escritorio no usa el llavero — 15/09/2026

La sesión se guarda en un sitio distinto según el aparato, y no por capricho:

| Destino | Dónde | Comprobado |
|---|---|---|
| **Android** | Keystore, vía `flutter_secure_storage` | sí, funciona |
| **Linux (escritorio)** | **fichero propio, cifrado**, en `~/.local/share/cloud.procovar.reparto/sesion.caja` | sí — entrar, cerrar, abrir sin red y entrar sin contraseña |
| **Windows (escritorio)** | DPAPI, vía `flutter_secure_storage` | **no** — no se puede comprobar desde Linux |
| **Web** | la cookie de auth; el almacén devuelve `null` siempre | sí |

En Linux el almacén del sistema **es de sólo escritura** y por eso se dejó de usar:
`flutter_secure_storage_linux` 3.0.3 arma su `SecretSchema` con
`the_schema.name = label.c_str()` en el constructor y después reasigna ese `std::string`
en `setLabel()`. El puntero queda colgando, el atributo `xdg:schema` que se escribe es
basura, y el `lookup` de vuelta —misma etiqueta, misma cuenta— no encuentra nada. `write`
dice que sí, `read` devuelve vacío. Eso es exactamente el caso S1 de `pruebas.md` fallando,
y **descalificaba la aplicación de escritorio entera**: cierras, abres sin señal y no
puedes entrar, con tus datos ahí mismo en el disco.

Se eligió almacén propio en vez de mantener un fork del plugin porque el fork obliga a
compilar C++ nuestro en cada máquina que compile, ata a seguir la versión de arriba para
siempre, y **aun arreglado dependería de que haya un servicio de secretos corriendo y
desbloqueado**. El fichero está siempre.

### Qué seguridad tiene ese fichero, sin adornos

La clave sale de `HMAC-SHA256(sal del fichero, machine-id + usuario + ruta)`, y las tres
piezas de ese material se pueden leer en esta máquina con esta cuenta. **Tiene que ser
así**: la regla de arriba dice que sin conexión no se comprueba ninguna contraseña, así que
la clave no puede salir de la contraseña de nadie — si saliera, abrir sin señal la pediría,
que es justo lo que este almacén evita.

- **No protege** de quien entre con esa cuenta en ese ordenador, ni de root, ni de un
  programa corriendo como esa persona. Ahí lo único que hay son los permisos `0600` y que
  el refresh caduca a los 30 días.
- **Sí protege** de que el fichero viaje suelto y siga sirviendo: una copia de seguridad
  restaurada en otra máquina, el directorio en un pendrive, la carpeta adjunta en un
  informe de fallo. Fuera de esa máquina y esa cuenta no se abre.
- **Sí evita** que el token salga en claro en un `grep`, en un indexador o en un vistazo al
  disco.

Es **cifrado atado a la máquina**, no una caja fuerte, y está escrito así en
`app/lib/nucleo/identidad/almacen_sesion_fichero.dart`.

### Windows sigue sin comprobarse

DPAPI es otro código nativo y el fallo de Linux no le aplica, pero **eso no es haberlo
probado**. Si alguna vez se ve el mismo cuadro —entrar, cerrar, abrir y que pida la
contraseña—, la salida ya está escrita: ese mismo fichero, que no depende de ningún
servicio del sistema. Mientras tanto, la comprobación es la de siempre y la hace la propia
aplicación al entrar: si el almacén no guarda, **no se promete** el día entero sin señal.

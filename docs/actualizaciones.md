# Cómo le llega una versión nueva a los diez logísticos

La web se actualiza sola. Los aparatos no: alguien tiene que bajarse un fichero e
instalarlo. Este documento dice cómo se anuncia que hay una versión nueva, cómo se entera
el aparato y con qué clave se firma el APK.

Compilar los ficheros es lo de antes y está aparte: **`docs/compilar.md`**.

Lo que hay montado:

```
docs/compilar.md                   cómo se saca cada salida y desde qué máquina
api/internal/api/version.go        GET /api/version: qué hay publicado y de dónde se baja
api/internal/config/config.go      de dónde sale ese anuncio (§ Publicada)
app/lib/nucleo/actualizacion/      la comprobación en el aparato, y la bajada (§5-bis)
app/lib/nucleo/descarga/           el motor de bajar, compartido con el mapa de Cuba
app/android/.../InstaladorDeApk.kt lo que le pide a Android que instale
docs/actualizaciones.md            esto
```

**En Android, desde el 05/10/2026, el fichero se baja DENTRO de la aplicación** —con su
barra, reanudable y comprobado por `sha256`— y sólo el «¿instalar?» final es una pantalla
del sistema. Ver **§5-bis**. En el escritorio sigue siendo el navegador.

---

## 1. Las tres reglas

Están escritas en el código, cada una en el sitio donde se cumple, y ninguna es una
preferencia de estilo.

### 1.1 No se actualiza con cola pendiente

Si al logístico le queda el cierre de la tarde sin subir, la aplicación **se niega** y dice
por qué: primero sube, después actualiza.

El motivo es concreto, no una precaución genérica. La base local es **la fuente de verdad**
de la aplicación: lo que se hizo sin red vive ahí y sólo ahí hasta que la cola de salida lo
sube (`app/lib/nucleo/cola/cola_salida.dart`). Una instalación que salga mal —o, en
Android, una que obligue a desinstalar (§4)— se lleva esa base por delante. Lo que se
pierde no es «la configuración»: es el trabajo del día de una persona, y no hay de dónde
sacarlo otra vez.

En el código: `ComprobadorDeActualizacion.comprobar()` mira
`BaseLocal.cuantosPendientes()` y devuelve `PrimeroSube` con **cuántos** quedan. Con el
número se puede decir «te quedan 14 cosas por subir», que es accionable; «no puedes
actualizar» no lo es.

La cuenta se mira **la última**, sólo cuando de verdad hay algo más nuevo que instalar.
Mandar a alguien a buscar señal para subir la cola cuando no hay ninguna versión nueva es
mandarle a buscar señal por nada.

### 1.2 Nunca se fuerza

Se avisa; decide la persona. No hay descarga automática, no hay instalación automática, no
hay pantalla que no se pueda cerrar y no hay versión mínima que bloquee la entrada.

Quien usa esto está en el patio de un almacén, con un camión delante y a lo mejor con la
señal justa. Que la aplicación decida por él que ahora toca bajarse 40 MB es peor que
cualquier versión vieja.

En el código: `comprobar()` hace **una** petición `GET` y devuelve un estado. No baja
nada, no abre nada y no instala nada; la prueba
`app/test/nucleo/actualizacion/comprobador_test.dart` lo comprueba contando las peticiones
que salieron.

### 1.3 La web se actualiza sola y no entra aquí

La web recarga y ya está con la última: no descarga nada, no instala nada y no tiene una
base que una instalación pueda romper. Meterle este aviso sería enseñarle a alguien un
«hay una versión nueva» que no puede hacer nada con él.

En el código: `Plataforma.deEsteAparato()` devuelve `ninguna` en web, y `comprobar()` sale
en la primera línea **sin llamar siquiera al servidor**. Ojo con el orden: `kIsWeb` se mira
antes que `defaultTargetPlatform`, porque en web esa última devuelve el sistema del
navegador —`android` en un teléfono— y sin esa línea la web abierta en un móvil se creería
una APK.

---

## 2. El anuncio: `GET /api/version`

La ruta ya existía y va **sin sesión** (la consulta el aparato antes de entrar). Lo que se
le añadió es el bloque `ultima`.

```jsonc
{
  "version": "a3f9c21",            // la de ESTE servicio, la del -ldflags. Ya estaba.
  "ultima": {                       // null mientras no haya nada publicado
    "version": "1.5.0",
    "compilacion": 12,              // el versionCode de Android; null si no se dijo
    "notas": "El cierre de ruta ya no pierde las fotos.",
    "publicadaAt": "2026-09-15T00:00:00Z",
    "descargas": {
      "android": "https://…/reparto-1.5.0.apk",
      "windows": "https://…/reparto-1.5.0-windows.zip",
      "linux":   "https://…/reparto-1.5.0-linux.tar.gz"
    }
  }
}
```

**`version` y `ultima.version` no son el mismo número y no tienen por qué coincidir
nunca.** `version` es la de la api; `ultima` es la de la aplicación. Se despliegan por
separado. Si el aparato comparase lo suyo contra `version`, cada despliegue de la api
mandaría a diez personas a reinstalar una aplicación que no ha cambiado.

Detalles que importan:

- **`ultima: null` es lo normal** mientras no haya un fichero colgado de verdad. El aparato
  entonces no avisa de nada. Es mejor que inventarse una versión y mandar a diez personas a
  un enlace que no existe.
- **Una plataforma sin fichero no aparece en `descargas`.** No sale con la cadena vacía:
  eso sería un enlace en la pantalla de alguien que al pulsarlo no lleva a ninguna parte.
- **No hay clave `web`** y no la va a haber (regla 1.3).
- Sigue siendo **síncrono y sin tocar Postgres**: los diez aparatos llaman aquí a la vez, al
  arrancar, la mañana que vuelve la señal.
- Sigue saliendo con `Cache-Control: no-store, must-revalidate`, que lo pone el middleware
  `httpx.SinCache`.

## 3. Cómo se publica una versión

Publicar son **dos actos separados**, y en este orden:

1. **Colgar los ficheros.** Se compilan a mano (`docs/compilar.md`) y se suben a **MinIO**,
   que es donde viven desde el 22/09/2026 — ver §3-bis.
2. **Anunciarlos**, poniéndole a la api estas variables y volviéndola a desplegar:

| Variable | ¿Obligatoria? | Qué es |
|---|---|---|
| `APP_ULTIMA_VERSION` | la que manda | El número de `pubspec.yaml` sin el `+`: `1.5.0`. Vacía = no se anuncia nada. |
| `APP_ULTIMA_COMPILACION` | muy recomendable | El número de después del `+`, el mismo `versionCode` del APK. |
| `APP_DESCARGA_ANDROID` | al menos una | URL del `.apk`. |
| `APP_DESCARGA_ANDROID_BYTES` | con su URL | Lo que dice `ls -l` del fichero. |
| `APP_DESCARGA_ANDROID_SHA256` | con su URL | Lo que dice `sha256sum`. |
| `APP_DESCARGA_WINDOWS` | al menos una | URL del `.zip` del escritorio de Windows. |
| `APP_DESCARGA_WINDOWS_BYTES` · `_SHA256` | con su URL | Igual que Android. |
| `APP_DESCARGA_LINUX` | al menos una | URL del paquete del escritorio de Linux. |
| `APP_DESCARGA_LINUX_BYTES` · `_SHA256` | con su URL | Igual que Android. |
| `APP_ULTIMA_NOTAS` | no | Una línea de qué trae. Si está vacía, el aviso no la enseña. |
| `APP_ULTIMA_PUBLICADA` | no | `2026-09-15` o `2026-09-15T10:00:00Z`. Se guarda normalizada. |

**Los tres números van juntos: URL, BYTES y SHA256.** Poner la URL sola para el arranque,
igual que en los niveles del mapa, y por los mismos dos motivos.

Y el primero de ellos se descubrió con Jose delante — **22/09/2026**. Se puso a bajar la
APK por datos móviles y la pantalla decía **«30 MB/?»**: no sabía cuánto le iba a costar.
El tamaño salía del `Content-Length`, y **Cloudflare lo quita de la respuesta completa**
(MinIO sí lo manda; se comprobó desde dentro del servidor, hablándole directo). Un número
que depende de lo que haya por el camino no es un número. Ahora lo dice la api, y el
aparato lo enseña antes de que nadie pulse: «Son 74,0 MB».

El segundo es el de siempre: sin `sha256` una descarga cortada pasa por buena. Es la
guarda que salva al mapa desde el principio y a la APK le faltaba.

**El contrato creció por un lado nuevo, no cambiando el que había.** `descargas` sigue
siendo una URL pelada por plataforma, y al lado va `ficheros` con `{bytes, sha256}`. No es
indecisión: las APK instaladas leen `descargas` esperando una cadena y **se saltan en
silencio lo que no lo sea**. Convertirla en objetos no habría dado un error, habría dado
teléfonos que dejan de ofrecer la actualización sin decir nada — y sin poder actualizarse
para arreglarlo. Lo sujeta `TestDescargasSigueSiendoLaURLPelada`.

**Media configuración no arranca el servicio**, y es a propósito
(`api/internal/config/config.go`, `leerPublicada`):

- URL puesta y `APP_ULTIMA_VERSION` vacía → no se anunciaría nada nunca, sin un solo error
  a la vista. Desde fuera se ve como «los aparatos no avisan».
- Versión puesta y ninguna URL → diez personas enteradas de que tienen que actualizar y
  ningún sitio de donde bajarlo.
- URL sin `http://` ni `https://`, o `APP_ULTIMA_COMPILACION` que no es un número → tampoco
  arranca: una errata ahí hace que el aviso no funcione nunca y no se parece en nada a un
  error de configuración cuando se descubre.

Las dos cosas paran el arranque, que es el momento en que lo ve quien despliega. Y si no se
anuncia nada, el registro lo dice al arrancar:

```
APP_ULTIMA_VERSION vacía: /api/version no anuncia ninguna versión de la aplicación,
así que ningún aparato avisará de que hay una nueva
```

### Por qué el entorno y no la base

Publicar es un acto del despliegue, no un dato del reparto: no tiene alcance por sucursal,
no lo edita nadie desde una pantalla y no hace falta una migración para cambiarlo. Además
así el manejador no toca Postgres, que es lo que permite que lo llamen los diez aparatos a
la vez.

## 3-bis. Dónde se cuelgan los ficheros: **MinIO**, desde el 22/09/2026

Estuvo sin decidir a propósito —y por eso `APP_ULTIMA_VERSION` se quedaba vacía, que es el
estado seguro—. Ya está decidido, y **está hecho**:

```
https://archivos.procovar.cloud/reparto/apk/reparto-<version>-<fecha>.apk
```

Es un almacén **S3 de verdad** (MinIO) en su propia Application de Dokploy, en el proyecto
Infraestructura del VPS. Los bytes viven en `/var/lib/procovar/minio` del **host**, no dentro
de ninguna imagen. El detalle entero —imagen fijada, montaje comprobado, credenciales,
consola— está en `../../docs/VPS-179.198.107.1.md`.

**Por qué no la carpeta del nginx de la web, que era el candidato natural**: porque ya se
probó y se cayó. El 21/09/2026 un despliegue de `reparto-web` se llevó por delante los
ficheros del mapa que estaban dentro de esa imagen, y la URL empezó a contestar **200 con el
`index.html` de la aplicación dentro de un `.pmtiles`**. Con el APK sería peor: un `.apk` de
1.608 bytes se baja «bien» y no instala. Lo cuenta entero `mapa-sin-conexion.md` §5.4.

**Y por qué no una Release de GitHub**: el repositorio es privado, así que la descarga pediría
credenciales en el teléfono de un logístico.

### Así se sube uno nuevo

Desde dentro del servidor, con `mc-procovar` —corre el cliente de MinIO en un contenedor de
usar y tirar; en el host no se instala nada—. `/var/lib/procovar` del host se ve como `/host`:

```bash
scp app/build/app/outputs/flutter-apk/app-release.apk \
    vps:/var/lib/procovar/apk/reparto-1.1.0-261005.apk

ssh vps 'mc-procovar cp \
  --attr "Content-Type=application/vnd.android.package-archive;Cache-Control=private, no-store" \
  /host/apk/reparto-1.1.0-261005.apk procovar/reparto/apk/reparto-1.1.0-261005.apk < /dev/null'
```

**El `Cache-Control: private, no-store` es obligatorio y no es cosmética.** El dominio pasa por
Cloudflare, Cloudflare **cachea los `.apk`** y de esa copia suya **no sirve peticiones por
rango**: contestaba `200` con los 77 MB enteros y un `ETag` débil en vez de `206`. Sin rango
**la descarga no se puede reanudar**, y 77 MB sin reanudar, en la conexión de allá, es una
descarga que no termina nunca. Con `no-store` Cloudflare contesta `BYPASS` y el rango llega
intacto a MinIO. Comprobado los dos casos el 22/09/2026.

**El `< /dev/null` tampoco sobra**: el contenedor se lanza con `-i` y dentro de un guion
remoto `mc` se come el resto del guion sin decir nada.

### Y así se comprueba, antes de anunciarlo

```bash
ssh vps 'U=https://archivos.procovar.cloud/reparto/apk/reparto-1.1.0-261005.apk
curl -s -o /tmp/z "$U"
echo "sha=$(sha256sum /tmp/z | cut -d\  -f1) bytes=$(stat -c%s /tmp/z)"
echo "rango=$(curl -s -o /dev/null -w "%{http_code}" -r 0-99 "$U")   # tiene que ser 206"
echo "magia=$(head -c2 /tmp/z)                                        # tiene que ser PK"
rm -f /tmp/z'
```

`PK` es la firma de un zip, que es lo que hay debajo de un APK. **Si ahí sale `<!`, lo que
contesta es una página web y no un APK** — que es exactamente el fallo del 21/09.

### El APK que se anuncia — la 1.0.1, desde el 24/09/2026

Estas son las cinco líneas que van en el Environment de `reparto-api` en Dokploy, y las
mismas que están escritas en `docker-compose.yml` (de donde las leen dos pruebas):

```
APP_ULTIMA_VERSION=1.0.1
APP_ULTIMA_COMPILACION=2
APP_ULTIMA_PUBLICADA=2026-09-22
APP_DESCARGA_ANDROID=https://archivos.procovar.cloud/reparto/apk/reparto-1.0.1-260922.apk
APP_DESCARGA_ANDROID_BYTES=77646816
APP_DESCARGA_ANDROID_SHA256=565647928d03200b2eda25ef28bde55e0f0d3e034f99d561f38b33a6aa47c49e
```

Los tres números están **medidos dentro del servidor el 22/09/2026**, bajando el fichero por
el dominio y no del disco del host: misma huella que el fichero de `/var/lib/procovar`, `206`
a la petición por rango y `PK` de magia. La compilación es el `+2` de `1.0.1+2`, que es lo
que tenía `app/pubspec.yaml` cuando se compiló ese APK.

**Por qué la 1.0.1 y no la que hay en el repositorio.** `pubspec.yaml` va por `1.0.4+5`, pero
de la 1.0.4 no hay fichero colgado. Se anuncia lo que existe: inventarse la URL de un APK que
no está es mandar a diez personas a un enlace roto — exactamente el fallo del 21/09, cuando
la URL contestaba `200` con el `index.html` de la web dentro de un `.pmtiles`.

Y la que estaba anunciada antes, que sigue colgada de red:

```
https://archivos.procovar.cloud/reparto/apk/reparto-1.0.0-260921.apk
bytes  76.810.980
sha256 02b12cf29dea62896f70d22c9fd8faa5e9e8d81a3d0bdc4ee34dc243db4c5bb5
```

Se borra —`ssh vps 'rm -f /var/lib/procovar/apk/reparto-1.0.0-260921.apk'`— cuando Jose
confirme que la 1.0.1 se descarga y se instala desde la URL nueva, y no antes.

> **La mudanza, tal como se hizo, y el orden importa.** Primero se subió el APK a MinIO y se
> comprobaron las cuatro cosas de arriba **con la api todavía anunciando la URL vieja** —así
> una prueba fallida no le cuesta la descarga a nadie—. Sólo entonces se cambió
> `APP_DESCARGA_ANDROID` en el entorno de `reparto-api` (`applicationId
> 0iQ8gLv5ZIHD1n_DRlzOa`) y se volvió a desplegar. Por la API de Dokploy,
> `application.saveEnvironment` quiere además `buildArgs`, `buildSecrets` y `createEnvFile` o
> contesta 400: se releen de `application.one` y se devuelven tal cual. Y la comprobación que
> vale es tomar la URL **de lo que contesta `/api/version`**, no de lo que uno cree haber
> puesto, y bajarla.
>
> **El `.apk` viejo dentro del contenedor de la web se queda de red** hasta que Jose confirme
> que se descarga y se instala desde la URL nueva. Cuando lo diga:
> `ssh vps 'rm -f /var/lib/procovar/apk/reparto-1.0.0-260921.apk'`.

> **El nombre lleva versión y fecha, y por eso.** Colgar uno nuevo encima del viejo son dos
> fallos en uno: mientras se sube, la api anuncia un fichero que ya no está debajo, y si algo
> sale mal no queda a qué volver. Con el nombre distinto el viejo sigue sirviendo hasta que
> las variables apuntan al nuevo, y el cambio lo hace el despliegue de la api.

## 4. La firma del APK — RESUELTA el 21/09/2026

> **YA ESTÁ PUESTA LA CLAVE DE VERDAD.** `app/android/key.properties` existe y apunta al
> almacén de `procovar/.secretos/`, así que `flutter build apk --release` sale firmado con
> ella. Este apartado decía «HOY ESTÁ MAL» hasta el 24/09/2026 y era lo primero que leía
> cualquiera que viniera a publicar una versión: mandaba a rehacer un trabajo ya hecho, y
> además daba por bloqueado el reparto de APK que ya no lo está. Se deja lo de abajo
> entero porque explica **por qué** importa y cómo se comprueba, que sigue haciendo falta
> cada vez.

> **De dónde venía.** `app/android/app/build.gradle.kts` firmaba el APK de release con la
> clave de DEPURACIÓN. Venía así de la plantilla de `flutter create`, con su `TODO` puesto.

Por qué no es un detalle:

- La clave de depuración (`~/.android/debug.keystore`) **la genera Android sola** en cada
  máquina, y **se regenera** si se borra, si se reinstala el sistema o si un día el APK sale
  de otro equipo. No es «una clave floja»: es una clave que no se controla.
- Android **no acepta como actualización** un APK firmado con una clave distinta de la del
  APK instalado. No es un aviso: el sistema lo rechaza. La única salida es **desinstalar**.
- **Desinstalar borra la base local.** Y la base local es el trabajo del día sin subir.

O sea: repartir hoy un APK «nuevo» le puede costar a un logístico el trabajo de la tarde, y
el aviso que verá es un «la aplicación no se pudo instalar» que no explica nada.

Lo que se cambió: el fichero ahora usa una clave de verdad **si la hay**, y si no la hay
sigue compilando con la de depuración pero lo avisa desde Gradle:

```
AVISO: no hay android/key.properties, así que este APK va firmado con la
clave de DEPURACIÓN. Android NO lo acepta como actualización de uno firmado
con otra clave: obliga a desinstalar, y desinstalar BORRA LA BASE LOCAL (el
trabajo del día sin subir). No se reparte. Ver docs/actualizaciones.md.
```

Compilar sin clave tiene que seguir funcionando —hace falta para `flutter run --release` y
para que cualquiera pueda clonar el repositorio y compilar—; lo que no puede pasar es que
salga un APK firmado con depuración y alguien lo reparta creyéndolo bueno.

> **Y ojo con esto, que se comprobó el 15/09/2026 y no es lo que uno esperaría:** con
> `flutter build apk --release` **el aviso NO se ve**. La herramienta de Flutter se traga la
> salida corriente de Gradle y sólo la enseña cuando el build falla. El aviso sale con
> `flutter build apk --release -v`, o llamando a Gradle directo.
>
> Por eso **la comprobación que vale es la de abajo, `apksigner`**, y no «no me salió
> ningún aviso».

### Cómo se configura la clave de verdad

**No se genera aquí ninguna clave y no se inventa ninguna contraseña.** Esto lo hace Jose,
una vez, en su equipo, y las contraseñas las elige y las guarda él.

**1. Crear el almacén de claves** (una sola vez en la vida del proyecto; `keytool` viene con
el JDK):

```bash
keytool -genkey -v \
  -keystore ~/procovar-reparto.jks \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias reparto
```

Pide dos contraseñas —la del almacén y la del alias— y unos datos de identificación.
Elígelas tú y guárdalas donde van las cosas de esta casa: `procovar/.secretos/`, con
permisos 600.

> **Este fichero es irreemplazable.** Si se pierde, **no hay forma** de publicar una
> actualización que Android acepte encima de lo instalado: habría que desinstalar en los
> diez aparatos, y eso es borrar la base local de los diez. Copia de seguridad fuera del
> portátil, y fuera del repositorio.
>
> `10000` días son unos 27 años. Una validez corta caduca y deja el mismo problema.

**2. En el equipo de quien compila**, crear `app/android/key.properties` (ya está en
`.gitignore`, junto con `*.jks`):

```properties
storeFile=/ruta/absoluta/a/procovar-reparto.jks
storePassword=<la que elegiste para el almacén>
keyAlias=reparto
keyPassword=<la que elegiste para el alias>
```

Con eso, `flutter build apk --release` sale firmado con la buena y el aviso desaparece.

**3. Comprobar con qué clave salió.** Esto se mira **en el APK ya hecho**, que es el único
sitio donde la respuesta es segura (`apksigner` viene con el SDK de Android, en
`$ANDROID_HOME/build-tools/<version>/`):

```bash
# En este equipo: ~/Android/sdk/build-tools/36.0.0/apksigner
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

El 15/09/2026, antes de tener la clave, eso contestaba **`CN=Android Debug`** sobre el APK
que salía de `flutter build apk --release`:

```
Signer #1 certificate DN: C=US, O=Android, CN=Android Debug
```

Con la clave de verdad puesta —lo está desde el 21/09/2026— ahí sale el nombre que se
escribió al crearla, y **no** `Android Debug`. **Se mira en cada publicación**, porque
`key.properties` no está en el repositorio: en una máquina que no lo tenga, Gradle vuelve a
firmar con depuración y el aviso no se ve con `flutter build apk --release` a secas. El `SHA-256` que salga es la identidad del APK para Android:
**apúntalo en `procovar/.secretos/`**, que es lo que permite comprobar de un vistazo, dentro
de un año, si un APK que apareció por ahí es de los nuestros o uno de depuración que alguien
dejó suelto.

### Si algún día el APK se compila en otra máquina

No hace falta hoy —se compila en el portátil de Jose— pero la regla es la misma en
cualquier sitio: **el `.jks` y sus contraseñas no se copian a ningún servicio ajeno sin
pensarlo**. Quien tenga ese fichero y esas contraseñas puede publicar un APK que los diez
aparatos aceptarán como actualización del bueno. Si un día se automatiza, van como secretos
cifrados y nunca en el repositorio — por eso `key.properties`, `*.jks` y `*.keystore` están
en `.gitignore`.

## 5. La comprobación en el aparato

`app/lib/nucleo/actualizacion/`:

| Fichero | Qué hay |
|---|---|
| `version_publicada.dart` | `Plataforma`, `VersionInstalada`, `VersionPublicada` y `hayQueActualizar` |
| `comprobador.dart` | `ComprobadorDeActualizacion` y los cinco estados |

Y en `app/lib/nucleo/proveedores.dart`: `clienteVersionProvider`, `comprobadorProvider` y
`actualizacionProvider`.

### Los cinco estados

`EstadoDeActualizacion` es **sellado**, así que la pantalla que lo mire tiene que tratar los
cinco. Eso es lo que impide que «no se pudo comprobar» acabe pintado como «está al día».

| Estado | Qué pasó | Qué se enseña |
|---|---|---|
| `AlDia` | no hay nada más nuevo, o no se anuncia ninguna | nada |
| `NoAplica` | web, o no hay fichero para esta plataforma | nada |
| `NoSeSupo` | no hubo red, o el servidor contestó algo raro | **nada** |
| `SePuedeActualizar` | hay una nueva, con su enlace | el aviso, que se puede cerrar |
| `PrimeroSube` | hay una nueva **y queda cola** | «sube primero, te quedan N» |

`NoSeSupo` no se enseña a propósito. No saber si hay versión nueva no es una noticia para
quien está trabajando: se mira mañana.

### Dos decisiones que parecen detalles

**El cliente de esta comprobación no reintenta.** `clienteVersionProvider` monta un
`ClienteApi` propio con `ComprobadorDeActualizacion.sinEsperas`. El de las pantallas
reintenta a 1 s, 4 s, 15 s y 60 s, que es lo correcto para el trabajo de alguien y lo peor
posible aquí: ochenta segundos esperando para averiguar algo que puede esperar a mañana,
justo cuando la persona quiere entrar.

**Manda la compilación, no el número de versión.** `hayQueActualizar` compara los
`versionCode` cuando se saben los dos, porque es lo único que Android compara de verdad al
instalar encima. Sin compilación se comparan los números del `1.5.0` **tramo a tramo, como
números**: comparados como texto, `"1.10.0" < "1.9.0"`, y la 1.10 no se anunciaría nunca.
Ante la duda, `false`: un aviso de más manda a alguien a reinstalar lo que ya tiene; uno de
menos llega mañana.

## 5-bis. La bajada DENTRO de la aplicación (sólo Android) — 05/10/2026

> «el mapa sí me funciona dentro de la aplicación, pero la APK me manda a descargarla al
> navegador en vez de actualizar ahí mismo en la aplicación sin necesidad de salir»
> — Jose, 05/10/2026

Era una incoherencia nuestra: el mapa de Cuba se baja aquí dentro y la actualización —que
pesa el triple— echaba al navegador. **Lo raro era la actualización, no el mapa.**

### Lo que se perdía al salir, medido contra producción el 05/10/2026

```
Petición completa:   HTTP 200 · SIN content-length · sin accept-ranges
Pidiendo un trozo:   HTTP 206 · content-range: bytes 0-1023/78485416
```

**Los rangos funcionan**; lo que falla es que la respuesta completa no los ofrece, así que el
gestor de descargas de Android ni lo intenta — y tampoco sabe cuánto pesa, porque el
`Content-Length` lo quita Cloudflare (§3). O sea: 75 MB, sin reanudar, con una barra que no
sabe cuánto queda, y el fichero a buscar en Descargas. **Una descarga de 75 MB que no se
puede reanudar es una descarga que no termina**, y esta semana empieza a usar esto el
logístico de Santiago.

Bajándola desde la aplicación eso deja de importar: se pide por trozos y punto. Y los dos
números que hacían falta **ya viajaban en el anuncio y no los usaba nadie**:
`ficheros.android.bytes` y `.sha256` (`FicheroPublicado`).

### Las piezas

| Fichero | Qué hay |
|---|---|
| `app/lib/nucleo/descarga/descarga_reanudable.dart` | **el motor, que es el del mapa**: `.parcial`, `Range`, la comprobación de que el servidor de verdad reanudó, el tope y el `sha256` |
| `app/lib/nucleo/descarga/almacen_de_bajadas.dart` | dónde se escribe (y el doble en memoria de las pruebas) |
| `app/lib/nucleo/actualizacion/bajada_de_la_actualizacion.dart` | los estados, el apunte de qué versión es lo bajado y el reparto de salidas |
| `app/lib/nucleo/actualizacion/instalador.dart` | el puerto hacia Android |
| `app/android/.../InstaladorDeApk.kt` | el canal: `sePuede`, `instalar`, `ajusteDelPermiso` |
| `app/android/.../res/xml/ficheros_de_la_actualizacion.xml` | qué carpetas puede ofrecer el `FileProvider` |

**El motor no se duplicó: se sacó del mapa.** `mapa/descarga_de_mapa.dart` quedó como una
envoltura con las palabras del mapa y su apunte, y su API no cambió ni una letra —la pantalla
del mapa y sus 121 pruebas no se tocaron—. Dos descargadores que se separan es el fallo
clásico de esta casa: el día que uno aprenda algo, el otro no lo sabrá, y el que no lo sepa
será el que corre en el teléfono de quien está repartiendo.

### El fichero baja a `files/actualizacion/`

```
reparto.apk           el bueno, comprobado por bytes y sha256
reparto.apk.parcial   lo que se lleva bajado y todavía no vale
reparto.json          de qué versión es eso
```

**El apunte no es adorno**: sin él, un `.parcial` de la 1.0.22 se reanudaría con el `Range` de
la 1.0.23, los bytes cuadrarían al final —el tamaño lo dice el anuncio— y lo cazaría el
`sha256` **después de haber gastado la descarga entera**. Con el apunte se tira el parcial
ajeno antes de pedir un solo byte.

Y lo que ya está bajado **no se vuelve a bajar**: pasa más de lo que parece —se baja, Android
enseña su pantalla, la persona la cancela porque está conduciendo, y vuelve por la tarde—.

### Los permisos: son DOS y sólo uno es nuestro

1. `REQUEST_INSTALL_PACKAGES`, en el manifiesto. Se concede al instalar la APK; no se le pide
   a nadie. **No da instalar en silencio**: Android sigue enseñando su «¿instalar?».
2. **El ajuste por aplicación** de «instalar aplicaciones desconocidas» (Android 8+). Lo da la
   persona y **la primera vez no está dado en ningún teléfono**. Se pregunta
   (`canRequestPackageInstalls`) **antes** de ofrecer el botón: uno que lleva a una pantalla
   que no sale enseña a no fiarse del botón.

El fichero se le entrega al instalador por un `FileProvider` nuestro
(`${applicationId}.ficheros`, clase `FicherosDelReparto`) porque desde Android 7 un `file://`
a otra aplicación es una excepción. **La clase es propia y no `androidx.core.content
.FileProvider` a secas**: en este APK ya hay dos proveedores que son `FileProvider`
—`share_plus` y `printing`— y Android exige una clase distinta por `<provider>`.

### Los tres caminos que no son el feliz, y el navegador que no se quita

| Qué pasa | Qué se ve | Qué se puede hacer |
|---|---|---|
| **Falta el permiso** | «está descargada, falta un permiso», con el motivo | ir al ajuste · «ya lo di: instalar» · abrir en el navegador |
| **La descarga se corta** | el motivo con los MB que llegaron y «toca Seguir descargando» | seguir desde donde iba (y a los **tres** fallos seguidos, también el navegador) |
| **La huella no cuadra** | «no se instala a medias», y se borra lo bajado | empezar de nuevo |
| **Queda trabajo sin subir** | «te quedan N cosas por subir», y el botón de instalar **apagado** | subir primero; bajar sí se puede, y lo bajado se queda |

La cuarta es §1.1 llevada al sitio donde se puede escapar: `actualizacionProvider` se
pregunta **una vez al arrancar**, así que no se entera de que la cola creció después — y
crece, porque se baja por la mañana y se trabaja sin señal el día entero. El cajón lee la cola
**en vivo** (contando los rechazados) y apaga el botón; **bajar** no se toca, porque bajar no
toca nada de lo que hay dentro y tenerlo bajado es justo lo que hace falta para instalar en
cuanto suba.

**El navegador sigue estando**, y es la salida en los tres primeros: quitar la única forma que
funciona hoy sería cambiar un problema por otro. Y con una api que no anuncie `bytes` y
`sha256` —anterior al 22/09/2026— **ni se intenta bajar dentro**: sin tamaño no hay barra
honesta y sin huella no hay forma de saber si llegó entero.

### Lo que lo ata

| Prueba | Qué caza |
|---|---|
| `app/test/nucleo/actualizacion/bajada_de_la_actualizacion_test.dart` | el corte a la mitad y el reanudado **contando los bytes pedidos**; la huella mala, que además **no llama al instalador**; el permiso que falta; los tres fallos; el parcial de otra versión; dos toques, una descarga |
| `app/test/navegacion/la_actualizacion_se_baja_dentro_test.dart` | que la barra sepa cuánto falta; que no se abra el navegador en el camino feliz; que **sí** se abra sin `bytes`/`sha256` y cuando falta el permiso; que la franja lo cuente con el cajón cerrado; que un toque no sean dos descargas; y que el botón de instalar se apague cuando la cola crece **con la pantalla delante** |
| `app/test/nucleo/actualizacion/el_lado_de_android_cuadra_test.dart` | que el canal, los códigos, el permiso del manifiesto y la autoridad del `FileProvider` **digan lo mismo en Dart y en Kotlin** |

Lo que ninguna prueba puede comprobar, y hay que mirar en un teléfono: **que la pantalla de
«¿instalar?» sale y que la instalación entra encima de la que hay**. Eso depende de la firma
(§4).

## 6. Lo que falta

- [x] **Dónde se cuelgan los ficheros.** Decidido y montado el 22/09/2026: **MinIO**, en
      `https://archivos.procovar.cloud/reparto/apk/`, con los bytes fuera de toda imagen.
      Ver §3-bis, que trae cómo se sube, cómo se comprueba y qué pasó con el rango y
      Cloudflare. Lo único que queda de esto es **barrer la copia vieja** cuando Jose
      confirme que se descarga e instala desde la URL nueva.
- [x] **Anunciarlo, que era lo único que faltaba para que el canal funcionara.** Hecho el
      24/09/2026: las cinco variables de Android están puestas en `docker-compose.yml` con
      los valores del APK colgado, y **el olvido ya no es un silencio** — con
      `ENTORNO=produccion` y `APP_ULTIMA_VERSION` vacía la api no arranca, y dos pruebas
      leen esos valores del compose y exigen que `/api/version` salga con su versión, sus
      bytes y su huella. El paso a paso de publicar está en `docs/despliegue.md` §3.1.
- [ ] **Subir la 1.0.4 y anunciarla.** Lo que se anuncia hoy es la **1.0.1** (compilación
      2), el último APK colgado y medido; `app/pubspec.yaml` va por `1.0.4+5`.
- [ ] **Windows y Linux siguen sin colgar.** `APP_DESCARGA_WINDOWS` y `APP_DESCARGA_LINUX`
      están vacías: el sitio ya existe (mismo bucket, prefijo `apk/` o uno nuevo), lo que
      falta es compilar y subir. No se inventa una URL que no tiene fichero detrás.
- [x] **La clave de firma**, §4. Puesta el 21/09/2026 (`app/android/key.properties`). Lo que
      queda es mirarla en cada publicación con `apksigner`, porque el fichero no está en el
      repositorio y una máquina sin él vuelve a firmar con depuración sin decir nada.
- [ ] **Enchufar el aviso a una pantalla.** `actualizacionProvider` está montado y probado,
      pero **nadie lo mira todavía**: no se tocó `app/lib/pantallas/`. Lo que falta es una
      pantalla que haga `ref.watch(actualizacionProvider)` y pinte los cinco casos —con el
      cajón en móvil y el modal en escritorio, como todo lo demás—. Después de subir la cola
      conviene `ref.invalidate(actualizacionProvider)`, para que un `PrimeroSube` se
      convierta en `SePuedeActualizar` sin reiniciar.
- [x] **Bajarla sin salir de la aplicación**, en Android. Hecho el 05/10/2026, §5-bis: con su
      barra, reanudable, comprobada por `sha256` y con el navegador de salida en los tres
      casos que no son el feliz. En el escritorio sigue siendo el navegador a propósito —una
      actualización de escritorio es un `.zip` que alguien descomprime encima, no un paquete
      que el sistema instale—.
- [ ] **Decidir si el aviso se repite.** Hoy se comprueba una vez por arranque, cuando
      alguien mira el provider. Si el aviso se cierra, no vuelve hasta el siguiente
      arranque. Puede estar bien; hay que verlo con gente usándolo.

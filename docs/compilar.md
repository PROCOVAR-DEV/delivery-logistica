# Compilar la aplicación

Cuatro salidas del **mismo** código: la web, el APK de Android, el escritorio de Windows y
el escritorio de Linux. Aquí están las órdenes exactas y desde qué máquina se saca cada
una.

## Lo que NO se compila a mano

**Los servicios no.** La api, el espejo, el sincronizador y la web de producción los
construye **Dokploy** él solo: clona el repositorio y corre los Dockerfile de `deploy/`
(`docs/despliegue.md`, y `procovar/docs/DOKPLOY-NUEVO-PROYECTO.md`). Compilarlos a mano y
subir una imagen sería hacer dos veces lo mismo y tener dos cosas que se pueden
desincronizar.

El único workflow de GitHub Actions es `.github/workflows/reparto-windows.yml`, que construye
el instalador y el ZIP de Windows; su publicación verificada se hace aparte, como explica el
apartado 4. **No hay `go.yml`**: se borró (commit `310bf2b`, «las mismas comprobaciones en
un script») y `api/` y `sync/` se comprueban con `./comprobar.sh`. Aquí decía que había un
workflow que comprobaba Go; ya no existe, y ninguno despliega.

## Quién compila qué

| Salida | Desde dónde | Por qué |
|---|---|---|
| **web** | el portátil Linux | Sólo para probar. La que se sirve la construye Dokploy con `deploy/Dockerfile.app`. |
| **APK** | el portátil Linux | Tiene el SDK de Android puesto y funcionando. |
| **escritorio de Linux** | el portátil Linux | Sólo para probar (`docs/entorno-local.md`). **No hay canal de escritorio Linux**: ni workflow, ni script de publicación, ni anuncio. |
| **escritorio de Windows** | **GitHub Actions con Windows Server 2022 o el portátil Windows de Jose** | El `.exe` necesita MSVC en Windows; desde Linux se puede lanzar la compilación remota. |

Y la versión de Flutter tiene que ser **la misma en las dos máquinas**, porque
`app/pubspec.yaml` fija las dependencias sin `^` justo para que dos máquinas no produzcan
cosas distintas:

```bash
flutter --version    # Flutter 3.47.4 · Dart 3.13.3
```

---

## 1. Antes de compilar nada: el número de versión

Sale de una sola línea, `app/pubspec.yaml`:

```yaml
version: 1.0.0+1
#        ^^^^^ ^
#        |     el `versionCode` de Android. ES LO QUE MANDA.
#        lo que se le enseña a la persona
```

**Súbelos los dos antes de compilar algo que vaya a repartirse.** El de después del `+` es
el único que Android compara al instalar encima: si no sube, el aparato se niega a instalar
y no dice por qué. Los dos números son los que después se anuncian en `APP_ULTIMA_VERSION`
y `APP_ULTIMA_COMPILACION` (`docs/actualizaciones.md`).

Las tres URL que se hornean al compilar son siempre las mismas y ya son los valores por
defecto de `app/lib/nucleo/red/entorno.dart`, así que **sólo hay que escribirlas si apuntas
a otro sitio**:

```bash
export API_URL=https://reparto.procovar.cloud/api
export SYNC_URL=https://reparto.procovar.cloud/sync
export AUTH_URL=https://auth.procovar.cloud
```

`String.fromEnvironment` se resuelve **al compilar**: cambiarlas después no cambia nada, hay
que volver a compilar.

---

## 2. Lo que se pasa siempre antes

```bash
cd ~/Work/procovar/delivery-logistica/app
flutter pub get
flutter analyze
flutter test
```

Compilar cuatro veces algo que no pasa el analizador es llegar al mismo sitio veinte
minutos más tarde.

---

## 3. El APK de Android (desde el portátil Linux)

### Las dos variables del espejo de Tencent, y por qué

Ya están en `~/.bashrc` de este equipo:

```bash
export ANDROID_HOME="$HOME/Android/sdk"
export SDK_TEST_BASE_URL="https://mirrors.cloud.tencent.com/AndroidSDK/"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:/opt/flutter/bin"
```

**`SDK_TEST_BASE_URL` no es opcional desde Cuba.** Los repositorios de Google devuelven 404
o no contestan, y **Gradle llama a `sdkmanager` por su cuenta** en mitad de la compilación
para bajarse lo que le falte. Si la variable no está **en el entorno del proceso que
compila**, vuelve a salir a Google y la compilación del APK se para ahí — sin un error que
diga «no hay red hacia Google», sólo un Gradle colgado.

O sea: no vale ponerla en una terminal y compilar en otra, y no vale un editor que arrancó
antes de que existiera. Si compilas desde un sitio raro, compruébalo:

```bash
echo "$SDK_TEST_BASE_URL"    # tiene que salir la de Tencent, no vacío
```

### La orden

```bash
cd ~/Work/procovar/delivery-logistica/app
flutter build apk --release
```

Sale en:

```
app/build/app/outputs/flutter-apk/app-release.apk
```

Con las URL cambiadas, si hiciera falta:

```bash
flutter build apk --release \
  --dart-define=API_URL="$API_URL" \
  --dart-define=SYNC_URL="$SYNC_URL" \
  --dart-define=AUTH_URL="$AUTH_URL"
```

### LA FIRMA — mira esto antes de dárselo a nadie

**Con qué clave salió el APK no se adivina: se mira.**

```bash
~/Android/sdk/build-tools/36.0.0/apksigner verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
```

Si contesta **`CN=Android Debug`**, **ese APK no se reparte**. La clave de depuración se
regenera sola, y Android **rechaza** como actualización un APK firmado con otra clave:
obliga a desinstalar, y desinstalar **borra la base local**, o sea el trabajo del día sin
subir.

Eso era lo que contestaba siempre hasta el 21/09/2026. Hoy el APK se firma con el almacén
de `app/android/key.properties` (ignorado por git, apunta a un `.jks` de
`procovar/.secretos/`), y el firmante que tiene que salir es el de la huella SHA-256
`01529f5a6fb1a238985745aff13cdcf7e8e85b624992f4e328bde9898fd80b21` (dato público). Cualquier
otra, o `CN=Android Debug`, y no se publica.

> No te fíes de que no haya salido ningún aviso al compilar. Gradle sí avisa, pero
> **`flutter build apk --release` se traga esa salida** (comprobado el 15/09/2026): el aviso
> sólo se ve con `-v`. La comprobación buena es la de `apksigner`, que mira el fichero.

Cómo se crea la clave de verdad y dónde se pone: **`docs/actualizaciones.md` §4**. No hace
falta tocar `build.gradle.kts`: en cuanto exista `app/android/key.properties`, el APK sale
firmado con la buena.

### Un APK por arquitectura (opcional)

```bash
flutter build apk --release --split-per-abi
```

Salen tres, más pequeños. Ojo: Flutter le suma `1000 * ABI` al `versionCode` de cada uno,
así que los números dejan de ser los de `pubspec.yaml` y el anuncio de versión se complica.
**Mientras sean diez aparatos, el APK único es más simple y no hay motivo para lo otro.**

---

## 4. El escritorio de Windows (compilador remoto o portátil Windows)

La compilación necesita las herramientas de Windows. Se puede lanzar desde Linux:
el trabajo lo hace un ejecutor **Windows Server 2022 de GitHub Actions**, con Flutter
**3.47.4**, y devuelve el instalador y el paquete completo. El portátil Windows no
tiene que estar encendido para esa compilación.

El proceso está en `.github/workflows/reparto-windows.yml` y
`deploy/windows/compilar.ps1`. Arranca al subir una rama `build/reparto-windows-*`;
cuando el workflow esté en la rama principal, también se puede ejecutar manualmente.
**La rama `build/reparto-windows-<versión>` se empuja al remoto `upstream`** (la organización
`PROCOVAR-DEV`), **no a `origin`** (el fork `jose22072000/…`, que desde el 07/10/2026 no es el
original): la ejecución de CI que se publica tiene que ser de `PROCOVAR-DEV/delivery-logistica`.
Antes de empaquetar corre `flutter analyze`, las pruebas de la Guía, del Tablero y de Rutas,
y las de base local, cola y sincronización; después hace la compilación nativa.
Inno Setup genera `reparto-<version>-windows-setup.exe`, instala una copia de
prueba sin abrir la aplicación y compara todos sus archivos con la compilación.

El artefacto del trabajo contiene:

- el **instalador `.exe`**, que instala Reparto para el usuario y crea su acceso directo;
- el **ZIP completo**, con el ejecutable, las DLL y `data/`;
- `windows-verification.json`, con el commit, versión, tamaños y SHA256, y el alcance
  de la comprobación. La instalación de prueba no acredita iniciar sesión, trabajar
  sin conexión ni instalarlo en el ordenador de una persona.

Antes de ofrecerlo en procovar.cloud hay que descargar ese artefacto, contrastar
sus huellas, publicar el instalador sin sobrescribir versiones y comprobar su descarga.

La versión **1.0.31+32** (09/10/2026) está en procovar.cloud como **Reparto para Windows**:
el botón «Abrir» descarga el [instalador de Windows](https://archivos.procovar.cloud/reparto/windows/reparto-1.0.31-windows-setup.exe)
(16.249.430 bytes). La ejecución [37949743642 de GitHub Actions](https://github.com/PROCOVAR-DEV/delivery-logistica/actions/runs/37949743642),
sobre el commit `5838ce8` en la organización, compiló e instaló la copia de prueba y cotejó sus archivos.
(La de la 1.0.30 fue la [37834921676](https://github.com/PROCOVAR-DEV/delivery-logistica/actions/runs/37834921676); la de la 1.0.29 fue la [37812597394](https://github.com/PROCOVAR-DEV/delivery-logistica/actions/runs/37812597394); la de la 1.0.28 la [37781825464](https://github.com/PROCOVAR-DEV/delivery-logistica/actions/runs/37781825464); la de la 1.0.27, [37537712382](https://github.com/PROCOVAR-DEV/delivery-logistica/actions/runs/37537712382),
bajo `jose22072000` da 404: ahora vive en la organización.) Las descargas públicas se
verificaron por tamaño y SHA256 antes de actualizar la tarjeta. Abrir, iniciar sesión
y trabajar sin conexión en el PC del usuario quedan pendientes de prueba física.

La 1.0.28 trajo las seis incidencias de Amado (`docs/incidencias-reparto.md`): quitar una parada de
una ruta planificada, camiones inactivos, rutas nuevas sólo con factura que cuadre, domicilio cobrado y
cotizado, y las facturas que vuelven a su zona del tablero al borrar una ruta. Incluye también los
controles con ratón del Tablero y la corrección de Rutas: se puede editar y
eliminar mientras no esté completada; los estados de paradas se revisan al pulsar
«Marcar como completada» y el histórico queda de sólo lectura. Una hoja rechazada
retiene el cierre de esa ruta en la cola nativa. Windows conserva su base local para
trabajar sin conexión; la web trabaja conectada al servidor.

La 1.0.31 trae la **sesión única** en la APK y el escritorio (`docs/sin-permiso.md`, sección final): cuando
Accesos corta la sesión o cambia los permisos, la aplicación renueva al instante (y al volver la red); cerrar
sesión sin conexión deja la revocación pendiente (`reparto.por_revocar`, que solo se borra con la respuesta
de NUESTRO servidor y nunca sirve para entrar); y manda `User-Agent: ProcovarReparto/<versión> (<plataforma>)`
para que la lista de dispositivos de Accesos distinga Android de Windows. Se publicó el 09/10/2026 con
`publicacion-1.0.31/` (APK `reparto-1.0.31-261009.apk`, 79.363.020 bytes, sha256 `6147d6e4…fabc20`; Windows y
Android en `production_verified`, tarjetas 12 y 13 del portal verificadas con navegador real, 5/5). En las dos
subidas la comprobación de rango dio 200 a la primera y se reanudó a mano (`--mode resume` y
`--resume-uploaded`), como en la 1.0.26 a 1.0.28. **Falta la prueba física** en un teléfono y un PC.

La 1.0.30 trae la pantalla «No tienes permiso para entrar a Reparto» (y su salida a Accesos, sin perder
la cola), las marcas de domicilio cobrado de Pedidos sin la columna Vehículo, y el login y el refresco de
la APK que reconocen el `sin_permiso` de Accesos (`docs/sin-permiso.md`). La 1.0.29 endurece lo que la revisión de la 1.0.28 dejó abierto (alcance que falla cerrado,
`PATCH /api/orders`, camión de otra sucursal, armado local del Tablero como el servidor, cajón de
acuse en el cierre parcial; ver `docs/reglas-negocio.md` §15.14).

Android y Windows están publicados como **1.0.31+32**, con el anuncio global y las dos
tarjetas del portal actualizadas (los diarios `.publish-*-1.0.31*` están en `production_verified`).
**Falta la prueba física** en un teléfono con una base 1.0.27 llena (el esquema local pasa de la 4
a la 6 con un `DROP COLUMN`) y en un PC. Se puede instalar Windows 1.0.31 desde el portal sobre la
versión anterior. La actualización automática en el PC del usuario no se ha probado;
separar el aviso de versión por plataforma sigue siendo un pendiente de arquitectura.
Las versiones anteriores se conservan.

Para hacerlo en el portátil en vez del ejecutor remoto:

Lo que tiene que haber instalado:

- **Flutter 3.47.4**, la misma que en el portátil Linux (`flutter --version`).
- **Visual Studio 2022** con la carga de trabajo **«Desarrollo para el escritorio con C++»**
  (*Desktop development with C++*). No vale Visual Studio **Code**: son cosas distintas y es
  la confusión de siempre. Lo que hace falta es el compilador MSVC.
- `flutter doctor` tiene que dar ✓ en **Visual Studio** y en **Windows (desktop)**.
- **Inno Setup 6** para generar el instalador. Desde la raíz del repositorio,
  `./deploy/windows/compilar.ps1` ejecuta el mismo proceso que GitHub Actions.

```powershell
cd <ruta>\delivery-logistica\app
flutter pub get
flutter build windows --release
```

Sale en:

```
app\build\windows\x64\runner\Release\
```

**Se copia la carpeta ENTERA, no sólo el `.exe`.** Al lado van las DLL y `data\`, y el
`.exe` suelto no arranca en ninguna máquina. Para repartirlo, un `.zip` de esa carpeta.

Con las URL cambiadas (en PowerShell las variables son `$env:NOMBRE`; escribirlas como en
bash no falla, pasa la cadena vacía y sale una aplicación que apunta a ninguna parte):

```powershell
flutter build windows --release `
  --dart-define=API_URL="$env:API_URL" `
  --dart-define=SYNC_URL="$env:SYNC_URL" `
  --dart-define=AUTH_URL="$env:AUTH_URL"
```

> El escritorio de Windows **no se firma** con nada hoy. Windows enseñará el aviso de
> SmartScreen la primera vez («editor desconocido»); se abre con *Más información → Ejecutar
> de todas formas*. Firmarlo necesita un certificado comprado, y con diez aparatos no se ha
> considerado que valga la pena. Si algún día se compra, esto se actualiza.

---

## 5. El escritorio de Linux (desde el portátil Linux)

Sólo para probar: **no hay canal de escritorio Linux** (ni workflow, ni script de
publicación, ni anuncio; las variables `APP_DESCARGA_LINUX*` de la api existen y se quedan
vacías).

```bash
cd ~/Work/procovar/delivery-logistica/app
flutter build linux --release
```

Sale en:

```
app/build/linux/x64/release/bundle/
```

Igual que en Windows: se reparte **la carpeta entera**, no el binario suelto.

---

## 6. La web (desde el portátil Linux, sólo para probar)

La que se sirve de verdad la construye Dokploy. Ésta es para mirarla en local:

```bash
cd ~/Work/procovar/delivery-logistica/app
flutter build web --release --no-web-resources-cdn
```

`--no-web-resources-cdn` deja CanvasKit **dentro** del build en vez de bajarlo de
gstatic.com al abrir la página. Es lo mismo que hace `deploy/Dockerfile.app`, y con la
conexión de allá son unos megas menos por aparato y una dependencia menos de una red que
unos días no está.

Y **el fichero del despliegue**, que el Dockerfile también comprueba:

```bash
test -f build/web/sqlite3.wasm || echo "FALTA sqlite3.wasm"
```

Si falta, la aplicación arranca y **la base no**
(`app/lib/nucleo/base/conexion/conexion_web.dart`). Es de los fallos que no se ven hasta
que alguien ya está sin conexión.

**Eran dos y ahora es uno.** `drift_worker.js` se fue el 24/09/2026, con su fuente, su
`.map` y su `.deps`: desde que la base de la web es en memoria (16/09) no hay
almacenamiento que compartir entre pestañas, así que no hay worker que coordinar. Eran
760 KB que la imagen servía sin que nadie los pidiera, y una guarda que hacía fallar el
build por un fichero muerto.

Para verla:

```bash
cd build/web && python3 -m http.server 8082
```

---

## 7. Y después

Compilar no es publicar. Para que los aparatos se enteren de que hay una versión nueva hay
que **colgar los ficheros** en MinIO y **anunciarlos**, poniéndole a la api las cinco
variables de golpe —`APP_ULTIMA_VERSION`, `APP_ULTIMA_COMPILACION`, `APP_DESCARGA_ANDROID`
y sus `_BYTES` y `_SHA256`— y volviéndola a desplegar. Los pasos numerados están en
**`docs/despliegue.md` §3.1**, y el detalle de MinIO (cómo se sube, el `Cache-Control` que
no es cosmética y las cuatro comprobaciones) en **`docs/actualizaciones.md` §3-bis**.

**Y se publica con el publicador de ESA versión, no con el de `deploy/`.** Los de `deploy/`
están fijados por versión y desfasados (el de APK sólo acepta la 1.0.25+26 y el de Windows
la 1.0.25 y la 1.0.26); cada versión se copia de
`app/build/codex-retoma-20261006/rutas-historico/publicacion-<versión anterior>/` (ignorada
por git) y se adapta. `deploy/publicar-apk.sh` no se usa: poda y no verifica. El orden es
**Windows primero, Android después**, y cada versión de Windows necesita su permiso de MinIO
(`allow-windows<N>.py`) o la descarga da 403. Todo, con el detalle de los diarios y los
redespliegues, en `docs/despliegue.md` §3.1 («Cómo se publica de verdad»). No hay canal de
Linux que publicar.

**Y la firma se mira SIEMPRE, en el APK ya hecho**, porque `android/key.properties` no está
en el repositorio y una máquina sin él vuelve a firmar con la de depuración sin que se vea:

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
# no puede decir CN=Android Debug
```

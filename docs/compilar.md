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

Lo único que hace GitHub Actions en este repositorio es **comprobar** que `api/` y `sync/`
compilan, pasan `vet`, pasan las pruebas y tienen el código de sqlc al día
(`.github/workflows/go.yml`). Nada de eso construye ni despliega: es para que el Deploy de
Dokploy no se caiga después.

## Quién compila qué

| Salida | Desde dónde | Por qué |
|---|---|---|
| **web** | el portátil Linux | Sólo para probar. La que se sirve la construye Dokploy con `deploy/Dockerfile.app`. |
| **APK** | el portátil Linux | Tiene el SDK de Android puesto y funcionando. |
| **escritorio de Linux** | el portátil Linux | |
| **escritorio de Windows** | **el portátil Windows de Jose** | Flutter **no cruza de una plataforma a otra**: el `.exe` necesita MSVC y no hay forma de sacarlo desde Linux. |

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

Si contesta **`CN=Android Debug`**, como contesta hoy, **ese APK no se reparte**. La clave
de depuración se regenera sola, y Android **rechaza** como actualización un APK firmado con
otra clave: obliga a desinstalar, y desinstalar **borra la base local**, o sea el trabajo
del día sin subir.

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
Antes de empaquetar corre `flutter analyze`, las pruebas de la Guía y la compilación
nativa. Inno Setup genera `reparto-<version>-windows-setup.exe`, instala una copia de
prueba sin abrir la aplicación y compara todos sus archivos con la compilación.

El artefacto del trabajo contiene:

- el **instalador `.exe`**, que instala Reparto para el usuario y crea su acceso directo;
- el **ZIP completo**, con el ejecutable, las DLL y `data/`;
- `windows-verification.json`, con el commit, versión, tamaños y SHA256, y el alcance
  de la comprobación. La instalación de prueba no acredita iniciar sesión, trabajar
  sin conexión ni instalarlo en el ordenador de una persona.

Antes de ofrecerlo en procovar.cloud hay que descargar ese artefacto, contrastar
sus huellas, publicar el instalador sin sobrescribir versiones y comprobar su descarga.

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

**Y la firma se mira SIEMPRE, en el APK ya hecho**, porque `android/key.properties` no está
en el repositorio y una máquina sin él vuelve a firmar con la de depuración sin que se vea:

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
# no puede decir CN=Android Debug
```

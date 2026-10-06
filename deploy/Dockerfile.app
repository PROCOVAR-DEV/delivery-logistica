# reparto-app — LA INTERFAZ, compilada a web y servida como ficheros estáticos.
#
# Dos etapas: el SDK de Flutter (unos 2 GB) compila, y de ahí sale una carpeta de
# ficheros que sirve nginx. En la imagen final no queda ni Flutter, ni Dart, ni el
# código fuente.
#
# EL CONTEXTO ES LA RAÍZ DEL REPO (este fichero vive en deploy/ y el código en app/):
#
#   docker build -f deploy/Dockerfile.app -t reparto-app \
#     --build-arg API_URL=https://reparto.procovar.cloud/api \
#     --build-arg SYNC_URL=https://reparto.procovar.cloud/sync \
#     --build-arg AUTH_URL=https://auth.procovar.cloud .
#
# En Dokploy:  Dockerfile Path = deploy/Dockerfile.app  ·  Docker Context Path = .
#              y las tres URL van en BUILD ARGS, no en Environment.
#
# LAS TRES URL SE HORNEAN AL COMPILAR. `String.fromEnvironment` (app/lib/nucleo/red/
# entorno.dart) se resuelve en tiempo de compilación: cambiar la variable en Dokploy
# después no cambia nada, hay que volver a construir. Es lo mismo que les pasa a las
# `VITE_*` del front de notify, y está avisado en docs/DOKPLOY-NUEVO-PROYECTO.md.

# El SDK se trae del repositorio OFICIAL de Flutter, pinchado por etiqueta.
#
# # Por qué no una imagen ya hecha
#
# Antes esto usaba `ghcr.io/cirruslabs/flutter:3.44.0`. Falló al construir, después de
# media hora bajando sus 794 MB:
#
#     Because reparto requires SDK version ^3.13.3, version solving failed.
#
# El proyecto pide Dart ^3.13.3 y esa imagen trae uno más viejo. Y comprobado el
# 15/09/2026, de esa familia **sólo existen `3.44.0` y `stable`**: no hay 3.45, ni 3.46,
# ni la 3.47.4 que usa el proyecto. Van por detrás de Flutter.
#
# `stable` resolvería hoy y es lo que NO se puede hacer: es una etiqueta móvil, así que la
# imagen cambia bajo los pies y reconstruir esto dentro de seis meses daría algo distinto
# sin que nadie tocara una línea. Es justo lo que `app/pubspec.yaml` evita fijando las
# versiones sin `^`.
#
# Clonando el repositorio oficial por etiqueta, la versión la decidimos nosotros y es
# exactamente la que se usa para desarrollar. `--depth 1` de una sola etiqueta trae lo
# justo.
ARG FLUTTER_VERSION=3.47.4

FROM debian:bookworm-slim AS build
# Lo que pide el SDK para compilar para web, y `libsqlite3` para poder PROBAR.
#
# `libsqlite3-dev` no es un adorno: las pruebas de este proyecto abren bases de
# verdad con Drift (`NativeDatabase`), y sin esa biblioteca cada una muere con
# «Failed to load dynamic library 'libsqlite3.so'». Se descubrió al añadir
# `flutter test` a esta imagen: el build se comió los 600 s del `timeout` viendo
# caer prueba tras prueba. Antes no hacía falta porque aquí no se probaba nada,
# que es justo lo que se vino a arreglar.
#
# Y **el `-dev` y no el `-0`**, aunque aquí no se compile nada de C: `libsqlite3-0`
# instala sólo `libsqlite3.so.0`, y Dart abre la biblioteca por su nombre SIN
# versión. El enlace `libsqlite3.so` lo trae el paquete de desarrollo y nada más.
# Comprobado en un `debian:bookworm-slim` limpio antes de volver a desplegar, que
# si no el segundo intento habría caído por lo mismo con otro nombre.
RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl unzip xz-utils ca-certificates libsqlite3-dev \
 && rm -rf /var/lib/apt/lists/*
ARG FLUTTER_VERSION
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git /sdk
ENV PATH="/sdk/bin:/sdk/bin/cache/dart-sdk/bin:${PATH}"
# `git config` porque el SDK se queja de ser un repositorio de otro dueño dentro de la
# imagen, y se para antes de hacer nada.
RUN git config --global --add safe.directory /sdk && flutter --version
WORKDIR /app

# Dependencias primero: la capa se cachea y no se rehace en cada cambio de pantalla.
COPY app/pubspec.yaml app/pubspec.lock ./
RUN flutter pub get

# El resto del código.
COPY app/ .

# LOS DOS FICHEROS DE FUERA DE `app/` QUE LAS PRUEBAS LEEN, y por qué están aquí.
#
# «Una imagen no es esta máquina» (CLAUDE.md §4-bis), y esto lo demuestra: las dos
# pruebas pasaban en el portátil y tiraban la construcción de la web el 22/09/2026,
# porque leen ficheros que viven fuera de `app/` y aquí sólo se copia `app/`.
#
#  * `docs/orden-de-paradas.casos.json` — el orden de visita de las paradas está
#    escrito DOS veces, en Dart y en Go, y este fichero es lo único que ata las dos
#    a que den el mismo resultado. `geo_test.dart` lo lee por `../docs/…`.
#  * `herramientas/mapa-cuba/niveles.go` — de ahí saca `colores_del_suelo_test.dart`
#    la lista de clases que escribe el generador, para exigir que **cada una tenga
#    color propio en el pintor**. Es la prueba que habría cazado el mismo día que la
#    Ciénaga de Zapata se pintara como un prado.
#
# Van a las MISMAS rutas relativas que en el repositorio, porque eso es lo que las
# pruebas abren: `/docs/…` y `/herramientas/…` al lado de `/app`.
COPY docs/orden-de-paradas.casos.json /docs/orden-de-paradas.casos.json
COPY herramientas/mapa-cuba/niveles.go /herramientas/mapa-cuba/niveles.go

#  * `docs/almacen-de-origen.casos.json` — el TERCERO, y del mismo tipo que el primero
#    (24/09/2026). La regla de qué almacén es el de origen está escrita dos veces, en Go y
#    en Dart, y este fichero es el único que las ata: lo leen
#    `almacen_de_origen_casos_compartidos_test.dart` por `../docs/…` y su gemelo de Go. De
#    ese almacén sale el kilometraje que se cobra, así que dos lados eligiendo cosas
#    distintas es un importe creíble y equivocado. Sin él la prueba muere con un `[E]` al
#    cargar y ESTA IMAGEN NO CONSTRUYE — comprobado el 24/09/2026, que es como se descubrió
#    que faltaba.
COPY docs/almacen-de-origen.casos.json /docs/almacen-de-origen.casos.json

#  * `docs/armado-rechazado.casos.json` — el CUARTO, y del mismo tipo (29/09/2026). La
#    cabecera del «no» del armado —«3 de los 4 pedidos elegidos no pueden ir en esta
#    ruta»— la redacta el teléfono cuando se arma sin señal y la nube cuando hay red, así
#    que está escrita dos veces y este fichero es lo único que las ata: lo leen
#    `encabezado_del_armado_test.dart` por `../docs/…` y su gemelo de Go. Ya estuvieron mal
#    las dos a la vez —«1 de los 1 pedidos elegidos no pueden ir»— y nadie las comparaba.
#    Sin él la prueba muere al cargar y ESTA IMAGEN NO CONSTRUYE.
COPY docs/armado-rechazado.casos.json /docs/armado-rechazado.casos.json

# LAS PRUEBAS, ANTES DE CONSTRUIR. Como en `Dockerfile.api` y `Dockerfile.sync`.
#
# El 16/09/2026 una mutación de prueba llegó a producción porque el Dockerfile del
# sincronizador sólo compilaba. Se arregló ahí y en la api, y aquí se quedó sin
# arreglar: la web se construía sin pasar una sola prueba.
#
# AQUÍ CORRÍA LA SUITE ENTERA, Y SE QUITÓ EL 26/09/2026 — decisión de Jose, con dos
# despliegues tirados en una tarde delante.
#
# Lo que la quitó no fue el tiempo: fue una prueba **colgada**. «Tablero a 390 px» se
# comió los diez minutos de tope de Flutter —el suyo, de fábrica— dentro del contenedor,
# mientras en el portátil pasaba: aquí hay 12 núcleos y en el VPS hay menos. Una prueba
# que se cuelga en vez de fallar es lo peor que puede hacer una prueba (`CLAUDE.md` §5),
# y desde una imagen no se depura.
#
# Jose: «las pruebas son necesarias, ponerlas en los builds si ya las estamos haciendo
# aquí en local no creo que haya necesidad».
#
# LO QUE SE PIERDE, dicho para que nadie lo descubra a base de sustos: esta línea cazaba
# el caso en que **lo que se sube no es lo que se probó** —un commit sin correr la suite,
# o trabajo que llega sin probar—. Ese agujero es por donde se coló una mutación de
# prueba a producción el 16/09/2026. La disciplina de correr `flutter test` ANTES de subir
# pasa a ser de quien sube, y no hay red debajo.
#
# LO QUE SE QUEDA es `flutter analyze`, que tarda segundos y caza lo que de verdad ha
# tirado builds aquí: un import que sobra, un texto generado que no está, código que no
# compila en un destino aunque ninguna prueba lo toque. Y en `Dockerfile.api` y
# `Dockerfile.sync` **sí sigue `go test`**: tarda menos de un segundo y nunca ha dado
# guerra.
#
# `lib test` y no sólo `lib`: el 26/09/2026 un fichero de pruebas con un import que
# sobraba dejó `analyze` en rojo y tiró el build. Mirar sólo `lib` lo habría dejado pasar.
RUN flutter analyze lib test

# Las tres URL. Los valores por defecto son los de producción, los mismos que están
# escritos en entorno.dart: si alguien construye sin argumentos, sale la de verdad y no
# un localhost que en el servidor no existe.
ARG API_URL=https://reparto.procovar.cloud/api
ARG SYNC_URL=https://reparto.procovar.cloud/sync
ARG AUTH_URL=https://auth.procovar.cloud

# Si la web cuelga de un subdirectorio (p. ej. /reparto/), esto tiene que decirlo.
ARG BASE_HREF=/

# `--no-web-resources-cdn` deja CanvasKit DENTRO de la imagen en vez de bajarlo de
# gstatic.com al abrir la página. En la conexión de allá eso son unos megas menos por
# cada aparato y una dependencia menos de una red que unos días no está.
RUN flutter build web --release \
      --no-web-resources-cdn \
      --base-href "${BASE_HREF}" \
      --dart-define=API_URL="${API_URL}" \
      --dart-define=SYNC_URL="${SYNC_URL}" \
      --dart-define=AUTH_URL="${AUTH_URL}"

# LA HUELLA, que es lo que hace que la caché deje de adivinar.
#
# Flutter llama a su código `main.dart.js` SIEMPRE IGUAL, en cada compilación: misma
# dirección, contenido distinto. Cualquier caché del mundo —el navegador, Cloudflare, el
# proxy de una oficina— tiene derecho a quedarse con la vieja, porque nadie le dijo que
# cambió. Eso pasó el 16/09: los cuatro servicios desplegados, el servidor sirviendo el
# fichero nuevo, y la pantalla enseñando la aplicación del día anterior.
#
# La salida NO es prohibir la caché: es que el nombre cambie cuando cambia el contenido.
# Se le pega a cada petición la huella del PROPIO fichero, así que:
#
#   * si el código no cambió, la dirección es la misma y la caché lo sirve al instante
#     —que con la conexión de allá es justo lo que se quiere—;
#   * si cambió, la dirección es otra y NO PUEDE servirse una copia vieja, porque de esa
#     dirección nadie tiene ninguna.
#
# `index.html` se queda sin cachear (`deploy/nginx.conf`) y es el único sitio donde vive
# la huella: se pide siempre, y de él sale la dirección buena de todo lo demás.
#
# EL FAVICON ENTRA TAMBIÉN, y no por simetría. El 16/09 se cambió el icono de Flutter por
# el de Procovar, el servidor servía el nuevo —mismo md5 que el del repo, comprobado— y en
# la pestaña seguía saliendo el de Flutter. El favicon es la caché más terca de un
# navegador: se lo guarda casi ignorando las cabeceras y ni una recarga forzada lo tira
# siempre. Con la huella en la dirección no hay nada que tirar: es otro fichero.
#
# Es SHA256 del código y de todos sus assets, no la fecha ni el commit: dos compilaciones del mismo
# código dan la MISMA huella, así que un redespliegue que no cambia nada no obliga a nadie
# a volver a bajarse cinco megas.
COPY deploy/preparar-web.sh /deploy/preparar-web.sh
RUN sh /deploy/preparar-web.sh build/web

# `sqlite3.wasm` es un FICHERO DEL DESPLIEGUE (app/lib/nucleo/base/conexion/
# conexion_web.dart lo dice con esas palabras): si falta, la aplicación arranca y la base
# NO. Que el build falle aquí es mucho mejor que descubrirlo en la pantalla de alguien que
# ya no tiene conexión para recargar.
#
# `drift_worker.js` ESTABA AQUÍ Y SE FUE — 24/09/2026. Era la segunda mitad de esta
# comprobación y llevaba desde el 16/09 defendiendo algo que nadie ejecuta: ese día la base
# de la web pasó a ser EN MEMORIA (`WasmDatabase.inMemory`), y sin almacenamiento que
# compartir entre pestañas no hay worker que coordinar. Comprobado antes de quitarlo, no
# leído del comentario: en todo `app/lib` no queda un `WasmDatabase.open` ni un
# `driftWorkerUri`, y el `main.dart.js` compilado no nombra el worker por ninguna parte.
# Con él se fueron los 760 KB de `web/drift_worker.js`, su `.map` y su `.deps`, que la
# imagen servía a cada navegador que pasara. Una guarda que protege un fichero muerto
# enseña a no fiarse de las guardas.
RUN test -f build/web/sqlite3.wasm     || (echo "FALTA sqlite3.wasm en build/web"     && exit 1)

FROM nginx:1.27-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html

# 8080 y no 80: es el Container Port que se pone en el dominio de Dokploy.
EXPOSE 8080

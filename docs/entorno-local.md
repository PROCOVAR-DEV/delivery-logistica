# El reparto ENTERO en el portátil, con Accesos incluido

Hasta el 24/09/2026 el entorno local del reparto se levantaba a medias: subían la
API, el sincronizador, el espejo, la web y su Postgres, pero **Accesos no**. Y sin
Accesos no se puede *entrar*: la aplicación de escritorio y la APK piden usuario y
contraseña contra `POST /api/auth/token`, que es suyo. Así que nadie había podido
hacer la jornada entera en esta máquina, y por eso los dos fallos más caros del
sistema estaban vivos sin que ninguna prueba los tocara (§«Lo que esto destapó»).

Esto es lo que hay que hacer, de cero, para dejarlo todo levantado y entrar.

---

## 0. Lo que hace falta tener

- Docker y `docker compose`.
- Flutter (para la aplicación de escritorio).
- Los dos repos al lado: `procovar/delivery-logistica` y `procovar/auth`. Se clonan de la
  organización `PROCOVAR-DEV` (`PROCOVAR-DEV/delivery-logistica`): desde el 07/10/2026
  `jose22072000/…` es un fork personal que no se actualiza solo.
- Para pulsar sin molestar a nadie: `Xvfb`, `openbox`, `xdotool`, `imagemagick`.

**Nada de esto llama a un dominio de Procovar.** Es la regla del `CLAUDE.md` de
Procovar y aquí se cumple entera: las tres URL de la aplicación van a `127.0.0.1`,
el canal de actualización se deja callado (§2) y Accesos es el de esta máquina.

## 1. El reparto

```bash
cd delivery-logistica
docker compose up -d --build postgres migraciones api sync
```

> **Aviso del 07/10/2026: hoy esto no arranca.** `docker-compose.yml` no es YAML válido
> desde el commit `ebc3480` (29/09): en la línea 117 la nota `APP_ULTIMA_NOTAS` va sin
> comillas y lleva un «: » dentro, y `docker compose` contesta «mapping values are not
> allowed in this context». Es un fichero de código; hasta que se ponga entre comillas
> dobles, este paso falla antes de levantar nada. (La jornada de abajo se hizo el 24/09,
> con el compose anterior.)

Deja:

| Qué | Dónde |
|---|---|
| Postgres (bases `reparto` y `reparto_sync`) | `127.0.0.1:5433`, usuario/clave `reparto` |
| La API | `127.0.0.1:8080` — `/health` |
| El sincronizador | `127.0.0.1:8081` — `/salud` |

El espejo (`espejo`) y la web (`app`) **no hacen falta** para probar el escritorio.
El espejo además da vueltas fallando contra un PEDIDO que no existe, que es lo
correcto pero llena el registro.

## 2. El fichero `.env` del reparto

Va al lado del `docker-compose.yml` y está en `.gitignore`. Cambia dos cosas:

```sh
# Accesos es el de aquí, no el dominio.
PROCOVAR_AUTH_URL=http://accesos:3500
PROCOVAR_AUTH_CLIENT_ID=delivery
PROCOVAR_AUTH_SIGNING_KEY=de-juguete-para-el-portatil

ORIGENES_PERMITIDOS=http://localhost:8082,http://127.0.0.1:8082
```

(Sobre «el canal de actualización se deja callado»: el `.env` de esta máquina trae las
`APP_*` en blanco, pero el compose las lee como `${APP_ULTIMA_VERSION:-1.0.15}`, y en
Compose `:-` también cae al valor por defecto cuando la variable está **vacía**. Por
construcción, un `.env` en blanco no calla el anuncio: la api local anunciaría la 1.0.15 con
su enlace a `archivos.procovar.cloud`. No se ha podido comprobar corriéndolo, porque hoy el
compose no parsea.)

**`http://accesos:3500`, por el nombre del servicio y no por `127.0.0.1`.** Desde
un contenedor no se llega al `localhost` del portátil: el cortafuegos del equipo
tira lo que sale del puente de Docker hacia el host, y lo que se ve entonces es
`GET /api/almacenes` contestando 502 durante minuto y medio. Por eso Accesos se
levanta **dentro de la red `reparto_default`** (§3) y no con `npm run dev` en el
host.

## 3. Accesos

Lo único que le faltaba al entorno. Va en `deploy/accesos-local/`:

```bash
# La base, una sola vez. UN motor de Postgres, muchas bases: es la regla de la casa.
docker exec reparto-postgres-1 psql -U reparto -d postgres \
  -c "CREATE DATABASE procovar_auth OWNER reparto;"

docker compose -f deploy/accesos-local/docker-compose.yml up -d --build
```

Levanta tres contenedores en la misma red que el reparto:

- **`redis`** y **`sentinel`**. Son dos y no uno porque Accesos no sabe hablar de
  otra forma: `src/lib/redis.ts` revienta si `REDIS_SENTINELS` viene vacía, y eso
  es lo mismo que hay en producción (`procovar-sentinel`). El limitador de
  `POST /api/auth/token` pasa por ahí, y si Redis no contesta **no se pasa**:
  contesta `503 rate_limit_unavailable`. Sin centinela no se entra.
- **`accesos`**, que aplica sus migraciones al arrancar y queda en
  `127.0.0.1:3500`.

`JWT_SECRET` es el mismo en los tres servicios —`api`, `sync` y `accesos`— y eso
no es un detalle: la API del reparto verifica a mano con `crypto/hmac` el token
que firma Accesos. Dos secretos distintos dan 401 en todo sin decir por qué.

## 4. Las semillas y una cuenta con la que entrar

Desde `procovar/auth`, con `DATABASE_URL` apuntando a `procovar_auth`:

```bash
npx prisma migrate deploy
npm run seed:rbac        # los 88 permisos y los siete roles
npm run seed:procovar    # las ocho sucursales y las nueve aplicaciones
npx tsx scripts/alta-local.ts   # dos cuentas de prueba
```

`scripts/alta-local.ts` no inventa filas: llama a `altaPersona`, que es el mismo
camino de la pantalla de Personas. Deja dos cuentas, con contraseñas **de
mentira**, a la vista a propósito porque no abren nada:

| Usuario | Rol | Sucursal |
|---|---|---|
| `logistica.cam` | `ADMINISTRADOR` | Camagüey (CAM) |
| `mando.local` | `SUPER ADMIN` | ninguna: las ve todas |

La contraseña de las dos está escrita en ese fichero.

> **Ojo con `seed:procovar`.** Hasta el 24/09/2026 creaba las ocho sucursales
> **sin `codigo`** —lo escribía en `metadata`, que es de donde se leía antes de
> que existiera la columna—, y `resolverIdentidad` filtra por `o.activa &&
> o.codigo`. O sea que una base recién sembrada le contestaba **403
> `sin_sucursal`** a todo el mundo: nadie podía entrar en la APK ni en el
> escritorio. Arreglado; la semilla repone el código si falta.

## 5. La aplicación de escritorio, apuntando aquí

(Es el escritorio de **Linux**, y es sólo para probar: **no hay canal de escritorio
Linux** —ni workflow, ni script de publicación, ni anuncio—. Lo que se publica es Android y
Windows: `docs/despliegue.md` §3.1.)

`lib/nucleo/red/entorno.dart` tiene las URL de **producción** como `defaultValue`,
así que un build sin `--dart-define` llama a `reparto.procovar.cloud` en cuanto
alguien lo abre. Las tres, siempre:

```bash
cd app
flutter build linux --release \
  --dart-define=API_URL=http://127.0.0.1:8080/api \
  --dart-define=SYNC_URL=http://127.0.0.1:8081/sync \
  --dart-define=AUTH_URL=http://127.0.0.1:3500 \
  --dart-define=PORTAL_URL=http://127.0.0.1:8082

# Y se comprueba, que es lo que convierte la regla en una garantía. Se busca una
# DIRECCIÓN, no el nombre suelto: desde el 24/09/2026 hay un rótulo que dice
# «Ir a procovar.cloud» y el `grep -c procovar.cloud` de siempre ya no puede dar
# 0 nunca más.
strings build/linux/x64/release/bundle/lib/libapp.so \
  | grep -cE 'https?://[a-z.]*procovar\.cloud'    # 0
```

**SON CUATRO, no tres.** El `CLAUDE.md` §5 dice tres porque cuando se escribió
había tres. El 24/09/2026 apareció `PORTAL_URL`
(`app/lib/pantallas/acceso/datos/oferta_de_la_puerta.dart`), el enlace al portal
de la puerta, con `https://procovar.cloud` como `defaultValue`. A ese enlace no
se le pide nada —lo pulsa una persona, y en escritorio ni se construye—, pero
sin su `--dart-define` **el binario se lleva la dirección de producción dentro**.

Y de paso: el `grep -c procovar.cloud` que dice el `CLAUDE.md` **ya no puede dar
0**, porque el botón de esa misma pantalla se llama literalmente «Ir a
procovar.cloud» y eso es un rótulo, no una dirección. Por eso arriba se busca
`https?://…procovar\.cloud`. Una comprobación que empieza a fallar por un motivo
legítimo deja de leerse, y entonces tampoco se lee el día que hay una dirección
de verdad clavada. Si mañana aparece un quinto `--dart-define`, va aquí.

## 6. Ejecutarla sin ocupar la pantalla

En una pantalla aparte, la `:99`. Nada aparece en el escritorio de verdad:

```bash
Xvfb :99 -screen 0 1400x900x24 &
DISPLAY=:99 openbox &

cd app/build/linux/x64/release/bundle
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 GDK_BACKEND=x11 ./reparto &

DISPLAY=:99 import -window root captura.png          # una foto
DISPLAY=:99 xdotool mousemove 700 459 click 1        # pulsar
DISPLAY=:99 xdotool type --delay 40 "logistica.cam"  # escribir
```

`LIBGL_ALWAYS_SOFTWARE=1` porque en `:99` no hay GPU; arranca con Impeller sobre
OpenGLES por software y pinta igual.

## 7. Quitar la red a mitad, que es de lo que va todo esto

La aplicación de escritorio tiene que seguir trabajando sin señal. La forma limpia
de quitársela sin tocar el cortafuegos del equipo es **parar los contenedores**:

```bash
docker stop reparto-api-1 reparto-sync-1     # se va la señal
docker start reparto-api-1 reparto-sync-1    # vuelve
```

Parar sólo `api` deja el sincronizador vivo y contestando, que es un estado que no
existe en la calle: o hay red o no la hay.

## 8. Al terminar, se para TODO

Una aplicación viva dispara un ciclo de sincronización cada pocos minutos:

```bash
pkill -f 'bundle/reparto'
docker compose -f deploy/accesos-local/docker-compose.yml down
docker compose down            # en delivery-logistica; la base se queda
pkill -f 'Xvfb :99'; pkill openbox
```

---

## Lo que esto destapó el primer día que se pudo entrar

Los dos son del mismo tronco: **Accesos firma la sucursal con su CÓDIGO** (`CAM`),
y el reparto esperaba un uuid suyo. Ninguna prueba lo tocaba porque todas metían
un uuid en el token, que es lo que el código suponía y nunca lo que llega.

1. **`reparto-api` enseñaba las OCHO sucursales a todo el mundo.**
   `alcance.Resolver` hacía `uuid.Parse("CAM")`, fallaba, y caía en el «esta
   sucursal no existe → se le enseñan todas». Un ADMINISTRADOR de Camagüey pedía
   `/api/orders` y le volvían los 46 pedidos de las tres sucursales en vez de sus
   19, con 200 y sin un error. Es la regla 1 de la casa, y el mismo fallo que ya
   costó dinero en delivery.
2. **`reparto-sync` contestaba 401 a todo el protocolo.** El mismo `uuid.Parse`,
   fallando hacia el otro lado. Sin `POST /sync/aparato` no hay alta, y sin alta
   `POST /sync/subida` contesta 404: **la cola del día no subía nunca**. Y un 401
   que sobrevive a renovar el cliente lo lee como «la sesión murió», así que echa
   a la persona a la pantalla de acceso justo cuando vuelve la señal.

Los dos arreglados el 24/09/2026, con sus pruebas en pareja y su mutación
(`api/internal/alcance/alcance_test.go`, `sync/internal/identidad/token_test.go`).
La traducción del código la hace quien tiene la tabla: `reparto-api` por su cuenta,
y `reparto-sync` preguntándoselo por `GET /api/service/sucursal?codigo=CAM`.

---

## La jornada entera, hecha el 24/09/2026

Las capturas de las dieciocho paradas están en
`capturas/jornada-escritorio-2026-09-24/`. El recorrido, tal cual se hizo, con la
aplicación de escritorio en la pantalla `:99`:

| # | Paso | Qué se vio |
|---|---|---|
| 1 | Entrar | `logistica.cam`, `ADMINISTRADOR` de Camagüey. Sin el aviso de «este aparato no guarda la sesión»: el almacén de fichero de Linux sirve |
| 2 | Configuración inicial | bajó entera y el porcentaje avanzó |
| 3 | Trabajar | Pedidos **19** (los suyos, no los 46), Tablero, zona «Centro», ruta armada de la zona, pre-despacho, cierre |
| 4 | Sin red | franja **«Sin conexión»**, se siguió trabajando: 3 tarjetas, una zona nueva, 2 tarjetas más y el cierre de la ruta. **7 sin subir** |
| 5 | Matarla de golpe | `kill -9` con la cola llena. Al volver a abrir: **sin pedir contraseña**, «Trabajando sin conexión · 7 sin subir», y «Entregados hoy 2» |
| 6 | Devolver la red | subió todo por `POST /sync/subida`, en orden; lo que el servidor rechazó se quedó a la vista con su motivo |
| 7 | Entregar el día | «Todo entregado» + «Rechazados, esperando a una persona (1)» |

**Aguanta la jornada entera sin perder nada** — pero sólo con los cinco arreglos
de §«Lo que esto destapó» y §«Y lo que encontró la jornada». Sin ellos no se
llega ni al paso 3.

## Y lo que encontró la jornada

Aparte de los dos del código de sucursal, tres más:

3. **El Tablero no se abría.** `Sesion.sucursalId` es el CÓDIGO y se usaba como
   id local: `/api/board?branchId=CAM` → 404 y las lecturas locales sin
   encontrar nada. Pulsabas «Tablero» y no pasaba nada.
4. **De Pedidos no se salía.** El `replace` que escribe los filtros en la
   dirección corre DESPUÉS de navegar y volvía a poner `/orders` encima. Una vez
   dentro de Pedidos, el menú de la izquierda quedaba muerto — y el resto de la
   pantalla seguía respondiendo, así que ni parecía colgada.
5. **El post-despacho decía que se entregó todo cuando no.** La tabla sale de los
   renglones de cada pedido, y un pedido sin renglones no aporta ninguna: la hoja
   que firma el almacén imprimía «Nada: se entregó todo lo que salió» con tres
   paradas SIN MARCAR listadas dos líneas más abajo. Ahora dice **NO CONSTA**.

Y dos que quedaron escritos aquí sin arreglar y **se cerraron el 29/09/2026**, los dos
fuera de esta aplicación:

- ~~**El motivo de un rechazo sale en inglés y sin el pedido**: «Not found»~~. Las catorce
  puertas del tablero contestan ya en español diciendo QUÉ no está —la zona, el pedido o la
  sucursal—, que son tres arreglos distintos para quien lo lee. Ver `docs/tablero.md` §10.
- ~~**Volver la señal no dispara la subida: hay que esperar al ciclo.**~~ Medido entonces:
  la red volvió a las 14:45 y la cola no salió hasta las 14:50 — cinco minutos con el día
  dentro del aparato. **Cinco minutos es, al segundo, `VigiaDeSincronizacion.
  periodoPorDefecto`**, y esa coincidencia era la pista: no lo disparaba la señal, lo
  disparaba el reloj. El vigía escuchaba sólo a `connectivity_plus`, que avisa cuando
  cambia A QUÉ ESTÁS ENGANCHADO, y aquí eso no cambia nunca: el teléfono se queda pegado al
  mismo wifi o a los mismos datos y lo que se cae y vuelve está aguas arriba. Desde el
  29/09/2026 se le junta el veredicto nativo de Android —el que enciende el icono de wifi
  con la exclamación—, que sí se entera (`avisosParaElVigiaProvider`).

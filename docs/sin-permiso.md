# Sin permiso para Reparto

Jose, 08/10/2026: «a los que no tienen permiso Reparto les diga no tienes permiso y que se
dirijan a Accesos, a su inicio con la ruta rápida».

Solo entran a Reparto **ADMINISTRADOR, SUPER ADMIN, DESARROLLADOR y LOGISTICO**. El resto
de roles de Procovar (GERENTE, SUPERVISOR, GESTOR, OPERADOR…) tienen cuenta en Accesos pero
no esta aplicación. (LOGISTICO no estaba entre los siete roles que lista el `CLAUDE.md` de
Procovar: si no existe aún en Accesos, hay que darlo de alta allí.)

## Qué ve la persona

Una pantalla (`/sin-permiso`, `pantallas/acceso/vista/pantalla_sin_permiso.dart`) con:

> **No tienes permiso para entrar a Reparto**
> Reparto es para el personal de logística y la administración. Si crees que es un error,
> pídele acceso a un administrador.

Se llega a ella **desde cualquier pantalla**, también durante la carga inicial, en cuanto una
sola llamada a la API contesta el 403 de abajo. Sin armazón: ni menú ni selector de sucursal.

## Qué hace cada plataforma

| | Web | APK y escritorio |
|---|---|---|
| Salida a Accesos | **Sola, a los 3 s**, con contador visible («Te llevamos al inicio de Accesos en 3 s…») y botón **«Ir ahora a Accesos»** (al instante) | **Nunca sola.** Botón **«Ir a Accesos»**: abre el inicio de Accesos en el navegador del sistema (`url_launcher`) |
| Cerrar sesión | No (Accesos ya tiene la suya) | Botón **«Cerrar sesión»**: el mismo cierre de la cuenta; si hay apuntes sin subir, **pregunta** y dice que salir NO los borra |
| A dónde | `AUTH_URL` + `/` (el inicio de Accesos: allí ve las aplicaciones a las que SÍ puede entrar) | igual |

La web se va con `navegadorProvider` (navegación de verdad, la misma pieza que el login único),
así que se prueba sin navegador. El destino sale de `Entorno.authUrl` (`--dart-define=AUTH_URL`).

## El contrato con el servidor

Cuando la persona no es de uno de esos 4 roles, **CUALQUIER** llamada autenticada a la API de
Reparto contesta:

```
HTTP 403
{"error":"No tienes permiso para entrar a Reparto.","codigo":"sin_permiso_reparto"}
```

Es DISTINTO de los otros 403 (alcance de sucursal: sin `codigo`; siguen siendo un `Rechazo`
normal). La app solo se dispara con las tres cosas a la vez: **403**, respuesta de **nuestra
API** (JSON; el 403 de un proxy no vale) y **`codigo == sin_permiso_reparto`**
(`esSinPermisoDeReparto`, `nucleo/red/interceptor_sesion.dart`). Un 401 con ese cuerpo no
cuenta: un 401 es sesión.

## Cómo se detecta y a dónde va

1. `InterceptorSesion.onError` ve el 403 y avisa (`alFaltarPermiso`). Está en los dos clientes
   (`/api` y `/sync`), así que lo ve cualquier pantalla, la bajada y la subida.
2. `Portero.sinPermiso()` pasa a `EstadoDeAcceso.sinPermiso`. **No es `fuera`**: la sesión, la
   base y la cola de la persona siguen abiertas e intactas.
3. `redirigir` manda a `/sin-permiso` desde cualquier ruta. El estado no se abandona solo
   (`_poner` no deja volver a `dentro`/`configurando`): se sale cerrando sesión o entrando de
   nuevo.
4. En la web, `/api/me` también puede traer ese 403 durante el arranque: `EntradaPorAccesos`
   lo devuelve como `SinPermiso` y `arrancar` lo manda a la pantalla **sin pasar por el login
   único** (si no, Accesos devolvería a la persona con la cookie puesta y sería un bucle).

**Sin bucles.** La pantalla no repite la llamada que dio el 403, y el ciclo de sincronización
y el vigía paran (`haySesionParaSincronizar(sinPermiso)` es falso; el vigía solo corre con
`dentro`). Volver de Accesos a Reparto reevalúa porque la persona entra de nuevo (en la web es
una carga nueva de la página; en la APK, cerrar sesión y entrar).

## NO PERDER TRABAJO: la cola

Un 403 `sin_permiso_reparto` **no es un rechazo del apunte**: es la PERSONA. Convertir su cola
en `rechazado` destruiría trabajo que arregla un administrador dándole el rol.

* Si el 403 llega como respuesta HTTP de `/sync/subida`, sale como `Rechazo` con marca desde
  `_mandarUno` y **nadie resuelve el apunte**: queda `pendiente`, con su ruta y su cuerpo
  intactos (como con un 401, la cola se conserva y espera).
* `Subida._aplicar` tiene una segunda cerradura: si el sync reenvía «No tienes permiso para
  entrar a Reparto.» como rechazo **dentro de un 200**, tampoco se resuelve el apunte.
* Probado en pareja en `test/nucleo/red/sin_permiso_de_reparto_test.dart`: un rechazo normal
  sigue siendo `rechazado`; el 403 con ese `codigo` deja el apunte `pendiente` e intacto.

### El servidor de sync (hecho)

`sync/` responde HTTP 403 con el mismo cuerpo (`{"error","codigo":"sin_permiso_reparto"}`) en
`/sync/subida` y en las demás rutas `/sync/*` si la persona no es de los 4 roles, **sin anotar
nada**: la cola se queda pendiente. La primera cerradura de la app (el 403 HTTP) es la de
verdad. La segunda —el motivo literal «No tienes permiso para entrar a Reparto.» dentro de un
200— ya no la dispara el servidor y queda como defensa. El literal vive en
`api/internal/auth/middleware.go` y `sync/internal/identidad/identidad.go`, y
`app/test/nucleo/red/el_literal_del_sin_permiso_test.dart` lee los dos ficheros y falla si
dejan de coincidir con `fallos.dart`.

`GET /api/me` NO da este 403 (contesta 200 con quién es la persona): el disparador real es la
PRIMERA llamada protegida (la bajada del sync o cualquier `/api/*`). El camino
`quienSoy()` → `SinPermiso` es defensivo.

## Accesos también lo dice: en el login y en el refresco

Accesos (`/api/auth/token` y `/api/auth/refresh`) contesta
`403 {"error":"sin_permiso","codigo":"sin_permiso","message":"No tienes permiso para entrar a
Reparto."}` si la cuenta no tiene `delivery.entrar` (`esSinPermisoDeAccesos`,
`nucleo/identidad/renovador.dart`; la marca vale en `error` o en `codigo`). No es la de la API
(`sin_permiso_reparto`) y no se confunden.

* **Login (APK y escritorio).** `MotivoDeAcceso.sinPermiso`, como `sin_sucursal`: aviso ámbar
  con el mensaje, «Reparto es para el personal de logística y la administración…» y el botón
  **«Ir a Accesos»** (el inicio de Accesos, en el navegador del sistema). **No se deja nada**:
  ninguna sesión guardada, el portero no se mueve, la cola de nadie se toca. El formulario se
  queda, para probar con otra cuenta.
* **Refresco (el token se renueva al sincronizar).** La persona perdió el permiso a media
  jornada. `Renovador` avisa al portero (`sinPermiso`) y lanza un `Rechazo` con la marca de
  «sin permiso», **no** `SesionMuerta`: la sesión no se tira, el par se queda (con él se revoca
  al cerrar sesión), y **la cola y la base se conservan**. Lo ven igual el interceptor
  (peticiones), el ciclo (sincronizar) y el arranque (`Arranque.sinPermiso`, con la sesión).
  «Cerrar sesión» sigue preguntando si hay apuntes sin subir. Un 401 al renovar sigue siendo
  sesión muerta. (Un 403 al renovar SIN la marca sigue como hasta hoy: `FalloDeRed`.)
* Pruebas: `test/nucleo/identidad/sin_permiso_al_renovar_test.dart` y
  `test/pantallas/acceso/sin_permiso_en_el_login_test.dart`, las dos con dos apuntes pendientes
  en la cola.

## De dónde se sale

* `Portero.sinPermiso()` estando `fuera` **se ignora**: un 403 tardío de una petición que iba en
  vuelo cuando se hizo `salir()`/`murio()` no resucita la pantalla.
* De `sinPermiso` **solo se sale SALIENDO**: `salir()` y volver a entrar desde el acceso (en la
  web, recargando). `entro()` estando en `sinPermiso` no lleva a `dentro`: se traga en silencio,
  **por diseño** (fijado en `test/navegacion/portero_sin_permiso_test.dart`).
* `AUTH_URL` vacío (`--dart-define=AUTH_URL=`) cae en `https://auth.procovar.cloud`; vacío
  mandaría la web a `/`, es decir a sí misma, cada 3 s.

## Accesibilidad de la web

La salida sola se anuncia una vez (`Semantics(liveRegion: true)`: «Te llevamos al inicio de
Accesos en unos segundos»); el contador visual va en `ExcludeSemantics` para que el lector de
pantalla no diga «3, 2, 1». El botón «Ir ahora a Accesos» se queda.

## Cómo se da acceso

En Accesos se le da a la persona el rol **LOGISTICO** (o ADMINISTRADOR / SUPER ADMIN /
DESARROLLADOR). No hay nada que tocar en Reparto: al volver a entrar, la API deja de contestar
el 403. Si la sucursal de la persona no está dada de alta en Reparto, es otro 403 (sin
`codigo`) y se trata como siempre.

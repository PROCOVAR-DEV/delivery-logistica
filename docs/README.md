# El pliego

Todo lo que hace falta saber para reconstruir el reparto **sin abrir el repositorio de
Next**. Sacado del código de `delivery`, que se queda en pie hasta el final como patrón.

| Documento | Qué hay dentro | De dónde sale |
|---|---|---|
| `modelo-datos.md` | Los 11 modelos con todos sus campos, las relaciones, los 10 pseudo-enums y los campos calculados | `prisma/schema.prisma` + `src/` |
| `contratos-api.md` | Las 35 rutas: parámetros, cuerpos, respuestas y los mensajes de error **literales**. Su §12 es la **bandeja de revisión** (Accesos `/api/auth/entrega` y `/sync/revision/*`, con todos sus códigos) | `src/app/api/**` + `sync/` y Accesos |
| `reglas-negocio.md` | Las 15 reglas con sus fórmulas, constantes y casos límite | `src/lib/` + el armado de ruta |
| `pantallas.md` | Las 7 pantallas, la navegación, los componentes y **qué sale impreso** | `src/app/(dashboard)/` + `src/components/` |
| `tablero.md` | El **tablero de preparación**: la pantalla nueva que no existe en delivery | diseño nuevo, encargo del 14/09/2026 |
| `sincronizacion.md` | El protocolo entre la aplicación y el sincronizador. Su §4 es la **revisión**: estados, las tres tablas, idempotencia, cupos y el invariante «el Aplicador no se llama nunca al entregar» | diseño nuevo |
| `identidad.md` | Entrar, renovar y trabajar sin conexión | diseño nuevo, patrón de `call-center-board` |
| `montar-en-dokploy.md` | Lo que queda para encenderlo: servicios, variables y avisos | paso a paso |
| `pruebas.md` | El guion de QA del dominio | diseño nuevo, método de `qa-como-usuario` |

Aparte del pliego, y porque no describe el reparto sino cómo se pone en pie:

| Documento | Qué hay dentro |
|---|---|
| `despliegue.md` | Los cinco contenedores, las variables de cada servicio, el orden de arranque y cómo se comprueba que están vivos. Su §4-bis es el **orden de la ronda de la bandeja de revisión** (1.0.32) |
| `bandeja-de-revision.md` | Qué pasa con la cola de quien pierde `delivery.entrar`: el diseño aprobado el 08/10/2026, y al final «Estado real (09/10/2026)» con lo que se hizo, en qué se desvió y lo que NO se hizo |
| `sin-permiso.md` | La pantalla de «no tienes permiso», cómo se conserva y se entrega la cola, y la sesión cerrada desde Accesos |
| `entorno-local.md` | El reparto entero en el portátil con Accesos, y las pruebas contra Postgres (`verif_reparto`, `verif_sync`) y Redis de verdad |
| `compilar.md` | Cómo se saca cada salida de la aplicación —web, APK, Windows, Linux— y desde qué máquina. Con las variables del espejo de Tencent, sin las que el APK no compila desde Cuba |
| `actualizaciones.md` | Cómo le llega una versión nueva a los diez logísticos: el anuncio de `/api/version`, la comprobación en el aparato y las tres reglas. Incluye **con qué clave se firma el APK**, que hoy es la de depuración y no se puede repartir así |

Los cuatro primeros describen **lo que ya existe** y no hay que volver a decidir: se leen y
se copian. Los tres últimos son **lo que hay que decidir bien**, porque no existe todavía.

## Dos cosas que salieron al escribir esto y hay que resolver

- **`Vehicle.type` es un conjunto abierto.** No hay catálogo declarado en ninguna parte, así
  que en Go no se puede cerrar el tipo sin decidir antes cuáles son los valores válidos.
- **`updatedAt` falta en 5 de los 11 modelos.** Sin esa marca no hay bajada por diferencias.
  Ver el apartado 4 de `modelo-datos.md`.

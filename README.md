# delivery-logistica

El reparto de Procovar, reconstruido. Tres piezas en un solo repositorio:

```
api/    Go       — las 35 rutas, los 11 modelos y la lógica de negocio
sync/   Go       — bajada por diferencias, subida por lotes, registro de aparatos
app/    Flutter  — la interfaz, única: se compila a web, APK y escritorio (Windows y Linux)
docs/   el pliego, sacado del código de delivery
deploy/ los cinco Dockerfile y el nginx de la web
.github/workflows/  reparto-windows.yml: compila el instalador de Windows (no despliega nada)
```

**Dónde vive el código:** `https://github.com/PROCOVAR-DEV/delivery-logistica` (la
organización). `jose22072000/delivery-logistica` es, desde el 07/10/2026, un **fork
personal** que no se actualiza solo. En el clon local, `upstream` es la organización (donde
se sube lo que se quiere desplegar) y `origin` es el fork.

**Los servicios los despliega Dokploy**, que clona la organización y construye él con los
Dockerfile de `deploy/`. Aquí no se construye ninguna imagen. Ya no hay un workflow que
compruebe Go: `./comprobar.sh` hace esa comprobación en local. Las migraciones **no** las
aplica la api al arrancar —se aplican a mano antes de desplegar y la api nueva se niega a
arrancar con la base atrasada—, y las dos bases del reparto **no están en el respaldo diario**
del servidor: `docs/despliegue.md` §2.1 y §2.2.

La aplicación se compila a mano: web y APK desde el portátil Linux, y el `.exe` de Windows
en el ejecutor de GitHub Actions (`reparto-windows.yml`) o en el portátil Windows de Jose
—Flutter no cruza de una plataforma a otra—. El escritorio de Linux es sólo para probar: no
hay canal de Linux. Las órdenes exactas están en `docs/compilar.md`, y cómo le llega después
una versión nueva a los diez aparatos (con la clave de firma del APK, ya resuelta desde el
21/09/2026) en `docs/actualizaciones.md`; cómo se publica cada versión, en
`docs/despliegue.md` §3.1.

## Para qué

Diez logísticos, uno por sucursal, que arman las rutas de la suya. **Por la mañana tienen
conexión; durante el día, no.** Hoy eso significa que no pueden trabajar: sin red no abre
la página, no pueden entrar y no tienen datos.

El problema no es sincronizar. Es que la aplicación tiene que vivir en el aparato —el
código, la sesión y los datos—, y hoy las tres cosas viven en el servidor.

## `delivery` NO SE TOCA

El proyecto de Next se queda en pie, entero, hasta el final. Es dos cosas:

- **El pliego.** Dice qué hace cada pantalla, con qué filtros y contra qué endpoint. No hay
  que volver a decidir nada de eso: se lee y se copia.
- **El patrón.** Terminado aquí significa **da los mismos números que la de Next**. Las dos
  en pie a la vez y se comparan.

Se apaga al final, cuando los diez estén dentro y nadie la abra.

## Por qué se puede reconstruir entero

Delivery está construido pero **no está en uso** — el piloto de Santiago no se ha
encendido. Sin usuarios no hay nada que migrar, ni convivencia de dos versiones, ni
despliegue sucursal por sucursal, ni la obligación de que cada paso deje algo funcionando.
Se construye al lado y se enciende una vez.

Eso también deja el esquema libre: lo que en un sistema en marcha sería una migración
delicada aquí es escribirlo bien a la primera, empezando por el `updatedAt` que hoy falta
en 5 de los 11 modelos y sin el cual no hay bajada por diferencias posible.

## Las reglas que no se negocian

1. **Para entrar hace falta conexión. Una vez dentro, no.**
2. **Nunca esperar al servidor.** Todo se guarda en el aparato primero y se pinta hecho.
3. **Una sola renovación de sesión en vuelo** — dos a la vez y el servidor revoca todas las
   sesiones de la cuenta.
4. **Renovar antes de subir.**
5. **Un 401 mata la sesión. Un fallo de red, no.**
6. **Nada se descarta en silencio.**
7. **La hora es la del aparato.**
8. **Al cerrar sesión se borra lo local.**

Cada una está explicada en el README de la pieza a la que le toca.

## Antes de subir

```
./comprobar.sh
```

gofmt, vet, test, build y `sqlc diff` de los dos módulos de Go, más `analyze` y `test` de
Flutter. No hay GitHub Actions para eso a propósito (el único workflow, `reparto-windows.yml`,
compila el instalador de Windows y no comprueba Go): despliega Dokploy, que clona y
construye él, y la comprobación es ésta, en local.

## Pruebas

El criterio de terminado es **dar los mismos números que la de Next**, y por eso Next se
queda en pie hasta el final. Qué hay que probar y en qué orden de riesgo: `docs/pruebas.md`.
El *cómo* sale de la skill de QA, que está pendiente de Jose.

Plan completo: https://claude.ai/code/artifact/9ca0b1de-25a6-486d-87eb-6a6d85ac978f

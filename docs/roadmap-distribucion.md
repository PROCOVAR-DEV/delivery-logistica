# Roadmap: la distribución (Reparto, APK `reparto-distribucion` y Accesos)

Pedido de Jose (04/11/2026): «necesito % de todo lo que vayas haciendo hasta estar en 100%, y aquí entra lo de Accesos, lo de Reparto y lo de la
APK reparto-distribucion». Este fichero es la fuente: se actualiza en cada avance. El modelo es el de `docs/plan-app-distribuidor.md` con los
cambios de hoy: **sin cuentas ni login**, el distribuidor trabaja con el **enlace** que le manda el logístico, la ruta queda asignada a **su
teléfono**, el APK trae el mapa dentro y el seguimiento (GPS, horas, cobro) sube cuando hay internet.

Leyenda: ✔ hecho y probado · ◔ en curso (con su %) · ☐ sin empezar · ⏸ aparcado (no cuenta en el %) · 🔒 espera tu visto bueno

**TOTAL: 78 %** (29 de 37 tareas) — 04/11/2026, tarde

## ORDEN DE TRABAJO (por prioridad)

**P0 — sin esto no se puede ni mandar una ruta ni usarla** (en curso, en este orden)
1. Servidor 8 y 9: cancelar ruta (solo sin entregadas) y «no entregada» con motivo
2. Servidor 12: página del enlace `/r/<token>` (adonde llega quien abre el enlace sin la app)
3. Reparto app 1 y 2: **«Enviar a distribuidor»** y el estado del enlace por ruta (web, Windows y APK de Reparto)
4. APK distribuidor 1, 7 y 8: entrada propia, mapa detallado dentro y pruebas con `flutter test` entero

**P1 — control de la logística sobre lo que hace el distribuidor**
5. Servidor 10 + Reparto app 6: revisión por logística (la segunda llave)
6. Reparto app 3: recorrido real de la ruta (mapa, traza, horas, cobro)
7. Servidor 11 + Reparto app 7: vehículo ↔ distribuidor

**P2 — administración de toda la vida de la distribución**
8. Reparto app 4: vista por vehículo (historial)
9. Reparto app 5: dónde están ahora

**P3 — salida a producción** (todo 🔒: cada paso con tu visto bueno)
10. Despliegue del servidor (migraciones 00032-33, API, sync) y de Accesos (rol)
11. Web de Reparto, APK de Reparto, **Windows** y tarjetas del portal
12. Compilar y publicar el APK del distribuidor + canal de descarga + tarjeta del portal
13. Prueba en teléfono real (tuya) y cierre al 100 %

## 1. Reparto — servidor (API y sync): 93 % (13 de 14; solo falta el despliegue)

- ✔ 1. Lista blanca del distribuidor en la API y en el sync (falla cerrado; lo que no está, 403)
- ✔ 2. Alcance por teléfono: solo ve y toca las rutas asignadas a su teléfono (rutas, pedidos, renglones, vehículos, bajada y cuadre)
- ✔ 3. Enlace por ruta (uno vivo por ruta), reclamar (un teléfono por ruta), renovar y token del teléfono (180 días, firmado por Reparto)
- ✔ 4. Hora real del aparato y «cobrado» por parada al cerrar
- ✔ 5. GPS: recepción por lotes, idempotente, varias rutas en curso a la vez
- ✔ 6. GPS: lecturas de la oficina (recorrido de una ruta, historial por vehículo, dónde están ahora); el distribuidor no las ve
- ✔ 7. Pruebas de extremo a extremo contra la API y el sync reales (7 pruebas) y de unidad
- ✔ 8. Cancelar la ruta por el distribuidor (solo si no hay ninguna entregada; las paradas sin marcar quedan libres) — con prueba e2e
- ✔ 9. «No entregada» exige motivo (validación en el servidor); completar exige todas las paradas marcadas — con prueba e2e
- ✔ 10. Revisión por logística (`revisadaAt/revisadaPor`, `POST /api/routes/{id}/revision`, migración 00034; solo la oficina, solo rutas completadas) — con prueba e2e
- ✔ 11. Vehículo ↔ distribuidor en la API (`distribuidorId` al crear/editar, en la lista, en el detalle y en la bajada; la app lo propone al armar la ruta) — con prueba e2e
- ✔ 12. Página web del enlace `/r/<código>` (avisa que hay que instalar la app y da la descarga; abre la app con intent) y `assetlinks.json` para que WhatsApp abra la app directamente — probada con nginx local. Falta, al publicar el APK, subir el alias `reparto-distribuidor-ultimo.apk`
- ✔ 14. Vehículo ↔ teléfono: el enlace lleva el vehículo y el distribuidor, el teléfono se vincula al vehículo (uno a uno), la oficina desvincula (403 `dispositivo_desvinculado`, la APK se vacía) y el servidor conserva la historia por id de dispositivo (migración 00035) — con prueba e2e
- 🔒 13. Despliegue en producción (migraciones 00032 a 00035, API, sync, web)

## 2. Reparto — la MISMA aplicación de siempre (web, **Windows**, APK de Reparto) con el apartado nuevo «Distribución»: 64 % (7 de 11; lo hecho pasa `flutter test` entero)

- ☐ 1. «Enviar a distribuidor»: crea el enlace de la ruta y lo comparte por WhatsApp (sustituye al enlace de Google Maps); en web, Windows y APK
- ☐ 2. Estado del enlace por ruta: sin reclamar / reclamado por qué teléfono / soltar y renovar
- ☐ 3. Recorrido real de la ruta: mapa, traza del GPS, cada parada con su hora real, tiempo en la parada y cobro
- ☐ 4. Vista por vehículo: la vida de cada vehículo (sus rutas, quién las hizo, qué hizo en cada una)
- ☐ 5. «Dónde están ahora»: último punto de cada distribuidor con ruta en curso
- ☐ 6. Revisión de rutas completadas por el distribuidor (la logística confirma o corrige: dos llaves)
- ☐ 7. Asignar vehículo ↔ distribuidor en Vehículos y Distribuidores
- ☐ 8. Publicar la **web** de Reparto con lo nuevo 🔒
- ☐ 9. Publicar el **APK de Reparto** (el de la oficina y los logísticos) con lo nuevo 🔒
- ☐ 10. **Windows**: comprobar que las pantallas nuevas (enviar a distribuidor, recorrido real, vehículos, dónde están) funcionan en el escritorio, compilar el instalador en la CI, verificarlo y publicarlo con la tarjeta 13 del portal 🔒
- ☐ 11. Portal: actualizar las tarjetas de Reparto (APK de Reparto y Windows) y verificarlas con navegador real 🔒

## 3. APK `reparto-distribucion` (la app del distribuidor): 80 % (8 de 10; compila y pasa `flutter test` entero; sin probar en teléfono)

Hecho por un agente aparte en una copia del repo (rama `feat/app-distribuidor`, sin subir). Los % son una estimación por lo escrito hasta ahora; ninguna
pieza está dada por buena hasta que pasen sus pruebas y `flutter test` entero.

- ✔ 1. Entrada propia (`main_distribuidor.dart`) y segundo `applicationId` opcional
- ✔ 2. Reclamar el enlace (abrir `/r/<token>`, pegar el enlace, dispositivo, secreto, renovar el acceso)
- ✔ 3. Mis rutas y ruta guiada (siguiente parada, qué entregar y cobrar, cronómetros, varias rutas a la vez)
- ✔ 4. Marcar paradas (entregado / «no entregada» con motivo / cobrado sí-no), completar sola, cancelar la ruta
- ✔ 5. Historial y registros del propio distribuidor
- ✔ 6. GPS (captura con servicio en primer plano, base local, subida por lotes, aviso de ubicación)
- ✔ 7. Mapa detallado de Cuba dentro del APK (se instala solo en el primer arranque, sin red)
- ✔ 8. Pruebas, `flutter analyze` y `flutter test` entero
- ☐ 9. Compilar y publicar el 2.º APK (script del mapa, canal de descarga, tarjeta del portal) 🔒 — 0 %
- ☐ 10. Prueba en un teléfono real, sin conexión y con GPS (la haces tú; yo no puedo) — 0 %

## 4. Accesos: 50 % (1 de 2)

- ✔ 1. Rol `DISTRIBUIDOR` en el código (1.409 pruebas en verde) — ya está en `main` de Accesos
- 🔒 2. Desplegar Accesos para que el rol exista en la base (el control automático bloqueó el despliegue; falta tu visto bueno)
- ⏸ Rutas de servicio para crear usuarios de distribuidor y refresh de 90 días — hechas en una rama aparte, **aparcadas**: el modelo por enlace no usa cuentas

## 5. Transversal

- ✔ Plan documentado (`docs/plan-app-distribuidor.md`)
- ☐ Plan reescrito al modelo por enlace (sin cuentas)
- ✔ Este roadmap
- ☐ Notas de Obsidian y horas del día (cuando digas lo del cierre)

## Qué espera algo tuyo

1. 🔒 Visto bueno para **desplegar**: Accesos (rol) y, cuando estén cerradas las tareas del servidor, Reparto (migraciones, API, sync, web).
2. Probar la APK del distribuidor en un teléfono real (yo no puedo), sin conexión.
3. Decidir cuándo se publica el segundo APK y su tarjeta en el portal.

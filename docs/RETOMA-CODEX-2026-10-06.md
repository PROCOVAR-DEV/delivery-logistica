# Reparto — corte para apagar la máquina, 06/10/2026

## Actualización al retomar el mismo día

El conteo por ocurrencias y las pruebas de la misma línea/fallback JS ya están
corregidos. Auditoría local v3 **LISTO**: suite completa verde, 25 mutaciones,
21 rojas y cuatro redundantes equivalentes, todas restauradas a verde; seis
archivos restaurados por bytes/SHA exactos. Evidencia en
`app/build/codex-retoma-20261006/auditoria-cache-cajon-v3/resultado.json`.
La conexión SSH normal al VPS agotó 15 segundos al retomar; no se cambió la red
ni se ejecutó ningún despliegue/publicador. Siguen pendientes compilación de
entrega y comprobación/publicación en producción. Los apartados siguientes
conservan el estado histórico al apagar; consultar también
`app/build/codex-retoma-20261006/verification.json` para la última evidencia local.

Trabajar exclusivamente en `/mnt/datos/Work/procovar/delivery-logistica`.
Leer AGENTS.md, CLAUDE.md y la nota de Obsidian indicada allí. No tocar VPN ni
configuración de red. Nunca republicar una APK ni repetir un despliegue a ciegas.

## Git y trabajo guardado

- `main` en `c93edb8ef8510bdabcba15b646b4512c637f940e`, tres commits por delante
  de `origin/main`. Conserva `184b8ec` y `1f26996`. No se hizo push.
- `c93edb8`: guía con demostración animada del gesto y arrastre real entre dos
  controles; versión `1.0.24+25`. Auditoría anterior LISTO.
- Cambios SIN COMMIT: `pantalla_guia.dart`, `deploy/Dockerfile.app`,
  `deploy/nginx.conf`, nuevo `deploy/preparar-web.sh`, nuevos tests
  `app/test/despliegue/recursos_de_la_web_test.dart` y
  `app/test/pantallas/ayuda/la_guia_cierra_su_cajon_test.dart`.
- Arreglan la fuente antigua de los iconos y el cajón que tapaba la tarjeta al
  enseñar la propia Guía. El cajón ahora se cierra desde su propio Navigator.
- Pruebas focales: 30 de guía y 17 de recursos verdes. Tras corregir cuatro
  avisos de lint de los tests, `./comprobar.sh` completo quedó verde.

## Auditoría pendiente: NO LISTO

El apagado interrumpió la auditoría adversaria, no un despliegue. Se restauraron
los seis archivos auditados al snapshot exacto y se cerraron sus procesos.
La evidencia vive en `app/build/codex-retoma-20261006/auditoria-cache-cajon-v2/`.

Hallazgo pendiente: `preparar-web.sh` usa `grep -Fc` para contar inicializadores
y entradas JS; cuenta líneas, no ocurrencias. Dos `_flutter.loader.load({` en
una misma línea se aceptan y sólo la primera recibe `assetBase`. Cambiar a
conteo de ocurrencias (`grep -Fo | wc -l`) y añadir el caso en una misma línea.
La guarda de `mainJsPath` sí es necesaria: el bootstrap real tiene un fallback
`main.dart.js`; el fixture mínimo no permite comprobar esa guarda al retirarla.
Añadir el fallback real al fixture. Ver `CIERRE-URGENTE.txt`,
`dos-inicializadores-misma-linea.json`, `guarda-mainJsPath-bootstrap-real.json`,
`mutaciones.json` y `build-real.json`. Repetir comprobación y auditoría antes de
commit, build de entrega o despliegue. No lanzar builds mientras se muta código.

## Producción: evidencia y límites

- Se accedió por SSH normal usando el ControlMaster existente. No se cambió la
  red ni se activó VPN. Todas las peticiones a Procovar se hicieron DENTRO del VPS.
- API anuncia `ultima.version=1.0.23`, compilación 24. APK anterior verificada
  en host, MinIO y descarga pública: 78.851.736 bytes, SHA256
  `630f58f7bc06c1573dbf630591b7ab97a7d4d6d2c4884eab0d325ba1352b7c49`.
  No se repitió su publicación; se preservaron las tres APK anteriores.
- Web `c93edb8` desplegada mediante Dokploy **application.redeploy**, que
  reconstruye el checkout local; **application.deploy** clona origin/main viejo.
  Despliegue `mNUcNKOBQZAZyfvKA11Yj`: done. Checkout VPS limpio en c93edb8,
  `/etc/dokploy/applications/reparto-web-dihwbq/code`. Imagen actual:
  `sha256:7d91b8672c7fa9482f02200fc1cbb14c536077018e54c69489efae5177bba8a9`.
- Origen web comprobado: `/` y `/guia` 200, versión 1.0.24/build25, JS nuevo y
  manual exacto. Navegador Chromium EN VPS abre tareas/documento, búsqueda y
  menú de escritorio/móvil. Usa identidad y API de prueba interceptadas: NO
  demuestra autenticación ni datos de negocio reales.
- **Web todavía NO verificada como entrega final**: icono Guía vacío porque
  Cloudflare sirve MaterialIcons del 01/10: 20.904 bytes, SHA256
  `48ac6aab844ba7b8184a416bf477bb86f936bfabf353630b816b14ef7dcdb887`.
  No contiene el glifo 0xf1c2. Origen nuevo: 22.060 bytes, SHA256
  `da3330a1aa7bd579e0371e6e942a31b7854675cdf5836c023ccd76c62d46ceca`,
  sí contiene el libro. Además el recorrido dejaba abierto el cajón; arreglo local.
- Nuevo postprocesador mueve assets a `recursos/<huella>/assets/` y configura
  `assetBase`. Probarlo contra build real cambiando sólo la fuente cambió la
  huella. Nginx aislado en VPS, fixtures propias y `--network none`: fuente200
  immutable, inexistente404, `/guia`200 no-cache; mutaciones de fallback/cache
  incorrectos fallaron. No se alteró el servicio de producción con esa prueba.

## APK nueva: NO PUBLICADA

- La APK `1.0.24+25` de c93edb8, SHA256
  `7afd5a0b4bb167d0de2e1cc7e1dd0f0c955405ef5a0f9a56d788bd547705fba9`,
  78.868.528 bytes, está en `/var/lib/procovar/apk/reparto-1.0.24-261006.apk`
  y en el directorio de verificación del VPS. **NO está en MinIO ni anunciada**.
  No incluye la corrección pendiente del cajón: NO publicarla como entrega final.
- Copia local independiente conservada en
  `app/build/codex-retoma-20261006/reparto-1.0.24-c93edb8-sin-publicar.apk`.
- Tras aprobar y commitear, recompilar Android con URLs de producción explícitas
  (compilar no ejecuta peticiones), verificar firma, versión, hash y manual.
  `verify-new-apk.py` está preparado en el directorio local ignorado. Firmante:
  `01529f5a6fb1a238985745aff13cdcf7e8e85b624992f4e328bde9898fd80b21`.
- Reemplazar deliberadamente el staging SIN PUBLICAR, comprobando primero el
  hash conocido, API anterior y ausencia del objeto nuevo en MinIO; conservar
  copia previa. Luego publicar sólo si la web corregida fue comprobada.
- Publicador seguro preparado `publish-verified-apk.py` local/VPS: nunca ejecutado.
  Recibe bytes/SHA reales; preserva APK anteriores, verifica descarga antes de
  cambiar anuncio, mantiene env privado y journal para no reintentar a ciegas.
  No usar `deploy/publicar-apk.sh` para recuperar este estado.
- No hay teléfono ADB conectado. Instalación física no comprobada; push pendiente
  por el orden exigido en AGENTS.md. No afirmar instalación ni producción completa.

## Herramientas preparadas y siguientes pasos

Directorio local ignorado: `app/build/codex-retoma-20261006/`.
Directorio VPS: `/var/lib/procovar/verificacion-guia-20261006/`.

1. Corregir los dos puntos del auditor, comprobar y auditar; verificar restauración.
2. Commit explícito, sin `git add -A`. Todos los agentes deben terminar antes de subir.
3. Nuevo bundle desde c93edb8. `deploy-verified-web-cache.py` preparado pero NO
   ejecutado; exige baseline c93edb8 e imagen exacta, preserva rollback y evita
   repetir un intento registrado. Ajustar SHA/commit del bundle final.
4. Compilar y verificar APK corregida. Desplegar web por `application.redeploy`.
5. Ejecutar `browser-guide-reviewed.cjs` EN VPS (Playwright1.63.0 ya instalado),
   verificar fuente nueva, icono visible, cajón cerrado, control real clicable,
   animación finita/repetible, avanzar/atrás/salir. No dar tests falsamente verdes.
6. Sólo entonces publicar APK nueva; comprobar despliegue API, anuncio y descarga.
   Resolver instalación física antes de decidir push. No exponer secretos.

Amado: la documentación indicada está en
`/mnt/datos/Work/procovar/docs/del-reparto-para-pedido.md`; manual del usuario en
`docs/manual/README.md` y `docs/manual/solo-administracion/canal-con-pedido.md`.
No se envió ningún mensaje a terceros. No se modificó fns-sync ni Obsidian.

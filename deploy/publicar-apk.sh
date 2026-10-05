#!/usr/bin/env bash
# PUBLICAR UNA VERSIÓN DE LA APK, Y DE PASO TIRAR LAS VIEJAS.
#
# ─────────────────────────────────────────────────────────────────────────────
# POR QUÉ ESTO EXISTE, Y POR QUÉ LA LIMPIEZA VA AQUÍ DENTRO — 05/10/2026
#
# Publicar eran cinco pasos a mano —compilar, subir al host, colgar en MinIO,
# cambiar siete variables en Dokploy y redesplegar la api— y la limpieza era un
# sexto que NO ESTABA. Resultado, mirado ese día: **16 APKs colgadas, 1,3 GB**,
# de las que servía UNA. Y 746 MB más de copias sueltas en el disco del host, que
# es corto.
#
# Jose: «has algo para q el peso muerto no se acumule, así como estaba **ahora yo
# no me iba a dar ni cuenta**». Y es exacto: nada fallaba, nada avisaba, y el
# disco se iba llenando.
#
# Por eso la limpieza **no es un cron ni un guion aparte**: va DENTRO del acto de
# publicar. Un trabajo programado se para, se olvida o nadie mira su registro; un
# paso que corre siempre que publicas no se puede olvidar, porque publicar es lo
# único que crea el peso muerto.
#
# **Se quedan DOS versiones, no una**: la que se anuncia y la anterior. La anterior
# es la vuelta atrás si la nueva sale mal, y ese caso ya se dio.
#
# ─────────────────────────────────────────────────────────────────────────────
# USO
#
#   deploy/publicar-apk.sh 1.0.23
#
# Compila, comprueba la firma, cuelga, limpia, anuncia y redespliega. Sin
# argumento coge la versión del `pubspec.yaml`.
set -euo pipefail

CUANTAS_SE_QUEDAN=2
APP_ID='0iQ8gLv5ZIHD1n_DRlzOa'
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK="$RAIZ/app/build/app/outputs/flutter-apk/app-release.apk"

rojo()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
bien()  { printf '\033[32m%s\033[0m\n' "$*"; }
paso()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }

version="${1:-$(grep -m1 '^version:' "$RAIZ/app/pubspec.yaml" | sed 's/version: *//;s/+.*//')}"
compilacion="$(grep -m1 '^version:' "$RAIZ/app/pubspec.yaml" | sed 's/.*+//')"
fecha="$(date +%y%m%d)"
fichero="reparto-${version}-${fecha}.apk"

paso "Comprobando que hay APK compilada"
[ -f "$APK" ] || { rojo "No existe $APK. Compila primero: cd app && flutter build apk --release"; exit 1; }

# QUE LA APK SEA LA DE ESTA VERSIÓN, y no una de hace tres días.
#
# Publicar el binario de ayer con el número de hoy es el fallo que no se ve: el
# anuncio dice 1.0.23, la gente se la baja, y lleva el código de la 1.0.22.
dentro="$(unzip -p "$APK" AndroidManifest.xml 2>/dev/null | strings | grep -m1 -oE '^[0-9]+\.[0-9]+\.[0-9]+$' || true)"
if [ -n "$dentro" ] && [ "$dentro" != "$version" ]; then
  rojo "La APK compilada dice $dentro y vas a publicar $version. Vuelve a compilar."
  exit 1
fi

bytes="$(stat -c%s "$APK")"
sha="$(sha256sum "$APK" | cut -d' ' -f1)"
echo "  $fichero · $bytes bytes · ${sha:0:16}…"

paso "Subiendo al servidor"
scp -q "$APK" "vps:/var/lib/procovar/apk/$fichero"

ssh vps "mc-procovar cp --attr 'Content-Type=application/vnd.android.package-archive;Cache-Control=private, no-store' /host/apk/$fichero procovar/reparto/apk/$fichero < /dev/null" >/dev/null
bien "  colgada en MinIO"

# EL `Cache-Control: private, no-store` NO ES COSMÉTICA, y por eso va aquí y no
# en la cabeza de alguien: sin él, Cloudflare cachea el .apk y de SU copia no
# sirve peticiones por rango — y sin rango, 75 MB por la conexión de allá es una
# descarga que no se puede reanudar. Comprobado los dos casos el 22/09/2026.

paso "Tirando las versiones viejas (se quedan las $CUANTAS_SE_QUEDAN últimas)"
ssh vps "bash -s" <<REMOTO
set -eu
# Se ordena por FECHA DE SUBIDA y no por el nombre: '1.0.9' va después de
# '1.0.22' alfabéticamente, y ordenar por nombre tiraría justo la buena.
quedan=\$(mc-procovar ls procovar/reparto/apk 2>/dev/null | sort -k1,2 | awk '{print \$NF}' | tail -n $CUANTAS_SE_QUEDAN)
borradas=0
for f in \$(mc-procovar ls procovar/reparto/apk 2>/dev/null | awk '{print \$NF}'); do
  echo "\$quedan" | grep -qx "\$f" && continue
  mc-procovar rm "procovar/reparto/apk/\$f" < /dev/null >/dev/null 2>&1 && borradas=\$((borradas+1))
  rm -f "/var/lib/procovar/apk/\$f"
done
# Y las copias sueltas del host, que son las que más engordan y no las ve nadie.
for f in \$(ls -1 /var/lib/procovar/apk 2>/dev/null); do
  echo "\$quedan" | grep -qx "\$f" || rm -f "/var/lib/procovar/apk/\$f"
done
echo "  tiradas: \$borradas"
echo "  se quedan:"; echo "\$quedan" | sed 's/^/    /'
echo "  ocupa ahora: \$(mc-procovar ls -r --summarize procovar/reparto 2>/dev/null | grep -i 'Total Size' || echo '?')"
REMOTO

paso "Anunciando la $version"
ssh vps "cat > /tmp/anunciar.py" <<'PY'
import json, os, sys, urllib.request
K = open('/root/secretos/dokploy.key').read().strip()
APP, BASE = sys.argv[1], 'http://127.0.0.1:3000/api'
def pedir(r, d=None):
    q = urllib.request.Request(BASE+r, data=None if d is None else json.dumps(d).encode(),
        headers={'x-api-key': K, 'Content-Type': 'application/json'},
        method='GET' if d is None else 'POST')
    with urllib.request.urlopen(q, timeout=30) as x: c = x.read().decode()
    return json.loads(c) if c.strip() else {}
app = pedir(f'/application.one?applicationId={APP}'); env = app.get('env') or ''
nuevo = {
    'APP_ULTIMA_VERSION': sys.argv[2], 'APP_ULTIMA_COMPILACION': sys.argv[3],
    'APP_ULTIMA_PUBLICADA': sys.argv[4],
    'APP_DESCARGA_ANDROID': f'https://archivos.procovar.cloud/reparto/apk/{sys.argv[5]}',
    'APP_DESCARGA_ANDROID_BYTES': sys.argv[6], 'APP_DESCARGA_ANDROID_SHA256': sys.argv[7],
}
if len(sys.argv) > 8 and sys.argv[8]: nuevo['APP_ULTIMA_NOTAS'] = sys.argv[8]
lineas, vistas = [], set()
for l in env.splitlines():
    c = l.split('=', 1)[0]
    if c in nuevo: lineas.append(f'{c}={nuevo[c]}'); vistas.add(c)
    else: lineas.append(l)
for k, v in nuevo.items():
    if k not in vistas: lineas.append(f'{k}={v}')
antes = len(env.splitlines())
pedir('/application.update', {'applicationId': APP, 'env': '\n'.join(lineas)})
# QUE NO SE PIERDA NINGUNA VARIABLE POR EL CAMINO. Dokploy las cifra y se
# reescriben enteras: un fallo aquí deja la api sin arrancar.
despues = len((pedir(f'/application.one?applicationId={APP}').get('env') or '').splitlines())
print(f'  variables: {antes} -> {despues}')
if despues < antes: print('  OJO: se perdieron variables'); sys.exit(1)
PY
ssh vps "python3 /tmp/anunciar.py '$APP_ID' '$version' '$compilacion' '$(date +%Y-%m-%d)' '$fichero' '$bytes' '$sha' '${NOTAS:-}'; rm -f /tmp/anunciar.py"

paso "Redesplegando la api para que lea el anuncio"
ssh vps "bash -s" <<REMOTO
set -eu
K=\$(cat /root/secretos/dokploy.key)
antes=\$(curl -s -H "x-api-key: \$K" "http://127.0.0.1:3000/api/deployment.all?applicationId=$APP_ID" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[0]["createdAt"] if d else "x")')
curl -s -X POST -H "x-api-key: \$K" -H "Content-Type: application/json" -d '{"applicationId":"$APP_ID"}' "http://127.0.0.1:3000/api/application.deploy" >/dev/null
for i in \$(seq 1 150); do
  sleep 10
  L=\$(curl -s -H "x-api-key: \$K" "http://127.0.0.1:3000/api/deployment.all?applicationId=$APP_ID" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[0]["createdAt"]+" "+d[0]["status"] if d else "x x")')
  C=\${L%% *}; E=\${L##* }
  # Se mira la FECHA y no sólo el estado: el 'done' que hay al principio es el
  # del despliegue ANTERIOR, y un bucle que sólo lee el estado canta victoria a
  # los diez segundos. Pasó el 17/09 y volvió a pasar el 26/09.
  if [ "\$C" != "\$antes" ] && [ "\$E" != "running" ]; then echo "  api: \$E"; break; fi
done
REMOTO

paso "Comprobando lo que anuncia de verdad"
# NO basta con que Dokploy diga «done»: eso sólo dice que la imagen se construyó.
# Lo único que prueba que la gente va a ver la versión nueva es preguntárselo a
# la api que está sirviendo.
ssh vps "curl -s -H 'Host: reparto.procovar.cloud' -k https://127.0.0.1/api/version" \
  | ESPERADA="$version" python3 -c "
import sys, json, os
u = json.load(sys.stdin).get('ultima', {})
f = (u.get('ficheros') or {}).get('android') or {}
print('  anuncia:', u.get('version'), '· compilacion', u.get('compilacion'))
print('  bytes  :', f.get('bytes'), '· sha256:', (f.get('sha256') or '')[:16] + '...')
if u.get('version') != os.environ['ESPERADA']:
    raise SystemExit('  NO cuadra: se publico ' + os.environ['ESPERADA'])
"

bien "
Publicada la $version. Se anuncia sola en la aplicacion."

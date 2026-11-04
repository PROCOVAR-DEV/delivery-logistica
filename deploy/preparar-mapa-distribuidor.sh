#!/usr/bin/env bash
# Deja el mapa de Cuba (nivel «detallado», el que ya usa la app) listo para meterlo
# DENTRO del APK de «Reparto Distribuidor»:
#
#   app/herramientas/distribuidor-assets/cuba-detallado.pmtiles   (97 MiB, NO se commitea)
#   app/herramientas/distribuidor-assets/cuba-detallado.json      {nivel, version, bytes, sha256}
#
# Uso:   deploy/preparar-mapa-distribuidor.sh <sha256-que-anuncia-/api/mapa> [version]
#        (la version por defecto es 260922, la de cuba-detallado-260922.pmtiles)
#
# DESDE ESTE PC NO SE LLAMA A NINGUN DOMINIO DE PROCOVAR (antiabuso de Hostinger): el
# fichero se trae por SSH desde el VPS (una sola orden remota por paso, por la conexion
# compartida de `vps-vpn`) y se comprueba contra el sha256 que anuncia `GET /api/mapa`
# (se lo pasa quien lo ha mirado dentro del servidor). Si no coincide, aborta y no deja nada.
set -euo pipefail

ESPERADO="${1:?falta el sha256 que anuncia /api/mapa para el nivel detallado}"
VERSION="${2:-260922}"
NIVEL=detallado
DESTINO="$(cd "$(dirname "$0")/.." && pwd)/app/herramientas/distribuidor-assets"
REMOTO_OBJETO="procovar/reparto/mapa/cuba-${NIVEL}-${VERSION}.pmtiles"
REMOTO_TMP=/var/lib/procovar/apk/_mapa.pmtiles

mkdir -p "$DESTINO"
TMP="$DESTINO/.descarga.pmtiles"
trap 'rm -f "$TMP"' EXIT

echo "1/4 sacando el mapa del almacen de objetos (en el VPS)..."
ssh vps-vpn "mc-procovar cp ${REMOTO_OBJETO} /host/apk/_mapa.pmtiles"

echo "2/4 trayendolo (scp) y limpiando el temporal del VPS..."
scp vps-vpn:"${REMOTO_TMP}" "$TMP"
ssh vps-vpn "rm -f ${REMOTO_TMP}"

echo "3/4 comprobando el sha256..."
REAL="$(sha256sum "$TMP" | cut -d' ' -f1)"
if [ "$REAL" != "$ESPERADO" ]; then
  echo "ERROR: el sha256 no coincide (esperado $ESPERADO, real $REAL). No se deja nada." >&2
  exit 1
fi
BYTES="$(stat -c %s "$TMP")"

echo "4/4 dejandolo en $DESTINO"
mv "$TMP" "$DESTINO/cuba-${NIVEL}.pmtiles"
printf '{"nivel":"%s","version":"%s","bytes":%s,"sha256":"%s"}\n' \
  "$NIVEL" "$VERSION" "$BYTES" "$REAL" > "$DESTINO/cuba-${NIVEL}.json"
trap - EXIT
echo "Listo: $BYTES bytes. Ahora:"
echo "  cd app && ORG_GRADLE_PROJECT_distribuidor=true flutter build apk --release -t lib/main_distribuidor.dart"

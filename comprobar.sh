#!/usr/bin/env bash
# Las comprobaciones de siempre, antes de subir nada.
#
# # Por que un script y no GitHub Actions
#
# Esto vivia en `.github/workflows/go.yml` y se quito el 15/09/2026 por dos razones:
#
#   1. El token de GitHub de Jose no tiene permiso `workflow`, asi que el push se
#      rechazaba entero por ese fichero — y arreglarlo era darle a un token mas permisos
#      de los que necesita para todo lo demas.
#   2. En Procovar despliega Dokploy, que clona y construye el. Un workflow que
#      construyera lo mismo seria duplicar lo que ya hay.
#
# Lo que si valia de aquel fichero era `sqlc diff`, y por algo concreto: cazo que el
# codigo generado llevaba SIETE COLUMNAS de retraso respecto a la migracion, o sea que la
# API no estaba leyendo los campos nuevos. Compilaba igual porque el cambio era aditivo, y
# por eso nadie lo habia visto. Eso se queda.
#
# Uso:   ./comprobar.sh
set -euo pipefail
export PATH="$PATH:$HOME/go/bin:/opt/flutter/bin"

fallos=0
paso() { printf "  %-34s " "$1"; }
bien() { echo "ok"; }
mal()  { echo "FALLA"; fallos=$((fallos+1)); }

raiz="$PWD"

# `herramientas/mapa-cuba` es su OTRO modulo Go, con sus 47 pruebas, y hasta el
# 24/09/2026 no lo construia ningun Dockerfile ni lo recorria este bucle: «Todo
# en verde» no decia absolutamente nada de el. De ahi sale `niveles.go`, que
# `deploy/Dockerfile.app` copia para generar los colores del suelo de la app.
# No lleva sqlc: no habla con Postgres.
for m in api sync herramientas/mapa-cuba; do
  echo "== $m =="
  cd "$raiz/$m"
  paso "gofmt";     [ -z "$(gofmt -l . 2>/dev/null)" ] && bien || mal
  paso "go vet";    go vet ./... >/dev/null 2>&1 && bien || mal
  paso "go test";   go test ./... >/dev/null 2>&1 && bien || mal
  paso "go build";  go build ./... >/dev/null 2>&1 && bien || mal
  # El que caza que el codigo generado se quedo atras respecto al esquema.
  if [ -f sqlc.yaml ]; then
    paso "sqlc diff"; sqlc diff >/dev/null 2>&1 && bien || mal
  fi
  cd "$raiz"
done

# LAS CONSULTAS NUEVAS CONTRA UN POSTGRES DE VERDAD. Las pruebas de `internal/api` usan
# dobles que reimplementan el SQL, y `go test` salta `consultas_motor_real_test.go` EN
# SILENCIO si no hay base: la auditoria del 08/10/2026 mutó 14 guardas del SQL y sólo esa
# prueba las cazó, así que sin ella una regresion pasaria en verde. Aqui se dice a gritos.
# La base ha de ser AISLADA y llamarse `verif…`/`…test…`/`…prueba…` (la prueba se niega si no),
# migrada con goose hasta la ultima: ver CLAUDE.md §5.
echo "== api: consultas contra Postgres real =="
if [ -n "${REPARTO_MOTOR_REAL_DSN:-}" ]; then
  paso "motor real"
  (cd "$raiz/api" && go test -count=1 -run MotorReal ./internal/store/sqlc/ >/dev/null 2>&1) && bien || mal
else
  paso "motor real"; echo "SALTADO (exporta REPARTO_MOTOR_REAL_DSN: CLAUDE.md §5)"
fi

echo "== app (Flutter) =="
cd "$raiz/app"
paso "analyze"; flutter analyze >/dev/null 2>&1 && bien || mal
# Con tope: una prueba colgada se come la sesion entera en vez de fallar. Ya paso.
paso "test";    timeout 300 flutter test >/dev/null 2>&1 && bien || mal
cd "$raiz"

echo
[ "$fallos" -eq 0 ] && echo "Todo en verde." || { echo "$fallos comprobaciones fallan."; exit 1; }

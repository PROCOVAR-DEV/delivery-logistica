package api

import (
	"net/http"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
)

// EL LOGÍSTICO GESTIONA LOS TIPOS DE VEHÍCULO — Jose, 14/10/2026.
//
// Amado entrenaba al logístico de Santiago y no podían crear un tipo. La causa de fondo era otra
// (la app mandaba los tipos a `PUT /api/settings`, que los tira), pero al arreglarla salió esto: las
// tres rutas de escritura de `/api/vehicle-types` pedían ADMIN y un LOGISTICO recibiría un 403.
// Jose: «la APK es completa para el logístico». Antes de la tabla, los tipos viajaban en un
// ajuste que no pedía admin.
//
// EN PAREJA: el LOGISTICO SÍ puede, y quien no entra a Reparto NO puede (403 y no se escribe).
func TestUnLogisticoGestionaLosTiposDeVehiculo(t *testing.T) {
	h := montarAvisos(t, &dobleAvisos{})
	logistico := tokenDeDatos(t, map[string]any{"sub": "p-stg", "email": "stg@procovar.cu",
		"role": "LOGISTICO", "branchId": avSucStg.String(), "entradas": []string{"delivery.entrar"}})

	w := pedirAv(t, h, http.MethodPost, "/api/vehicle-types", logistico, `{"nombre":"rastra"}`)
	avCodigo(t, w, http.StatusCreated)

	w = pedirAv(t, h, http.MethodPatch, "/api/vehicle-types/"+avTipoCam.String(), logistico,
		`{"costoKmUsd":0.9}`)
	avCodigo(t, w, http.StatusOK)

	w = pedirAv(t, h, http.MethodDelete, "/api/vehicle-types/"+avTipoCam.String(), logistico, "")
	avCodigo(t, w, http.StatusOK)
}

func TestQuienNoEntraAReparteNoTocaLosTipos(t *testing.T) {
	h := montarAvisos(t, &dobleAvisos{})
	gestor := tokenDeDatos(t, map[string]any{"sub": "p-gestor", "email": "g@procovar.cu",
		"role": "GESTOR", "branchId": avSucStg.String(), "entradas": []string{}})

	for _, c := range []struct{ metodo, ruta, cuerpo string }{
		{http.MethodPost, "/api/vehicle-types", `{"nombre":"rastra"}`},
		{http.MethodPatch, "/api/vehicle-types/" + avTipoCam.String(), `{"costoKmUsd":0.9}`},
		{http.MethodDelete, "/api/vehicle-types/" + avTipoCam.String(), ""},
	} {
		w := pedirAv(t, h, c.metodo, c.ruta, gestor, c.cuerpo)
		avCodigo(t, w, http.StatusForbidden)
	}
}

// RENOMBRAR a un nombre que ya existe es 409 con su motivo, no un 500: la app toma un 5xx por
// fallo de red, reintenta quince segundos y dice «no se guardó nada». Auditoría del 14/10/2026.
// Ahora que el cajón de tipos renombra de verdad (antes nadie hacía PATCH del nombre), pasa
// al intercambiar dos nombres o al renombrar al de un tipo RETIRADO, que el cajón ni enseña.
func TestRenombrarAUnNombreRepetidoEs409(t *testing.T) {
	d := &dobleAvisos{falloAlActualizarTipo: &pgconn.PgError{Code: "23505"}}
	h := montarAvisos(t, d)
	w := pedirAv(t, h, http.MethodPatch, "/api/vehicle-types/"+avTipoCam.String(), avAdmin(t),
		`{"nombre":"van"}`)
	avCodigo(t, w, http.StatusConflict)
	if !strings.Contains(w.Body.String(), "Ya existe un tipo de vehículo con ese nombre") {
		t.Fatalf("el 409 no dice por qué: %s", w.Body.String())
	}
}

func TestRenombrarAUnNombreVacioEs400(t *testing.T) {
	h := montarAvisos(t, &dobleAvisos{})
	for _, cuerpo := range []string{`{"nombre":""}`, `{"nombre":"   "}`} {
		w := pedirAv(t, h, http.MethodPatch, "/api/vehicle-types/"+avTipoCam.String(), avAdmin(t), cuerpo)
		avCodigo(t, w, http.StatusBadRequest)
	}
}

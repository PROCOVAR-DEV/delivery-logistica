package api

// EL PUNTO DE SALIDA DE CADA ZONA (00020, Jose 15/10/2026): de qué almacén sale la ruta de una
// zona, y el «no» cuando el que tiene puesto ya no sirve.
//
// La regla se escribe dos veces —aquí y en el aparato, que arma la ruta sin señal— y
// `docs/punto-de-salida.casos.json` las ata: lo leen esta prueba y su gemela de la app. Es EL
// MISMO fichero, no una copia (`CLAUDE.md` §3-bis).

import (
	"encoding/json"
	"math"
	"net/http"
	"os"
	"testing"

	"procovar/reparto-api/internal/cotizar"
)

const rutaDeLosCasosDelPuntoDeSalida = "../../../docs/punto-de-salida.casos.json"

type casosDelPuntoDeSalida struct {
	Sucursal  string    `json:"sucursal"`
	Zona      string    `json:"zona"`
	Almacenes []Almacen `json:"almacenes"`
	Casos     []struct {
		Nombre         string  `json:"nombre"`
		AlmacenID      *string `json:"almacenId"`
		SaleDe         string  `json:"saleDe"`
		Rechazo        string  `json:"rechazo"`
		RechazoAlArmar string  `json:"rechazoAlArmar"`
	} `json:"casos"`
}

func leerCasosDelPuntoDeSalida(t *testing.T) casosDelPuntoDeSalida {
	t.Helper()
	b, err := os.ReadFile(rutaDeLosCasosDelPuntoDeSalida)
	if err != nil {
		t.Fatalf("no se pudo leer %s: %v\nEs lo que ata la regla del servidor con la del "+
			"aparato; sin él esta prueba no comprueba nada.", rutaDeLosCasosDelPuntoDeSalida, err)
	}
	var f casosDelPuntoDeSalida
	if err := json.Unmarshal(b, &f); err != nil {
		t.Fatalf("%s no se puede interpretar: %v", rutaDeLosCasosDelPuntoDeSalida, err)
	}
	if len(f.Casos) == 0 || len(f.Almacenes) == 0 {
		t.Fatalf("%s sin casos o sin almacenes: una prueba sobre nada sale verde",
			rutaDeLosCasosDelPuntoDeSalida)
	}
	return f
}

func TestElPuntoDeSalidaEsElDelAparato(t *testing.T) {
	f := leerCasosDelPuntoDeSalida(t)
	elegido := cotizar.ElegirAlmacen(almacenesConPunto(f.Almacenes))
	if elegido == nil {
		t.Fatal("los casos no tienen ningún almacén que sirva: el principal no se puede probar")
	}
	principal := AlmacenSalida{Nombre: elegido.Nombre, Lat: *elegido.Latitud, Lng: *elegido.Longitud}
	porID := map[string]Almacen{}
	for _, a := range f.Almacenes {
		porID[*a.ID] = a
	}

	for _, c := range f.Casos {
		t.Run(c.Nombre, func(t *testing.T) {
			origen, motivo := origenDeLaZona(principal, f.Almacenes, c.AlmacenID, f.Zona, f.Sucursal)
			if c.SaleDe != "" {
				if motivo != "" {
					t.Fatalf("la zona tenía que salir de %s y se rechazó: %s", c.SaleDe, motivo)
				}
				esperado := porID[c.SaleDe]
				if origen.Nombre != esperado.Nombre || origen.Lat != *esperado.Latitud {
					t.Fatalf("la zona sale de %q (%v) y tenía que salir de %q (%v)",
						origen.Nombre, origen.Lat, esperado.Nombre, *esperado.Latitud)
				}
				return
			}
			if motivo != c.RechazoAlArmar {
				t.Fatalf("al armar, el «no» dice\n  %q\ny el aparato dice\n  %q", motivo, c.RechazoAlArmar)
			}
			if _, alGuardar := puntoDeSalida(f.Almacenes, *c.AlmacenID, f.Sucursal); alGuardar != c.Rechazo {
				t.Fatalf("al guardarlo, el «no» dice\n  %q\ny el aparato dice\n  %q", alGuardar, c.Rechazo)
			}
		})
	}
}

// ---------------------------------------------------------------------------
// Por las puertas, con los almacenes de los casos en el Accesos de mentira
// ---------------------------------------------------------------------------

// conLosAlmacenesDeLosCasos pone en Santiago los almacenes de los casos y en Holguín uno con el
// id `alm-holguin`, que es el que el caso «de-otra-sucursal» intenta colar en Santiago.
func conLosAlmacenesDeLosCasos(t *testing.T) casosDelPuntoDeSalida {
	t.Helper()
	f := leerCasosDelPuntoDeSalida(t)
	hol := "alm-holguin"
	conAccesos(t, &accesosFalso{sucursales: []SucursalConAlmacenes{
		{Codigo: "STG", Nombre: "Santiago", Almacenes: f.Almacenes},
		{Codigo: "HOL", Nombre: "Holguín", Almacenes: []Almacen{
			{ID: &hol, Nombre: "Nave de Holguín", Principal: true, Activo: true,
				Latitud: flotante(20.8872), Longitud: flotante(-76.2631)},
		}},
	}})
	return f
}

// EN PAREJA: el almacén de OTRA sucursal se rechaza y no se guarda; el de la suya se guarda y
// sale con su nombre en `GET /api/board`; `null` lo quita.
func TestElPuntoDeSalidaDeUnaZonaSoloEsDeSuSucursal(t *testing.T) {
	conLosAlmacenesDeLosCasos(t)
	q := nuevoTablero()
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())
	ruta := "/api/board/columns/" + colCentro.String()

	w := pedirTab(t, h, http.MethodPatch, ruta, jwt, `{"almacenId":"alm-holguin"}`)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("un almacén de Holguín en una zona de Santiago: código %d, tenía que ser 400 — %s",
			w.Code, w.Body.String())
	}
	if msg := leerTab(t, w)["error"]; msg != "No existe el almacén 'alm-holguin' en Santiago" {
		t.Fatalf("el «no» dice %q", msg)
	}
	if q.columnas[colCentro].AlmacenID != nil {
		t.Fatalf("se rechazó y se guardó igual: %q", *q.columnas[colCentro].AlmacenID)
	}

	// Un almacén de baja o sin ubicación, tampoco: no se puede salir de él.
	for _, id := range []string{"alm-baja", "alm-sin-punto", "alm-cero"} {
		if w := pedirTab(t, h, http.MethodPatch, ruta, jwt, `{"almacenId":"`+id+`"}`); w.Code != http.StatusBadRequest {
			t.Fatalf("%s no sirve de punto de salida y contestó %d", id, w.Code)
		}
	}

	// LA OTRA MITAD: el de su sucursal sí, y se ve con su nombre.
	w = pedirTab(t, h, http.MethodPatch, ruta, jwt, `{"almacenId":"alm-aurora"}`)
	if w.Code != http.StatusOK {
		t.Fatalf("AURORA es de Santiago y contestó %d — %s", w.Code, w.Body.String())
	}
	if got := q.columnas[colCentro].AlmacenID; got == nil || *got != "alm-aurora" {
		t.Fatalf("no se guardó el punto de salida: %v", got)
	}
	w = pedirTab(t, h, http.MethodGet, "/api/board", jwt, "")
	var centro map[string]any
	for _, c := range leerTab(t, w)["columnas"].([]any) {
		if m := c.(map[string]any); m["id"] == colCentro.String() {
			centro = m
		}
	}
	punto, _ := centro["almacen"].(map[string]any)
	if centro["almacenId"] != "alm-aurora" || punto["nombre"] != "AURORA" || punto["id"] != "alm-aurora" {
		t.Fatalf("GET /api/board no enseña el punto de la zona: almacenId=%v almacen=%v",
			centro["almacenId"], centro["almacen"])
	}

	// Renombrar NO lo toca (campo ausente) …
	pedirTab(t, h, http.MethodPatch, ruta, jwt, `{"nombre":"Centro histórico"}`)
	if got := q.columnas[colCentro].AlmacenID; got == nil || *got != "alm-aurora" {
		t.Fatalf("renombrar se llevó el punto de salida: %v", got)
	}
	// … y `null` lo quita: vuelve a salir del principal.
	if w := pedirTab(t, h, http.MethodPatch, ruta, jwt, `{"almacenId":null}`); w.Code != http.StatusOK {
		t.Fatalf("quitar el punto: %d — %s", w.Code, w.Body.String())
	}
	if got := q.columnas[colCentro].AlmacenID; got != nil {
		t.Fatalf("`null` no quitó el punto de salida: %q", *got)
	}
}

// Una zona NUEVA nace con el punto que mande la pantalla (el elegido arriba), validado igual.
func TestUnaZonaNuevaNaceConSuPuntoDeSalida(t *testing.T) {
	conLosAlmacenesDeLosCasos(t)
	q := nuevoTablero()
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns?branchId="+sucStg.String(), jwt,
		`{"nombre":"Aguadores","almacenId":"alm-holguin"}`)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("una zona de Santiago nació saliendo de Holguín: %d — %s", w.Code, w.Body.String())
	}
	if len(q.creadas) != 0 {
		t.Fatalf("se rechazó y se creó igual: %v", q.creadas)
	}

	w = pedirTab(t, h, http.MethodPost, "/api/board/columns?branchId="+sucStg.String(), jwt,
		`{"nombre":"Aguadores","almacenId":"alm-aurora"}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("crear con AURORA: %d — %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	punto, _ := m["almacen"].(map[string]any)
	if m["almacenId"] != "alm-aurora" || punto["nombre"] != "AURORA" {
		t.Fatalf("la zona nueva no nació con su punto: %v / %v", m["almacenId"], m["almacen"])
	}
}

// EN PAREJA, lo que importa de verdad: la ruta armada desde una zona con punto SALE DE ÉL y no
// del de arriba (el principal); sin punto, del principal como antes.
func TestLaRutaDeLaZonaSaleDeSuPuntoYNoDelDeArriba(t *testing.T) {
	f := conLosAlmacenesDeLosCasos(t)
	var aurora, pv Almacen
	for _, a := range f.Almacenes {
		switch *a.ID {
		case "alm-aurora":
			aurora = a
		case "alm-pv":
			pv = a
		}
	}

	for _, c := range []struct {
		nombre   string
		punto    *string
		esperado Almacen
	}{
		{"con punto, de AURORA", &[]string{"alm-aurora"}[0], aurora},
		{"sin punto, del principal (lo de antes)", nil, pv},
	} {
		t.Run(c.nombre, func(t *testing.T) {
			q := nuevoTablero()
			q.tresPuestas()
			centro := q.columnas[colCentro]
			centro.AlmacenID = c.punto
			q.columnas[colCentro] = centro
			h := montarTab(t, q)
			jwt := tokenTab(t, sucStg.String())

			// Los km de las tarjetas puestas en la zona, desde el mismo punto.
			w := pedirTab(t, h, http.MethodGet, "/api/board", jwt, "")
			p := q.pedidos[ped1]
			quiero := kmHaversine(*c.esperado.Latitud, *c.esperado.Longitud, p.lat, p.lng)
			vista := false
			for _, tj := range leerTab(t, w)["colocados"].([]any) {
				m := tj.(map[string]any)
				if m["pedidoId"] != ped1.String() {
					continue
				}
				vista = true
				if math.Abs(m["kmAlAlmacen"].(float64)-quiero) > 1e-9 {
					t.Fatalf("la tarjeta de Ana mide %v km y desde %s son %v",
						m["kmAlAlmacen"], c.esperado.Nombre, quiero)
				}
			}
			if !vista {
				t.Fatal("GET /api/board no trajo la tarjeta de Ana: la comprobación de los km no miró nada")
			}

			w = pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route", jwt, `{}`)
			if w.Code != http.StatusCreated {
				t.Fatalf("armar: %d — %s", w.Code, w.Body.String())
			}
			r := q.rutaCreada
			if r == nil || r.OriginAddress == nil || *r.OriginAddress != c.esperado.Nombre ||
				*r.OriginLat != *c.esperado.Latitud || *r.OriginLng != *c.esperado.Longitud {
				t.Fatalf("la ruta salió de %v (%v, %v) y tenía que salir de %s",
					deref(r.OriginAddress), deref(r.OriginLat), deref(r.OriginLng), c.esperado.Nombre)
			}
			if o, _ := leerTab(t, w)["origen"].(map[string]any); o["nombre"] != c.esperado.Nombre {
				t.Fatalf("la respuesta dice que sale de %v", o)
			}
		})
	}
}

// Un punto que YA NO SIRVE (Accesos lo dio de baja después de ponerlo) no cae al principal en
// silencio: 409 con su motivo y sin ruta.
func TestUnPuntoQueYaNoSirveNoSeCambiaPorElPrincipal(t *testing.T) {
	conLosAlmacenesDeLosCasos(t)
	q := nuevoTablero()
	q.tresPuestas()
	centro := q.columnas[colCentro]
	baja := "alm-baja"
	centro.AlmacenID = &baja
	q.columnas[colCentro] = centro
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)
	if w.Code != http.StatusConflict {
		t.Fatalf("armar desde un almacén de baja: %d — %s", w.Code, w.Body.String())
	}
	quiero := "La zona «Centro» no puede salir de su punto de salida: «Almacén viejo» está dado de " +
		"baja en Accesos. Elige otro en «Punto de salida»."
	if msg := leerTab(t, w)["error"]; msg != quiero {
		t.Fatalf("el «no» dice %q", msg)
	}
	if q.rutaCreada != nil {
		t.Fatal("se rechazó y se creó la ruta igual")
	}
}

func deref[T any](p *T) any {
	if p == nil {
		return nil
	}
	return *p
}

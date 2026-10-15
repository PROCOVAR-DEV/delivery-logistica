package api

// «SIN COLOCAR» CON UN ALMACÉN ELEGIDO ARRIBA (Jose, 15/10/2026): los de ese almacén primero,
// del más cercano al más lejano, y después los demás por la fecha de la factura.
//
// La regla vive dos veces —aquí (`almacenDeLaCabecera` + `ListarPedidosSinColocar`) y en el
// aparato, que ordena sin señal— y `docs/orden-sin-colocar.casos.json` las ata. Esta prueba
// lee ese fichero para dos cosas:
//
//  1. DE QUÉ ALMACÉN VAN PRIMERO: `almacenDeLaCabecera` con el `?almacenId=` de cada caso deja
//     `primero` en el código del caso (o nil) y mide desde el elegido. El SQL con esos
//     parámetros lo ataca contra Postgres `TestMotorReal_SinColocarConAlmacenElegido`.
//  2. EL CABLEADO HTTP: `GET /api/board/unplaced?almacenId=…` paginado de 1 en 1, de 2 en 2…
//     por el `siguiente` de cada respuesta —con su `+Inf` de «los demás» ida y vuelta por la
//     URL— sale entero y en el orden del caso. El doble repite el `ORDER BY`, así que esto
//     no prueba el SQL: prueba que el parámetro llega a la consulta y que el cursor vuelve.

import (
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"slices"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
)

func tableroTexto(s string) *string { return &s }

func pgtypeSinFecha() pgtype.Timestamptz { return pgtype.Timestamptz{} }

const rutaDeLosCasosDelOrdenSinColocar = "../../../docs/orden-sin-colocar.casos.json"

type casosDelOrdenSinColocar struct {
	Almacenes []Almacen `json:"almacenes"`
	Pedidos   []struct {
		Nombre        string     `json:"nombre"`
		ID            string     `json:"id"`
		AlmacenCodigo *string    `json:"almacenCodigo"`
		Latitud       float64    `json:"latitud"`
		Longitud      float64    `json:"longitud"`
		FacturaAt     *time.Time `json:"facturaAt"`
		OrderDate     *time.Time `json:"orderDate"`
	} `json:"pedidos"`
	Casos []struct {
		Nombre       string   `json:"nombre"`
		Elegido      *string  `json:"elegido"`
		PrimeroLosDe *string  `json:"primeroLosDe"`
		Esperado     []string `json:"esperado"`
	} `json:"casos"`
}

func leerCasosDelOrdenSinColocar(t *testing.T) casosDelOrdenSinColocar {
	t.Helper()
	b, err := os.ReadFile(rutaDeLosCasosDelOrdenSinColocar)
	if err != nil {
		t.Fatalf("no se pudo leer %s: %v\nEs lo que ata el orden del servidor con el del "+
			"aparato; sin él esta prueba no comprueba nada.", rutaDeLosCasosDelOrdenSinColocar, err)
	}
	var f casosDelOrdenSinColocar
	if err := json.Unmarshal(b, &f); err != nil {
		t.Fatalf("%s no se puede interpretar: %v", rutaDeLosCasosDelOrdenSinColocar, err)
	}
	if len(f.Casos) == 0 || len(f.Pedidos) == 0 || len(f.Almacenes) == 0 {
		t.Fatalf("%s sin casos, pedidos o almacenes: una prueba sobre nada sale verde",
			rutaDeLosCasosDelOrdenSinColocar)
	}
	return f
}

// conLosCasos: Santiago con los almacenes del fichero y SÓLO sus pedidos sin colocar.
func conLosCasos(t *testing.T, f casosDelOrdenSinColocar) (http.Handler, map[string]string) {
	t.Helper()
	conAccesos(t, &accesosFalso{sucursales: []SucursalConAlmacenes{
		{Codigo: "STG", Nombre: "Santiago", Almacenes: f.Almacenes},
	}})
	q := nuevoTablero()
	for id, p := range q.pedidos {
		if p.sucursal == sucStg {
			delete(q.pedidos, id)
		}
	}
	nombreDe := map[string]string{}
	for _, p := range f.Pedidos {
		id := uuid.MustParse(p.ID)
		codigo := ""
		if p.AlmacenCodigo != nil {
			codigo = *p.AlmacenCodigo
		}
		q.pedidos[id] = pedidoFalso{id: id, sucursal: sucStg, nombre: p.Nombre, peso: 1,
			lat: p.Latitud, lng: p.Longitud, almacen: codigo, facturaAt: p.FacturaAt, fecha: p.OrderDate}
		nombreDe[id.String()] = p.Nombre
	}
	return montarTab(t, q), nombreDe
}

func TestDeQueAlmacenVanPrimeroEsElDelAparato(t *testing.T) {
	f := leerCasosDelOrdenSinColocar(t)
	porDefecto := AlmacenSalida{}
	for _, a := range f.Almacenes {
		if a.Principal {
			porDefecto = AlmacenSalida{Nombre: a.Nombre, Lat: *a.Latitud, Lng: *a.Longitud}
		}
	}
	for _, c := range f.Casos {
		t.Run(c.Nombre, func(t *testing.T) {
			ruta := "/api/board/unplaced"
			esperado := porDefecto
			if c.Elegido != nil {
				ruta += "?almacenId=" + url.QueryEscape(*c.Elegido)
				for _, a := range f.Almacenes {
					if *a.ID == *c.Elegido {
						esperado = AlmacenSalida{Nombre: a.Nombre, Lat: *a.Latitud, Lng: *a.Longitud}
					}
				}
			}
			tc := tableroCtx{nombre: "Santiago", almacen: porDefecto, almacenes: f.Almacenes}
			w := httptest.NewRecorder()
			if !almacenDeLaCabecera(w, httptest.NewRequest(http.MethodGet, ruta, nil), &tc) {
				t.Fatalf("el almacén %v se rechazó: %s", *c.Elegido, w.Body.String())
			}
			if tc.almacen != esperado {
				t.Errorf("se mide desde %+v y tendría que ser desde %+v", tc.almacen, esperado)
			}
			if (tc.primero == nil) != (c.PrimeroLosDe == nil) ||
				(tc.primero != nil && *tc.primero != *c.PrimeroLosDe) {
				t.Errorf("primero van los de %v y tendrían que ser los de %v", deRef(tc.primero), deRef(c.PrimeroLosDe))
			}
		})
	}
}

// UN CÓDIGO EN BLANCO NO ES UN CÓDIGO. En SQL, un código de espacios queda en la cadena vacía y casaría con
// todo pedido que llegara con el código vacío: con un almacén así, «sus» pedidos serían los
// que no traen almacén. El aparato lo descarta en `_codigoDeAlmacen`; aquí, `almacenDeLaCabecera`.
func TestUnAlmacenConElCodigoEnBlancoNoTienePedidosSuyos(t *testing.T) {
	f := leerCasosDelOrdenSinColocar(t)
	var lista []Almacen
	for _, a := range f.Almacenes {
		if *a.ID == "alm-aurora" {
			a.Codigo = tableroTexto("  ")
		}
		lista = append(lista, a)
	}
	tc := tableroCtx{nombre: "Santiago", almacenes: lista}
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/api/board/unplaced?almacenId=alm-aurora", nil)
	if !almacenDeLaCabecera(w, r, &tc) {
		t.Fatalf("se rechazó: %s", w.Body.String())
	}
	if tc.primero != nil {
		t.Fatalf("con el código en blanco van primero los de %q: los que no traen almacén", *tc.primero)
	}
}

func deRef(s *string) string {
	if s == nil {
		return "(ninguno: el orden de siempre)"
	}
	return *s
}

func TestElTableroSinColocarConAlmacenPaginaEnteroYEnSuOrden(t *testing.T) {
	f := leerCasosDelOrdenSinColocar(t)
	h, nombreDe := conLosCasos(t, f)
	jwt := tokenTab(t, sucStg.String())
	for _, c := range f.Casos {
		t.Run(c.Nombre, func(t *testing.T) {
			for limite := 1; limite <= len(c.Esperado); limite++ {
				var salida []string
				desde := ""
				for vuelta := 0; ; vuelta++ {
					if vuelta > 20 {
						t.Fatalf("de %d en %d: el cursor no avanza, van %v", limite, limite, salida)
					}
					ruta := fmt.Sprintf("/api/board/unplaced?limite=%d", limite)
					if c.Elegido != nil {
						ruta += "&almacenId=" + url.QueryEscape(*c.Elegido)
					}
					if desde != "" {
						ruta += "&desde=" + url.QueryEscape(desde)
					}
					w := pedirTab(t, h, http.MethodGet, ruta, jwt, "")
					if w.Code != http.StatusOK {
						t.Fatalf("de %d en %d: %d — %s", limite, limite, w.Code, w.Body.String())
					}
					m := leerTab(t, w)
					if total, _ := m["total"].(float64); int(total) != len(c.Esperado) {
						t.Fatalf("el total dice %v y son %d: el orden no cambia cuántos son", total, len(c.Esperado))
					}
					for _, p := range m["pedidos"].([]any) {
						salida = append(salida, nombreDe[p.(map[string]any)["id"].(string)])
					}
					siguiente, _ := m["siguiente"].(string)
					if siguiente == "" {
						break
					}
					desde = siguiente
				}
				if !slices.Equal(salida, c.Esperado) {
					t.Fatalf("de %d en %d sale %v y tendría que salir %v", limite, limite, salida, c.Esperado)
				}
			}
		})
	}
}

// LOS DE OTRO ALMACÉN LLEVAN «+Inf» EN EL CURSOR, y tiene que volver tal cual. Es la mitad
// que un cursor con los km «normales» rompería: el infinito no es un número que se escriba
// solo, y si volviera como otra cosa la tanda siguiente empezaría en otro sitio.
func TestElCursorDeLosDemasLlevaElInfinitoYVuelve(t *testing.T) {
	id := uuid.MustParse("0e000000-0000-4000-8000-000000000004")
	c := cursorHacia(math.Inf(1), pgtypeSinFecha(), id)
	if c != "+Inf||"+id.String() {
		t.Fatalf("el cursor de un pedido de los demás sin fecha es %q", c)
	}
	vuelta, err := cursorDeLaTanda(c)
	if err != nil || vuelta.cercania == nil || !math.IsInf(*vuelta.cercania, 1) || vuelta.fecha.Valid {
		t.Fatalf("el cursor %q no vuelve igual: %+v, %v", c, vuelta, err)
	}
	// Y una distancia de verdad vuelve EXACTA: el corte compara por igualdad.
	km := 1.1119492664455874
	vuelta, err = cursorDeLaTanda(cursorHacia(km, pgtypeSinFecha(), id))
	if err != nil || *vuelta.cercania != km {
		t.Fatalf("%v vuelve como %v (%v): un decimal perdido salta el edificio entero", km, vuelta.cercania, err)
	}
}

// UN ALMACÉN QUE NO SIRVE ES UN 400 CON SU MOTIVO, no «se mide desde otro» callado. Y en
// pareja: sin `almacenId` y con uno bueno, 200.
func TestUnAlmacenElegidoQueNoSirveEs400(t *testing.T) {
	f := leerCasosDelOrdenSinColocar(t)
	f.Almacenes = append(f.Almacenes, Almacen{ID: tableroTexto("alm-sin-punto"), Nombre: "Sin punto", Activo: true})
	h, _ := conLosCasos(t, f)
	jwt := tokenTab(t, sucStg.String())
	for _, ruta := range []string{"/api/board/unplaced", "/api/board"} {
		for almacen, codigo := range map[string]int{
			"":                http.StatusOK,
			"alm-aurora":      http.StatusOK,
			"alm-sin-punto":   http.StatusBadRequest,
			"alm-de-holguin":  http.StatusBadRequest,
			"no-existe-nunca": http.StatusBadRequest,
		} {
			r := ruta
			if almacen != "" {
				r += "?almacenId=" + almacen
			}
			w := pedirTab(t, h, http.MethodGet, r, jwt, "")
			if w.Code != codigo {
				t.Errorf("%s: %d y se esperaba %d — %s", r, w.Code, codigo, w.Body.String())
			}
			if codigo == http.StatusBadRequest && leerTab(t, w)["error"] == "" {
				t.Errorf("%s: 400 sin decir por qué", r)
			}
		}
	}
}

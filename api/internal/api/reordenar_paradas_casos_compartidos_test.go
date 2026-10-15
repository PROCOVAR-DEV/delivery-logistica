package api

// REORDENAR LAS PARADAS: el servidor contra `docs/reordenar-paradas.casos.json`, el MISMO
// fichero que lee la app (`app/test/pantallas/rutas/reordenar_paradas_casos_compartidos_test.dart`).
// Si uno de los dos lados cambia el orden por cercanía, los km o un literal de rechazo y el
// otro no, se pone rojo aquí o allí.

import (
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"testing"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/store/sqlc"
)

type casosDeReordenar struct {
	Tolerancia float64 `json:"toleranciaKm"`
	SinOrigen  string  `json:"sinOrigen"`
	Origen     struct {
		Lat float64 `json:"lat"`
		Lng float64 `json:"lng"`
	} `json:"origen"`
	Paradas []struct {
		ID      uuid.UUID `json:"id"`
		Conduce *string   `json:"conduce"`
		Cliente string    `json:"cliente"`
		Lat     *float64  `json:"lat"`
		Lng     *float64  `json:"lng"`
	} `json:"paradas"`
	RadialKm    map[uuid.UUID]float64 `json:"radialKm"`
	PorCercania struct {
		Orden   []uuid.UUID `json:"orden"`
		TotalKm float64     `json:"totalKm"`
	} `json:"porCercania"`
	AMano []struct {
		Nombre  string      `json:"nombre"`
		Orden   []uuid.UUID `json:"orden"`
		TotalKm float64     `json:"totalKm"`
	} `json:"aMano"`
	Rechazos []struct {
		Nombre string      `json:"nombre"`
		Orden  []uuid.UUID `json:"orden"`
		Codigo int         `json:"codigo"`
		Motivo string      `json:"motivo"`
	} `json:"rechazos"`
}

func leerCasosDeReordenar(t *testing.T) casosDeReordenar {
	t.Helper()
	crudo, err := os.ReadFile(filepath.Clean("../../../docs/reordenar-paradas.casos.json"))
	if err != nil {
		t.Fatalf("no se pudo leer ../../../docs/reordenar-paradas.casos.json: %v", err)
	}
	var c casosDeReordenar
	if err := json.Unmarshal(crudo, &c); err != nil {
		t.Fatalf("el fichero de casos no es JSON válido: %v", err)
	}
	if len(c.Paradas) == 0 || len(c.Rechazos) == 0 || len(c.AMano) == 0 {
		t.Fatal("el fichero de casos viene vacío: así esta prueba no comprueba nada")
	}
	return c
}

// filasDeLosCasos: las paradas como las devuelve `ListarParadasDeRutas`, en su orden.
func filasDeLosCasos(c casosDeReordenar) []sqlc.ListarParadasDeRutasRow {
	filas := make([]sqlc.ListarParadasDeRutasRow, 0, len(c.Paradas))
	for _, p := range c.Paradas {
		filas = append(filas, sqlc.ListarParadasDeRutasRow{
			ID: p.ID, OperationNumber: p.Conduce, CustomerName: p.Cliente, EndLat: p.Lat, EndLng: p.Lng,
		})
	}
	return filas
}

// recorridoDe: las paradas con punto, en el orden dado (como hace el manejador).
func recorridoDe(conPunto []paradaGeo, orden []uuid.UUID) []paradaGeo {
	porID := map[uuid.UUID]paradaGeo{}
	for _, g := range conPunto {
		porID[g.id] = g
	}
	var salida []paradaGeo
	for _, id := range orden {
		if g, ok := porID[id]; ok {
			salida = append(salida, g)
		}
	}
	return salida
}

func TestReordenarPorCercaniaDaLoDelFicheroCompartido(t *testing.T) {
	c := leerCasosDeReordenar(t)
	conPunto, sinPunto := paradasConYSinPunto(filasDeLosCasos(c))
	orden := ordenPorCercania(c.Origen.Lat, c.Origen.Lng, conPunto, sinPunto)
	if len(orden) != len(c.PorCercania.Orden) {
		t.Fatalf("por cercanía salieron %d paradas y el fichero espera %d: %v", len(orden), len(c.PorCercania.Orden), orden)
	}
	for i := range orden {
		if orden[i] != c.PorCercania.Orden[i] {
			t.Fatalf("por cercanía el orden es %v y el fichero compartido espera %v (posición %d). "+
				"La app ordena con el fichero; si cambias uno, cambia el otro", orden, c.PorCercania.Orden, i+1)
		}
	}
	total, _ := kmDelRecorrido(c.Origen.Lat, c.Origen.Lng, recorridoDe(conPunto, orden))
	if math.Abs(total-c.PorCercania.TotalKm) > c.Tolerancia {
		t.Fatalf("por cercanía el circuito mide %.12f km y el fichero espera %.12f", total, c.PorCercania.TotalKm)
	}
}

func TestReordenarAManoMideLoDelFicheroCompartido(t *testing.T) {
	c := leerCasosDeReordenar(t)
	conPunto, _ := paradasConYSinPunto(filasDeLosCasos(c))
	for _, caso := range c.AMano {
		total, radial := kmDelRecorrido(c.Origen.Lat, c.Origen.Lng, recorridoDe(conPunto, caso.Orden))
		if math.Abs(total-caso.TotalKm) > c.Tolerancia {
			t.Errorf("%s: el circuito mide %.12f km y el fichero espera %.12f", caso.Nombre, total, caso.TotalKm)
		}
		if len(radial) != len(c.RadialKm) {
			t.Errorf("%s: %d paradas con km en recta y el fichero espera %d (la de sin mapa NO lleva km)",
				caso.Nombre, len(radial), len(c.RadialKm))
		}
		for id, esperado := range c.RadialKm {
			if math.Abs(radial[id]-esperado) > c.Tolerancia {
				t.Errorf("%s: la parada %s está a %.12f km en recta y el fichero dice %.12f", caso.Nombre, id, radial[id], esperado)
			}
		}
	}
}

func TestLosRechazosDelOrdenDicenLoDelFicheroCompartido(t *testing.T) {
	c := leerCasosDeReordenar(t)
	filas := filasDeLosCasos(c)
	if msgRutaSinOrigen != c.SinOrigen {
		t.Errorf("sin origen dice %q y el fichero %q", msgRutaSinOrigen, c.SinOrigen)
	}
	for _, caso := range c.Rechazos {
		codigo, motivo := motivoDelOrden(caso.Orden, filas)
		if codigo != caso.Codigo || motivo != caso.Motivo {
			t.Errorf("%s:\n  contesta %d %q\n  y el fichero dice %d %q", caso.Nombre, codigo, motivo, caso.Codigo, caso.Motivo)
		}
	}
}

// LA TAREA QUE DEJA LA TASA ESCRITA EN CADA SUCURSAL.
//
// Lo que estas pruebas cuidan no es que escriba: es QUÉ escribe y DÓNDE. La tasa de una
// sucursal aplicada a otra da un importe en CUP creíble y equivocado —«Granma enseñaba los
// 685 de La Habana como si fueran suyos»— y ése es el fallo que no revienta, no se ve en
// pantalla y aparece en la caja.
package api

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"
	"time"

	"procovar/reparto-api/internal/cotizar"
	"procovar/reparto-api/internal/store/sqlc"
)

// --------------------------------------------------------------------------- dobles

// lasOchoDePrueba: dos sucursales con tasa y una sin, que es la forma que tiene hoy
// producción (sólo HAB y STG tienen; las otras seis no).
type baseDeTasas struct {
	sqlc.Querier
	sucursales []sqlc.CodigosParaRefrescarLaTasaRow
	// guardado es lo que quedó escrito, POR CÓDIGO. Que sea un mapa por código es lo que
	// deja ver si una tasa acabó en la sucursal que no era.
	guardado map[string]sqlc.GuardarTasaDeSucursalParams
	fallarAl string // el código cuyo UPDATE revienta
	// sinFilasTocadas hace que el UPDATE no escriba NINGUNA fila, que es lo que pasa de
	// verdad casi siempre: `GuardarTasaDeSucursal` lleva un `IS DISTINCT FROM` en el WHERE
	// y la tasa se mueve a diario, no por hora. Es la forma de probar que no se avisa de
	// una tasa que no cambió.
	sinFilasTocadas bool
}

func (b *baseDeTasas) CodigosParaRefrescarLaTasa(context.Context) ([]sqlc.CodigosParaRefrescarLaTasaRow, error) {
	return b.sucursales, nil
}

func (b *baseDeTasas) GuardarTasaDeSucursal(_ context.Context, arg sqlc.GuardarTasaDeSucursalParams) (int64, error) {
	if arg.ExternalID == nil {
		return 0, errors.New("se intentó guardar una tasa sin código de sucursal")
	}
	if *arg.ExternalID == b.fallarAl {
		return 0, errors.New("la base dijo que no")
	}
	if b.guardado == nil {
		b.guardado = map[string]sqlc.GuardarTasaDeSucursalParams{}
	}
	b.guardado[*arg.ExternalID] = arg
	if b.sinFilasTocadas {
		return 0, nil
	}
	return 1, nil
}

func (b *baseDeTasas) Consultas() sqlc.Querier { return b }

// accesosDeTasasFalso contesta lo que se le diga, POR CÓDIGO.
type accesosDeTasasFalso struct {
	tasas    map[string]*cotizar.Tasa
	revienta map[string]bool
	// preguntado deja constancia de a quién se le preguntó, para poder comprobar que se
	// pregunta una vez por sucursal y no una por cada cosa.
	preguntado []string
}

func (a *accesosDeTasasFalso) TasaDeSucursal(_ context.Context, codigo string) (*cotizar.Tasa, error) {
	a.preguntado = append(a.preguntado, codigo)
	if a.revienta[codigo] {
		return nil, errors.New("Accesos no contestó")
	}
	return a.tasas[codigo], nil // nil = «esta sucursal no tiene», que es un 200 normal
}

func codDePrueba(s string) *string { return &s }

func mudoDeTasas() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

func lasOchoDePrueba() *baseDeTasas {
	return &baseDeTasas{sucursales: []sqlc.CodigosParaRefrescarLaTasaRow{
		{Name: "Granma", ExternalID: codDePrueba("GR")},
		{Name: "La Habana", ExternalID: codDePrueba("HAB")},
		{Name: "Santiago", ExternalID: codDePrueba("STG")},
	}}
}

func tasaDePrueba(cup float64, iso string, fresca bool) *cotizar.Tasa {
	f := "entrega"
	return &cotizar.Tasa{CupPorUsd: cup, Fuente: &f, TraidoAt: iso, Fresca: fresca}
}

// --------------------------------------------------------------------------- pruebas

// EL DATO DE PRODUCCIÓN DE HOY: sólo HAB y STG tienen tasa (700 CUP/USD, del 09/09). Las
// otras seis no. Lo correcto es que las seis se queden sin nada y sigan en USD.
func TestSoloSeGuardaLaTasaDeQuienLaTiene(t *testing.T) {
	base := lasOchoDePrueba()
	accesos := &accesosDeTasasFalso{tasas: map[string]*cotizar.Tasa{
		"HAB": tasaDePrueba(700, "2026-09-09T22:03:04Z", false),
		"STG": tasaDePrueba(700, "2026-09-09T22:03:04Z", false),
		// GR no está: Accesos contesta 200 con `tasa: null`.
	}}

	r := NuevoRefrescoDeTasas(base, accesos, mudoDeTasas(), time.Hour)
	if cambiadas := r.UnaVuelta(context.Background()); cambiadas != 2 {
		t.Fatalf("cambiadas = %d, se esperaban 2 (HAB y STG)", cambiadas)
	}
	if _, hay := base.guardado["GR"]; hay {
		t.Error("se le escribió una tasa a Granma, que no tiene: es el fallo de los 685 de La Habana")
	}
	if base.guardado["HAB"].CupRate != 700 || base.guardado["STG"].CupRate != 700 {
		t.Errorf("no se guardaron las dos tasas buenas: %+v", base.guardado)
	}
}

// LA IMPORTANTE: cada tasa acaba en SU sucursal y en ninguna otra.
//
// Con tasas distintas a propósito — si el refresco confundiera las filas, dos números
// iguales lo taparían.
func TestLaTasaDeUnaSucursalNoAcabaEnOtra(t *testing.T) {
	base := lasOchoDePrueba()
	accesos := &accesosDeTasasFalso{tasas: map[string]*cotizar.Tasa{
		"HAB": tasaDePrueba(685, "2026-09-09T22:03:04Z", true),
		"STG": tasaDePrueba(700, "2026-09-09T22:03:04Z", true),
	}}

	NuevoRefrescoDeTasas(base, accesos, mudoDeTasas(), time.Hour).UnaVuelta(context.Background())

	if v := base.guardado["HAB"].CupRate; v != 685 {
		t.Errorf("La Habana quedó con %v y su tasa es 685: se le metió la de otra sucursal", v)
	}
	if v := base.guardado["STG"].CupRate; v != 700 {
		t.Errorf("Santiago quedó con %v y su tasa es 700: se le metió la de otra sucursal", v)
	}
	if len(base.guardado) != 2 {
		t.Errorf("se escribieron %d sucursales y sólo dos tienen tasa: %+v",
			len(base.guardado), base.guardado)
	}
	// Y se le preguntó a Accesos por cada una con SU código, una vez.
	if len(accesos.preguntado) != 3 {
		t.Errorf("se preguntó %d veces y hay 3 sucursales: %v",
			len(accesos.preguntado), accesos.preguntado)
	}
}

// ACCESOS NO CONTESTA: no se toca nada. Un tropiezo de red no puede dejar sin CUP a una
// sucursal que tiene la tasa puesta — lo guardado sigue valiendo, con su fecha al lado.
func TestSiAccesosFallaNoSeToca(t *testing.T) {
	base := lasOchoDePrueba()
	accesos := &accesosDeTasasFalso{
		tasas:    map[string]*cotizar.Tasa{"STG": tasaDePrueba(700, "2026-09-09T22:03:04Z", true)},
		revienta: map[string]bool{"HAB": true},
	}

	NuevoRefrescoDeTasas(base, accesos, mudoDeTasas(), time.Hour).UnaVuelta(context.Background())

	if _, hay := base.guardado["HAB"]; hay {
		t.Error("Accesos falló y aun así se escribió en La Habana")
	}
	if base.guardado["STG"].CupRate != 700 {
		t.Error("el fallo de una sucursal se llevó por delante a las demás")
	}
}

// «ESTA SUCURSAL NO TIENE TASA» NO BORRA LA QUE HABÍA.
//
// Es la decisión que menos se ve venir, así que tiene prueba propia: desde aquí un `null`
// de Accesos y un «nunca la tuvo» se parecen, y el precio de equivocarse no es simétrico.
func TestElNoHayTasaNoBorraLaGuardada(t *testing.T) {
	base := lasOchoDePrueba()
	accesos := &accesosDeTasasFalso{tasas: map[string]*cotizar.Tasa{}} // ninguna tiene

	NuevoRefrescoDeTasas(base, accesos, mudoDeTasas(), time.Hour).UnaVuelta(context.Background())

	if len(base.guardado) != 0 {
		t.Errorf("se escribió algo cuando Accesos dijo que no hay tasa de ninguna: %+v",
			base.guardado)
	}
}

// LA MARCA DE CUÁNDO ES LO QUE DEMUESTRA QUE LA TASA EXISTE (regla 3). Un `traidoAt` que
// no se entiende se guarda como NULL a propósito: la tasa queda inutilizable, que es mucho
// mejor que darle una fecha inventada a un número con el que se cobra.
func TestUnTraidoAtIlegibleSeGuardaSinFecha(t *testing.T) {
	base := lasOchoDePrueba()
	accesos := &accesosDeTasasFalso{tasas: map[string]*cotizar.Tasa{
		"STG": tasaDePrueba(700, "el martes pasado", true),
	}}

	NuevoRefrescoDeTasas(base, accesos, mudoDeTasas(), time.Hour).UnaVuelta(context.Background())

	if base.guardado["STG"].CupRateTraidoAt.Valid {
		t.Error("una fecha ilegible se guardó como si fuera buena")
	}
}

// Y la fecha buena se guarda tal cual: es lo que se enseña al lado del número.
func TestLaFechaDeAccesosSeGuardaTalCual(t *testing.T) {
	base := lasOchoDePrueba()
	accesos := &accesosDeTasasFalso{tasas: map[string]*cotizar.Tasa{
		"STG": tasaDePrueba(700, "2026-09-09T22:03:04Z", false),
	}}

	NuevoRefrescoDeTasas(base, accesos, mudoDeTasas(), time.Hour).UnaVuelta(context.Background())

	marca := base.guardado["STG"].CupRateTraidoAt
	if !marca.Valid || !marca.Time.Equal(time.Date(2026, 9, 9, 22, 3, 4, 0, time.UTC)) {
		t.Errorf("la fecha quedó en %v y tenía que ser la del 09/09", marca)
	}
	// `fresca` la decide Accesos: aquí se copia, no se calcula.
	if base.guardado["STG"].CupRateFresca {
		t.Error("Accesos dijo que no es fresca y se guardó como fresca")
	}
}

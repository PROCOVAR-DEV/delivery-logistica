package sincro

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/identidad"
	"procovar/reparto-sync/internal/store"
	"procovar/reparto-sync/internal/store/sqlc"
)

// LA ENTREGA A REVISIÓN (`docs/bandeja-de-revision.md`, S1). Las pruebas que importan, por orden:
//
//  1. EL `Aplicador` NO SE LLAMA NUNCA al entregar. Entregar no es aplicar.
//  2. Idempotencia: entregar dos veces es UNA fila; otro contenido con la misma clave es 409 y no pisa nada.
//  3. El original se guarda TAL CUAL (byte a byte) y con su huella.
//  4. Quién (la persona y la sucursal del aparato), la lista blanca de rutas y los cupos.
//
// Casi todas corren dos veces: contra el doble de la base y, si hay `SYNC_MOTOR_REAL_DSN`, contra Postgres de
// verdad (`revision_motor_real_test.go`). Lo que el SQL hace no lo ve un doble.

// ---------------------------------------------------------------------------
// El entorno
// ---------------------------------------------------------------------------

type entorno struct {
	t        *testing.T
	motor    string
	datos    store.Datos
	servicio *Servicio
	// publico es el mux de `main`: la fuente normal en `/sync/` y las dos rutas de entrega, cada una con la suya.
	publico   *http.ServeMux
	aplicador *aplicadorFalso
	aparato   sqlc.Aparato
	sucursal  uuid.UUID
	persona   string
	// Quién llama según cada fuente. Las pruebas los cambian a mano.
	entrega identidad.Identidad
	normal  identidad.Identidad
	reloj   time.Time
	log     *bytes.Buffer
	// Si no es nil, el contexto de las peticiones de `pedir` (una prueba lo cancela a mitad para ver qué pasa cuando
	// el cliente se va).
	ctx context.Context
}

func nuevoEntorno(t *testing.T, motor string, datos store.Datos) *entorno {
	t.Helper()
	e := &entorno{t: t, motor: motor, datos: datos, aplicador: nuevoAplicador(), log: &bytes.Buffer{},
		sucursal: uuid.New(), persona: "p-" + uuid.NewString(), reloj: enPuntoFijo()}
	e.servicio = Nuevo(Opciones{
		Datos: datos, Origen: &origenFalso{}, Aplicador: e.aplicador,
		Ahora: func() time.Time { return e.reloj },
		Log:   slog.New(slog.NewTextHandler(e.log, &slog.HandlerOptions{Level: slog.LevelInfo})),
	})

	aparato, err := datos.AltaAparato(context.Background(), sqlc.AltaAparatoParams{Persona: e.persona, BranchID: e.sucursal})
	if err != nil {
		t.Fatal(err)
	}
	if err := datos.AbrirEstado(context.Background(), aparato.ID); err != nil {
		t.Fatal(err)
	}
	e.aparato = aparato

	e.entrega = identidad.Identidad{Persona: e.persona, Nombre: "Yasmani", Sucursal: e.sucursal,
		Jti: "jti-" + uuid.NewString(), Ambito: identidad.AmbitoEntrega, Caduca: time.Now().Add(10 * time.Minute)}
	e.normal = identidad.Identidad{Persona: e.persona, Sucursal: e.sucursal, Token: "token-normal"}

	interno := http.NewServeMux()
	e.servicio.Rutas(interno)
	e.publico = http.NewServeMux()
	e.publico.Handle("/sync/", identidad.Exigir(func(*http.Request) (identidad.Identidad, error) { return e.normal, nil }, interno))
	e.servicio.RutasDeRevision(e.publico,
		func(*http.Request) (identidad.Identidad, error) { return e.entrega, nil },
		func(*http.Request) (identidad.Identidad, error) { return e.entrega, nil })
	return e
}

// motores: el doble siempre; Postgres de verdad sólo si hay `SYNC_MOTOR_REAL_DSN`.
func paraCadaMotor(t *testing.T, prueba func(t *testing.T, e *entorno)) {
	t.Helper()
	t.Run("doble", func(t *testing.T) {
		prueba(t, nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase())))
	})
	t.Run("motor_real", func(t *testing.T) {
		prueba(t, nuevoEntorno(t, "motor_real", datosEnPostgresReal(t)))
	})
}

func (e *entorno) hechoHaceUnaHora() string {
	return e.reloj.Add(-time.Hour).UTC().Format(time.RFC3339Nano)
}

// ap: un apunte con valores por defecto válidos, y los cambios que pida la prueba.
func (e *entorno) ap(clave string, cambios ...map[string]any) map[string]any {
	a := map[string]any{
		"clave": clave, "hecho": e.hechoHaceUnaHora(), "metodo": "POST", "ruta": "/routes",
		"cuerpo": map[string]any{"vehicleId": "v1", "orderIds": []string{"p1", "p2"}}, "provisional": "local-" + strings.ReplaceAll(clave, "-", ""),
	}
	for _, c := range cambios {
		for k, v := range c {
			if v == nil {
				delete(a, k)
			} else {
				a[k] = v
			}
		}
	}
	return a
}

func (e *entorno) cuerpoDeEntrega(apuntes ...map[string]any) map[string]any {
	return map[string]any{"aparato": e.aparato.ID.String(), "apuntes": apuntes, "version_app": "1.0.32"}
}

// pedir manda `cuerpo` (un valor a codificar, o ya los bytes) a una ruta del mux de `main`.
func (e *entorno) pedir(metodo, ruta string, cuerpo any) *httptest.ResponseRecorder {
	e.t.Helper()
	var datos []byte
	switch v := cuerpo.(type) {
	case nil:
	case []byte:
		datos = v
	case string:
		datos = []byte(v)
	default:
		var err error
		if datos, err = json.Marshal(v); err != nil {
			e.t.Fatal(err)
		}
	}
	req := httptest.NewRequest(metodo, ruta, bytes.NewReader(datos))
	if e.ctx != nil {
		req = req.WithContext(e.ctx)
	}
	w := httptest.NewRecorder()
	e.publico.ServeHTTP(w, req)
	return w
}

func (e *entorno) entregar(apuntes ...map[string]any) (*httptest.ResponseRecorder, entregaSalida) {
	e.t.Helper()
	return e.entregarCuerpo(e.cuerpoDeEntrega(apuntes...))
}

func (e *entorno) entregarCuerpo(cuerpo any) (*httptest.ResponseRecorder, entregaSalida) {
	e.t.Helper()
	w := e.pedir(http.MethodPost, "/sync/revision/entrega", cuerpo)
	var salida entregaSalida
	if w.Code == http.StatusOK {
		if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
			e.t.Fatalf("la respuesta de la entrega no se entiende: %v (%s)", err, w.Body.String())
		}
	}
	return w, salida
}

func (e *entorno) esperar(w *httptest.ResponseRecorder, estado int, codigo string) {
	e.t.Helper()
	if w.Code != estado {
		e.t.Fatalf("se esperaba %d y contestó %d: %s", estado, w.Code, w.Body.String())
	}
	if codigo != "" {
		var sobre struct{ Codigo string }
		_ = json.Unmarshal(w.Body.Bytes(), &sobre)
		if !strings.EqualFold(sobre.Codigo, codigo) {
			e.t.Fatalf("se esperaba el código %q y vino %q: %s", codigo, sobre.Codigo, w.Body.String())
		}
	}
}

func (e *entorno) fila(clave string) (sqlc.EstadoDeRevisionDeApunteRow, bool) {
	e.t.Helper()
	f, err := e.datos.EstadoDeRevisionDeApunte(context.Background(), sqlc.EstadoDeRevisionDeApunteParams{AparatoID: e.aparato.ID, Clave: clave})
	if store.SinFilas(err) {
		return sqlc.EstadoDeRevisionDeApunteRow{}, false
	}
	if err != nil {
		e.t.Fatal(err)
	}
	return f, true
}

func (e *entorno) cuantas() int {
	e.t.Helper()
	filas, err := e.datos.RevisionDeAparato(context.Background(), sqlc.RevisionDeAparatoParams{AparatoID: e.aparato.ID, Limite: 100000})
	if err != nil {
		e.t.Fatal(err)
	}
	return len(filas)
}

func (e *entorno) sinAplicar() {
	e.t.Helper()
	if n := len(e.aplicador.llamadas); n != 0 {
		e.t.Fatalf("EL APLICADOR SE LLAMÓ %d VECES: entregar a revisión no puede aplicar NADA (%v)", n, e.aplicador.rutas())
	}
}

// ---------------------------------------------------------------------------
// 1 · La invariante central
// ---------------------------------------------------------------------------

func TestEntregarNoAplicaNada(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		// De todo un poco: un POST que crea con provisional, otro apunte que lo usa, un PUT, un DELETE y un PATCH.
		w, salida := e.entregar(
			e.ap("A1"),
			e.ap("A2", map[string]any{"metodo": "PUT", "ruta": "/routes/local-A1/stops/p1", "provisional": nil}),
			e.ap("A3", map[string]any{"metodo": "PATCH", "ruta": "/board/placements/p9", "provisional": nil}),
			e.ap("A4", map[string]any{"metodo": "DELETE", "ruta": "/routes/local-A1", "cuerpo": nil, "provisional": nil}),
		)
		e.esperar(w, http.StatusOK, "")
		if len(salida.Resultados) != 4 {
			t.Fatalf("resultados: %+v", salida)
		}
		for _, r := range salida.Resultados {
			if r.Estado != EstadoEnRevision || r.EstadoActual != "en_revision" || r.Revision == nil {
				t.Errorf("tenía que quedar en revisión: %+v", r)
			}
		}
		// LA INVARIANTE: el reparto no vio nada.
		e.sinAplicar()
		if len(e.aplicador.estado) != 0 {
			t.Errorf("el reparto cambió: %v", e.aplicador.estado)
		}
		// Ni la contabilidad de lo aplicado: ni el libro `apuntes` ni la traducción de provisionales.
		if _, err := e.datos.BuscarApunte(context.Background(), sqlc.BuscarApunteParams{AparatoID: e.aparato.ID, Clave: "A1"}); !store.SinFilas(err) {
			t.Errorf("entregar a revisión anotó el apunte en el libro de lo aplicado: %v", err)
		}
		if _, err := e.datos.ResolverProvisional(context.Background(), sqlc.ResolverProvisionalParams{AparatoID: e.aparato.ID, Provisional: "local-A1"}); !store.SinFilas(err) {
			t.Errorf("entregar a revisión tradujo un provisional: %v", err)
		}
		if n := e.cuantas(); n != 4 {
			t.Errorf("filas en la bandeja = %d, se esperaban 4", n)
		}
		// Y en orden FIFO, el de llegada.
		for i, clave := range []string{"A1", "A2", "A3", "A4"} {
			if f, _ := e.fila(clave); int(f.Orden) != i {
				t.Errorf("%s: orden = %d, se esperaba %d", clave, f.Orden, i)
			}
		}
	})
}

// ---------------------------------------------------------------------------
// 2 · Idempotencia
// ---------------------------------------------------------------------------

func TestEntregarDosVecesEsUnaFila(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		_, primera := e.entregar(e.ap("B1"))
		if primera.Resultados[0].Estado != EstadoEnRevision {
			t.Fatalf("la primera: %+v", primera)
		}
		// Otro token (otra pulsación del botón): el mismo apunte, el mismo contenido.
		e.entrega.Jti = "jti-otro-" + uuid.NewString()
		w, segunda := e.entregar(e.ap("B1"))
		e.esperar(w, http.StatusOK, "")
		r := segunda.Resultados[0]
		if r.Estado != EstadoRepetido || r.EstadoActual != "en_revision" || r.Revision == nil ||
			*r.Revision != *primera.Resultados[0].Revision {
			t.Fatalf("la segunda tenía que ser `repetido` en la MISMA revisión: %+v", r)
		}
		if n := e.cuantas(); n != 1 {
			t.Fatalf("entregar dos veces dejó %d filas, tenía que ser UNA", n)
		}
		e.sinAplicar()
	})
}

func TestUnaMismaClaveRepetidaDentroDelEnvioNoSeAdmite(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		w, _ := e.entregar(e.ap("C1"), e.ap("C1"))
		e.esperar(w, http.StatusUnprocessableEntity, CodigoEntregaNoAdmitida)
		if e.cuantas() != 0 {
			t.Error("una entrega no admitida guardó algo")
		}
	})
}

func TestLaMismaClaveConOtroContenidoEs409YNoSobrescribe(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		_, _ = e.entregar(e.ap("D1"))
		antes, _ := e.fila("D1")

		otros := map[string]map[string]any{
			"el cuerpo":      {"cuerpo": map[string]any{"vehicleId": "OTRO"}},
			"la ruta":        {"ruta": "/routes/otra"},
			"el método":      {"metodo": "PUT"},
			"la hora":        {"hecho": e.reloj.Add(-2 * time.Hour).UTC().Format(time.RFC3339Nano)},
			"el provisional": {"provisional": "local-otro"},
		}
		for qué, cambio := range otros {
			w, _ := e.entregar(e.ap("D1", cambio))
			e.esperar(w, http.StatusConflict, CodigoHuellaDistinta)
			if despues, _ := e.fila("D1"); despues.Huella != antes.Huella || despues.EntregaID != antes.EntregaID {
				t.Fatalf("cambiar %s SOBRESCRIBIÓ el original: antes %+v, después %+v", qué, antes, despues)
			}
		}
		// El original sigue entero.
		completo, err := e.datos.RevisionApunteDeRevisor(context.Background(), sqlc.RevisionApunteDeRevisorParams{AparatoID: e.aparato.ID, Clave: "D1"})
		if err != nil {
			t.Fatal(err)
		}
		if completo.Metodo != "POST" || completo.Ruta != "/routes" || completo.Cuerpo == nil || strings.Contains(*completo.Cuerpo, "OTRO") {
			t.Errorf("el original cambió: %+v", completo)
		}
		if n := e.cuantas(); n != 1 {
			t.Errorf("filas = %d", n)
		}
		// Y que el 409 queda en el registro, con quién y de qué aparato, pero sin contenido ni token.
		if !strings.Contains(e.log.String(), "otro contenido") || !strings.Contains(e.log.String(), e.persona) {
			t.Errorf("el 409 no quedó en el registro: %s", e.log.String())
		}
	})
}

// Todo o nada: un envío con un apunte nuevo y otro en conflicto NO guarda el nuevo.
func TestUnEnvioConUnConflictoNoGuardaNada(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		_, _ = e.entregar(e.ap("E1"))
		w, _ := e.entregar(e.ap("E2"), e.ap("E1", map[string]any{"ruta": "/routes/otra"}))
		e.esperar(w, http.StatusConflict, CodigoHuellaDistinta)
		if _, hay := e.fila("E2"); hay {
			t.Error("el apunte nuevo de un envío con conflicto SE GUARDÓ")
		}
		if n := e.cuantas(); n != 1 {
			t.Errorf("filas = %d", n)
		}
	})
}

// ---------------------------------------------------------------------------
// 3 · El original, tal cual
// ---------------------------------------------------------------------------

func TestElCuerpoSeGuardaTalCualYConSuHuella(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		// Espacios, orden de claves, un escape y un número que al re-serializar cambia: cualquier
		// `json.Marshal` de por medio dejaría otro texto.
		original := "{ \"z\" : 1.50 ,\n  \"a\":[1,  2],\"nombre\":\"Mar\\u00eda \\/ x\",   \"b\":{\"k\":null} }"
		hecho := e.reloj.Add(-90 * time.Minute).UTC().Truncate(time.Microsecond)
		peticion := fmt.Sprintf(`{"aparato":%q,"version_app":"1.0.32","apuntes":[{"clave":"F1","hecho":%q,"metodo":"POST","ruta":"/routes","cuerpo":%s,"provisional":"local-F1","resumen":"Armar ruta"}]}`,
			e.aparato.ID, hecho.Format(time.RFC3339Nano), original)
		w, _ := e.entregarCuerpo(peticion)
		e.esperar(w, http.StatusOK, "")

		f, err := e.datos.RevisionApunteDeRevisor(context.Background(), sqlc.RevisionApunteDeRevisorParams{AparatoID: e.aparato.ID, Clave: "F1"})
		if err != nil {
			t.Fatal(err)
		}
		if f.Cuerpo == nil || *f.Cuerpo != original {
			t.Fatalf("EL CUERPO NO SE GUARDÓ TAL CUAL.\n guardado: %v\n original: %s", f.Cuerpo, original)
		}
		// La huella es la del original: se recalcula desde lo guardado.
		recalculada := huellaDeApunte(e.aparato.ID, apunteDeEntrega{
			Clave: f.Clave, Hecho: f.HechoAt.Time, Metodo: f.Metodo, Ruta: f.Ruta, Cuerpo: json.RawMessage(*f.Cuerpo), Provisional: *f.Provisional})
		if f.Huella != recalculada || len(f.Huella) != 64 {
			t.Errorf("la huella guardada (%s) no es la del original (%s)", f.Huella, recalculada)
		}
		// La hora es la del APARATO, no la de la entrega.
		if !f.HechoAt.Time.Equal(hecho) {
			t.Errorf("hecho_at = %v, se esperaba la del aparato %v", f.HechoAt.Time, hecho)
		}
		if f.PersonaNombre == nil || *f.PersonaNombre != "Yasmani" || f.Persona != e.persona || f.BranchID != e.sucursal ||
			f.TokenJti != e.entrega.Jti || f.VersionApp == nil || *f.VersionApp != "1.0.32" {
			t.Errorf("la constancia de quién entregó: %+v", f)
		}
		if f.ResumenDelAparato == nil || *f.ResumenDelAparato != "Armar ruta" {
			t.Errorf("el resumen del aparato: %v", f.ResumenDelAparato)
		}
		// Sin token ni cabecera de autorización en NINGÚN sitio: el registro no los lleva.
		if strings.Contains(e.log.String(), "Bearer") {
			t.Errorf("el registro lleva una cabecera de autorización: %s", e.log.String())
		}
	})
}

// Un apunte sin cuerpo (un DELETE) se guarda sin cuerpo, no con un `null` inventado.
func TestUnApunteSinCuerpoSeGuardaSinCuerpo(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		w, _ := e.entregar(e.ap("G1", map[string]any{"metodo": "DELETE", "ruta": "/routes/r1", "cuerpo": nil, "provisional": nil}))
		e.esperar(w, http.StatusOK, "")
		f, _ := e.datos.RevisionApunteDeRevisor(context.Background(), sqlc.RevisionApunteDeRevisorParams{AparatoID: e.aparato.ID, Clave: "G1"})
		if f.Cuerpo != nil || f.Provisional != nil {
			t.Errorf("cuerpo=%v provisional=%v", f.Cuerpo, f.Provisional)
		}
	})
}

// ---------------------------------------------------------------------------
// 4 · Quién
// ---------------------------------------------------------------------------

func TestUnTokenNormalNoEntregaAunqueLleguePorLaRuta(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		// Aunque alguien montara mal la fuente de la ruta de entrega con una identidad normal (con `Token`, sin
		// ámbito), el manejador se planta.
		e.entrega = e.normal
		w, _ := e.entregar(e.ap("H1"))
		e.esperar(w, http.StatusForbidden, identidad.CodigoSinPermisoReparto)
		if e.cuantas() != 0 {
			t.Error("un token normal entregó")
		}
		// Ni siquiera con el ámbito puesto si trae un token reenviable (o es Super Admin).
		e.entrega = identidad.Identidad{Persona: e.persona, Sucursal: e.sucursal, Jti: "j", Ambito: identidad.AmbitoEntrega, Token: "x"}
		w, _ = e.entregar(e.ap("H1"))
		e.esperar(w, http.StatusForbidden, identidad.CodigoSinPermisoReparto)
		// La identidad que dan las cabeceras de un proxy: ni token ni ámbito. No es un token de entrega.
		e.entrega = identidad.Identidad{Persona: e.persona, Sucursal: e.sucursal, Jti: "j"}
		w, _ = e.entregar(e.ap("H1"))
		e.esperar(w, http.StatusForbidden, identidad.CodigoSinPermisoReparto)
		e.entrega = identidad.Identidad{Persona: e.persona, Sucursal: e.sucursal, Jti: "j", Ambito: identidad.AmbitoEntrega, EsSuperAdmin: true}
		w, _ = e.entregar(e.ap("H1"))
		e.esperar(w, http.StatusForbidden, identidad.CodigoSinPermisoReparto)
		if e.cuantas() != 0 {
			t.Error("entregó quien no debía")
		}
	})
}

func TestElAparatoTieneQueSerDeEstaPersona(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		// Otra persona de la MISMA sucursal, con el aparato de la primera (que existe y que `quien.Ve` dejaría
		// pasar). En la subida normal esto hoy pasa; aquí NO.
		e.entrega.Persona = "p-otra-" + uuid.NewString()
		w, _ := e.entregar(e.ap("I1"))
		e.esperar(w, http.StatusForbidden, CodigoAparatoAjeno)
		if e.cuantas() != 0 {
			t.Error("entregó por el aparato de otra persona")
		}
	})
}

func TestElAparatoTieneQueSerDeEstaSucursal(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		// La persona es la del aparato, pero el token trae OTRA sucursal (se la cambiaron en Accesos).
		e.entrega.Sucursal = uuid.New()
		w, _ := e.entregar(e.ap("J1"))
		e.esperar(w, http.StatusForbidden, CodigoAparatoAjeno)
		if e.cuantas() != 0 {
			t.Error("entregó con una sucursal que no es la del aparato")
		}
	})
}

func TestUnAparatoQueNoExisteNoSeDaDeAltaYTrae404ConLaMarca(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		cuerpo := e.cuerpoDeEntrega(e.ap("K1"))
		cuerpo["aparato"] = uuid.NewString()
		w, _ := e.entregarCuerpo(cuerpo)
		e.esperar(w, http.StatusNotFound, "aparato_no_registrado")
		cuerpo["aparato"] = "no-es-un-uuid"
		w, _ = e.entregarCuerpo(cuerpo)
		e.esperar(w, http.StatusBadRequest, "")
		cuerpo["aparato"] = ""
		w, _ = e.entregarCuerpo(cuerpo)
		e.esperar(w, http.StatusBadRequest, "")
		w = e.pedir(http.MethodPost, "/sync/revision/entrega", "esto no es json")
		e.esperar(w, http.StatusBadRequest, "")
	})
}

// ---------------------------------------------------------------------------
// 5 · La lista blanca y los límites de un apunte
// ---------------------------------------------------------------------------

func TestLaListaBlancaDeMetodoYRuta(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		largo := "/routes/" + strings.Repeat("a", 300)
		malos := []map[string]any{
			{"ruta": "/admin/recompute"},
			{"ruta": "/api/admin/recompute"},
			{"ruta": "/routes/../admin/recompute"},
			{"ruta": "/routes/..%2fadmin"},
			{"ruta": "/routes/%2e%2e/admin/recompute"},
			{"ruta": "//routes"},
			{"ruta": "/routes//x"},
			{"ruta": "/routesx"},
			{"ruta": "/routes/"},
			{"ruta": "/routes/x/"},
			{"ruta": "routes"},
			{"ruta": "/orders"},
			{"ruta": "/customers/c1"},
			{"ruta": "/board/columns?x=../a"},
			{"ruta": "/routes/x y"},
			{"ruta": "/routes/x\\y"},
			{"ruta": "/routes/x#frag"},
			{"ruta": "http://evil.example/routes"},
			{"ruta": largo},
			{"ruta": ""},
			{"metodo": "GET"},
			{"metodo": "HEAD"},
			{"metodo": "OPTIONS"},
			{"metodo": "TRACE"},
			{"metodo": "post"},
			{"metodo": "POST "},
			{"metodo": ""},
			{"clave": ""},
			{"clave": "con espacio"},
			{"clave": strings.Repeat("x", 101)},
			// LA LISTA BLANCA ES POR FORMA (auditoría B3): ni un punto como segmento, ni más profundidad.
			{"ruta": "/routes/."}, {"ruta": "/routes/a/./b"}, {"ruta": "/routes/a.b"}, {"ruta": "/routes/a/b/c/d"},
			{"ruta": "/routes/a/stops"}, {"ruta": "/routes/a/stops/b/c"}, {"ruta": "/routes/a/results/x"},
			{"ruta": "/board"}, {"ruta": "/board/unplaced"}, {"ruta": "/board/columns/a/b"}, {"ruta": "/board/columns/a/route/x"},
			{"ruta": "/board/placements"}, {"ruta": "/board/placements/a/b"}, {"ruta": "/board/columns?x=.."},
			{"provisional": "local-"},
			{"provisional": "no-es-local"},
			{"provisional": "local-a-b"},
		}
		for _, cambio := range malos {
			w, _ := e.entregar(e.ap("L1", cambio))
			if w.Code != http.StatusUnprocessableEntity {
				t.Errorf("%v: contestó %d y tenía que ser 422: %s", cambio, w.Code, w.Body.String())
			}
		}
		if e.cuantas() != 0 {
			t.Fatal("una entrega no admitida guardó algo")
		}

		// (Pasa un minuto: tantas peticiones seguidas toparían con la tasa de 60 por minuto, que no es lo que se prueba.)
		e.reloj = e.reloj.Add(2 * time.Minute)
		// Y TODAS las rutas que la cola emite de verdad, que no pueden rechazarse.
		buenos := []struct{ metodo, ruta string }{
			{"POST", "/routes"}, {"PUT", "/routes/6f9619ff-8b86-d011-b42d-00c04fc964ff"}, {"DELETE", "/routes/local-9f3a"},
			{"PUT", "/routes/local-9f3a/stops/6f9619ff-8b86-d011-b42d-00c04fc964ff"},
			{"POST", "/routes/6f9619ff-8b86-d011-b42d-00c04fc964ff/results"},
			{"PUT", "/board/placements/6f9619ff-8b86-d011-b42d-00c04fc964ff"},
			{"POST", "/board/columns?branchId=6f9619ff-8b86-d011-b42d-00c04fc964ff"},
			{"PATCH", "/board/columns/orden?branchId=6f9619ff-8b86-d011-b42d-00c04fc964ff"},
			{"DELETE", "/board/columns/c1?destino=c2"}, {"DELETE", "/board/columns/c1?vaciar=1"},
			{"PUT", "/board/columns/c1/route"}, {"POST", "/board/columns"}, {"PUT", "/board/placements/p9"},
			{"DELETE", "/routes/6f9619ff-8b86-d011-b42d-00c04fc964ff/stops/6f9619ff-8b86-d011-b42d-00c04fc964ff"},
			{"POST", "/board/columns/6f9619ff-8b86-d011-b42d-00c04fc964ff/route"},
		}
		// OJO, cambio de significado respecto a S1: `POST /board` estaba aquí como buena y NO es una ruta de
		// escritura de la API (sólo `GET /api/board`); la lista por forma la rechaza, y está arriba con las malas.
		for i, b := range buenos {
			w, _ := e.entregar(e.ap(fmt.Sprintf("OK%d", i), map[string]any{"metodo": b.metodo, "ruta": b.ruta, "provisional": nil}))
			if w.Code != http.StatusOK {
				t.Errorf("%s %s: contestó %d y tenía que entrar: %s", b.metodo, b.ruta, w.Code, w.Body.String())
			}
		}
	})
}

func TestLosLimitesDeUnApunte(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		casos := map[string]map[string]any{
			"cuerpo de 128 KiB + 1": {"cuerpo": map[string]any{"x": strings.Repeat("a", topeCuerpoDeApunte)}},
			"sin hecho":             {"hecho": nil},
			"hecho en el futuro":    {"hecho": e.reloj.Add(25 * time.Hour).UTC().Format(time.RFC3339Nano)},
			"hecho de hace 61 días": {"hecho": e.reloj.Add(-61 * 24 * time.Hour).UTC().Format(time.RFC3339Nano)},
			"hecho de 1970":         {"hecho": "1970-01-01T00:00:00Z"},
			"hecho cero":            {"hecho": "0001-01-01T00:00:00Z"},
		}
		for nombre, cambio := range casos {
			w, _ := e.entregar(e.ap("M1", cambio))
			if w.Code != http.StatusUnprocessableEntity {
				t.Errorf("%s: contestó %d y tenía que ser 422: %s", nombre, w.Code, w.Body.String())
			}
		}
		// Los bordes que SÍ entran.
		bordes := map[string]map[string]any{
			"cuerpo de justo 128 KiB": {"cuerpo": strings.Repeat("a", topeCuerpoDeApunte-2)},
			"hecho +23 h":             {"hecho": e.reloj.Add(23 * time.Hour).UTC().Format(time.RFC3339Nano)},
			"hecho -59 días":          {"hecho": e.reloj.Add(-59 * 24 * time.Hour).UTC().Format(time.RFC3339Nano)},
		}
		i := 0
		for nombre, cambio := range bordes {
			i++
			w, _ := e.entregar(e.ap(fmt.Sprintf("N%d", i), cambio))
			if w.Code != http.StatusOK {
				t.Errorf("%s: contestó %d y tenía que entrar: %s", nombre, w.Code, w.Body.String())
			}
		}
		// El cuerpo con UTF-8 roto no es un texto que Postgres acepte: se rechaza, no es un 500.
		roto := fmt.Sprintf(`{"aparato":%q,"apuntes":[{"clave":"U1","hecho":%q,"metodo":"POST","ruta":"/routes","cuerpo":"abc`,
			e.aparato.ID, e.hechoHaceUnaHora()) + "\xff\xfe" + `"}]}`
		w, _ := e.entregarCuerpo([]byte(roto))
		e.esperar(w, http.StatusUnprocessableEntity, CodigoEntregaNoAdmitida)

		// Por envío: ninguno, 26, y 512 KiB + 1.
		w, _ = e.entregar()
		e.esperar(w, http.StatusUnprocessableEntity, CodigoEntregaNoAdmitida)
		var muchos []map[string]any
		for i := 0; i < topeApuntesPorEntrega+1; i++ {
			muchos = append(muchos, e.ap(fmt.Sprintf("Z%02d", i)))
		}
		w, _ = e.entregar(muchos...)
		e.esperar(w, http.StatusUnprocessableEntity, CodigoEntregaNoAdmitida)
		w, _ = e.entregar(muchos[:topeApuntesPorEntrega]...)
		e.esperar(w, http.StatusOK, "")
		grande := e.cuerpoDeEntrega(e.ap("G1"))
		grande["version_app"] = strings.Repeat("v", topePeticionDeEntrega+1)
		w, _ = e.entregarCuerpo(grande)
		e.esperar(w, http.StatusUnprocessableEntity, CodigoEntregaNoAdmitida)
	})
}

// Un envío con un apunte malo no guarda NINGUNO, ni siquiera los buenos que iban delante.
func TestUnEnvioConUnApunteMaloNoGuardaNingunoDelResto(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		w, _ := e.entregar(e.ap("P1"), e.ap("P2", map[string]any{"ruta": "/admin/recompute"}))
		e.esperar(w, http.StatusUnprocessableEntity, CodigoEntregaNoAdmitida)
		if e.cuantas() != 0 {
			t.Fatal("se guardó parte de un envío no admitido")
		}
	})
}

// ---------------------------------------------------------------------------
// 6 · Los cupos
// ---------------------------------------------------------------------------

// sembrar mete `n` apuntes en el estado dado, de una persona y una sucursal, por las mismas consultas que usa
// la entrega.
func (e *entorno) sembrar(persona string, sucursal uuid.UUID, n int, estado sqlc.RevisionEstado, cuerpo string) {
	e.t.Helper()
	ctx := context.Background()
	aparato, err := e.datos.AltaAparato(ctx, sqlc.AltaAparatoParams{Persona: persona, BranchID: sucursal})
	if err != nil {
		e.t.Fatal(err)
	}
	if err := e.datos.EnTransaccion(ctx, func(q sqlc.Querier) error {
		ent, err := q.AltaRevisionEntrega(ctx, sqlc.AltaRevisionEntregaParams{
			AparatoID: aparato.ID, Persona: persona, BranchID: sucursal, TokenJti: "siembra-" + uuid.NewString()})
		if err != nil {
			return err
		}
		for i := 0; i < n; i++ {
			c := cuerpo
			clave := fmt.Sprintf("S%d", i)
			a, err := q.InsertarRevisionApunte(ctx, sqlc.InsertarRevisionApunteParams{
				AparatoID: aparato.ID, Clave: clave, EntregaID: ent.ID, Metodo: "POST", Ruta: "/routes", Cuerpo: &c,
				HechoAt: marca(e.reloj.Add(-time.Hour)), Huella: strings.Repeat("a", 64)})
			if err != nil {
				return err
			}
			// Para dejarlo en otro estado se recorre el camino de verdad (reclamar, cerrar o descartar): la
			// base no deja inventarse un `aplicado` sin dueño.
			switch estado {
			case sqlc.RevisionEstadoEnRevision:
			case sqlc.RevisionEstadoDescartado:
				if _, err := q.DescartarRevisionApunte(ctx, sqlc.DescartarRevisionApunteParams{
					Revisor: "revisor-siembra", Motivo: "no hacía falta", AparatoID: a.AparatoID, Clave: clave}); err != nil {
					return err
				}
			default:
				e.t.Fatalf("la siembra no sabe dejarlo en %s", estado)
			}
		}
		return nil
	}); err != nil {
		e.t.Fatal(err)
	}
}

func TestElCupoDeLaPersonaPorNumeroCuentaSoloLoVivo(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		// Lo DECIDIDO no cuenta: 500 descartados y se puede entregar.
		e.sembrar(e.persona, e.sucursal, topeVivosPorPersona, sqlc.RevisionEstadoDescartado, "{}")
		w, _ := e.entregar(e.ap("Q0"))
		e.esperar(w, http.StatusOK, "")

		// 498 vivos + el Q0 de arriba = 499: cabe UNO más, el 500, y no dos.
		e.sembrar(e.persona, e.sucursal, topeVivosPorPersona-2, sqlc.RevisionEstadoEnRevision, "{}")
		w, _ = e.entregar(e.ap("Q1"), e.ap("Q2"))
		e.esperar(w, http.StatusTooManyRequests, CodigoCupoDeRevision)
		if _, hay := e.fila("Q1"); hay {
			t.Error("una entrega que no cabe guardó el primero")
		}
		w, _ = e.entregar(e.ap("Q1"))
		e.esperar(w, http.StatusOK, "")
		// Ya son 500: el siguiente no cabe, PERO reentregar uno que ya está NO cuenta (es `repetido`).
		w, _ = e.entregar(e.ap("Q3"))
		e.esperar(w, http.StatusTooManyRequests, CodigoCupoDeRevision)
		if !strings.Contains(w.Body.String(), "500") {
			t.Errorf("el literal no dice el máximo: %s", w.Body.String())
		}
		w, salida := e.entregar(e.ap("Q1"))
		e.esperar(w, http.StatusOK, "")
		if salida.Resultados[0].Estado != EstadoRepetido {
			t.Errorf("reentregar con el cupo lleno tenía que ser `repetido`: %+v", salida)
		}
		e.sinAplicar()
	})
}

func TestElCupoDeLaPersonaPorPeso(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		// Casi 8 MiB vivos de esta persona, en filas de 100 KiB.
		fila := strings.Repeat("a", 100<<10)
		e.sembrar(e.persona, e.sucursal, 80, sqlc.RevisionEstadoEnRevision, fila) // 8.000 KiB
		w, _ := e.entregar(e.ap("W1", map[string]any{"cuerpo": strings.Repeat("b", 100<<10)}))
		// 8.000 KiB + 100 KiB = 8.100 KiB ≤ 8.192 KiB: cabe.
		e.esperar(w, http.StatusOK, "")
		w, _ = e.entregar(e.ap("W2", map[string]any{"cuerpo": strings.Repeat("c", 100<<10)}))
		// 8.100 + 100 = 8.200 KiB > 8.192: NO cabe, aunque el número de apuntes (82) está lejísimos de 500.
		e.esperar(w, http.StatusTooManyRequests, CodigoCupoDeRevision)
		if !strings.Contains(w.Body.String(), "8 MiB") {
			t.Errorf("el literal no dice el máximo de peso: %s", w.Body.String())
		}
		if _, hay := e.fila("W2"); hay {
			t.Error("guardó lo que no cabía")
		}
	})
}

func TestElCupoDeLaSucursalEsDeTodasSusPersonas(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		// Muchas personas de la sucursal, ninguna cerca de su tope personal.
		for p := 0; p < 6; p++ {
			e.sembrar(fmt.Sprintf("otro-%d-%s", p, uuid.NewString()), e.sucursal, 499, sqlc.RevisionEstadoEnRevision, "{}")
		}
		// 6 × 499 = 2.994; con el de Yasmani, 2.995.
		w, _ := e.entregar(e.ap("X1"))
		e.esperar(w, http.StatusOK, "")
		// Ahora son 2.995 vivos: cabe hasta 3.000 → 5 más.
		var cinco []map[string]any
		for i := 0; i < 5; i++ {
			cinco = append(cinco, e.ap(fmt.Sprintf("Y%d", i)))
		}
		w, _ = e.entregar(cinco...)
		e.esperar(w, http.StatusOK, "")
		// 3.000 exactos: uno más ya no cabe.
		w, _ = e.entregar(e.ap("X2"))
		e.esperar(w, http.StatusTooManyRequests, CodigoCupoDeRevision)
		if !strings.Contains(w.Body.String(), "3000") {
			t.Errorf("el literal no dice el máximo de la sucursal: %s", w.Body.String())
		}
		// Otra sucursal no se ve afectada.
		otra := uuid.New()
		e.sembrar("lejano-"+uuid.NewString(), otra, 1, sqlc.RevisionEstadoEnRevision, "{}")
		cupo, err := e.datos.CupoDeRevision(context.Background(), sqlc.CupoDeRevisionParams{Persona: "nadie", Sucursal: otra})
		if err != nil || cupo.DeLaSucursal != 1 {
			t.Errorf("el cupo de otra sucursal: %+v %v", cupo, err)
		}
	})
}

// Contar el cupo y escribir son UNA cosa: la sucursal se bloquea dentro de la transacción.
func TestLaEntregaBloqueaLaSucursalAntesDeContar(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	w, _ := e.entregar(e.ap("BL1"))
	e.esperar(w, http.StatusOK, "")
	bloqueos := e.datos.(*baseRevisionFalsa).m.bloqueos
	if len(bloqueos) != 1 || bloqueos[0] != e.sucursal {
		t.Fatalf("la entrega tenía que bloquear UNA vez la sucursal del aparato y bloqueó %v", bloqueos)
	}
}

// ---------------------------------------------------------------------------
// 7 · Lo que ya resolvió la subida normal
// ---------------------------------------------------------------------------

// Si la clave ya la aplicó (o rechazó) la subida normal, entregarla a revisión dejaría que un revisor la
// aplicara OTRA VEZ.
func TestUnaClaveQueLaSubidaNormalYaResolvioNoSeEntrega(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	creada := uuid.New()
	e.aplicador.responde = func(Peticion) (*uuid.UUID, error) { return &creada, nil }

	// La subida normal aplica R1 y rechaza R2 (provisional sin traducir).
	_, res := e.normalSubir(
		apunteEntrada{Clave: "R1", Hecho: e.reloj.Add(-time.Hour), Metodo: "POST", Ruta: "/routes", Cuerpo: json.RawMessage(`{}`), Provisional: "local-r1"},
		apunteEntrada{Clave: "R2", Hecho: e.reloj.Add(-time.Hour), Metodo: "PUT", Ruta: "/routes/local-nadie", Cuerpo: json.RawMessage(`{}`)},
	)
	if res[0].Estado != EstadoAplicado || res[1].Estado != EstadoRechazado {
		t.Fatalf("la subida normal: %+v", res)
	}
	llamadas := len(e.aplicador.llamadas)

	w, salida := e.entregar(e.ap("R1"), e.ap("R2", map[string]any{"metodo": "PUT", "ruta": "/routes/local-nadie", "provisional": nil}), e.ap("R3"))
	e.esperar(w, http.StatusOK, "")
	r1, r2, r3 := salida.Resultados[0], salida.Resultados[1], salida.Resultados[2]
	if r1.Estado != EstadoRepetido || r1.EstadoActual != "aplicado" || r1.Revision != nil {
		t.Errorf("R1 ya estaba aplicada: %+v", r1)
	}
	if r2.Estado != EstadoRepetido || r2.EstadoActual != "rechazado" || !strings.Contains(r2.Motivo, "local-nadie") {
		t.Errorf("R2 ya estaba rechazada, con su motivo: %+v", r2)
	}
	if r3.Estado != EstadoEnRevision {
		t.Errorf("R3 es nueva: %+v", r3)
	}
	if _, hay := e.fila("R1"); hay {
		t.Error("R1 se guardó en la bandeja: un revisor podría aplicarla otra vez")
	}
	if len(e.aplicador.llamadas) != llamadas {
		t.Error("entregar llamó al aplicador")
	}
}

// normalSubir manda por la ruta de siempre, con la identidad normal.
func (e *entorno) normalSubir(apuntes ...apunteEntrada) (*httptest.ResponseRecorder, []resultado) {
	e.t.Helper()
	w := e.pedir(http.MethodPost, "/sync/subida", loteEntrada{Aparato: e.aparato.ID.String(), Apuntes: apuntes})
	if w.Code != http.StatusOK {
		e.t.Fatalf("la subida normal contestó %d: %s", w.Code, w.Body.String())
	}
	var s subidaSalida
	if err := json.Unmarshal(w.Body.Bytes(), &s); err != nil {
		e.t.Fatal(err)
	}
	return w, s.Resultados
}

// ---------------------------------------------------------------------------
// 8 · El paso 0 de la subida normal
// ---------------------------------------------------------------------------

// Una clave que está en la bandeja NO se aplica por la subida normal: se contesta lo que corresponde a como
// esté ahora. Es la otra mitad de la idempotencia (recupera el rol, reenvía, y no se duplica).
func TestLaSubidaNormalNoAplicaLoQueEstaEnLaBandeja(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		ctx := context.Background()
		_, _ = e.entregar(e.ap("S1"), e.ap("S2"), e.ap("S3"), e.ap("S4"), e.ap("S5"))
		creada := uuid.New()
		descartados := json.RawMessage(`[{"pedido":"p7","motivo":"ya va en otra ruta"}]`)

		// Un revisor (otra persona, misma sucursal) decide cada uno por el camino de verdad:
		//   S1 en_revision · S2 aplicando · S3 aplicado · S4 rechazado · S5 descartado
		reclamar := func(clave string) {
			if _, err := e.datos.ReclamarRevisionApunte(ctx, sqlc.ReclamarRevisionApunteParams{
				Revisor: "revisor-1", AparatoID: e.aparato.ID, Clave: clave}); err != nil {
				t.Fatalf("reclamar %s: %v", clave, err)
			}
		}
		reclamar("S2")
		reclamar("S3")
		if _, err := e.datos.CerrarRevisionComoAplicado(ctx, sqlc.CerrarRevisionComoAplicadoParams{
			AparatoID: e.aparato.ID, Clave: "S3", Revisor: "revisor-1", IDCreado: identificador(creada), Descartados: descartados}); err != nil {
			t.Fatal(err)
		}
		reclamar("S4")
		if _, err := e.datos.CerrarRevisionComoRechazado(ctx, sqlc.CerrarRevisionComoRechazadoParams{
			AparatoID: e.aparato.ID, Clave: "S4", Revisor: "revisor-1", Motivo: "Ese pedido ya va en otra ruta."}); err != nil {
			t.Fatal(err)
		}
		nombre := "Marta Pérez"
		if _, err := e.datos.DescartarRevisionApunte(ctx, sqlc.DescartarRevisionApunteParams{
			Revisor: "revisor-1", RevisorNombre: &nombre, Motivo: "lo rehace con permiso", AparatoID: e.aparato.ID, Clave: "S5"}); err != nil {
			t.Fatal(err)
		}

		// La persona recupera el rol y reenvía TODA su cola por la subida de siempre.
		mk := func(clave string) apunteEntrada {
			return apunteEntrada{Clave: clave, Hecho: e.reloj.Add(-time.Hour), Metodo: "POST", Ruta: "/routes",
				Cuerpo: json.RawMessage(`{}`), Provisional: "local-" + clave}
		}
		_, res := e.normalSubir(mk("S1"), mk("S2"), mk("S3"), mk("S4"), mk("S5"))
		e.sinAplicar() // ← LA INVARIANTE de este paso: nada de la bandeja llega al reparto

		quiere := map[string]string{"S1": EstadoEnRevision, "S2": EstadoEnRevision, "S3": EstadoRepetido, "S4": EstadoRepetido, "S5": EstadoRepetido}
		for _, r := range res {
			if r.Estado != quiere[r.Clave] {
				t.Errorf("%s: estado %q, se esperaba %q", r.Clave, r.Estado, quiere[r.Clave])
			}
			switch r.Clave {
			case "S3":
				if r.ID == nil || *r.ID != creada || !strings.Contains(string(r.Descartados), "otra ruta") {
					t.Errorf("S3 (aplicado) tenía que devolver el id que se creó y lo que se cayó: %+v", r)
				}
			case "S4":
				if r.Motivo != "Ese pedido ya va en otra ruta." {
					t.Errorf("S4 (rechazado) tenía que llevar el motivo LITERAL del reparto: %q", r.Motivo)
				}
			case "S5":
				if !strings.Contains(r.Motivo, "Marta Pérez") || !strings.Contains(r.Motivo, "lo rehace con permiso") {
					t.Errorf("S5 (descartado) tenía que decir quién y por qué: %q", r.Motivo)
				}
			case "S1", "S2":
				if r.Motivo != "" || r.ID != nil {
					t.Errorf("%s sigue esperando: no lleva ni motivo ni id: %+v", r.Clave, r)
				}
			}
		}
		// Ni el libro de lo aplicado ni nada se tocó.
		if _, err := e.datos.BuscarApunte(ctx, sqlc.BuscarApunteParams{AparatoID: e.aparato.ID, Clave: "S1"}); !store.SinFilas(err) {
			t.Errorf("la subida normal anotó en el libro una clave de la bandeja: %v", err)
		}

		// LA PAREJA: lo que NO está en la bandeja se aplica con normalidad.
		_, res = e.normalSubir(mk("NUEVA"))
		if res[0].Estado != EstadoAplicado || len(e.aplicador.llamadas) != 1 {
			t.Errorf("una clave que no está en la bandeja tiene que aplicarse: %+v (%d llamadas)", res, len(e.aplicador.llamadas))
		}
	})
}

// El id de lo que creó un apunte aplicado por la revisión traduce el `local-…` de los que van detrás en el
// mismo lote, igual que un `repetido` de siempre.
func TestUnAplicadoPorRevisionTraduceElProvisionalDeLosSiguientes(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	ctx := context.Background()
	_, _ = e.entregar(e.ap("T1", map[string]any{"provisional": "local-t1"}))
	creada := uuid.New()
	if _, err := e.datos.ReclamarRevisionApunte(ctx, sqlc.ReclamarRevisionApunteParams{Revisor: "revisor-1", AparatoID: e.aparato.ID, Clave: "T1"}); err != nil {
		t.Fatal(err)
	}
	if _, err := e.datos.CerrarRevisionComoAplicado(ctx, sqlc.CerrarRevisionComoAplicadoParams{
		AparatoID: e.aparato.ID, Clave: "T1", Revisor: "revisor-1", IDCreado: identificador(creada)}); err != nil {
		t.Fatal(err)
	}
	_, res := e.normalSubir(
		apunteEntrada{Clave: "T1", Hecho: e.reloj.Add(-time.Hour), Metodo: "POST", Ruta: "/routes", Provisional: "local-t1"},
		apunteEntrada{Clave: "T2", Hecho: e.reloj.Add(-time.Hour), Metodo: "PUT", Ruta: "/routes/local-t1/stops/p1"},
	)
	if res[0].Estado != EstadoRepetido || res[1].Estado != EstadoAplicado {
		t.Fatalf("%+v", res)
	}
	if got := e.aplicador.rutas(); len(got) != 1 || got[0] != "/routes/"+creada.String()+"/stops/p1" {
		t.Errorf("el apunte siguiente tenía que ir al id de verdad: %v", got)
	}
}

// ---------------------------------------------------------------------------
// 9 · La carrera entre mirar y escribir, y la vuelta atrás
// ---------------------------------------------------------------------------

func TestSiOtraPeticionLaGuardoEntreMirarYEscribirNoSeDuplicaNiSePisa(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	base := e.datos.(*baseRevisionFalsa)
	ctx := context.Background()

	// «Otra petición» la guarda JUSTO antes de nuestro insert: con el mismo contenido…
	colar := func(cambio map[string]any) func(sqlc.InsertarRevisionApunteParams) {
		return func(arg sqlc.InsertarRevisionApunteParams) {
			base.m.alInsertar = nil
			a := e.ap(arg.Clave, cambio)
			var cuerpo json.RawMessage
			cuerpo, _ = json.Marshal(a["cuerpo"])
			ent, _ := base.AltaRevisionEntrega(ctx, sqlc.AltaRevisionEntregaParams{AparatoID: arg.AparatoID, Persona: e.persona, BranchID: e.sucursal, TokenJti: "otra"})
			h, _ := time.Parse(time.RFC3339Nano, a["hecho"].(string))
			c := string(cuerpo)
			_, _ = base.InsertarRevisionApunte(ctx, sqlc.InsertarRevisionApunteParams{
				AparatoID: arg.AparatoID, Clave: arg.Clave, EntregaID: ent.ID, Metodo: "POST", Ruta: "/routes", Cuerpo: &c,
				Provisional: ptr("local-" + arg.Clave), HechoAt: marca(h), Huella: huellaDeApunte(arg.AparatoID, apunteDeEntrega{
					Clave: arg.Clave, Hecho: h, Metodo: "POST", Ruta: "/routes", Cuerpo: cuerpo, Provisional: "local-" + arg.Clave})})
		}
	}
	base.m.alInsertar = colar(nil)
	w, salida := e.entregar(e.ap("CA1"))
	e.esperar(w, http.StatusOK, "")
	if r := salida.Resultados[0]; r.Estado != EstadoRepetido || r.EstadoActual != "en_revision" {
		t.Errorf("con el mismo contenido tenía que contestar `repetido`: %+v", r)
	}
	if n := e.cuantas(); n != 1 {
		t.Errorf("filas = %d", n)
	}

	// …y con otro contenido: 409, y lo que ya estaba no se toca.
	base.m.alInsertar = colar(map[string]any{"ruta": "/routes/otra"})
	w, _ = e.entregar(e.ap("CA2", map[string]any{"cuerpo": map[string]any{"distinto": true}}))
	e.esperar(w, http.StatusConflict, CodigoHuellaDistinta)
}

func ptr[T any](v T) *T { return &v }

func TestUnFalloAMitadDeLaEntregaNoDejaNadaGuardado(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	base := e.datos.(*baseRevisionFalsa)
	base.m.fallaAlInsertar["FB2"] = errorFalso("se cayó la base")
	w, _ := e.entregar(e.ap("FB1"), e.ap("FB2"))
	e.esperar(w, http.StatusInternalServerError, "")
	if _, hay := e.fila("FB1"); hay {
		t.Error("el primer apunte quedó guardado aunque la entrega falló: debía deshacerse entera")
	}
	if len(base.m.entregas) != 0 {
		t.Error("la entrega quedó guardada sin sus apuntes")
	}
	if strings.Contains(w.Body.String(), "se cayó la base") {
		t.Errorf("el 500 enseña el error interno: %s", w.Body.String())
	}
	e.sinAplicar()
}

// ---------------------------------------------------------------------------
// 10 · La tasa
// ---------------------------------------------------------------------------

func TestSesentaPeticionesPorMinutoPorPersona(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	for i := 0; i < topePeticionesPorMinuto; i++ {
		w, _ := e.entregar(e.ap("TA1"))
		if w.Code == http.StatusTooManyRequests {
			t.Fatalf("la petición %d ya se frenó", i+1)
		}
	}
	w, _ := e.entregar(e.ap("TA1"))
	e.esperar(w, http.StatusTooManyRequests, CodigoTasaDeRevision)
	if w.Header().Get("Retry-After") == "" {
		t.Error("el 429 no dice cuándo reintentar")
	}
	// `mias` comparte el contador de la persona.
	if w := e.pedir(http.MethodGet, "/sync/revision/mias?aparato="+e.aparato.ID.String(), nil); w.Code != http.StatusTooManyRequests {
		t.Errorf("`mias` no comparte la tasa: %d", w.Code)
	}
	// Otra persona no se ve afectada.
	e.entrega.Persona = "p-otra"
	w, _ = e.entregar(e.ap("TA2"))
	if w.Code == http.StatusTooManyRequests {
		t.Error("la tasa de una persona frenó a otra")
	}
	// Y pasado el minuto, se abre.
	e.entrega.Persona = e.persona
	e.reloj = e.reloj.Add(61 * time.Second)
	w, _ = e.entregar(e.ap("TA1"))
	if w.Code == http.StatusTooManyRequests {
		t.Error("pasado el minuto sigue frenado")
	}
}

// ---------------------------------------------------------------------------
// 11 · mias, y el número rojo
// ---------------------------------------------------------------------------

func (e *entorno) mias(aparato string) (*httptest.ResponseRecorder, miasSalida) {
	e.t.Helper()
	w := e.pedir(http.MethodGet, "/sync/revision/mias?aparato="+aparato, nil)
	var s miasSalida
	if w.Code == http.StatusOK {
		if err := json.Unmarshal(w.Body.Bytes(), &s); err != nil {
			e.t.Fatalf("mias: %v (%s)", err, w.Body.String())
		}
	}
	return w, s
}

func TestMiasDiceQueHaPasadoConLoMio(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		ctx := context.Background()
		_, _ = e.entregar(e.ap("M1"), e.ap("M2"), e.ap("M3"))
		nombre := "Marta Pérez"
		creada := uuid.New()
		_, _ = e.datos.ReclamarRevisionApunte(ctx, sqlc.ReclamarRevisionApunteParams{Revisor: "r1", RevisorNombre: &nombre, AparatoID: e.aparato.ID, Clave: "M2"})
		_, _ = e.datos.CerrarRevisionComoAplicado(ctx, sqlc.CerrarRevisionComoAplicadoParams{AparatoID: e.aparato.ID, Clave: "M2", Revisor: "r1", IDCreado: identificador(creada),
			Descartados: json.RawMessage(`[{"pedido":"p7"}]`)})
		_, _ = e.datos.DescartarRevisionApunte(ctx, sqlc.DescartarRevisionApunteParams{Revisor: "r1", RevisorNombre: &nombre, Motivo: "no era para hoy", AparatoID: e.aparato.ID, Clave: "M3"})

		for nombreDelToken, identidadDeLaFuente := range map[string]identidad.Identidad{"token de entrega": e.entrega, "token normal": e.normal} {
			e.entrega = identidadDeLaFuente
			w, s := e.mias(e.aparato.ID.String())
			e.esperar(w, http.StatusOK, "")
			if len(s.Entregas) != 3 || s.Truncado {
				t.Fatalf("%s: %+v", nombreDelToken, s)
			}
			// Lo vivo primero.
			if s.Entregas[0].Clave != "M1" || s.Entregas[0].Estado != "en_revision" {
				t.Errorf("%s: lo que sigue esperando tenía que ir primero: %+v", nombreDelToken, s.Entregas)
			}
			por := map[string]miaDeRevision{}
			for _, m := range s.Entregas {
				por[m.Clave] = m
			}
			if m := por["M2"]; m.Estado != "aplicado" || m.IDCreado == nil || *m.IDCreado != creada ||
				m.DecididoPorNombre == nil || *m.DecididoPorNombre != nombre || m.DecididoAt == nil || !strings.Contains(string(m.Descartados), "p7") {
				t.Errorf("M2 aplicado: %+v", m)
			}
			if m := por["M3"]; m.Estado != "descartado" || m.Motivo == nil || *m.Motivo != "no era para hoy" || m.DecididoPorNombre == nil {
				t.Errorf("M3 descartado: %+v", m)
			}
			// Y sin el cuerpo ni el token de nadie.
			if strings.Contains(string(mustJSON(t, s)), "vehicleId") {
				t.Errorf("mias enseña el cuerpo del apunte")
			}
		}
		e.sinAplicar()
	})
}

func mustJSON(t *testing.T, v any) []byte {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestMiasSoloEnseñaLoDeLaMismaPersona(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		_, _ = e.entregar(e.ap("MI1"))
		ajeno := func(id identidad.Identidad) {
			e.entrega = id
			w, _ := e.mias(e.aparato.ID.String())
			e.esperar(w, http.StatusForbidden, CodigoAparatoAjeno)
		}
		// Otra persona de la misma sucursal, con token de entrega o normal.
		ajeno(identidad.Identidad{Persona: "otra", Sucursal: e.sucursal, Jti: "j", Ambito: identidad.AmbitoEntrega})
		ajeno(identidad.Identidad{Persona: "otra", Sucursal: e.sucursal, Token: "t"})
		// Un Super Admin tampoco lee lo de otra persona por aquí.
		ajeno(identidad.Identidad{Persona: "jefe", EsSuperAdmin: true, Token: "t"})
		// La misma persona con otra sucursal en el token.
		ajeno(identidad.Identidad{Persona: e.persona, Sucursal: uuid.New(), Jti: "j", Ambito: identidad.AmbitoEntrega})
		// Un aparato que no existe: 404 con la marca; falta o mal escrito: 400.
		e.entrega = identidad.Identidad{Persona: e.persona, Sucursal: e.sucursal, Jti: "j", Ambito: identidad.AmbitoEntrega}
		w, _ := e.mias(uuid.NewString())
		e.esperar(w, http.StatusNotFound, "aparato_no_registrado")
		w, _ = e.mias("")
		e.esperar(w, http.StatusBadRequest, "")
	})
}

func TestMiasDiceCuandoSeQuedaCorto(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	base := e.datos.(*baseRevisionFalsa)
	ctx := context.Background()
	ent, _ := base.AltaRevisionEntrega(ctx, sqlc.AltaRevisionEntregaParams{AparatoID: e.aparato.ID, Persona: e.persona, BranchID: e.sucursal, TokenJti: "x"})
	for i := 0; i < topeDeFilasEnMias+1; i++ {
		_, _ = base.InsertarRevisionApunte(ctx, sqlc.InsertarRevisionApunteParams{AparatoID: e.aparato.ID, Clave: fmt.Sprintf("K%04d", i), EntregaID: ent.ID,
			Metodo: "POST", Ruta: "/routes", HechoAt: marca(e.reloj), Huella: strings.Repeat("b", 64)})
	}
	_, s := e.mias(e.aparato.ID.String())
	if len(s.Entregas) != topeDeFilasEnMias || !s.Truncado {
		t.Errorf("con %d filas tenía que devolver %d y avisar del corte: %d, truncado=%v", topeDeFilasEnMias+1, topeDeFilasEnMias, len(s.Entregas), s.Truncado)
	}
}

func TestEstadoSumaLoEntregadoPorSucursalConSuAlcance(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		ctx := context.Background()
		otra := uuid.New()
		_, _ = e.entregar(e.ap("ES1"), e.ap("ES2"), e.ap("ES3"))
		e.sembrar("otra-"+uuid.NewString(), otra, 2, sqlc.RevisionEstadoEnRevision, "{}")
		// Uno decidido no cuenta.
		_, _ = e.datos.DescartarRevisionApunte(ctx, sqlc.DescartarRevisionApunteParams{Revisor: "r1", Motivo: "no hacía falta", AparatoID: e.aparato.ID, Clave: "ES3"})

		leer := func(quien identidad.Identidad) map[uuid.UUID]int64 {
			e.normal = quien
			w := e.pedir(http.MethodGet, "/sync/estado", nil)
			if w.Code != http.StatusOK {
				t.Fatalf("estado: %d %s", w.Code, w.Body.String())
			}
			var s estadoSalida
			if err := json.Unmarshal(w.Body.Bytes(), &s); err != nil {
				t.Fatal(err)
			}
			cuenta := map[uuid.UUID]int64{}
			for _, c := range s.EnRevision {
				cuenta[c.Sucursal] = c.EnRevision
			}
			return cuenta
		}
		// Un administrador de SU sucursal ve solo la suya.
		propia := leer(identidad.Identidad{Persona: "admin", Sucursal: e.sucursal, Token: "t"})
		if len(propia) != 1 || propia[e.sucursal] != 2 {
			t.Errorf("la sucursal propia: %v (se esperaba 2 en %v)", propia, e.sucursal)
		}
		// Un Super Admin las ve todas (la otra la sembró esta prueba; en el motor real puede haber más).
		todas := leer(identidad.Identidad{Persona: "jefe", EsSuperAdmin: true, Token: "t"})
		if todas[e.sucursal] != 2 || todas[otra] != 2 {
			t.Errorf("las dos: %v", todas)
		}
		// Y quien no es de ninguna de las dos no ve ni una.
		ninguna := leer(identidad.Identidad{Persona: "admin-de-otra", Sucursal: uuid.New(), Token: "t"})
		if len(ninguna) != 0 {
			t.Errorf("otra sucursal veía %v", ninguna)
		}
	})
}

// ---------------------------------------------------------------------------
// 12 · Con tokens de verdad, por el cableado de `main`
// ---------------------------------------------------------------------------

const secretoDePrueba = "0123456789012345678901234567890123456789"

func firmarToken(t *testing.T, claims map[string]any) string {
	t.Helper()
	b := func(v []byte) string { return base64.RawURLEncoding.EncodeToString(v) }
	cab, _ := json.Marshal(map[string]string{"alg": "HS256", "typ": "JWT"})
	carga, _ := json.Marshal(claims)
	firmado := b(cab) + "." + b(carga)
	mac := hmac.New(sha256.New, []byte(secretoDePrueba))
	mac.Write([]byte(firmado))
	return firmado + "." + b(mac.Sum(nil))
}

// Los dos tokens que firma Accesos para la misma persona sin llave / con llave.
func tokensDe(t *testing.T, persona string) (entrega, normalConLlave, normalSinLlave string) {
	t.Helper()
	ahora := time.Now()
	comun := map[string]any{"sub": persona, "name": "Yasmani", "sucursal": "STG", "branch_id": "STG", "jti": "j-" + uuid.NewString(),
		"iat": ahora.Unix(), "exp": ahora.Add(10 * time.Minute).Unix()}
	mk := func(extra map[string]any) string {
		c := map[string]any{}
		for k, v := range comun {
			c[k] = v
		}
		for k, v := range extra {
			c[k] = v
		}
		return firmarToken(t, c)
	}
	entrega = mk(map[string]any{"purpose": identidad.PropositoEntrega, "ambito": identidad.AmbitoEntrega, "entradas": []string{}, "roles": []string{}, "role": ""})
	normalConLlave = mk(map[string]any{"role": "LOGISTICO", "roles": []string{"LOGISTICO"}, "entradas": []string{"delivery.entrar"}})
	normalSinLlave = mk(map[string]any{"role": "GESTOR", "entradas": []string{}})
	return
}

// Lo que arma `cmd/sync/main.go`: la fuente normal en `/sync/`, y las dos rutas de entrega con las suyas.
func TestElCableadoDeMainDejaEntrarAlTokenDeEntregaSoloPorSusDosRutas(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	resolutor := func(_ context.Context, codigo string) (uuid.UUID, error) {
		if codigo == "STG" {
			return e.sucursal, nil
		}
		return uuid.Nil, identidad.ErrSinSesion
	}
	secreto := []byte(secretoDePrueba)
	normal := identidad.DeToken(secreto, resolutor)
	entrega, mias := identidad.FuentesDeEntrega("token", secreto, resolutor, nil, normal)
	interno := http.NewServeMux()
	e.servicio.Rutas(interno)
	publico := http.NewServeMux()
	publico.Handle("/sync/", identidad.Exigir(normal, interno))
	e.servicio.RutasDeRevision(publico, entrega, mias)

	tEntrega, tConLlave, tSinLlave := tokensDe(t, e.persona)
	llamar := func(token, metodo, ruta string, cuerpo any) *httptest.ResponseRecorder {
		var datos []byte
		if cuerpo != nil {
			datos, _ = json.Marshal(cuerpo)
		}
		r := httptest.NewRequest(metodo, ruta, bytes.NewReader(datos))
		if token != "" {
			r.Header.Set("Authorization", "Bearer "+token)
		}
		w := httptest.NewRecorder()
		publico.ServeHTTP(w, r)
		return w
	}
	cuerpo := e.cuerpoDeEntrega(e.ap("TK1"))
	miasURL := "/sync/revision/mias?aparato=" + e.aparato.ID.String()

	// El de entrega: SU ruta, y mias. Nada más.
	if w := llamar(tEntrega, "POST", "/sync/revision/entrega", cuerpo); w.Code != http.StatusOK {
		t.Fatalf("el token de entrega no entró por su ruta: %d %s", w.Code, w.Body.String())
	}
	if w := llamar(tEntrega, "GET", miasURL, nil); w.Code != http.StatusOK {
		t.Errorf("el token de entrega no entró por mias: %d %s", w.Code, w.Body.String())
	}
	for _, c := range []struct{ metodo, ruta string }{
		{"POST", "/sync/subida"}, {"GET", "/sync/bajada?aparato=" + e.aparato.ID.String()}, {"GET", "/sync/estado"},
		{"POST", "/sync/aparato"}, {"GET", "/sync/revision"}, {"POST", "/sync/revision/" + e.aparato.ID.String() + "/TK1/aplicar"},
	} {
		w := llamar(tEntrega, c.metodo, c.ruta, map[string]any{"aparato": e.aparato.ID.String(), "apuntes": []any{}})
		if w.Code != http.StatusForbidden || !strings.Contains(w.Body.String(), identidad.CodigoSinPermisoReparto) {
			t.Errorf("EL TOKEN DE ENTREGA ENTRÓ POR %s %s: %d %s", c.metodo, c.ruta, w.Code, w.Body.String())
		}
	}
	e.sinAplicar()

	// El normal, con la llave: NO entrega (403), pero sí puede preguntar por lo suyo.
	if w := llamar(tConLlave, "POST", "/sync/revision/entrega", e.cuerpoDeEntrega(e.ap("TK2"))); w.Code != http.StatusForbidden {
		t.Errorf("un token normal con la llave entregó: %d %s", w.Code, w.Body.String())
	}
	if _, hay := e.fila("TK2"); hay {
		t.Error("el token normal dejó un apunte en la bandeja")
	}
	if w := llamar(tConLlave, "GET", miasURL, nil); w.Code != http.StatusOK {
		t.Errorf("mias con el token normal de la misma persona: %d %s", w.Code, w.Body.String())
	}
	// El normal SIN llave (la persona de antes del cambio de rol): ni entrega ni mias.
	for _, ruta := range []string{"/sync/revision/entrega", miasURL} {
		metodo := "POST"
		if strings.Contains(ruta, "mias") {
			metodo = "GET"
		}
		if w := llamar(tSinLlave, metodo, ruta, cuerpo); w.Code != http.StatusForbidden {
			t.Errorf("%s con un token sin llave y sin ámbito: %d", ruta, w.Code)
		}
	}
	// Sin token: 401. Con un token roto: 401.
	for _, tok := range []string{"", "esto.no.es-un-token", tEntrega[:len(tEntrega)-3] + "AAA"} {
		if w := llamar(tok, "POST", "/sync/revision/entrega", cuerpo); w.Code != http.StatusUnauthorized {
			t.Errorf("token %q: %d, se esperaba 401", tok, w.Code)
		}
	}

	// El registro de la entrega lleva quién, el aparato y la sucursal… y NO el token.
	if l := e.log.String(); !strings.Contains(l, "entrega a revisión") || !strings.Contains(l, e.persona) ||
		strings.Contains(l, tEntrega) || strings.Contains(l, tConLlave) {
		t.Errorf("el registro de la entrega: %s", l)
	}
	// Y el nombre que queda es el del TOKEN.
	f, err := e.datos.RevisionApunteDeRevisor(context.Background(), sqlc.RevisionApunteDeRevisorParams{AparatoID: e.aparato.ID, Clave: "TK1"})
	if err != nil || f.PersonaNombre == nil || *f.PersonaNombre != "Yasmani" {
		t.Errorf("el nombre de quien entregó no salió del token: %+v %v", f.PersonaNombre, err)
	}
}

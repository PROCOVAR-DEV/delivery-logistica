package sincro

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math/rand"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/identidad"
	"procovar/reparto-sync/internal/store"
	"procovar/reparto-sync/internal/store/sqlc"
)

// APLICAR LO QUE OTRO ENTREGÓ (`docs/bandeja-de-revision.md`, B.2 «Aplicar: lo que pasa y lo que NO puede
// pasar», B.4). Es donde el payload de alguien SIN permiso se ejecuta con la autoridad de otra persona, así
// que cada paso tiene su prueba, y casi todas corren contra el doble Y contra Postgres de verdad:
//
//	candado `aplicando` (el doble clic no aplica dos veces) · lista blanca al aplicar · token del REVISOR ·
//	X-Sucursal-Id forzada · 4xx = rechazado con el LITERAL, sin reintento solo · 5xx = NO rechazado ·
//	al aplicar se escribe en el libro `apuntes` · «aplicar todo en orden» se detiene en el primer fallo.

func (e *entorno) aplicarUno(aparato uuid.UUID, clave string, cuerpo any) *httptest.ResponseRecorder {
	return e.pedir(http.MethodPost, "/sync/revision/"+aparato.String()+"/"+clave+"/aplicar", cuerpo)
}

func (e *entorno) aplicarEntrega(entrega uuid.UUID) (*httptest.ResponseRecorder, resultadosSalida) {
	e.t.Helper()
	w := e.pedir(http.MethodPost, "/sync/revision/"+entrega.String()+"/aplicar", nil)
	var s resultadosSalida
	if w.Code == http.StatusOK {
		if err := json.Unmarshal(w.Body.Bytes(), &s); err != nil {
			e.t.Fatalf("la respuesta de aplicar en orden no se entiende: %v (%s)", err, w.Body.String())
		}
	}
	return w, s
}

func resultadosDe(t *testing.T, w *httptest.ResponseRecorder) resultadosSalida {
	t.Helper()
	var s resultadosSalida
	if err := json.Unmarshal(w.Body.Bytes(), &s); err != nil {
		t.Fatalf("la respuesta no se entiende: %v (%s)", err, w.Body.String())
	}
	return s
}

func (e *entorno) llamadasEn(claves ...string) {
	e.t.Helper()
	var got []string
	for _, l := range e.aplicador.llamadas {
		got = append(got, l.Clave)
	}
	if strings.Join(got, ",") != strings.Join(claves, ",") {
		e.t.Fatalf("el reparto recibió %v, se esperaba %v", got, claves)
	}
}

// ---------------------------------------------------------------------------
// 1 · La misma tubería, con el token del REVISOR y la sucursal FORZADA
// ---------------------------------------------------------------------------

func TestAplicarReenviaPorLaMismaTuberiaConElTokenDelRevisor(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		cuerpoRaro := `{ "vehicleId":"v1",   "orderIds":["p1","p2"] }`
		hecho := e.hechoHaceUnaHora()
		crudo := fmt.Sprintf(`{"aparato":%q,"apuntes":[`+
			`{"clave":"A1","hecho":%q,"metodo":"POST","ruta":"/routes?x=1","cuerpo":%s,"provisional":"local-A1"},`+
			`{"clave":"A2","hecho":%q,"metodo":"PUT","ruta":"/routes/local-A1/stops/p1","cuerpo":{"estado":"ok","ref":"local-A1"}}]}`,
			e.aparato.ID.String(), hecho, cuerpoRaro, hecho)
		w, salida := e.entregarCuerpo(crudo)
		e.esperar(w, http.StatusOK, "")
		entrega := *salida.Resultados[0].Revision
		e.sinAplicar()

		creada := uuid.New()
		e.aplicador.responde = func(p Peticion) (*uuid.UUID, error) {
			if p.Clave == "A1" {
				return &creada, nil
			}
			return nil, nil
		}
		e.aplicador.descarta = func(p Peticion) json.RawMessage {
			if p.Clave == "A1" {
				return json.RawMessage(`[{"pedido":"p7","motivo":"ya va en otra ruta"}]`)
			}
			return nil
		}
		e.comoRevisor("admin-cam", "ADMINISTRADOR", e.sucursal)

		w = e.aplicarUno(e.aparato.ID, "A1", nil)
		e.esperar(w, http.StatusOK, "")
		r := resultadosDe(t, w).Resultados
		if len(r) != 1 || r[0].Clave != "A1" || r[0].Estado != EstadoAplicado || r[0].ID == nil || *r[0].ID != creada ||
			!strings.Contains(string(r[0].Descartados), "otra ruta") {
			t.Fatalf("el resultado: %+v", r)
		}

		// LA PETICIÓN AL REPARTO: lo mismo que vino, con el token del REVISOR y las tres cabeceras.
		if len(e.aplicador.llamadas) != 1 {
			t.Fatalf("llamadas al reparto: %d", len(e.aplicador.llamadas))
		}
		p := e.aplicador.llamadas[0]
		original, _ := time.Parse(time.RFC3339Nano, hecho)
		switch {
		case p.Metodo != "POST" || p.Ruta != "/routes?x=1" || string(p.Cuerpo) != cuerpoRaro:
			t.Errorf("método, ruta y cuerpo tenían que ser el ORIGINAL exacto: %s %s %s", p.Metodo, p.Ruta, p.Cuerpo)
		case p.Token != "token-de-admin-cam":
			t.Errorf("tenía que firmar el REVISOR con SU token: %q", p.Token)
		case p.Persona != "admin-cam":
			t.Errorf("Persona = %q, tenía que ser el revisor", p.Persona)
		case p.Autor != e.persona:
			t.Errorf("X-Autor = %q, tenía que ser quien lo hizo (%s)", p.Autor, e.persona)
		case p.Revision != entrega.String():
			t.Errorf("X-Revision = %q, tenía que ser la entrega %s", p.Revision, entrega)
		case p.SucursalPedida != e.sucursal || p.Sucursal != e.sucursal:
			t.Errorf("X-Sucursal-Id forzada a la sucursal del apunte: pedida=%s sucursal=%s, se esperaba %s", p.SucursalPedida, p.Sucursal, e.sucursal)
		case !p.Hecho.Equal(original):
			t.Errorf("X-Hecho-At = %s, tenía que ser la hora ORIGINAL %s", p.Hecho, original)
		case p.Clave != "A1":
			t.Errorf("clave %q", p.Clave)
		}

		// EL CIERRE: el apunte aplicado, con quién y cuándo, y una anotación en el libro de decisiones.
		f, _ := e.datos.RevisionApunteDeRevisor(context.Background(), sqlc.RevisionApunteDeRevisorParams{AparatoID: e.aparato.ID, Clave: "A1"})
		if f.Estado != sqlc.RevisionEstadoAplicado || f.DecididoPor == nil || *f.DecididoPor != "admin-cam" || !f.DecididoAt.Valid ||
			deIdentificador(f.IDCreado) == nil || *deIdentificador(f.IDCreado) != creada || f.Intentos != 1 ||
			!strings.Contains(string(f.Descartados), "otra ruta") {
			t.Errorf("el apunte aplicado: %+v", f)
		}
		d := e.decisiones(e.aparato.ID, "A1")
		if len(d) != 1 || d[0].Accion != "aplicar" || d[0].Resultado != "aplicado" || d[0].Por != "admin-cam" ||
			d[0].Rol == nil || *d[0].Rol != "ADMINISTRADOR" {
			t.Errorf("el libro de decisiones: %+v", d)
		}

		// EL LIBRO `apuntes` (para que la reentrega normal dé `repetido`) y los provisionales.
		libro, err := e.datos.BuscarApunte(context.Background(), sqlc.BuscarApunteParams{AparatoID: e.aparato.ID, Clave: "A1"})
		if err != nil || libro.Estado != sqlc.ApunteEstadoAplicado || deIdentificador(libro.IDCreado) == nil ||
			*deIdentificador(libro.IDCreado) != creada || libro.Ruta != "/routes?x=1" ||
			!strings.Contains(string(libro.Descartados), "otra ruta") {
			t.Errorf("NO SE COPIÓ AL LIBRO `apuntes`: %+v (%v)", libro, err)
		}
		if id, err := e.datos.ResolverProvisional(context.Background(), sqlc.ResolverProvisionalParams{AparatoID: e.aparato.ID, Provisional: "local-A1"}); err != nil || id != creada {
			t.Errorf("el `local-A1` tenía que traducirse a %s: %v %v", creada, id, err)
		}

		// El siguiente apunte de la entrega usa el id de verdad (en la ruta y en el cuerpo).
		e.esperar(e.aplicarUno(e.aparato.ID, "A2", nil), http.StatusOK, "")
		if got := e.aplicador.llamadas[1]; got.Ruta != "/routes/"+creada.String()+"/stops/p1" ||
			!strings.Contains(string(got.Cuerpo), creada.String()) || strings.Contains(string(got.Cuerpo), "local-A1") {
			t.Errorf("el `local-A1` de A2 tenía que traducirse: %s %s", got.Ruta, got.Cuerpo)
		}

		// LA PERSONA recupera el rol y reenvía lo mismo por la subida de siempre: `repetido`, con el id, sin
		// volver a aplicar nada.
		e.normal = identidad.Identidad{Persona: e.persona, Sucursal: e.sucursal, Token: "token-normal"}
		llamadas := len(e.aplicador.llamadas)
		_, res := e.normalSubir(apunteEntrada{Clave: "A1", Hecho: original, Metodo: "POST", Ruta: "/routes?x=1",
			Cuerpo: json.RawMessage(cuerpoRaro), Provisional: "local-A1"})
		if res[0].Estado != EstadoRepetido || res[0].ID == nil || *res[0].ID != creada || len(e.aplicador.llamadas) != llamadas {
			t.Errorf("la reentrega normal de lo aplicado por revisión: %+v (llamadas %d → %d)", res[0], llamadas, len(e.aplicador.llamadas))
		}
	})
}

// Un SUPER ADMIN que ve las ocho (sin sucursal en el token) aplica lo de HOL ACOTADO A HOL. Es lo que impide
// que la autoridad prestada llegue a las otras siete.
func TestUnSuperAdminQueVeLasOchoAplicaAcotadoALaSucursalDelApunte(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		hol := uuid.New()
		apHOL, entHOL := e.entregarDeOtro("persona-de-hol", hol, "H1", "H2")
		e.comoRevisorDeTodas("super-1", "SUPER ADMIN")

		e.esperar(e.aplicarUno(apHOL.ID, "H1", nil), http.StatusOK, "")
		w, s := e.aplicarEntrega(entHOL)
		e.esperar(w, http.StatusOK, "")
		if len(e.aplicador.llamadas) != 2 {
			t.Fatalf("llamadas: %d (H1, y H2 en orden; H1 ya estaba aplicado)", len(e.aplicador.llamadas))
		}
		for _, p := range e.aplicador.llamadas {
			if p.SucursalPedida != hol || p.Sucursal != hol {
				t.Errorf("%s: X-Sucursal-Id = %s, tenía que ser la de HOL (%s) aunque el revisor vea todas", p.Clave, p.SucursalPedida, hol)
			}
			if p.Autor != "persona-de-hol" || p.Token != "token-de-super-1" {
				t.Errorf("%s: autor %q, token %q", p.Clave, p.Autor, p.Token)
			}
		}
		if len(s.Resultados) != 1 || s.Resultados[0].Clave != "H2" || s.Detenido {
			t.Errorf("aplicar en orden: H1 ya estaba aplicado, sólo H2: %+v", s)
		}
	})
}

// ---------------------------------------------------------------------------
// 2 · El candado
// ---------------------------------------------------------------------------

// El DOBLE CLIC: mientras el reparto está contestando al primero, llega otro Aplicar sobre el mismo apunte
// (el mismo revisor, o uno distinto). El reparto lo recibe UNA vez.
func TestElDobleClicNoAplicaDosVeces(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		e.entregaDeLaPersona("K1")
		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)
		var segundo, tercero *httptest.ResponseRecorder
		primero := true
		e.aplicador.responde = func(Peticion) (*uuid.UUID, error) {
			if primero {
				primero = false
				segundo = e.aplicarUno(e.aparato.ID, "K1", nil) // el doble clic
				e.comoRevisor("admin-2", "ADMINISTRADOR", e.sucursal)
				tercero = e.aplicarUno(e.aparato.ID, "K1", nil) // otro revisor a la vez
				e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)
			}
			id := uuid.New()
			return &id, nil
		}
		w := e.aplicarUno(e.aparato.ID, "K1", nil)
		e.esperar(w, http.StatusOK, "")
		e.esperar(segundo, http.StatusConflict, CodigoYaSeEstaAplicando)
		e.esperar(tercero, http.StatusConflict, CodigoYaSeEstaAplicando)
		if !strings.Contains(segundo.Body.String(), "Marta Pérez") {
			t.Errorf("el 409 tiene que decir QUIÉN lo está aplicando: %s", segundo.Body.String())
		}
		if n := len(e.aplicador.llamadas); n != 1 {
			t.Fatalf("EL DOBLE CLIC APLICÓ %d VECES, tenía que ser UNA", n)
		}
		// Y después de aplicado, otro clic tampoco.
		e.esperar(e.aplicarUno(e.aparato.ID, "K1", nil), http.StatusConflict, CodigoYaDecidido)
		if n := len(e.aplicador.llamadas); n != 1 {
			t.Fatalf("un clic sobre algo ya aplicado volvió a llamar al reparto (%d)", n)
		}
		if got := e.decisiones(e.aparato.ID, "K1"); len(got) != 1 {
			t.Errorf("el libro de decisiones: %+v", got)
		}
	})
}

// ---------------------------------------------------------------------------
// 3 · La lista blanca, otra vez, al aplicar
// ---------------------------------------------------------------------------

func TestAplicarVuelveAPasarLaListaBlanca(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		ctx := context.Background()
		entrega, err := e.datos.AltaRevisionEntrega(ctx, sqlc.AltaRevisionEntregaParams{
			AparatoID: e.aparato.ID, Persona: e.persona, BranchID: e.sucursal, TokenJti: "jti-siembra"})
		if err != nil {
			t.Fatal(err)
		}
		// Lo que la entrega (S1) NUNCA dejaría pasar, metido por debajo: la lista pudo endurecerse entre
		// entregar y aplicar, o alguien tocó la base. Lo que importa es que el reparto no lo vea.
		malos := map[string][2]string{
			"M1": {"POST", "/admin/recompute"},
			"M2": {"DELETE", "/routes/../admin/recompute"},
			"M3": {"GET", "/routes"},
			"M4": {"POST", "/board//columns"},
			"M5": {"POST", "/api/routes"},
			"M6": {"PATCH", "/routes/%2e%2e/x"},
			// Y lo que `valido` le exige a la subida normal: un apunte sin hora del aparato.
			"M7": {"POST", "/routes"},
			// LA FORMA (auditoría B3): un punto como segmento y lo que cuelga de más profundidad.
			"M8": {"PUT", "/routes/."}, "M9": {"PUT", "/routes/a/b/c/d"}, "M10": {"POST", "/board/placements"},
		}
		for clave, mr := range malos {
			cu := `{}`
			hecho := e.reloj.Add(-time.Hour)
			if clave == "M7" {
				hecho = time.Time{}
			}
			if _, err := e.datos.InsertarRevisionApunte(ctx, sqlc.InsertarRevisionApunteParams{AparatoID: e.aparato.ID, Clave: clave,
				EntregaID: entrega.ID, Metodo: mr[0], Ruta: mr[1], Cuerpo: &cu, HechoAt: marca(hecho),
				Huella: strings.Repeat("c", 64)}); err != nil {
				t.Fatal(err)
			}
		}
		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)
		for clave, mr := range malos {
			w := e.aplicarUno(e.aparato.ID, clave, nil)
			e.esperar(w, http.StatusOK, "")
			r := resultadosDe(t, w).Resultados
			if len(r) != 1 || r[0].Estado != "rechazado" || !strings.Contains(r[0].Motivo, "No se ha mandado nada al reparto") {
				t.Errorf("%s %s: tenía que quedar rechazado con su frase: %+v", mr[0], mr[1], r)
			}
			if e.estadoDe(e.aparato.ID, clave) != sqlc.RevisionEstadoRechazado {
				t.Errorf("%s %s: no quedó `rechazado`", mr[0], mr[1])
			}
		}
		e.sinAplicar() // ← lo que no pasa la lista blanca NO llega al reparto
		d := e.decisiones(e.aparato.ID, "M1")
		if len(d) != 1 || d[0].Resultado != "rechazado" {
			t.Errorf("el libro: %+v", d)
		}
		// Rechazado = vivo y a la vista: se ve en la bandeja y se puede descartar.
		if _, l := e.lista(""); len(l.Entregas) != 1 || l.Entregas[0].Rechazados != int64(len(malos)) {
			t.Errorf("la bandeja: %+v", l.Entregas)
		}
		e.esperar(e.descartar(e.aparato.ID, "M1", map[string]string{"motivo": "ruta no admitida"}), http.StatusOK, "")
	})
}

// ---------------------------------------------------------------------------
// 4 · Lo que dice el reparto
// ---------------------------------------------------------------------------

func TestUnCuatrocientosQuedaRechazadoConSuMotivoLiteralYNoSeReintentaSolo(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		e.entregaDeLaPersona("R1")
		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)
		literal := "Ese pedido ya va en otra ruta."
		e.aplicador.responde = func(Peticion) (*uuid.UUID, error) { return nil, &Rechazo{Motivo: literal} }

		w := e.aplicarUno(e.aparato.ID, "R1", nil)
		e.esperar(w, http.StatusOK, "")
		if r := resultadosDe(t, w).Resultados; len(r) != 1 || r[0].Estado != "rechazado" || r[0].Motivo != literal {
			t.Fatalf("el resultado: %+v", r)
		}
		// NO SE REINTENTA SOLO: una llamada al reparto y ya.
		if n := len(e.aplicador.llamadas); n != 1 {
			t.Fatalf("un 4xx se reintentó solo: %d llamadas", n)
		}
		// Sigue vivo y a la vista, con el LITERAL, y a nombre de quien lo intentó.
		f, _ := e.datos.RevisionApunteDeRevisor(context.Background(), sqlc.RevisionApunteDeRevisorParams{AparatoID: e.aparato.ID, Clave: "R1"})
		if f.Estado != sqlc.RevisionEstadoRechazado || f.Motivo == nil || *f.Motivo != literal || f.Intentos != 1 {
			t.Errorf("el apunte: %+v", f)
		}
		if _, l := e.lista(""); len(l.Entregas) != 1 || l.Entregas[0].Rechazados != 1 {
			t.Errorf("la bandeja: %+v", l.Entregas)
		}
		// NO va al libro de lo aplicado ni a la bandeja de rechazos del panel: sigue siendo de la revisión.
		if _, err := e.datos.BuscarApunte(context.Background(), sqlc.BuscarApunteParams{AparatoID: e.aparato.ID, Clave: "R1"}); !store.SinFilas(err) {
			t.Errorf("un rechazo de la revisión entró en el libro `apuntes`: %v", err)
		}
		// La persona lo ve en `mias` con el literal.
		if d := e.decisiones(e.aparato.ID, "R1"); len(d) != 1 || d[0].Resultado != "rechazado" || d[0].Motivo == nil || *d[0].Motivo != literal {
			t.Errorf("el libro: %+v", d)
		}

		// REINTENTAR es otro Aplicar, de una persona (otra, incluso): ahora el reparto dice que sí.
		e.aplicador.responde = nil
		e.comoRevisor("admin-2", "ADMINISTRADOR", e.sucursal)
		e.esperar(e.aplicarUno(e.aparato.ID, "R1", nil), http.StatusOK, "")
		g, _ := e.datos.RevisionApunteDeRevisor(context.Background(), sqlc.RevisionApunteDeRevisorParams{AparatoID: e.aparato.ID, Clave: "R1"})
		if g.Estado != sqlc.RevisionEstadoAplicado || g.Intentos != 2 || g.DecididoPor == nil || *g.DecididoPor != "admin-2" || g.Motivo != nil {
			t.Errorf("reintentado: %+v", g)
		}
		if d := e.decisiones(e.aparato.ID, "R1"); len(d) != 2 || d[0].Resultado != "rechazado" || d[1].Resultado != "aplicado" {
			t.Errorf("el libro guarda LOS DOS intentos: %+v", d)
		}
	})
}

// Un 5xx, la red o el 403 de rol del REVISOR no son un rechazo del apunte: vuelve a `en_revision`.
func TestUnCincoCientosNoEsUnRechazo(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		e.entregaDeLaPersona("S1", "S2", "S3")
		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)

		casos := []struct {
			clave       string
			causa       error
			estado      int
			codigo      string
			noDebeDecir string
		}{
			{"S1", errors.New("el reparto contestó 503: base caída en 10.0.0.7"), http.StatusBadGateway, CodigoRepartoNoContesta, "10.0.0.7"},
			{"S2", context.DeadlineExceeded, http.StatusBadGateway, CodigoRepartoNoContesta, "deadline"},
			{"S3", &SinPermiso{Motivo: "rol"}, http.StatusForbidden, identidad.CodigoSinPermisoReparto, ""},
		}
		for i, c := range casos {
			e.aplicador.responde = func(Peticion) (*uuid.UUID, error) { return nil, c.causa }
			w := e.aplicarUno(e.aparato.ID, c.clave, nil)
			e.esperar(w, c.estado, c.codigo)
			if c.noDebeDecir != "" && strings.Contains(strings.ToLower(w.Body.String()), c.noDebeDecir) {
				t.Errorf("%s: el error interno llegó al revisor: %s", c.clave, w.Body.String())
			}
			if n := len(e.aplicador.llamadas); n != i+1 {
				t.Fatalf("%s: se reintentó solo (%d llamadas)", c.clave, n)
			}
			f, _ := e.datos.RevisionApunteDeRevisor(context.Background(), sqlc.RevisionApunteDeRevisorParams{AparatoID: e.aparato.ID, Clave: c.clave})
			if f.Estado != sqlc.RevisionEstadoEnRevision || f.DecididoPor != nil || f.Intentos != 1 || f.Motivo != nil {
				t.Errorf("%s: tenía que VOLVER a en_revision, sin dueño y con un intento más, NO rechazado: %+v", c.clave, f)
			}
			if d := e.decisiones(e.aparato.ID, c.clave); len(d) != 1 || d[0].Resultado != "caida" {
				t.Errorf("%s: el libro: %+v", c.clave, d)
			}
		}
		// Y se puede reintentar a mano.
		e.aplicador.responde = nil
		for _, c := range []string{"S1", "S2", "S3"} {
			e.esperar(e.aplicarUno(e.aparato.ID, c, nil), http.StatusOK, "")
			if e.estadoDe(e.aparato.ID, c) != sqlc.RevisionEstadoAplicado {
				t.Errorf("%s no se aplicó al reintentar", c)
			}
		}
		if _, l := e.lista(""); len(l.Entregas) != 0 {
			t.Errorf("no quedó nada esperando: %+v", l.Entregas)
		}
	})
}

// ---------------------------------------------------------------------------
// 5 · Aplicar todo en orden
// ---------------------------------------------------------------------------

func TestAplicarTodoEnOrdenSeDetieneEnElPrimerFallo(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		w, salida := e.entregar(
			e.ap("O1"),
			e.ap("O2", map[string]any{"metodo": "PUT", "ruta": "/routes/local-O1/stops/p1", "provisional": nil}),
			e.ap("O3", map[string]any{"metodo": "PUT", "ruta": "/routes/local-O1/stops/p2", "provisional": nil}),
			e.ap("O4", map[string]any{"metodo": "PUT", "ruta": "/routes/local-O1/stops/p3", "provisional": nil}),
		)
		e.esperar(w, http.StatusOK, "")
		entrega := *salida.Resultados[0].Revision
		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)

		// El reparto rechaza O2: O3 y O4 NO se tocan.
		rechaza := true
		e.aplicador.responde = func(p Peticion) (*uuid.UUID, error) {
			if p.Clave == "O2" && rechaza {
				return nil, &Rechazo{Motivo: "La parada ya está cerrada."}
			}
			if p.Clave == "O1" {
				id := uuid.New()
				return &id, nil
			}
			return nil, nil
		}
		w, s := e.aplicarEntrega(entrega)
		e.esperar(w, http.StatusOK, "")
		e.llamadasEn("O1", "O2") // FIFO, y se paró
		if len(s.Resultados) != 2 || s.Resultados[0].Estado != EstadoAplicado || s.Resultados[1].Estado != "rechazado" ||
			s.Resultados[1].Motivo != "La parada ya está cerrada." {
			t.Fatalf("resultados: %+v", s.Resultados)
		}
		if !s.Detenido || s.DetenidoEn != "O2" || s.SinProcesar != 2 || s.DetenidoPorque != "La parada ya está cerrada." {
			t.Errorf("tenía que decir que se detuvo en O2 y cuántos quedan: %+v", s)
		}
		for c, q := range map[string]sqlc.RevisionEstado{"O1": sqlc.RevisionEstadoAplicado, "O2": sqlc.RevisionEstadoRechazado,
			"O3": sqlc.RevisionEstadoEnRevision, "O4": sqlc.RevisionEstadoEnRevision} {
			if got := e.estadoDe(e.aparato.ID, c); got != q {
				t.Errorf("%s = %s, se esperaba %s", c, got, q)
			}
		}
		// O1 creó el `local-O1`: lo que va detrás usará el id de verdad.
		if got := e.aplicador.llamadas[1].Ruta; strings.Contains(got, "local-") {
			t.Errorf("O2 se mandó sin traducir: %s", got)
		}

		// Arreglado el motivo: se vuelve a pulsar. O1 (aplicado) se salta, O2 (rechazado) se reintenta, y
		// el resto sigue EN ORDEN.
		rechaza = false
		w, s = e.aplicarEntrega(entrega)
		e.esperar(w, http.StatusOK, "")
		e.llamadasEn("O1", "O2", "O2", "O3", "O4")
		if len(s.Resultados) != 3 || s.Detenido || s.SinProcesar != 0 {
			t.Errorf("segunda pasada: %+v", s)
		}
		for _, c := range []string{"O1", "O2", "O3", "O4"} {
			if e.estadoDe(e.aparato.ID, c) != sqlc.RevisionEstadoAplicado {
				t.Errorf("%s no quedó aplicado", c)
			}
		}
		// Una tercera pasada no tiene nada que hacer.
		w, s = e.aplicarEntrega(entrega)
		e.esperar(w, http.StatusOK, "")
		if len(s.Resultados) != 0 || len(e.aplicador.llamadas) != 5 {
			t.Errorf("no había nada que aplicar: %+v (%d llamadas)", s, len(e.aplicador.llamadas))
		}
	})
}

// Una caída del reparto también detiene el orden: el apunte vuelve a en_revision y el resto no se toca.
func TestAplicarTodoSeDetieneSiElRepartoSeCae(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		entrega := e.entregaDeLaPersona("P1", "P2", "P3")
		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)
		e.aplicador.responde = func(p Peticion) (*uuid.UUID, error) {
			if p.Clave == "P2" {
				return nil, errors.New("connection refused")
			}
			return nil, nil
		}
		w, s := e.aplicarEntrega(entrega)
		e.esperar(w, http.StatusOK, "")
		e.llamadasEn("P1", "P2")
		if !s.Detenido || s.DetenidoEn != "P2" || s.SinProcesar != 1 || len(s.Resultados) != 1 || s.Resultados[0].Clave != "P1" {
			t.Errorf("%+v", s)
		}
		for c, q := range map[string]sqlc.RevisionEstado{"P1": sqlc.RevisionEstadoAplicado, "P2": sqlc.RevisionEstadoEnRevision, "P3": sqlc.RevisionEstadoEnRevision} {
			if got := e.estadoDe(e.aparato.ID, c); got != q {
				t.Errorf("%s = %s, se esperaba %s", c, got, q)
			}
		}
	})
}

// ---------------------------------------------------------------------------
// 6 · Sin token del revisor no se aplica jamás, y que cierre la pestaña no deja nada a medias
// ---------------------------------------------------------------------------

func TestSiElRevisorCierraLaPestañaElApunteNoQuedaAMedias(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		e.entregaDeLaPersona("Z1")
		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)
		ctx, cierra := context.WithCancel(context.Background())
		defer cierra()
		e.aplicador.responde = func(Peticion) (*uuid.UUID, error) {
			cierra() // el navegador se va a mitad de la llamada al reparto
			id := uuid.New()
			return &id, nil
		}
		req := httptest.NewRequest(http.MethodPost, "/sync/revision/"+e.aparato.ID.String()+"/Z1/aplicar", nil).WithContext(ctx)
		e.publico.ServeHTTP(httptest.NewRecorder(), req)
		if got := e.estadoDe(e.aparato.ID, "Z1"); got != sqlc.RevisionEstadoAplicado {
			t.Fatalf("el reparto lo aplicó y el apunte quedó %s: un cliente que se va no puede dejar la fila a medias", got)
		}
		if _, err := e.datos.BuscarApunte(context.Background(), sqlc.BuscarApunteParams{AparatoID: e.aparato.ID, Clave: "Z1"}); err != nil {
			t.Errorf("no está en el libro: %v", err)
		}
	})
}

// Se aplicó en el reparto y esta base no lo pudo anotar: se dice a gritos, porque reintentar sin mirar lo
// aplicaría dos veces. Se provoca haciendo que, MIENTRAS el reparto contesta, el apunte deje de ser del revisor
// (como si otro proceso lo hubiera soltado): el cierre no encuentra su fila y la transacción se deshace entera.
func TestSiSeAplicoPeroNoSePudoAnotarSeDiceYNoSeEscribeMedio(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		e.entregaDeLaPersona("N1")
		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)
		e.aplicador.responde = func(Peticion) (*uuid.UUID, error) {
			if _, err := e.datos.DevolverRevisionAEnRevision(context.Background(), sqlc.DevolverRevisionAEnRevisionParams{
				AparatoID: e.aparato.ID, Clave: "N1", Revisor: "admin-1"}); err != nil {
				t.Fatal(err)
			}
			id := uuid.New()
			return &id, nil
		}
		w := e.aplicarUno(e.aparato.ID, "N1", nil)
		e.esperar(w, http.StatusInternalServerError, CodigoNoSePudoAnotar)
		if !strings.Contains(w.Body.String(), "comprueba a mano") {
			t.Errorf("tiene que decir que se compruebe a mano: %s", w.Body.String())
		}
		if len(e.aplicador.llamadas) != 1 {
			t.Fatalf("llamadas: %d", len(e.aplicador.llamadas))
		}
		// La transacción se deshizo entera: ni el libro `apuntes` ni la traducción ni el libro de decisiones.
		if _, err := e.datos.BuscarApunte(context.Background(), sqlc.BuscarApunteParams{AparatoID: e.aparato.ID, Clave: "N1"}); !store.SinFilas(err) {
			t.Errorf("quedó escrito el libro `apuntes` a medias: %v", err)
		}
		if n := len(e.decisiones(e.aparato.ID, "N1")); n != 0 {
			t.Errorf("el libro de decisiones tiene %d anotaciones de algo que no se pudo cerrar", n)
		}
	})
}

// B6 (auditoría final) · LA SUBIDA NORMAL YA LO RESOLVIÓ: un sync VIEJO (rollback del despliegue) aplicó por la
// subida normal una clave que estaba entregada aquí. Aplicarla otra vez la haría DOS VECES con la autoridad
// del revisor: se cierra con lo que dice el libro `apuntes` y NO se reenvía.
func TestAplicarMiraElLibroAntesDeReenviar(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		ctx := context.Background()
		e.entregaDeLaPersona("B1", "B2", "B3")
		ya := uuid.New()
		descartados := json.RawMessage(`[{"pedido":"p7","motivo":"ya va en otra ruta"}]`)
		// B1 la aplicó la subida de un sync viejo; B2 la rechazó.
		if _, err := e.datos.AnotarApunteAplicado(ctx, sqlc.AnotarApunteAplicadoParams{AparatoID: e.aparato.ID, Clave: "B1",
			Metodo: "POST", Ruta: "/routes", IDCreado: identificador(ya), HechoAt: marca(e.reloj), Descartados: descartados}); err != nil {
			t.Fatal(err)
		}
		if err := e.datos.EnTransaccion(ctx, func(q sqlc.Querier) error {
			if _, err := q.AnotarApunteRechazado(ctx, sqlc.AnotarApunteRechazadoParams{AparatoID: e.aparato.ID, Clave: "B2",
				Metodo: "POST", Ruta: "/routes", HechoAt: marca(e.reloj)}); err != nil {
				return err
			}
			_, err := q.AnotarRechazo(ctx, sqlc.AnotarRechazoParams{AparatoID: e.aparato.ID, Clave: "B2", Motivo: "Ese pedido ya va en otra ruta."})
			return err
		}); err != nil {
			t.Fatal(err)
		}
		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)

		w := e.aplicarUno(e.aparato.ID, "B1", nil)
		e.esperar(w, http.StatusOK, "")
		r := resultadosDe(t, w).Resultados
		if len(r) != 1 || r[0].Estado != EstadoAplicado || r[0].ID == nil || *r[0].ID != ya || !strings.Contains(string(r[0].Descartados), "otra ruta") {
			t.Errorf("B1 tenía que cerrarse como aplicado con el id (%s) y lo que se cayó DEL LIBRO: %+v", ya, r)
		}
		f, _ := e.datos.RevisionApunteDeRevisor(ctx, sqlc.RevisionApunteDeRevisorParams{AparatoID: e.aparato.ID, Clave: "B1"})
		if f.Estado != sqlc.RevisionEstadoAplicado || deIdentificador(f.IDCreado) == nil || *deIdentificador(f.IDCreado) != ya ||
			f.DecididoPor == nil || *f.DecididoPor != "admin-1" {
			t.Errorf("la fila de la bandeja: %+v", f)
		}
		if d := e.decisiones(e.aparato.ID, "B1"); len(d) != 1 || d[0].Resultado != "aplicado" || d[0].Motivo == nil || !strings.Contains(*d[0].Motivo, "no se reenvió") {
			t.Errorf("el libro de decisiones tiene que decir que no se reenvió: %+v", d)
		}

		w = e.aplicarUno(e.aparato.ID, "B2", nil)
		e.esperar(w, http.StatusOK, "")
		if r := resultadosDe(t, w).Resultados; len(r) != 1 || r[0].Estado != "rechazado" || r[0].Motivo != "Ese pedido ya va en otra ruta." {
			t.Errorf("B2 (rechazada por la subida normal) tenía que quedar rechazada con el LITERAL: %+v", r)
		}
		e.sinAplicar() // ← NINGUNA de las dos se reenvió

		// La pareja: una clave que NO está en el libro se aplica como siempre.
		e.esperar(e.aplicarUno(e.aparato.ID, "B3", nil), http.StatusOK, "")
		e.llamadasEn("B3")

		// Y en «aplicar todo en orden» pasa lo mismo, sin parar en lo ya resuelto.
		e.entrega.Jti = "jti-otra-pulsacion-" + uuid.NewString() // otra pulsación del botón = otra entrega
		ent2 := e.entregaDeLaPersona("B4", "B5")
		if _, err := e.datos.AnotarApunteAplicado(ctx, sqlc.AnotarApunteAplicadoParams{AparatoID: e.aparato.ID, Clave: "B4",
			Metodo: "POST", Ruta: "/routes", HechoAt: marca(e.reloj)}); err != nil {
			t.Fatal(err)
		}
		_, s := e.aplicarEntrega(ent2)
		if len(s.Resultados) != 2 || s.Detenido {
			t.Errorf("aplicar en orden: %+v", s)
		}
		e.llamadasEn("B3", "B5")
	})
}

// La red por si la subida normal de un sync viejo se cuela ENTRE mirar el libro y escribirlo: el INSERT es
// `ON CONFLICT DO NOTHING` y la transacción NO se cae (la fila que ya estaba cuenta lo mismo). Se dice en el
// registro, porque el reparto recibió el apunte dos veces.
func TestSiLaSubidaViejaSeColaEntreMirarYEscribirNoSeCaeLaTransaccion(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		e.entregaDeLaPersona("C1")
		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)
		colada := uuid.New()
		e.aplicador.responde = func(Peticion) (*uuid.UUID, error) {
			if _, err := e.datos.AnotarApunteAplicado(context.Background(), sqlc.AnotarApunteAplicadoParams{AparatoID: e.aparato.ID,
				Clave: "C1", Metodo: "POST", Ruta: "/routes", IDCreado: identificador(colada), HechoAt: marca(e.reloj)}); err != nil {
				t.Fatal(err)
			}
			id := uuid.New()
			return &id, nil
		}
		e.esperar(e.aplicarUno(e.aparato.ID, "C1", nil), http.StatusOK, "")
		if e.estadoDe(e.aparato.ID, "C1") != sqlc.RevisionEstadoAplicado {
			t.Error("el INSERT en conflicto dejó la fila sin cerrar")
		}
		if libro, err := e.datos.BuscarApunte(context.Background(), sqlc.BuscarApunteParams{AparatoID: e.aparato.ID, Clave: "C1"}); err != nil ||
			*deIdentificador(libro.IDCreado) != colada {
			t.Errorf("la fila que ya estaba en el libro no se pisa: %+v %v", libro, err)
		}
		if !strings.Contains(e.log.String(), "DOS VECES") {
			t.Errorf("tiene que quedar en el registro que se aplicó dos veces: %s", e.log.String())
		}
	})
}

// ---------------------------------------------------------------------------
// 7 · Un aplicando interrumpido
// ---------------------------------------------------------------------------

func TestUnAplicandoRecienteNoSePuedeTomarNiConfirmando(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		e.entregaDeLaPersona("I1")
		if _, err := e.datos.ReclamarRevisionApunte(context.Background(), sqlc.ReclamarRevisionApunteParams{
			Revisor: "revisor-que-lo-esta-aplicando", AparatoID: e.aparato.ID, Clave: "I1"}); err != nil {
			t.Fatal(err)
		}
		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)
		e.esperar(e.aplicarUno(e.aparato.ID, "I1", nil), http.StatusConflict, CodigoYaSeEstaAplicando)
		e.esperar(e.aplicarUno(e.aparato.ID, "I1", map[string]bool{"reintentarInterrumpido": true}), http.StatusConflict, CodigoYaSeEstaAplicando)
		e.esperar(e.descartar(e.aparato.ID, "I1", map[string]string{"motivo": "no hacía falta"}), http.StatusConflict, CodigoYaSeEstaAplicando)
		e.sinAplicar()
		if got := e.estadoDe(e.aparato.ID, "I1"); got != sqlc.RevisionEstadoAplicando {
			t.Errorf("estado %s", got)
		}
	})
}

// Con el doble se puede envejecer la fila (en Postgres, dentro de una transacción, `now()` no avanza).
func TestUnAplicandoInterrumpidoSeReintentaSoloConfirmandolo(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	base := e.datos.(*baseRevisionFalsa)
	e.entregaDeLaPersona("V1")
	ctx := context.Background()
	if _, err := e.datos.ReclamarRevisionApunte(ctx, sqlc.ReclamarRevisionApunteParams{
		Revisor: "revisor-que-murio", AparatoID: e.aparato.ID, Clave: "V1"}); err != nil {
		t.Fatal(err)
	}
	k := llave(e.aparato.ID, "V1")
	a := base.m.apuntes[k]
	vieja := marca(enPuntoFijo().Add(-time.Hour))
	a.UpdatedAt, a.DecididoAt = vieja, vieja
	base.m.apuntes[k] = a

	e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)
	// La bandeja lo marca `interrumpido`.
	_, d := e.detalle(a.EntregaID)
	if len(d.Apuntes) != 1 || !d.Apuntes[0].Interrumpido || d.Apuntes[0].Estado != "aplicando" {
		t.Errorf("tenía que verse interrumpido: %+v", d.Apuntes)
	}
	// Sin confirmar: 409 y el reparto no se entera.
	e.esperar(e.aplicarUno(e.aparato.ID, "V1", nil), http.StatusConflict, CodigoYaSeEstaAplicando)
	e.sinAplicar()
	// Confirmando que se comprobó a mano: se aplica, y el libro cuenta que el intento anterior se interrumpió.
	e.esperar(e.aplicarUno(e.aparato.ID, "V1", map[string]bool{"reintentarInterrumpido": true}), http.StatusOK, "")
	if len(e.aplicador.llamadas) != 1 || e.estadoDe(e.aparato.ID, "V1") != sqlc.RevisionEstadoAplicado {
		t.Fatalf("no se aplicó: %d llamadas", len(e.aplicador.llamadas))
	}
	dec := e.decisiones(e.aparato.ID, "V1")
	if len(dec) != 2 || dec[0].Resultado != "interrumpido" || dec[0].Por != "admin-1" || dec[1].Resultado != "aplicado" {
		t.Errorf("el libro: %+v", dec)
	}
}

// ---------------------------------------------------------------------------
// 8 · La pareja: la subida normal no cambió
// ---------------------------------------------------------------------------

func TestLaSubidaNormalNoMandaNadaDeLaRevision(t *testing.T) {
	e := nuevoEntorno(t, "doble", nuevaBaseConRevision(nuevaBase()))
	_, res := e.normalSubir(apunteEntrada{Clave: "U1", Hecho: e.reloj.Add(-time.Hour), Metodo: "POST", Ruta: "/routes", Cuerpo: json.RawMessage(`{}`)})
	if res[0].Estado != EstadoAplicado || len(e.aplicador.llamadas) != 1 {
		t.Fatalf("%+v", res)
	}
	p := e.aplicador.llamadas[0]
	if p.Autor != "" || p.Revision != "" || p.SucursalPedida != uuid.Nil {
		t.Errorf("la subida normal mandó cosas de la revisión: autor=%q revision=%q sucursalPedida=%s", p.Autor, p.Revision, p.SucursalPedida)
	}
	if p.Token != "token-normal" || p.Sucursal != e.sucursal || p.Persona != e.persona {
		t.Errorf("la subida normal firma la persona con su token y su sucursal: %+v", p)
	}
}

// ---------------------------------------------------------------------------
// 9 · Arreglos que halló la app (G-APP1): el provisional y el `repetido`
// ---------------------------------------------------------------------------

// El UUIDv7 que el Tablero manda como `provisional` al crear una zona es un id DEFINITIVO que puso el aparato:
// la subida normal lo acepta (no valida su forma), así que la entrega no puede tumbarlo con un 422. Y las dos
// reglas no pueden separarse: lo que la subida sabe TRADUCIR (`reProvisional`) nunca queda fuera de la entrega.
func TestElProvisionalDeLaRevisionEsComoElDeLaSubida(t *testing.T) {
	v7, err := uuid.NewV7()
	if err != nil {
		t.Fatal(err)
	}
	buenos := []string{"local-9f3a2b7c", "local-A1", uuid.NewString(), v7.String(), strings.ToUpper(v7.String()), "local-" + strings.Repeat("a", 94)}
	malos := []string{"local-" + strings.Repeat("a", 95), "local-", "no-es-local", "local-a-b", "local-ñ", "local- x", "local\nx", "a b",
		"a/b", "local-1;DROP", "01J9ZQ3K8M4N5P6R7S8T9V0W1X", v7.String()[1:], v7.String() + "0"}
	for _, s := range buenos {
		if !reProvisionalDeRevision.MatchString(s) {
			t.Errorf("%q: lo acepta la subida y la entrega lo rechazaba", s)
		}
	}
	for _, s := range malos {
		if reProvisionalDeRevision.MatchString(s) {
			t.Errorf("%q: la entrega lo dejó pasar", s)
		}
	}

	// LA ATADURA: todo lo que la subida traduce entero (`local-` + letras y números, hasta el tope) cabe en la
	// entrega. Si alguien estrecha una de las dos regex, esto se pone rojo.
	traducible := regexp.MustCompile("^(?:" + reProvisional.String() + ")$")
	azar := rand.New(rand.NewSource(7))
	alfabeto := []rune("local-ABCxyz019_.:- ñ/")
	for i := 0; i < 5000; i++ {
		n := 1 + azar.Intn(30)
		r := make([]rune, n)
		for j := range r {
			r[j] = alfabeto[azar.Intn(len(alfabeto))]
		}
		s := string(r)
		if i%3 == 0 {
			s = "local-" + s
		}
		if traducible.MatchString(s) && !reProvisionalDeRevision.MatchString(s) {
			t.Fatalf("%q lo traduce la subida y la entrega lo rechaza: las dos reglas se separaron", s)
		}
	}

	// DE PUNTA A PUNTA, en los dos motores: lo que la subida normal aplica con ese provisional, la entrega lo
	// admite; y un revisor lo aplica y el provisional queda anotado con el id de verdad.
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		for i, p := range buenos {
			clave := fmt.Sprintf("PV%d", i)
			_, res := e.normalSubir(apunteEntrada{Clave: clave + "s", Hecho: e.reloj.Add(-time.Hour), Metodo: "POST",
				Ruta: "/routes", Cuerpo: json.RawMessage(`{}`), Provisional: p})
			if res[0].Estado != EstadoAplicado {
				t.Fatalf("la subida normal con provisional %q: %+v", p, res[0])
			}
			w, salida := e.entregar(e.ap(clave, map[string]any{"provisional": p}))
			e.esperar(w, http.StatusOK, "")
			if salida.Resultados[0].Estado != EstadoEnRevision {
				t.Errorf("la entrega con provisional %q: %+v", p, salida.Resultados[0])
			}
		}
		for _, p := range malos {
			w, _ := e.entregar(e.ap("PVMALO", map[string]any{"provisional": p}))
			e.esperar(w, http.StatusUnprocessableEntity, CodigoEntregaNoAdmitida)
		}
		if n := e.cuantas(); n != len(buenos) {
			t.Errorf("filas en la bandeja: %d, se esperaban %d (los malos no guardan nada)", n, len(buenos))
		}
		// El UUIDv7 de una zona, aplicado por un revisor: queda anotado como provisional del id que creó.
		zona, _ := uuid.NewV7()
		w, _ := e.entregar(e.ap("ZONA", map[string]any{"provisional": zona.String()}))
		e.esperar(w, http.StatusOK, "")
		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)
		creada := uuid.New()
		e.aplicador.responde = func(Peticion) (*uuid.UUID, error) { return &creada, nil }
		e.esperar(e.aplicarUno(e.aparato.ID, "ZONA", nil), http.StatusOK, "")
		if id, err := e.datos.ResolverProvisional(context.Background(), sqlc.ResolverProvisionalParams{AparatoID: e.aparato.ID, Provisional: zona.String()}); err != nil || id != creada {
			t.Errorf("el UUIDv7 tenía que quedar anotado como provisional de %s: %v %v", creada, id, err)
		}
	})
}

// El `repetido` de una entrega lleva el id de lo que creó el apunte (y lo que se cayó) venga de donde venga:
// del libro de la subida normal o de la revisión. Y el de un descartado, además de la frase de siempre, quién y
// el texto por separado. Todo aditivo: `motivo` sigue siendo la frase.
func TestElRepetidoDeLaEntregaLlevaElIdYLosDescartados(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		porLaSubida, porLaRevision := uuid.New(), uuid.New()
		e.aplicador.responde = func(p Peticion) (*uuid.UUID, error) {
			switch p.Clave {
			case "L1":
				return &porLaSubida, nil
			case "L3":
				return &porLaRevision, nil
			}
			return nil, nil
		}
		e.aplicador.descarta = func(p Peticion) json.RawMessage {
			if p.Clave == "L1" || p.Clave == "L3" {
				return json.RawMessage(`[{"pedido":"p7","motivo":"ya va en otra ruta"}]`)
			}
			return nil
		}
		hecho := e.reloj.Add(-time.Hour)

		// (a) La subida normal aplica L1 y rechaza L2; después alguien intenta ENTREGARLAS: `repetido` del libro.
		_, res := e.normalSubir(
			apunteEntrada{Clave: "L1", Hecho: hecho, Metodo: "POST", Ruta: "/routes", Cuerpo: json.RawMessage(`{}`), Provisional: "local-L1"},
			apunteEntrada{Clave: "L2", Hecho: hecho, Metodo: "PUT", Ruta: "/routes/local-nadie", Cuerpo: json.RawMessage(`{}`)},
		)
		if res[0].Estado != EstadoAplicado || res[1].Estado != EstadoRechazado {
			t.Fatalf("la subida normal: %+v", res)
		}
		w, salida := e.entregar(e.ap("L1"), e.ap("L2", map[string]any{"metodo": "PUT", "ruta": "/routes/local-nadie", "provisional": nil}))
		e.esperar(w, http.StatusOK, "")
		l1, l2 := salida.Resultados[0], salida.Resultados[1]
		if l1.Estado != EstadoRepetido || l1.EstadoActual != "aplicado" || l1.ID == nil || *l1.ID != porLaSubida ||
			!strings.Contains(string(l1.Descartados), "otra ruta") {
			t.Errorf("el repetido del LIBRO tenía que llevar el id (%s) y lo que se cayó: %+v", porLaSubida, l1)
		}
		if l2.Estado != EstadoRepetido || l2.EstadoActual != "rechazado" || l2.ID != nil || !strings.Contains(l2.Motivo, "local-nadie") {
			t.Errorf("un rechazado no lleva id y sí su motivo: %+v", l2)
		}

		// (b) Entregan L3 y L4; un revisor aplica L3 y descarta L4; reenvían lo mismo: `repetido` de la revisión.
		w, _ = e.entregar(e.ap("L3"), e.ap("L4"))
		e.esperar(w, http.StatusOK, "")
		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)
		e.esperar(e.aplicarUno(e.aparato.ID, "L3", nil), http.StatusOK, "")
		e.esperar(e.descartar(e.aparato.ID, "L4", map[string]string{"motivo": "Lo rehace con permiso"}), http.StatusOK, "")
		w, salida = e.entregar(e.ap("L3"), e.ap("L4"))
		e.esperar(w, http.StatusOK, "")
		l3, l4 := salida.Resultados[0], salida.Resultados[1]
		if l3.Estado != EstadoRepetido || l3.EstadoActual != "aplicado" || l3.ID == nil || *l3.ID != porLaRevision ||
			!strings.Contains(string(l3.Descartados), "otra ruta") || l3.DecididoPorNombre != "Marta Pérez" || l3.DecididoAt == nil {
			t.Errorf("el repetido de lo aplicado por revisión: %+v", l3)
		}
		frase := "Descartado en la revisión por Marta Pérez: Lo rehace con permiso"
		if l4.Estado != EstadoRepetido || l4.EstadoActual != "descartado" || l4.ID != nil {
			t.Errorf("el repetido de lo descartado: %+v", l4)
		}
		if l4.Motivo != frase {
			t.Errorf("`motivo` sigue siendo la frase ya montada (la app la lee): %q", l4.Motivo)
		}
		if l4.DecididoPorNombre != "Marta Pérez" || l4.MotivoDelDescarte != "Lo rehace con permiso" || l4.DecididoAt == nil {
			t.Errorf("quién y el texto, por separado: %+v", l4)
		}

		// (c) Lo mismo por la subida normal (paso 0): la frase de siempre y, además, lo separado.
		e.normal = identidad.Identidad{Persona: e.persona, Sucursal: e.sucursal, Token: "token-normal"}
		_, res = e.normalSubir(apunteEntrada{Clave: "L4", Hecho: hecho, Metodo: "POST", Ruta: "/routes", Cuerpo: json.RawMessage(`{}`), Provisional: "local-L4"})
		if res[0].Estado != EstadoRepetido || res[0].Motivo != frase || res[0].DecididoPorNombre != "Marta Pérez" || res[0].MotivoDelDescarte != "Lo rehace con permiso" {
			t.Errorf("el repetido de la subida normal para un descartado: %+v", res[0])
		}
		// Y lo que no es un descarte no trae esos campos.
		_, res = e.normalSubir(apunteEntrada{Clave: "L3", Hecho: hecho, Metodo: "POST", Ruta: "/routes", Cuerpo: json.RawMessage(`{}`), Provisional: "local-L3"})
		if res[0].DecididoPorNombre != "" || res[0].MotivoDelDescarte != "" || res[0].ID == nil || *res[0].ID != porLaRevision {
			t.Errorf("el repetido de lo aplicado: %+v", res[0])
		}
	})
}

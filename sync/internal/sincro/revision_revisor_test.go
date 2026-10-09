package sincro

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-sync/internal/identidad"
	"procovar/reparto-sync/internal/store"
	"procovar/reparto-sync/internal/store/sqlc"
)

// LA BANDEJA DEL REVISOR (`docs/bandeja-de-revision.md`, S2): listar, ver el original, descartar y QUIÉN puede.
// Las que importan, por orden:
//
//  1. Sólo ADMINISTRADOR / SUPER ADMIN / DESARROLLADOR, con token; un LOGISTICO no. Por nombre de rol.
//  2. El ALCANCE, por lista y por id: el ADMINISTRADOR de CAM no ve ni toca lo de HOL.
//  3. NADIE REVISA LO SUYO.
//  4. Descartar exige motivo, se ESCRIBE con quién y cuándo, y no borra nada.
//
// Casi todas corren dos veces: contra el doble y, con `SYNC_MOTOR_REAL_DSN`, contra Postgres de verdad.

// ---------------------------------------------------------------------------
// Los dobles de las consultas nuevas de S2
// ---------------------------------------------------------------------------

func (b *baseRevisionFalsa) ListarEntregasParaRevisor(_ context.Context, arg sqlc.ListarEntregasParaRevisorParams) ([]sqlc.ListarEntregasParaRevisorRow, error) {
	porEntrega := map[uuid.UUID]*sqlc.ListarEntregasParaRevisorRow{}
	for _, a := range b.m.apuntes {
		e := b.m.entregas[a.EntregaID]
		if !cuadraSucursal(arg.Sucursal, e.BranchID) {
			continue
		}
		f := porEntrega[e.ID]
		if f == nil {
			f = &sqlc.ListarEntregasParaRevisorRow{
				ID: e.ID, AparatoID: e.AparatoID, AparatoNombre: nombreEnLaBandeja(b.baseFalsa.aparatos[e.AparatoID].Nombre), Persona: e.Persona,
				PersonaNombre: e.PersonaNombre, BranchID: e.BranchID, EntregadaAt: e.EntregadaAt, VersionApp: e.VersionApp,
			}
			porEntrega[e.ID] = f
		}
		switch a.Estado {
		case sqlc.RevisionEstadoEnRevision:
			f.EnRevision++
		case sqlc.RevisionEstadoAplicando:
			f.Aplicando++
		case sqlc.RevisionEstadoRechazado:
			f.Rechazados++
		case sqlc.RevisionEstadoAplicado:
			f.Aplicados++
		case sqlc.RevisionEstadoDescartado:
			f.Descartados++
		}
	}
	var filas []sqlc.ListarEntregasParaRevisorRow
	for _, f := range porEntrega {
		if f.EnRevision+f.Aplicando+f.Rechazados > 0 { // HAVING: sólo las que aún tienen algo esperando
			filas = append(filas, *f)
		}
	}
	sort.Slice(filas, func(i, j int) bool { // ORDER BY e.entregada_at, e.id
		if !filas[i].EntregadaAt.Time.Equal(filas[j].EntregadaAt.Time) {
			return filas[i].EntregadaAt.Time.Before(filas[j].EntregadaAt.Time)
		}
		return filas[i].ID.String() < filas[j].ID.String()
	})
	if int32(len(filas)) > arg.Limite {
		filas = filas[:arg.Limite]
	}
	return filas, nil
}

func (b *baseRevisionFalsa) RevisionEntregaPorId(_ context.Context, id uuid.UUID) (sqlc.RevisionEntregaPorIdRow, error) {
	e, hay := b.m.entregas[id]
	if !hay {
		return sqlc.RevisionEntregaPorIdRow{}, pgx.ErrNoRows
	}
	return sqlc.RevisionEntregaPorIdRow{ID: e.ID, Persona: e.Persona, BranchID: e.BranchID}, nil
}

// ---------------------------------------------------------------------------
// Ayudas
// ---------------------------------------------------------------------------

// comoRevisor: quien llama por la fuente NORMAL es esta persona, con este rol, de esta sucursal.
func (e *entorno) comoRevisor(persona, rol string, sucursal uuid.UUID) {
	e.normal = identidad.Identidad{Persona: persona, Nombre: "Marta Pérez", Sucursal: sucursal,
		Token: "token-de-" + persona, Roles: []string{rol}}
}

// comoRevisorDeTodas: SUPER ADMIN / DESARROLLADOR sin sucursal en el token (ven las ocho).
func (e *entorno) comoRevisorDeTodas(persona, rol string) {
	e.normal = identidad.Identidad{Persona: persona, Nombre: "Jose", EsSuperAdmin: true,
		Token: "token-de-" + persona, Roles: []string{rol}}
}

// entregarDeOtro: otra persona, de otra sucursal, entrega estos apuntes (por su camino de verdad). Devuelve su
// aparato y el id de su entrega.
func (e *entorno) entregarDeOtro(persona string, sucursal uuid.UUID, claves ...string) (sqlc.Aparato, uuid.UUID) {
	e.t.Helper()
	ctx := context.Background()
	aparato, err := e.datos.AltaAparato(ctx, sqlc.AltaAparatoParams{Persona: persona, BranchID: sucursal})
	if err != nil {
		e.t.Fatal(err)
	}
	if err := e.datos.AbrirEstado(ctx, aparato.ID); err != nil {
		e.t.Fatal(err)
	}
	entrega0, aparato0 := e.entrega, e.aparato
	defer func() { e.entrega, e.aparato = entrega0, aparato0 }()
	e.entrega = identidad.Identidad{Persona: persona, Nombre: "Otro", Sucursal: sucursal, Jti: "jti-" + uuid.NewString(), Ambito: identidad.AmbitoEntrega}
	e.aparato = aparato
	var apuntes []map[string]any
	for _, c := range claves {
		apuntes = append(apuntes, e.ap(c))
	}
	w, salida := e.entregar(apuntes...)
	e.esperar(w, http.StatusOK, "")
	return aparato, *salida.Resultados[0].Revision
}

func (e *entorno) entregaDeLaPersona(claves ...string) uuid.UUID {
	e.t.Helper()
	var apuntes []map[string]any
	for _, c := range claves {
		apuntes = append(apuntes, e.ap(c))
	}
	w, salida := e.entregar(apuntes...)
	e.esperar(w, http.StatusOK, "")
	return *salida.Resultados[0].Revision
}

func (e *entorno) lista(query string) (*httptest.ResponseRecorder, bandejaSalida) {
	e.t.Helper()
	w := e.pedir(http.MethodGet, "/sync/revision"+query, nil)
	var s bandejaSalida
	if w.Code == http.StatusOK {
		if err := json.Unmarshal(w.Body.Bytes(), &s); err != nil {
			e.t.Fatalf("la bandeja no se entiende: %v (%s)", err, w.Body.String())
		}
	}
	return w, s
}

func (e *entorno) detalle(entrega uuid.UUID) (*httptest.ResponseRecorder, detalleSalida) {
	e.t.Helper()
	w := e.pedir(http.MethodGet, "/sync/revision/"+entrega.String(), nil)
	var s detalleSalida
	if w.Code == http.StatusOK {
		if err := json.Unmarshal(w.Body.Bytes(), &s); err != nil {
			e.t.Fatalf("el detalle no se entiende: %v (%s)", err, w.Body.String())
		}
	}
	return w, s
}

func (e *entorno) descartar(aparato uuid.UUID, clave string, cuerpo any) *httptest.ResponseRecorder {
	return e.pedir(http.MethodPost, "/sync/revision/"+aparato.String()+"/"+clave+"/descartar", cuerpo)
}

func (e *entorno) estadoDe(aparato uuid.UUID, clave string) sqlc.RevisionEstado {
	e.t.Helper()
	f, err := e.datos.EstadoDeRevisionDeApunte(context.Background(), sqlc.EstadoDeRevisionDeApunteParams{AparatoID: aparato, Clave: clave})
	if err != nil {
		e.t.Fatalf("%s: %v", clave, err)
	}
	return f.Estado
}

func (e *entorno) decisiones(aparato uuid.UUID, clave string) []sqlc.RevisionDecisione {
	e.t.Helper()
	d, err := e.datos.RevisionDecisionesDeApunte(context.Background(), sqlc.RevisionDecisionesDeApunteParams{AparatoID: aparato, Clave: clave})
	if err != nil {
		e.t.Fatal(err)
	}
	return d
}

func claves(a []apunteDelRevisor) []string {
	var s []string
	for _, x := range a {
		s = append(s, x.Clave)
	}
	return s
}

// ---------------------------------------------------------------------------
// 1 · Quién puede
// ---------------------------------------------------------------------------

// Un LOGISTICO entra a Reparto pero NO revisa; ni nadie sin token, ni el token de entrega. En CADA ruta, y sin
// que el reparto vea nada.
func TestSoloRevisanAdministradorSuperAdminYDesarrollador(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		ent := e.entregaDeLaPersona("Q1", "Q2")
		quienes := map[string]identidad.Identidad{
			"LOGISTICO": {Persona: "r-1", Sucursal: e.sucursal, Token: "t", Roles: []string{"LOGISTICO"}},
			"GERENTE":   {Persona: "r-1", Sucursal: e.sucursal, Token: "t", Roles: []string{"GERENTE"}},
			"sin token": {Persona: "r-1", Sucursal: e.sucursal, Roles: []string{"ADMINISTRADOR"}},
			"sin roles": {Persona: "r-1", Sucursal: e.sucursal, Token: "t"},
			"token de entrega": {Persona: "r-1", Sucursal: e.sucursal, Token: "t", Roles: []string{"ADMINISTRADOR"},
				Ambito: identidad.AmbitoEntrega},
		}
		for nombre, q := range quienes {
			e.normal = q
			peticiones := map[string]*httptest.ResponseRecorder{
				"lista":           e.pedir(http.MethodGet, "/sync/revision", nil),
				"detalle":         e.pedir(http.MethodGet, "/sync/revision/"+ent.String(), nil),
				"aplicar":         e.pedir(http.MethodPost, "/sync/revision/"+e.aparato.ID.String()+"/Q1/aplicar", nil),
				"aplicar entrega": e.pedir(http.MethodPost, "/sync/revision/"+ent.String()+"/aplicar", nil),
				"descartar":       e.descartar(e.aparato.ID, "Q1", map[string]string{"motivo": "no hacía falta"}),
			}
			for que, w := range peticiones {
				if w.Code != http.StatusForbidden || !strings.Contains(w.Body.String(), CodigoNoRevisa) {
					t.Errorf("%s · %s: contestó %d %s; se esperaba 403 %s", nombre, que, w.Code, w.Body.String(), CodigoNoRevisa)
				}
			}
		}
		e.sinAplicar()
		for _, c := range []string{"Q1", "Q2"} {
			if e.estadoDe(e.aparato.ID, c) != sqlc.RevisionEstadoEnRevision {
				t.Errorf("%s cambió de estado sin que nadie pudiera revisar", c)
			}
		}
		if n := len(e.decisiones(e.aparato.ID, "Q1")); n != 0 {
			t.Errorf("el libro tiene %d anotaciones de quien no podía decidir", n)
		}

		// Y los tres que sí, entran.
		for _, rol := range []string{"ADMINISTRADOR", "SUPER ADMIN", "DESARROLLADOR"} {
			e.comoRevisor("r-ok", rol, e.sucursal)
			if w, _ := e.lista(""); w.Code != http.StatusOK {
				t.Errorf("%s no puede listar: %d %s", rol, w.Code, w.Body.String())
			}
		}
	})
}

// ---------------------------------------------------------------------------
// 2 · El alcance, por lista Y por id
// ---------------------------------------------------------------------------

func TestElAdministradorDeUnaSucursalNoVeNiToca_LoDeOtra(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		cam, hol := e.sucursal, uuid.New()
		entCAM := e.entregaDeLaPersona("C1", "C2")
		apHOL, entHOL := e.entregarDeOtro("persona-de-hol", hol, "H1", "H2")

		// El ADMINISTRADOR de CAM.
		e.comoRevisor("admin-cam", "ADMINISTRADOR", cam)

		// POR LISTA: sólo ve lo suyo, y el parámetro NO le abre HOL.
		for _, q := range []string{"", "?sucursal=" + hol.String(), "?sucursal=" + cam.String()} {
			_, l := e.lista(q)
			if len(l.Entregas) != 1 || l.Entregas[0].ID != entCAM || l.Entregas[0].Sucursal != cam {
				t.Errorf("lista%s: %+v; el administrador de CAM sólo ve su entrega", q, l.Entregas)
			}
		}

		// POR ID: ni el detalle, ni aplicar, ni aplicar en orden, ni descartar.
		e.esperar(e.pedir(http.MethodGet, "/sync/revision/"+entHOL.String(), nil), http.StatusForbidden, CodigoSucursalAjena)
		e.esperar(e.pedir(http.MethodPost, "/sync/revision/"+apHOL.ID.String()+"/H1/aplicar", nil), http.StatusForbidden, CodigoSucursalAjena)
		e.esperar(e.pedir(http.MethodPost, "/sync/revision/"+entHOL.String()+"/aplicar", nil), http.StatusForbidden, CodigoSucursalAjena)
		e.esperar(e.descartar(apHOL.ID, "H1", map[string]string{"motivo": "no hacía falta"}), http.StatusForbidden, CodigoSucursalAjena)
		e.sinAplicar() // ← el reparto no vio NADA de HOL
		for _, c := range []string{"H1", "H2"} {
			if e.estadoDe(apHOL.ID, c) != sqlc.RevisionEstadoEnRevision {
				t.Errorf("%s (HOL) cambió de estado por mano de un administrador de CAM", c)
			}
		}
		if n := len(e.decisiones(apHOL.ID, "H1")); n != 0 {
			t.Errorf("el libro de HOL tiene %d anotaciones de un administrador de CAM", n)
		}
		// Algo que no existe es 404, no 403: la frase la elige la segunda lectura SIN alcance.
		e.esperar(e.pedir(http.MethodGet, "/sync/revision/"+uuid.NewString(), nil), http.StatusNotFound, CodigoNoEncontrado)
		e.esperar(e.pedir(http.MethodPost, "/sync/revision/"+apHOL.ID.String()+"/NOEXISTE/aplicar", nil), http.StatusNotFound, CodigoNoEncontrado)

		// El SUPER ADMIN (sin sucursal en el token) ve las dos y puede estrechar.
		e.comoRevisorDeTodas("super-1", "SUPER ADMIN")
		_, l := e.lista("")
		if len(l.Entregas) != 2 {
			t.Errorf("el super admin ve las dos: %+v", l.Entregas)
		}
		_, l = e.lista("?sucursal=" + hol.String())
		if len(l.Entregas) != 1 || l.Entregas[0].ID != entHOL {
			t.Errorf("?sucursal= estrecha: %+v", l.Entregas)
		}
		e.esperar(e.pedir(http.MethodGet, "/sync/revision?sucursal=basura", nil), http.StatusBadRequest, "")
		// Un DESARROLLADOR o SUPER ADMIN CON sucursal en el token es de UNA sucursal, como en el resto de sync.
		e.comoRevisor("super-con-sucursal", "SUPER ADMIN", cam)
		_, l = e.lista("")
		if len(l.Entregas) != 1 || l.Entregas[0].ID != entCAM {
			t.Errorf("un super admin con sucursal en el token ve sólo la suya: %+v", l.Entregas)
		}
	})
}

// ---------------------------------------------------------------------------
// 3 · Nadie revisa lo suyo
// ---------------------------------------------------------------------------

func TestNadieRevisaLoSuyo(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		ent := e.entregaDeLaPersona("M1", "M2")
		// La MISMA persona que lo hizo es ahora ADMINISTRADOR de esa sucursal: lo suyo no lo revisa.
		e.comoRevisor(e.persona, "ADMINISTRADOR", e.sucursal)

		e.esperar(e.pedir(http.MethodPost, "/sync/revision/"+e.aparato.ID.String()+"/M1/aplicar", nil), http.StatusForbidden, CodigoEsLoTuyo)
		e.esperar(e.pedir(http.MethodPost, "/sync/revision/"+ent.String()+"/aplicar", nil), http.StatusForbidden, CodigoEsLoTuyo)
		e.esperar(e.descartar(e.aparato.ID, "M1", map[string]string{"motivo": "no hacía falta"}), http.StatusForbidden, CodigoEsLoTuyo)
		e.sinAplicar()
		for _, c := range []string{"M1", "M2"} {
			if e.estadoDe(e.aparato.ID, c) != sqlc.RevisionEstadoEnRevision {
				t.Errorf("%s: un revisor decidió sobre lo suyo", c)
			}
		}
		if n := len(e.decisiones(e.aparato.ID, "M1")); n != 0 {
			t.Errorf("el libro tiene %d anotaciones de alguien revisando lo suyo", n)
		}
		// Ni siquiera siendo SUPER ADMIN: «nadie».
		e.comoRevisorDeTodas(e.persona, "SUPER ADMIN")
		e.esperar(e.pedir(http.MethodPost, "/sync/revision/"+e.aparato.ID.String()+"/M2/aplicar", nil), http.StatusForbidden, CodigoEsLoTuyo)
		e.sinAplicar()

		// La pareja: OTRA persona, con el mismo rol, sí puede.
		e.comoRevisor("otra-persona", "ADMINISTRADOR", e.sucursal)
		e.esperar(e.descartar(e.aparato.ID, "M1", map[string]string{"motivo": "no hacía falta"}), http.StatusOK, "")
	})
}

// ---------------------------------------------------------------------------
// 4 · El original exacto, y lo que se enseña
// ---------------------------------------------------------------------------

func TestElDetalleEnseñaElOriginalExactoYLasCuentas(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		// A mano, con espacios y orden de claves raros: lo que el revisor mira es lo que llegó, byte a byte.
		cuerpoRaro := `{ "z": 1,   "a": [3, 1, 2], "nombre": "Ruta de Camagüey ñandú" }`
		hecho := e.hechoHaceUnaHora()
		crudo := fmt.Sprintf(`{"aparato":%q,"version_app":"1.0.32","apuntes":[`+
			`{"clave":"X1","hecho":%q,"metodo":"POST","ruta":"/routes","cuerpo":%s,"provisional":"local-X1"},`+
			`{"clave":"X2","hecho":%q,"metodo":"DELETE","ruta":"/routes/local-X1"}]}`,
			e.aparato.ID.String(), hecho, cuerpoRaro, hecho)
		w, salida := e.entregarCuerpo(crudo)
		e.esperar(w, http.StatusOK, "")
		ent := *salida.Resultados[0].Revision

		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)
		w, d := e.detalle(ent)
		e.esperar(w, http.StatusOK, "")
		if got := claves(d.Apuntes); !reflect.DeepEqual(got, []string{"X1", "X2"}) {
			t.Fatalf("los apuntes, en orden FIFO: %v", got)
		}
		x1 := d.Apuntes[0]
		if x1.Cuerpo == nil || *x1.Cuerpo != cuerpoRaro {
			t.Errorf("EL CUERPO NO ES EL ORIGINAL:\n  llegó:  %s\n  se ve:  %v", cuerpoRaro, x1.Cuerpo)
		}
		if x1.Metodo != "POST" || x1.Ruta != "/routes" || x1.Estado != "en_revision" || x1.HechoAt == nil ||
			!x1.HechoAt.Equal(enPuntoFijo().Add(-time.Hour)) {
			t.Errorf("método, ruta, estado y la hora DEL APARATO: %+v", x1)
		}
		if d.Apuntes[1].Cuerpo != nil {
			t.Errorf("X2 no llevaba cuerpo: %v", d.Apuntes[1].Cuerpo)
		}
		c := d.Entrega
		if c.ID != ent || c.Persona != e.persona || c.PersonaNombre == nil || *c.PersonaNombre != "Yasmani" ||
			c.Sucursal != e.sucursal || c.Aparato != e.aparato.ID || c.EntregadaAt == nil || c.EnRevision != 2 {
			t.Errorf("quién, cuándo y desde qué aparato: %+v", c)
		}
		// La bandeja: una fila por entrega, con las cuentas.
		_, l := e.lista("")
		if len(l.Entregas) != 1 || l.Entregas[0].ID != ent || l.Entregas[0].EnRevision != 2 || l.Entregas[0].Persona != e.persona ||
			l.Entregas[0].VersionApp == nil || *l.Entregas[0].VersionApp != "1.0.32" || l.Truncado {
			t.Errorf("la bandeja: %+v", l)
		}
		e.sinAplicar()
	})
}

// Las cuentas son de TODA la entrega, no sólo de lo vivo; y una entrega totalmente decidida sale de la bandeja
// (pero no se borra: sigue en el detalle).
func TestLaBandejaCuentaTodoYSoloEnseñaLoQueEspera(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		ent := e.entregaDeLaPersona("L1", "L2", "L3")
		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)
		e.esperar(e.descartar(e.aparato.ID, "L1", map[string]string{"motivo": "no hacía falta"}), http.StatusOK, "")
		e.esperar(e.pedir(http.MethodPost, "/sync/revision/"+e.aparato.ID.String()+"/L2/aplicar", nil), http.StatusOK, "")
		_, l := e.lista("")
		if len(l.Entregas) != 1 || l.Entregas[0].EnRevision != 1 || l.Entregas[0].Aplicados != 1 || l.Entregas[0].Descartados != 1 {
			t.Errorf("las cuentas de TODA la entrega: %+v", l.Entregas)
		}
		e.esperar(e.descartar(e.aparato.ID, "L3", map[string]string{"motivo": "no hacía falta"}), http.StatusOK, "")
		if _, l := e.lista(""); len(l.Entregas) != 0 {
			t.Errorf("lo totalmente decidido ya no espera: %+v", l.Entregas)
		}
		w, d := e.detalle(ent)
		e.esperar(w, http.StatusOK, "")
		if len(d.Apuntes) != 3 || d.Entrega.Aplicados != 1 || d.Entrega.Descartados != 2 {
			t.Errorf("NADA SE BORRA: el detalle sigue teniendo los tres: %+v", d)
		}
	})
}

// ---------------------------------------------------------------------------
// 5 · Descartar
// ---------------------------------------------------------------------------

func TestDescartarExigeMotivoDeCincoLetras(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		e.entregaDeLaPersona("D1")
		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)
		sin := []any{nil, map[string]string{}, map[string]string{"motivo": ""}, map[string]string{"motivo": "   "},
			map[string]string{"motivo": "abcd"}, map[string]string{"motivo": "  abcd  "}, map[string]string{"motivo": "ñand"}}
		for _, cuerpo := range sin {
			w := e.descartar(e.aparato.ID, "D1", cuerpo)
			e.esperar(w, http.StatusUnprocessableEntity, CodigoMotivoObligatorio)
		}
		if e.estadoDe(e.aparato.ID, "D1") != sqlc.RevisionEstadoEnRevision || len(e.decisiones(e.aparato.ID, "D1")) != 0 {
			t.Error("un descarte sin motivo cambió algo")
		}
		// «ñand» son 5 bytes y 4 letras: no basta. «ñandú» son 5 letras: sí (se cuenta en caracteres, no en bytes).
		e.esperar(e.descartar(e.aparato.ID, "D1", map[string]string{"motivo": "ñandú"}), http.StatusOK, "")
	})
}

func TestDescartarSeEscribeConQuienYCuandoYNoBorraNada(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		ent := e.entregaDeLaPersona("E1", "E2")
		antes := e.cuantas()
		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)
		w := e.descartar(e.aparato.ID, "E1", map[string]string{"motivo": "  Lo rehace con permiso  "})
		e.esperar(w, http.StatusOK, "")
		var s resultadosSalida
		_ = json.Unmarshal(w.Body.Bytes(), &s)
		if len(s.Resultados) != 1 || s.Resultados[0].Estado != "descartado" || s.Resultados[0].Clave != "E1" ||
			s.Resultados[0].Motivo != "Lo rehace con permiso" || s.Resultados[0].DecididoAt == nil ||
			s.Resultados[0].DecididoPorNombre == nil || *s.Resultados[0].DecididoPorNombre != "Marta Pérez" {
			t.Errorf("la respuesta: %+v", s)
		}

		// NO SE BORRA: la fila sigue, con el original intacto, y dice quién, cuándo y por qué.
		if n := e.cuantas(); n != antes {
			t.Fatalf("filas: %d antes, %d después: DESCARTAR BORRÓ", antes, n)
		}
		f, err := e.datos.RevisionApunteDeRevisor(context.Background(), sqlc.RevisionApunteDeRevisorParams{AparatoID: e.aparato.ID, Clave: "E1"})
		if err != nil {
			t.Fatal(err)
		}
		if f.Estado != sqlc.RevisionEstadoDescartado || f.DecididoPor == nil || *f.DecididoPor != "admin-1" ||
			f.DecididoPorNombre == nil || *f.DecididoPorNombre != "Marta Pérez" || !f.DecididoAt.Valid ||
			f.Motivo == nil || *f.Motivo != "Lo rehace con permiso" || f.Cuerpo == nil || f.Ruta != "/routes" {
			t.Errorf("el descarte tiene que quedar ESCRITO con quién, cuándo y por qué, y con el original: %+v", f)
		}
		// El libro de decisiones.
		d := e.decisiones(e.aparato.ID, "E1")
		if len(d) != 1 || d[0].Accion != "descartar" || d[0].Resultado != "descartado" || d[0].Por != "admin-1" ||
			d[0].Rol == nil || *d[0].Rol != "ADMINISTRADOR" || d[0].Motivo == nil || *d[0].Motivo != "Lo rehace con permiso" {
			t.Errorf("el libro: %+v", d)
		}
		// Se ve en el detalle, con su motivo.
		_, det := e.detalle(ent)
		if det.Apuntes[0].Estado != "descartado" || det.Apuntes[0].Motivo == nil || *det.Apuntes[0].Motivo != "Lo rehace con permiso" ||
			det.Apuntes[0].DecididoPorNombre == nil {
			t.Errorf("el detalle: %+v", det.Apuntes[0])
		}
		// Una vez: otro descarte, o aplicarlo, es 409 y no reescribe nada.
		e.esperar(e.descartar(e.aparato.ID, "E1", map[string]string{"motivo": "otro motivo distinto"}), http.StatusConflict, CodigoYaDecidido)
		e.esperar(e.pedir(http.MethodPost, "/sync/revision/"+e.aparato.ID.String()+"/E1/aplicar", nil), http.StatusConflict, CodigoYaDecidido)
		e.sinAplicar()
		if g, _ := e.datos.RevisionApunteDeRevisor(context.Background(), sqlc.RevisionApunteDeRevisorParams{AparatoID: e.aparato.ID, Clave: "E1"}); g.Motivo == nil || *g.Motivo != "Lo rehace con permiso" {
			t.Error("un segundo descarte reescribió el motivo")
		}
		if len(e.decisiones(e.aparato.ID, "E1")) != 1 {
			t.Error("un descarte que no se hizo dejó rastro en el libro")
		}
		// La persona que reenvía por la subida normal recibe `repetido` CON el motivo (y no se aplica).
		e.normal = identidad.Identidad{Persona: e.persona, Sucursal: e.sucursal, Token: "token-normal"}
		_, res := e.normalSubir(apunteEntrada{Clave: "E1", Hecho: e.reloj.Add(-time.Hour), Metodo: "POST", Ruta: "/routes", Provisional: "local-E1"})
		if res[0].Estado != EstadoRepetido || !strings.Contains(res[0].Motivo, "Lo rehace con permiso") {
			t.Errorf("la subida normal de lo descartado: %+v", res[0])
		}
		e.sinAplicar()
	})
}

// ---------------------------------------------------------------------------
// 6 · Las consultas nuevas: el doble y Postgres, el mismo guion
// ---------------------------------------------------------------------------

func guionDeLaBandejaDelRevisor(t *testing.T, d store.Datos) []string {
	t.Helper()
	ctx := context.Background()
	var s []string
	anota := func(formato string, a ...any) { s = append(s, fmt.Sprintf(formato, a...)) }

	s1, s2 := uuid.New(), uuid.New()
	nombre := "Samsung de Palma"
	crear := func(persona string, sucursal uuid.UUID, nombre *string, claves ...string) sqlc.RevisionEntrega {
		a, _ := d.AltaAparato(ctx, sqlc.AltaAparatoParams{Persona: persona, BranchID: sucursal, Nombre: nombre})
		e, err := d.AltaRevisionEntrega(ctx, sqlc.AltaRevisionEntregaParams{AparatoID: a.ID, Persona: persona, BranchID: sucursal, TokenJti: "j-" + persona})
		if err != nil {
			t.Fatal(err)
		}
		for _, c := range claves {
			cu := `{}`
			if _, err := d.InsertarRevisionApunte(ctx, sqlc.InsertarRevisionApunteParams{AparatoID: a.ID, Clave: c, EntregaID: e.ID,
				Metodo: "POST", Ruta: "/routes", Cuerpo: &cu, HechoAt: marca(enPuntoFijo()), Huella: strings.Repeat("b", 64)}); err != nil {
				t.Fatal(err)
			}
		}
		return e
	}
	eA := crear("ana", s1, &nombre, "a1", "a2", "a3", "a4")
	crear("beto", s1, nil, "b1")
	eC := crear("carla", s2, nil, "c1", "c2")
	eD := crear("dani", s1, nil, "d1")

	// ana: a1 aplicado, a2 rechazado, a3 aplicando, a4 descartado. dani: todo descartado (ya no espera).
	rec := func(ap uuid.UUID, clave string) {
		if _, err := d.ReclamarRevisionApunte(ctx, sqlc.ReclamarRevisionApunteParams{Revisor: "rev", AparatoID: ap, Clave: clave}); err != nil {
			t.Fatal(err)
		}
	}
	ap := eA.AparatoID
	rec(ap, "a1")
	_, _ = d.CerrarRevisionComoAplicado(ctx, sqlc.CerrarRevisionComoAplicadoParams{AparatoID: ap, Clave: "a1", Revisor: "rev"})
	rec(ap, "a2")
	_, _ = d.CerrarRevisionComoRechazado(ctx, sqlc.CerrarRevisionComoRechazadoParams{AparatoID: ap, Clave: "a2", Revisor: "rev", Motivo: "no"})
	rec(ap, "a3")
	_, _ = d.DescartarRevisionApunte(ctx, sqlc.DescartarRevisionApunteParams{Revisor: "rev", Motivo: "no hacía falta", AparatoID: ap, Clave: "a4"})
	_, _ = d.DescartarRevisionApunte(ctx, sqlc.DescartarRevisionApunteParams{Revisor: "rev", Motivo: "no hacía falta", AparatoID: eD.AparatoID, Clave: "d1"})

	linea := func(f sqlc.ListarEntregasParaRevisorRow) string {
		n := "-"
		if f.AparatoNombre != "" {
			n = f.AparatoNombre
		}
		return fmt.Sprintf("%s suc=%v aparato=%s en=%d ap=%d re=%d aplicados=%d desc=%d", f.Persona, f.BranchID == s1, n,
			f.EnRevision, f.Aplicando, f.Rechazados, f.Aplicados, f.Descartados)
	}
	listar := func(etiqueta string, p sqlc.ListarEntregasParaRevisorParams) {
		filas, err := d.ListarEntregasParaRevisor(ctx, p)
		if err != nil {
			t.Fatal(err)
		}
		var ls []string
		for _, f := range filas {
			ls = append(ls, linea(f))
		}
		sort.Strings(ls)   // en una transacción de Postgres `entregada_at` empata y el desempate es el id al azar
		if p.Limite < 10 { // y con tope, CUÁLES caben depende de ese empate: sólo se compara cuántas
			ls = nil
		}
		anota("%s (%d): %s", etiqueta, len(filas), strings.Join(ls, " | "))
	}
	listar("todas", sqlc.ListarEntregasParaRevisorParams{Limite: 100})
	listar("sólo S1", sqlc.ListarEntregasParaRevisorParams{Sucursal: identificador(s1), Limite: 100})
	listar("sólo S2", sqlc.ListarEntregasParaRevisorParams{Sucursal: identificador(s2), Limite: 100})
	listar("tope 2", sqlc.ListarEntregasParaRevisorParams{Limite: 2})
	listar("otra sucursal", sqlc.ListarEntregasParaRevisorParams{Sucursal: identificador(uuid.New()), Limite: 100})

	for _, c := range []struct {
		etiqueta string
		id       uuid.UUID
	}{{"existe (S1)", eA.ID}, {"existe (S2)", eC.ID}, {"no existe", uuid.New()}} {
		f, err := d.RevisionEntregaPorId(ctx, c.id)
		switch {
		case store.SinFilas(err):
			anota("entrega %s: sin filas", c.etiqueta)
		case err != nil:
			anota("entrega %s: error", c.etiqueta)
		default:
			anota("entrega %s: persona=%s suc1=%v", c.etiqueta, f.Persona, f.BranchID == s1)
		}
	}

	// El libro: la primera copia escribe, la segunda (ON CONFLICT DO NOTHING) no, y la fila que ya estaba no se pisa.
	copia := func(id uuid.UUID) int64 {
		n, err := d.CopiarApunteAplicadoAlLibro(ctx, sqlc.CopiarApunteAplicadoAlLibroParams{AparatoID: eC.AparatoID, Clave: "c1",
			Metodo: "POST", Ruta: "/routes", IDCreado: identificador(id), HechoAt: marca(enPuntoFijo())})
		if err != nil {
			t.Fatal(err)
		}
		return n
	}
	primero := uuid.New()
	n1, n2 := copia(primero), copia(uuid.New())
	libro, err := d.BuscarApunte(ctx, sqlc.BuscarApunteParams{AparatoID: eC.AparatoID, Clave: "c1"})
	anota("libro: primera copia=%d segunda=%d estado=%s id_es_el_primero=%v err=%v", n1, n2, libro.Estado, deIdentificador(libro.IDCreado) != nil && *deIdentificador(libro.IDCreado) == primero, err)
	return s
}

func TestMotorRealElDobleDeLaBandejaDelRevisorHaceLoMismoQuePostgres(t *testing.T) {
	real := guionDeLaBandejaDelRevisor(t, datosEnPostgresReal(t))
	doble := guionDeLaBandejaDelRevisor(t, nuevaBaseConRevision(nuevaBase()))
	if len(real) != len(doble) {
		t.Fatalf("el guion dio %d líneas en Postgres y %d en el doble", len(real), len(doble))
	}
	for i := range real {
		if real[i] != doble[i] {
			t.Errorf("EL DOBLE MIENTE en el paso %d:\n  Postgres: %s\n  doble:    %s", i, real[i], doble[i])
		}
	}
	if t.Failed() {
		t.Logf("todo el guion de Postgres:\n%s", strings.Join(real, "\n"))
	}
}

// nombreEnLaBandeja es el `COALESCE(left(p.nombre, 200), ”)` de las consultas del revisor.
func nombreEnLaBandeja(n *string) string {
	if n == nil {
		return ""
	}
	if r := []rune(*n); len(r) > 200 {
		return string(r[:200])
	}
	return *n
}

// ---------------------------------------------------------------------------
// 7 · Arreglos de la auditoría de seguridad (09/10/2026)
// ---------------------------------------------------------------------------

// M3 · El nombre de un aparato lo manda el aparato. Antes llegaba entero —hasta los 32 MiB del cuerpo— al
// panel y a la bandeja del revisor.
func TestElNombreDelAparatoSeLimpiaYSeRecortaAlDarloDeAlta(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		enorme := strings.Repeat("ñandú ", 900_000)[:5<<20] + "\x00\x07fin"
		w := e.pedir(http.MethodPost, "/sync/aparato", map[string]any{"nombre": enorme})
		e.esperar(w, http.StatusCreated, "")
		var alta altaSalida
		if err := json.Unmarshal(w.Body.Bytes(), &alta); err != nil {
			t.Fatal(err)
		}
		if alta.Nombre == nil || utf8.RuneCountInString(*alta.Nombre) > topeNombreDeAparato || strings.ContainsAny(*alta.Nombre, "\x00\x07") {
			t.Fatalf("EL NOMBRE DE 5 MiB LLEGÓ ENTERO: %d bytes en la respuesta", len(w.Body.Bytes()))
		}
		guardado, err := e.datos.AparatoPorId(context.Background(), alta.Aparato)
		if err != nil || guardado.Nombre == nil || utf8.RuneCountInString(*guardado.Nombre) != topeNombreDeAparato {
			t.Errorf("lo guardado: %v %v", guardado.Nombre, err)
		}
		// Un nombre normal pasa tal cual; uno que se queda vacío es «sin nombre».
		for nombre, quiere := range map[string]string{"el Samsung de Palma": "el Samsung de Palma", "  \x00 ": ""} {
			w := e.pedir(http.MethodPost, "/sync/aparato", map[string]any{"nombre": nombre})
			e.esperar(w, http.StatusCreated, "")
			var a altaSalida
			_ = json.Unmarshal(w.Body.Bytes(), &a)
			if (quiere == "") != (a.Nombre == nil) || (a.Nombre != nil && *a.Nombre != quiere) {
				t.Errorf("nombre %q → %v, se esperaba %q", nombre, a.Nombre, quiere)
			}
		}
	})
}

// La red debajo (00004): ni un alta torcida ni una mano en la base meten un nombre de más de 200 letras. Sólo
// tiene sentido contra Postgres.
func TestMotorRealLaBaseAcotaElNombreDelAparato(t *testing.T) {
	d := datosEnPostgresReal(t).(*datosEnTx)
	ctx := context.Background()
	cuyo := func(n int) error {
		nombre := strings.Repeat("ñ", n)
		return d.EnTransaccion(ctx, func(q sqlc.Querier) error {
			_, err := q.AltaAparato(ctx, sqlc.AltaAparatoParams{Persona: "p", BranchID: uuid.New(), Nombre: &nombre})
			return err
		})
	}
	if err := cuyo(200); err != nil {
		t.Errorf("200 letras tenían que caber: %v", err)
	}
	if err := cuyo(201); err == nil || !strings.Contains(err.Error(), "aparatos_nombre_acotado") {
		t.Errorf("201 letras: LA BASE LO DEJÓ PASAR (%v)", err)
	}
	if err := d.EnTransaccion(ctx, func(q sqlc.Querier) error {
		_, err := q.AltaAparato(ctx, sqlc.AltaAparatoParams{Persona: "p", BranchID: uuid.New()}) // sin nombre: NULL pasa
		return err
	}); err != nil {
		t.Errorf("un aparato sin nombre tenía que caber: %v", err)
	}
}

// Un nombre enorme que se coló (una mano con la restricción quitada; la 00004 recorta los que ya había) no llega
// entero al revisor.
func TestLaBandejaRecortaUnNombreViejoEnormeDeAparato(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		if d, real := e.datos.(*datosEnTx); real { // la fila vieja no podría entrar con la restricción puesta
			if _, err := d.tx.Exec(context.Background(), "ALTER TABLE aparatos DROP CONSTRAINT aparatos_nombre_acotado"); err != nil {
				t.Fatal(err)
			}
		}
		enorme := strings.Repeat("ñ", 1<<20)
		aparato, err := e.datos.AltaAparato(context.Background(), sqlc.AltaAparatoParams{Persona: e.persona, BranchID: e.sucursal, Nombre: &enorme})
		if err != nil {
			t.Fatal(err)
		}
		e.aparato = aparato
		ent := e.entregaDeLaPersona("G1")
		e.comoRevisor("admin-1", "ADMINISTRADOR", e.sucursal)

		_, l := e.lista("")
		if len(l.Entregas) != 1 || l.Entregas[0].AparatoNombre == nil || utf8.RuneCountInString(*l.Entregas[0].AparatoNombre) != topeNombreEnLaBandeja {
			t.Errorf("la bandeja: %v", l.Entregas)
		}
		w, d := e.detalle(ent)
		e.esperar(w, http.StatusOK, "")
		if d.Entrega.AparatoNombre == nil || utf8.RuneCountInString(*d.Entrega.AparatoNombre) != topeNombreEnLaBandeja {
			t.Errorf("el detalle: %d letras", utf8.RuneCountInString(*d.Entrega.AparatoNombre))
		}
		if w.Body.Len() > 64<<10 {
			t.Errorf("el detalle pesa %d bytes: el nombre llegó entero", w.Body.Len())
		}
	})
}

// SERIO 3 · `ReclamarRevisionInterrumpida` también exige `persona <> revisor` y el alcance: quien entregó no
// recoge un `aplicando` viejo de lo suyo. (Antigüedad negativa: dentro de una transacción `now()` no avanza y
// así «más vieja que −60 s» se cumple en los dos motores.)
func TestReclamarUnAplicandoInterrumpidoTambienExigeOtraPersonaYElAlcance(t *testing.T) {
	paraCadaMotor(t, func(t *testing.T, e *entorno) {
		ctx := context.Background()
		e.entregaDeLaPersona("W1")
		if _, err := e.datos.ReclamarRevisionApunte(ctx, sqlc.ReclamarRevisionApunteParams{
			Revisor: "revisor-que-murio", AparatoID: e.aparato.ID, Clave: "W1"}); err != nil {
			t.Fatal(err)
		}
		recoger := func(revisor string, sucursal pgtype.UUID) error {
			_, err := e.datos.ReclamarRevisionInterrumpida(ctx, sqlc.ReclamarRevisionInterrumpidaParams{
				Revisor: revisor, AparatoID: e.aparato.ID, Clave: "W1", AntiguedadSegundos: -60, Sucursal: sucursal})
			return err
		}
		if err := recoger(e.persona, pgtype.UUID{}); !store.SinFilas(err) {
			t.Errorf("EL AUTOR RECOGIÓ UN `aplicando` DE LO SUYO: %v", err)
		}
		if err := recoger("admin-2", identificador(uuid.New())); !store.SinFilas(err) {
			t.Errorf("un revisor de otra sucursal recogió un `aplicando` ajeno: %v", err)
		}
		if err := recoger("admin-2", pgtype.UUID{}); err != nil {
			t.Errorf("otra persona, con alcance, tenía que poder recogerlo: %v", err)
		}
	})
}

func (b *baseRevisionFalsa) CopiarApunteAplicadoAlLibro(_ context.Context, arg sqlc.CopiarApunteAplicadoAlLibroParams) (int64, error) {
	if _, hay := b.baseFalsa.apuntes[llave(arg.AparatoID, arg.Clave)]; hay { // ON CONFLICT DO NOTHING
		return 0, nil
	}
	_, err := b.baseFalsa.guardarApunte(sqlc.Apunte{AparatoID: arg.AparatoID, Clave: arg.Clave, Metodo: arg.Metodo, Ruta: arg.Ruta,
		Estado: sqlc.ApunteEstadoAplicado, IDCreado: arg.IDCreado, HechoAt: arg.HechoAt, Descartados: arg.Descartados})
	return 1, err
}

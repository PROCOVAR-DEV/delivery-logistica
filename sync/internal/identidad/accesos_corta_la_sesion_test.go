package identidad

// ACCESOS CORTA LA SESIÓN DE LA APK Y EL ESCRITORIO (08/10/2026, segunda fase).
//
// `reparto-sync` verifica el token por su cuenta, sin estado: tras un corte de seguridad en Accesos
// un token de 15 minutos seguiría sirviendo la bajada y la SUBIDA del día. Jose: «la web es la web
// y las APK son la APK». Ahora un token emitido ANTES de una marca `todo` de esa persona da 401.
//
// Y 401, no 403 (lo ata `TestElCorteEsUn401…`): el cliente trata un 401 como sesión caducada,
// renueva contra Accesos, y es Accesos quien decide si la sesión murió o sólo falta un permiso. Un
// 403 `sin_permiso_reparto` aquí mandaría a la pantalla de «no tienes permiso» a quien sólo tiene que
// renovar, y con su cola dentro.

import (
	"bytes"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/sesiones"
)

func registroDePrueba() *sesiones.Registro {
	return sesiones.Nuevo(nil, slog.New(slog.NewTextHandler(&bytes.Buffer{}, nil)))
}

// tokenDe firma un token de la APK con su `iat` en segundos, de un rol que SÍ entra a Reparto.
func tokenDe(t *testing.T, persona string, iatSeg int64) string {
	t.Helper()
	return firmar(t, map[string]any{
		"sub": persona, "role": "LOGISTICO", "branchId": uuid.New().String(),
		"iat": iatSeg, "exp": time.Now().Add(time.Hour).Unix(),
		"entradas": []string{llaveEntrarReparto},
	}, "HS256")
}

func conInvalidaciones(t *testing.T, token string, inv Invalidaciones) (Identidad, error) {
	t.Helper()
	r := httptest.NewRequest(http.MethodPost, "/sync/subida", nil)
	r.Header.Set("Authorization", "Bearer "+token)
	return DeTokenConInvalidaciones([]byte(secreto), nil, inv)(r)
}

func corte(r *sesiones.Registro, alcance string, tms int64, personas ...string) {
	ids := `"` + strings.Join(personas, `","`) + `"`
	r.Aplicar(`{"v":1,"tipo":"sesion-cerrada","alcance":"` + alcance + `","userIds":[` + ids +
		`],"tms":` + strconv.FormatInt(tms, 10) + `}`)
}

func TestUnTokenEmitidoAntesDelCorteTodoNoEntra(t *testing.T) {
	inv := registroDePrueba()
	viejo := tokenDe(t, "u-ana", time.Now().Unix())
	if _, err := conInvalidaciones(t, viejo, inv); err != nil {
		t.Fatalf("sin marca el token tenía que entrar: %v", err)
	}

	corte(inv, "todo", time.Now().UnixMilli()+1000, "u-ana")

	_, err := conInvalidaciones(t, viejo, inv)
	if !errors.Is(err, ErrSesionInvalidada) || !errors.Is(err, ErrSinSesion) {
		t.Fatalf("el token anterior al corte dio %v, se esperaba ErrSesionInvalidada (que es un ErrSinSesion)", err)
	}
	// Renovado DESPUÉS del corte (otro segundo), entra: el 401 se arregla solo.
	if _, err := conInvalidaciones(t, tokenDe(t, "u-ana", time.Now().Unix()+5), inv); err != nil {
		t.Errorf("el token renovado después del corte no entra: %v", err)
	}
	// Y el corte es de ESA persona.
	if _, err := conInvalidaciones(t, tokenDe(t, "u-beto", time.Now().Unix()), inv); err != nil {
		t.Errorf("el corte de Ana echó a Beto: %v", err)
	}
}

// UN CIERRE DE SESIÓN `web` NO LE LLEGA A LA APK.
func TestUnCierreWebNoTocaAlTokenDeLaAPK(t *testing.T) {
	inv := registroDePrueba()
	corte(inv, "web", time.Now().UnixMilli()+10_000, "u-ana")
	if _, err := conInvalidaciones(t, tokenDe(t, "u-ana", time.Now().Unix()), inv); err != nil {
		t.Errorf("un cierre de sesión del navegador echó al teléfono: %v", err)
	}
}

func TestSinIatMsLaComparacionEsConservadoraPorSegundos(t *testing.T) {
	inv := registroDePrueba()
	iat := time.Now().Unix() - 10
	corte(inv, "todo", iat*1000+500, "u-ana")
	if _, err := conInvalidaciones(t, tokenDe(t, "u-ana", iat), inv); !errors.Is(err, ErrSesionInvalidada) {
		t.Errorf("emitido en el mismo segundo que la marca: %v, se esperaba el corte", err)
	}
	if _, err := conInvalidaciones(t, tokenDe(t, "u-ana", iat+1), inv); err != nil {
		t.Errorf("emitido el segundo siguiente: %v", err)
	}
}

// EL REBOTE (auditoría, 08/10/2026): la APK renueva en cuanto le llega el aviso. Con `iat*1000` un
// token pedido 250 ms después del evento se rechazaba en ~75 % de los casos; con `iatms` manda el
// milisegundo exacto.
func TestUnTokenPedido250MsDespuesDelCorteNoRebota(t *testing.T) {
	inv := registroDePrueba()
	marca := (time.Now().Unix()-30)*1000 + 100 // a mitad de segundo: iat*1000 quedaría ANTES y lo invalidaría
	corte(inv, "todo", marca, "u-ana")

	conMs := func(iatMs int64) string {
		return firmar(t, map[string]any{
			"sub": "u-ana", "role": "LOGISTICO", "branchId": uuid.New().String(),
			"iat": iatMs / 1000, "iatms": iatMs, "exp": time.Now().Add(time.Hour).Unix(),
			"entradas": []string{llaveEntrarReparto},
		}, "HS256")
	}
	if _, err := conInvalidaciones(t, conMs(marca+250), inv); err != nil {
		t.Errorf("el token renovado 250 ms después del corte rebota: %v", err)
	}
	if _, err := conInvalidaciones(t, conMs(marca-50), inv); !errors.Is(err, ErrSesionInvalidada) {
		t.Errorf("el token emitido 50 ms ANTES del corte dio %v", err)
	}
	// Sin `iatms` cae a iat*1000, que es conservador.
	if _, err := conInvalidaciones(t, tokenDe(t, "u-ana", (marca+250)/1000), inv); !errors.Is(err, ErrSesionInvalidada) {
		t.Errorf("sin iatms, en el mismo segundo que la marca dio %v, se esperaba el corte", err)
	}
}

func TestUnTokenSinIatSoloSeCortaSiHayMarcaTodo(t *testing.T) {
	inv := registroDePrueba()
	sinIat := firmar(t, map[string]any{
		"sub": "u-ana", "role": "LOGISTICO", "branchId": uuid.New().String(),
		"exp": time.Now().Add(time.Hour).Unix(), "entradas": []string{llaveEntrarReparto},
	}, "HS256")
	if _, err := conInvalidaciones(t, sinIat, inv); err != nil {
		t.Fatalf("sin marca, un token sin iat no se rechaza por faltarle el claim: %v", err)
	}
	corte(inv, "todo", 1, "u-ana")
	if _, err := conInvalidaciones(t, sinIat, inv); !errors.Is(err, ErrSesionInvalidada) {
		t.Errorf("con marca todo, un token sin iat (instante 0) dio %v", err)
	}
}

// EL CORTE ES UN 401 Y NO UN 403, y va ANTES que la decisión de «sin permiso»: un token cortado
// de alguien que además no entra a Reparto sigue siendo un token que ya no vale.
func TestElCorteEsUn401YNoUn403(t *testing.T) {
	inv := registroDePrueba()
	sinPermiso := firmar(t, map[string]any{ // GERENTE con `entradas: []`: sin el corte daría 403
		"sub": "u-gerente", "role": "GERENTE", "branchId": uuid.New().String(),
		"iat": time.Now().Unix(), "exp": time.Now().Add(time.Hour).Unix(), "entradas": []string{},
	}, "HS256")
	buenoPeroCortado := tokenDe(t, "u-ana", time.Now().Unix())
	corte(inv, "todo", time.Now().UnixMilli()+1000, "u-gerente", "u-ana")

	h := Exigir(DeTokenConInvalidaciones([]byte(secreto), nil, inv),
		http.HandlerFunc(func(http.ResponseWriter, *http.Request) { t.Error("llegó al manejador un token cortado") }))
	for nombre, token := range map[string]string{"bueno pero cortado": buenoPeroCortado, "sin permiso y cortado": sinPermiso} {
		r := httptest.NewRequest(http.MethodPost, "/sync/subida", nil)
		r.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != http.StatusUnauthorized {
			t.Errorf("%s: dio %d, se esperaba 401 (el cliente renueva; un 403 lo mandaría a «no tienes permiso»)", nombre, w.Code)
		}
		if strings.Contains(w.Body.String(), CodigoSinPermisoReparto) {
			t.Errorf("%s: el 401 lleva el código de «sin permiso»: %s", nombre, w.Body.String())
		}
	}
}

// SIN EMPUJE (Redis sin configurar o caído) TODO SIGUE COMO ANTES.
func TestSinInvalidacionesElTokenEntraComoSiempre(t *testing.T) {
	if _, err := conInvalidaciones(t, tokenDe(t, "u-ana", time.Now().Unix()), nil); err != nil {
		t.Errorf("sin invalidaciones enganchadas, el token no entra: %v", err)
	}
	// Un registro sin fuente (Redis sin configurar) tampoco corta a nadie.
	if _, err := conInvalidaciones(t, tokenDe(t, "u-ana", time.Now().Unix()), registroDePrueba()); err != nil {
		t.Errorf("con un registro vacío, el token no entra: %v", err)
	}
}

// EL SINCRONIZADOR NO PREGUNTA A NADIE POR PETICIÓN: una consulta por token, a la memoria.
type contador struct{ n atomic.Int32 }

func (c *contador) ElBearerNoVale(string, int64, int64) bool { c.n.Add(1); return false }

func TestUnaConsultaDeMemoriaPorPeticion(t *testing.T) {
	c := &contador{}
	for i := 0; i < 5; i++ {
		if _, err := conInvalidaciones(t, tokenDe(t, "u-ana", time.Now().Unix()), c); err != nil {
			t.Fatal(err)
		}
	}
	if n := c.n.Load(); n != 5 {
		t.Errorf("5 peticiones hicieron %d consultas, se esperaba 1 por petición", n)
	}
}

package sincro_test

import (
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"procovar/reparto-sync/internal/reparto"
	"procovar/reparto-sync/internal/sincro"
)

// DE EXTREMO A EXTREMO: EL CLIENTE REAL DEL REPARTO DENTRO DE ESTE SERVICIO.
//
// Las pruebas de `internal/reparto` atan qué TIPO de error sale de cada código, y las de
// `internal/sincro` atan qué hace el servicio con cada tipo —pero con un `Aplicador` falso—.
// Cada mitad está verde por su lado y nada ata la JUNTA: si mañana el cliente devolviera el
// 409 como un error cualquiera, o el 503 como `Rechazo`, ninguna de las dos mitades lo vería.
// Es el «ninguna pieza mentía: fallaba la junta de tres» del CLAUDE.md, §4.
//
// Aquí el servidor del reparto es de mentira (httptest) y todo lo demás es de verdad.

// elReparto es un servidor que contesta lo que se le diga y cuenta cuántas veces le llaman.
type elReparto struct {
	mu     sync.Mutex
	codigo int
	cuerpo string
	veces  int
	srv    *httptest.Server
}

func nuevoReparto(t *testing.T, codigo int, cuerpo string) *elReparto {
	t.Helper()
	r := &elReparto{codigo: codigo, cuerpo: cuerpo}
	r.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		r.mu.Lock()
		r.veces++
		codigo, cuerpo := r.codigo, r.cuerpo
		r.mu.Unlock()
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(codigo)
		_, _ = w.Write([]byte(cuerpo))
	}))
	t.Cleanup(r.srv.Close)
	return r
}

func (r *elReparto) contesta(codigo int, cuerpo string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.codigo, r.cuerpo = codigo, cuerpo
}

func (r *elReparto) llamadas() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.veces
}

const (
	// El `error` REAL del 409 parcial del cierre, con el conduce ya interpolado.
	motivo409 = "Se guardaron 1 de las 2 paradas de esta hoja. 1 no se pudieron guardar: " +
		"PTB25-261005-1480 (ese pedido no va en esta ruta)."
	cuerpo409 = `{"error":"` + motivo409 + `",` +
		`"aplicados":[{"orderId":"A","resultado":"entregado"}],` +
		`"rechazados":[{"orderId":"B","numeroOperacion":"PTB25-261005-1480",` +
		`"motivo":"ese pedido no va en esta ruta"}]}`

	hoja = `{"resultados":[{"orderId":"A","resultado":"entregado"},{"orderId":"B","resultado":"entregado"}]}`
)

// UNA HOJA CON UNA PARADA RECHAZADA QUEDA RECHAZADA, A LA VISTA, Y NO SE VUELVE A PEDIR.
//
// Es la decisión de Jose para la APK y el escritorio (CLAUDE.md §1): el 409 parcial rechaza
// el apunte ENTERO con el texto de `error`, y la hoja se queda en la bandeja reteniendo el
// completar hasta que una persona decida. La junta que se ata aquí: motivo literal en la
// respuesta, en el libro y en la bandeja; y que el reintento del aparato recibe `repetido`
// con el mismo motivo SIN volver a molestar al reparto.
func TestUnaHojaConUnaParadaRechazadaQuedaRechazadaYNoSeReintenta(t *testing.T) {
	rep := nuevoReparto(t, http.StatusConflict, cuerpo409)
	p := sincro.MontarConAplicador(t, reparto.Nuevo(rep.srv.URL, "k", 5*time.Second))

	res := p.Subir([3]string{"01J9S001", "/routes/ruta-1/results", hoja})
	if len(res) != 1 || res[0].Estado != sincro.EstadoRechazado || res[0].Motivo != motivo409 {
		t.Fatalf("el apunte tenía que salir rechazado con el `error` literal del reparto: %+v", res)
	}
	if p.Anotado("01J9S001") != sincro.EstadoRechazado {
		t.Fatalf("el apunte tenía que quedar anotado como rechazado, y consta %q", p.Anotado("01J9S001"))
	}
	if m, hay := p.EnLaBandeja("01J9S001"); !hay || m != motivo409 {
		t.Fatalf("el motivo tenía que estar en la bandeja para que una persona lo lea: %q (%v)", m, hay)
	}

	// El aparato reenvía lo mismo: se le contesta lo de la primera vez y no se pregunta.
	otra := p.Subir([3]string{"01J9S001", "/routes/ruta-1/results", hoja})
	if otra[0].Estado != sincro.EstadoRepetido || otra[0].Motivo != motivo409 {
		t.Fatalf("un rechazo reenviado contesta `repetido` con su motivo: %+v", otra[0])
	}
	if rep.llamadas() != 1 {
		t.Fatalf("un rechazo no se reintenta: el reparto recibió %d llamadas, se esperaba 1", rep.llamadas())
	}
}

// LA PAREJA: UNA CAÍDA NO DEJA NADA ANOTADO Y SE VUELVE A INTENTAR.
//
// Con un 503 el apunte no es aplicado, ni rechazado, ni repetido: es que no se pudo
// preguntar. El lote se corta ahí (lo de detrás depende del orden), el apunte NO consta en
// el libro ni en la bandeja y cuenta como pendiente, y cuando el reparto vuelve el MISMO
// apunte entra. Si la caída se tratara como rechazo, la hoja quedaría muerta en la bandeja
// esperando a una persona por algo que se arregla solo.
func TestUnaCaidaDelRepartoNoRechazaNadaYElApunteEntraAlVolver(t *testing.T) {
	rep := nuevoReparto(t, http.StatusServiceUnavailable, cuerpo409)
	p := sincro.MontarConAplicador(t, reparto.Nuevo(rep.srv.URL, "k", 5*time.Second))

	res := p.Subir(
		[3]string{"01J9S010", "/routes/ruta-1/results", hoja},
		[3]string{"01J9S011", "/routes/ruta-2/results", hoja},
	)
	if len(res) != 0 {
		t.Fatalf("una caída no contesta NADA de los apuntes (se quedan en la cola del aparato): %+v", res)
	}
	for _, clave := range []string{"01J9S010", "01J9S011"} {
		if estado := p.Anotado(clave); estado != "" {
			t.Errorf("%s consta como %q: una caída no deja nada en el libro", clave, estado)
		}
		if _, hay := p.EnLaBandeja(clave); hay {
			t.Errorf("%s está en la bandeja: una caída no es un rechazo", clave)
		}
	}
	if rep.llamadas() != 1 {
		t.Errorf("el lote tenía que cortarse en la primera caída (el orden es sagrado): %d llamadas", rep.llamadas())
	}
	if p.Pendientes() != 2 {
		t.Errorf("los dos apuntes siguen en la cola del aparato y el panel tiene que decirlo: %d", p.Pendientes())
	}

	// El reparto vuelve: el mismo apunte, con la misma clave, entra.
	rep.contesta(http.StatusOK, `{"aPedido":{}}`)
	res = p.Subir([3]string{"01J9S010", "/routes/ruta-1/results", hoja})
	if len(res) != 1 || res[0].Estado != sincro.EstadoAplicado {
		t.Fatalf("al volver el reparto el apunte tenía que entrar como aplicado: %+v", res)
	}
}

// Y LA OTRA PAREJA: la hoja que SÍ entera entra y no deja nada en la bandeja. Sin ella,
// «devolver siempre rechazo» pasaría las dos de arriba (§3-quinquies).
func TestUnaHojaQueEntraEnteraNoDejaNadaEnLaBandeja(t *testing.T) {
	rep := nuevoReparto(t, http.StatusOK, `{"aplicados":[{"orderId":"A","resultado":"entregado"},`+
		`{"orderId":"B","resultado":"entregado"}],"rechazados":[]}`)
	p := sincro.MontarConAplicador(t, reparto.Nuevo(rep.srv.URL, "k", 5*time.Second))

	res := p.Subir([3]string{"01J9S020", "/routes/ruta-1/results", hoja})
	if len(res) != 1 || res[0].Estado != sincro.EstadoAplicado {
		t.Fatalf("la hoja entera tenía que entrar: %+v", res)
	}
	if _, hay := p.EnLaBandeja("01J9S020"); hay {
		t.Fatal("una hoja que entra no deja nada en la bandeja")
	}
}

package api

import (
	"context"
	"errors"
	"fmt"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"io"
	"log/slog"
	"net/http"
	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
	"testing"
)

// La misma operación del usuario, con y sin pedidos devueltos que ya soltaron route_id.
func TestRutaVivaSePuedeBorrarConResultadosProvisionales(t *testing.T) {
	for _, estado := range []sqlc.RouteStatus{sqlc.RouteStatusPlanned, sqlc.RouteStatusInProgress} {
		for _, resultado := range []string{"", "entregado", "devuelto", "cancelado"} {
			t.Run(string(estado)+"/"+resultado, func(t *testing.T) {
				d, stg, _ := datosDeReparto()
				h := montarRutas(t, d)
				jwt := deSantiagoEnRutas(t)
				id := armarRutaDePrueba(t, h, jwt, stg[0])
				d.rutas[id].estado = estado
				if resultado != "" {
					w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":%q}]}`, stg[0], resultado))
					if w.Code != 200 {
						t.Fatalf("marcar antes de completar: %d %s", w.Code, w.Body.String())
					}
				}
				if resultado == "devuelto" || resultado == "cancelado" {
					if d.pedidos[stg[0]].rutaID != nil {
						t.Fatal("el fixture no reproduce la ruta vacía de la captura")
					}
				}
				w := llamarRutas(t, h, http.MethodDelete, "/api/routes/"+id.String(), jwt, "")
				if w.Code != 200 {
					t.Fatalf("ruta aún %s debe poder borrarse, incluso con %s: %d %s", estado, resultado, w.Code, w.Body.String())
				}
				if d.rutas[id] != nil {
					t.Fatal("200 pero ruta sigue existiendo")
				}
				if d.pedidos[stg[0]] == nil {
					t.Fatal("borrar ruta borró el pedido")
				}
				if resultado != "" && (d.pedidos[stg[0]].resultado == nil || string(*d.pedidos[stg[0]].resultado) != resultado) {
					t.Fatal("borrar ruta debe conservar el resultado del pedido")
				}
			})
		}
	}
}

func TestRutaCompletadaNoSePuedeModificarNiEliminarAunqueEsteVacia(t *testing.T) {
	for _, caso := range []struct{ nombre, metodo, sufijo, cuerpo string }{
		{"borrar", http.MethodDelete, "", ""},
		{"nombre", http.MethodPatch, "", `{"name":"cambiada"}`},
		{"camion", http.MethodPatch, "", `{"vehicleId":null}`},
		{"reabrir", http.MethodPatch, "", `{"status":"in_progress"}`},
		{"cancelar", http.MethodPatch, "", `{"status":"cancelled"}`},
		{"sin resultados", http.MethodPost, "/results", `{}`},
		{"estado inválido", http.MethodPatch, "", `{"status":"inventado"}`},
		{"marcar", http.MethodPost, "/results", `{"resultados":[{"orderId":"11111111-1111-1111-1111-111111111111","resultado":"devuelto"}]}`},
	} {
		t.Run(caso.nombre, func(t *testing.T) {
			d, stg, _ := datosDeReparto()
			h := montarRutas(t, d)
			jwt := deSantiagoEnRutas(t)
			id := armarRutaDePrueba(t, h, jwt, stg[0])
			d.rutas[id].estado = sqlc.RouteStatusCompleted
			// No queda una sola parada cargada ni marcada: completar, y no una cuenta, protege.
			d.pedidos[stg[0]].rutaID = nil
			d.pedidos[stg[0]].ultimaRuta = nil
			antes := *d.rutas[id]
			camion := *d.camiones[camionStg]
			pedido := *d.pedidos[stg[0]]
			w := llamarRutas(t, h, caso.metodo, "/api/routes/"+id.String()+caso.sufijo, jwt, caso.cuerpo)
			if w.Code != 409 || errorDeRutas(t, w) != msgRutaCompletada {
				t.Fatalf("histórico completado exige409 literal: %d %s", w.Code, w.Body.String())
			}
			if d.rutas[id] == nil || *d.rutas[id] != antes {
				t.Fatal("el histórico cambió aunque se denegó")
			}
			if *d.camiones[camionStg] != camion {
				t.Fatal("se tocó el camión del histórico")
			}
			if d.pedidos[stg[0]].rutaID != pedido.rutaID || d.pedidos[stg[0]].resultado != pedido.resultado {
				t.Fatal("se tocó el pedido del histórico")
			}
		})
	}
}

// Una segunda petición completa después de que ésta leyó la cabecera.
// El test cambia la base después de producir la foto, no modifica el cuerpo ni el status leído.
type lecturaQueSeQuedaVieja struct {
	*dobleDeRutas
	completar         bool
	borrar            bool
	falloBloqueo      error
	falloSegundaMarca bool
	marcas            int
	sucursalBloqueada pgtype.UUID
}

func (d *lecturaQueSeQuedaVieja) ObtenerRuta(ctx context.Context, p sqlc.ObtenerRutaParams) (sqlc.ObtenerRutaRow, error) {
	fila, err := d.dobleDeRutas.ObtenerRuta(ctx, p)
	if err == nil && d.completar {
		d.completar = false
		d.rutas[p.ID].estado = sqlc.RouteStatusCompleted
	}
	if err == nil && d.borrar {
		d.borrar = false
		delete(d.rutas, p.ID)
	}
	return fila, err
}
func (d *lecturaQueSeQuedaVieja) BloquearRuta(ctx context.Context, p sqlc.BloquearRutaParams) (sqlc.RouteStatus, error) {
	d.sucursalBloqueada = p.Sucursal
	if d.falloBloqueo != nil {
		return "", d.falloBloqueo
	}
	return d.dobleDeRutas.BloquearRuta(ctx, p)
}

type fuenteDeFotoVieja struct{ q *lecturaQueSeQuedaVieja }

func (f fuenteDeFotoVieja) Consultas() sqlc.Querier { return f.q }
func (f fuenteDeFotoVieja) EnTx(ctx context.Context, fn func(sqlc.Querier) error) error {
	return fuenteDeRutas{f.q.dobleDeRutas}.EnTx(ctx, func(sqlc.Querier) error { return fn(f.q) })
}
func TestCompletarEntreLecturaYEscrituraNoPermiteCambiarHistorico(t *testing.T) {
	for _, caso := range []struct{ nombre, metodo, sufijo, cuerpo string }{
		{"borrar", "DELETE", "", ""}, {"nombre", "PATCH", "", `{"name":"foto vieja"}`},
		{"camion", "PATCH", "", `{"vehicleId":null}`},
		{"marcar", "POST", "/results", ""}, {"desmarcar", "POST", "/results", "null"},
	} {
		t.Run(caso.nombre, func(t *testing.T) {
			d, stg, _ := datosDeReparto()
			base := montarRutas(t, d)
			jwt := deSantiagoEnRutas(t)
			id := armarRutaDePrueba(t, base, jwt, stg[0])
			d.rutas[id].estado = sqlc.RouteStatusInProgress
			cuerpo := caso.cuerpo
			if caso.metodo == "POST" {
				result := `"entregado"`
				if cuerpo == "null" {
					result = "null"
				}
				cuerpo = fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":%s}]}`, stg[0], result)
			}
			reg := slog.New(slog.NewTextHandler(io.Discard, nil))
			cfg, err := config.Cargar("pruebas")
			if err != nil {
				t.Fatal(err)
			}
			q := &lecturaQueSeQuedaVieja{dobleDeRutas: d, completar: true}
			port := alcance.NuevaPorteria(fuenteDeFotoVieja{q}, reg)
			ver := auth.NuevoVerificador([]byte(secretoDeRutas))
			srv := NuevoServidor(cfg, reg, port, ver, func(context.Context) error { return nil })
			rt := httpx.NuevoRouter(httpx.RecuperarPanico)
			middle := []httpx.Medio{ver.Exigir, port.Exigir}
			srv.rutasDeReparto(rt, middle, middle)
			nombreAntes := d.rutas[id].nombre
			pedido := *d.pedidos[stg[0]]
			camion := *d.camiones[camionStg]
			w := llamarRutas(t, rt.Handler(), caso.metodo, "/api/routes/"+id.String()+caso.sufijo, jwt, cuerpo)
			if w.Code != http.StatusConflict {
				t.Fatalf("otra petición completó antes de escribir: requiere409 sin tocar histórico; llegó%d %s", w.Code, w.Body.String())
			}
			if errorDeRutas(t, w) != msgRutaCompletada {
				t.Fatal(w.Body.String())
			}
			if !q.sucursalBloqueada.Valid || uuid.UUID(q.sucursalBloqueada.Bytes) != stgDeRutas {
				t.Fatal("el bloqueo no conservó la sucursal del usuario autenticado")
			}
			if d.rutas[id] == nil || d.rutas[id].estado != sqlc.RouteStatusCompleted || d.rutas[id].nombre != nombreAntes {
				t.Fatal("se borró/reabrió/renombró el histórico tras completar")
			}
			if *d.camiones[camionStg] != camion || d.pedidos[stg[0]].resultado != pedido.resultado || d.pedidos[stg[0]].rutaID != pedido.rutaID {
				t.Fatal("se modificó camión/pedido del histórico")
			}
		})
	}
}

func montarConFotoVieja(t *testing.T, q *lecturaQueSeQuedaVieja) http.Handler {
	t.Helper()
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	cfg, err := config.Cargar("pruebas")
	if err != nil {
		t.Fatal(err)
	}
	port := alcance.NuevaPorteria(fuenteDeFotoVieja{q}, reg)
	ver := auth.NuevoVerificador([]byte(secretoDeRutas))
	srv := NuevoServidor(cfg, reg, port, ver, func(context.Context) error { return nil })
	rt := httpx.NuevoRouter(httpx.RecuperarPanico)
	middle := []httpx.Medio{ver.Exigir, port.Exigir}
	srv.rutasDeReparto(rt, middle, middle)
	return rt.Handler()
}
func TestLaLecturaBloqueadaDistingueRutaDesaparecidaYErrorDeBase(t *testing.T) {
	for _, metodo := range []string{"DELETE", "PATCH", "POST"} {
		for _, fallo := range []bool{false, true} {
			t.Run(fmt.Sprintf("%s/falloBase=%t", metodo, fallo), func(t *testing.T) {
				d, stg, _ := datosDeReparto()
				h := montarRutas(t, d)
				jwt := deSantiagoEnRutas(t)
				id := armarRutaDePrueba(t, h, jwt, stg[0])
				q := &lecturaQueSeQuedaVieja{dobleDeRutas: d, borrar: !fallo}
				expected := 404
				if fallo {
					q.falloBloqueo = errors.New("error de base simulado")
					expected = 500
				}
				cuerpo := `{"name":"no debe guardarse"}`
				suffix := ""
				if metodo == "POST" {
					suffix = "/results"
					cuerpo = fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, stg[0])
				}
				camion := *d.camiones[camionStg]
				pedido := *d.pedidos[stg[0]]
				w := llamarRutas(t, montarConFotoVieja(t, q), metodo, "/api/routes/"+id.String()+suffix, jwt, cuerpo)
				if w.Code != expected {
					t.Fatalf("fallo al bloquear exige%d, nunca éxito ni histórico modificado: %d %s", expected, w.Code, w.Body.String())
				}
				if *d.camiones[camionStg] != camion || d.pedidos[stg[0]].rutaID != pedido.rutaID || d.pedidos[stg[0]].resultado != pedido.resultado {
					t.Fatal("fallo de lectura tocó camión/pedido")
				}
			})
		}
	}
}

func TestRutaVivaSePuedeEditarConMarcasProvisionales(t *testing.T) {
	for _, estado := range []sqlc.RouteStatus{sqlc.RouteStatusPlanned, sqlc.RouteStatusInProgress} {
		for _, resultado := range []string{"entregado", "devuelto", "cancelado"} {
			t.Run(string(estado)+"/"+resultado, func(t *testing.T) {
				d, stg, _ := datosDeReparto()
				h := montarRutas(t, d)
				jwt := deSantiagoEnRutas(t)
				id := armarRutaDePrueba(t, h, jwt, stg[0])
				d.rutas[id].estado = estado
				w := llamarRutas(t, h, "POST", "/api/routes/"+id.String()+"/results", jwt, fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":%q}]}`, stg[0], resultado))
				if w.Code != 200 {
					t.Fatal(w.Body.String())
				}
				for _, body := range []string{`{"name":"corregida"}`, `{"vehicleId":null}`, fmt.Sprintf(`{"status":%q}`, estado)} {
					w = llamarRutas(t, h, "PATCH", "/api/routes/"+id.String(), jwt, body)
					if w.Code != 200 {
						t.Fatalf("marca provisional no bloquea editar ruta%s: %d %s", estado, w.Code, w.Body.String())
					}
				}
				if d.rutas[id].nombre == nil || *d.rutas[id].nombre != "corregida" || d.rutas[id].vehiculo != nil || d.rutas[id].estado != estado {
					t.Fatal("200 pero los cambios del usuario no se guardaron")
				}
				if d.pedidos[stg[0]].resultado == nil || string(*d.pedidos[stg[0]].resultado) != resultado {
					t.Fatal("editar ruta descartó marca del pedido")
				}
			})
		}
	}
}

func (d *lecturaQueSeQuedaVieja) MarcarResultadoDeParada(ctx context.Context, p sqlc.MarcarResultadoDeParadaParams) (int64, error) {
	d.marcas++
	if d.falloSegundaMarca && d.marcas == 2 {
		return 0, errors.New("falló guardar segunda parada")
	}
	return d.dobleDeRutas.MarcarResultadoDeParada(ctx, p)
}
func TestErrorDeBaseDuranteCierreNoAcusaNiDejaUnaHojaParcial(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[0], stg[1])
	q := &lecturaQueSeQuedaVieja{dobleDeRutas: d, falloSegundaMarca: true}
	body := fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"},{"orderId":%q,"resultado":"devuelto"}]}`, stg[0], stg[1])
	w := llamarRutas(t, montarConFotoVieja(t, q), "POST", "/api/routes/"+id.String()+"/results", jwt, body)
	if w.Code != 500 {
		t.Fatalf("error de base debe conservar apunte pendiente, no acusarlo como aplicado: %d %s", w.Code, w.Body.String())
	}
	for _, p := range stg[:2] {
		if d.pedidos[p].resultado != nil {
			t.Fatal("500 dejó medio cierre escrito")
		}
	}
	q.falloSegundaMarca = false
	q.marcas = 0
	w = llamarRutas(t, montarConFotoVieja(t, q), "POST", "/api/routes/"+id.String()+"/results", jwt, body)
	if w.Code != 200 || d.pedidos[stg[0]].resultado == nil || d.pedidos[stg[1]].resultado == nil {
		t.Fatalf("reintento de hoja conservada no guardó ambos resultados: %d %s", w.Code, w.Body.String())
	}
}

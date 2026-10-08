package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// avisarCambioDeAjustes publica «cambiaron los ajustes» para que las pantallas abiertas se
// enteren sin esperar al temporizador.
//
// Vacío por defecto y lo engancha el fichero del bus (`eventos.go`), igual que el de rutas
// y el del tablero. **No devuelve error y no se mira lo que conteste**.
//
// Aquí vive la MONEDA y su TASA, y con ellas se convierte todo importe que se pinta. Una
// tasa vieja en la pantalla de al lado no se ve rota: se ve como un número creíble y
// equivocado, que es lo peor que le puede pasar a algo que alguien va a cobrar. El mismo
// caso de Granma enseñando los 685 de La Habana (`../CLAUDE.md` §4).
var avisarCambioDeAjustes = func(_ context.Context) {}

// Los ajustes. GLOBALES: no llevan alcance por sucursal y no es un olvido — son de toda
// la empresa, y no hay ninguna columna de sucursal en estas dos tablas que filtrar. La
// tasa POR SUCURSAL es otra cosa y vive en Accesos, no aquí.

type AjustesSalida struct {
	SyncBarridoDia   int32          `json:"syncBarridoDia"`
	CatalogoTraidoAt *time.Time     `json:"catalogoTraidoAt"`
	Currency         string         `json:"currency"`
	CupRate          float64        `json:"cupRate"`
	CupRateUpdatedAt *time.Time     `json:"cupRateUpdatedAt"`
	CreatedAt        *time.Time     `json:"createdAt"`
	UpdatedAt        *time.Time     `json:"updatedAt"`
	Currencies       []MonedaSalida `json:"currencies"`
}

type MonedaSalida struct {
	Code      string     `json:"code"`
	Rate      float64    `json:"rate"`
	Activa    bool       `json:"activa"`
	UpdatedAt *time.Time `json:"updatedAt"`
}

// GET /api/settings
//
// En delivery este GET CREABA la fila si no había: un efecto lateral en una lectura, y
// dos filas de ajustes son media aplicación mirando una y media mirando la otra. Aquí no
// hace falta: la clave primaria es un booleano con `CHECK (id)`, así que la base impide
// que haya dos, y la fila la deja puesta la migración. Si no estuviera, es que alguien
// la borró a mano y hay que verlo, no taparlo.
func (s *Servidor) obtenerAjustes(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	ajustes, err := a.ObtenerAjustes(r.Context())
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Registro(r).Error("no hay fila de ajustes: la migración la crea, así que alguien la borró")
		httpx.ErrorInterno(w, r, err)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	monedas, err := a.ListarMonedas(r.Context(), nil)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, http.StatusOK, deAjustes(ajustes, monedas))
}

type cuerpoAjustes struct {
	Currency httpx.Opcional[string]  `json:"currency"`
	CupRate  httpx.Opcional[float64] `json:"cupRate"`
	// `currencies` era un array dentro de un JSON; ahora es una tabla. Se sigue
	// aceptando la misma forma para no obligar a la pantalla a cambiar el mismo día,
	// pero cada elemento va a su fila: así se puede corregir una sin reescribir las
	// demás y se sabe cuándo cambió cada tasa.
	Currencies []monedaEntrada `json:"currencies"`
	// Se declara para poder AVISAR de que llegó, no para guardarlo. Ver el comentario
	// del manejador.
	TiposVehiculo json.RawMessage `json:"tiposVehiculo"`
}

type monedaEntrada struct {
	Code   string               `json:"code"`
	Rate   float64              `json:"rate"`
	Activa httpx.Opcional[bool] `json:"activa"`
}

// PUT /api/settings
//
// NO EXIGE ADMIN, igual que en delivery: la tasa del día la pone quien esté.
//
// `tiposVehiculo` YA NO SE LEE AQUÍ. Era un campo que no existía en el esquema y lo que
// se mandaba se perdía en silencio. Ahora es la tabla `vehicle_types`, con sus rutas en
// /api/vehicle-types. Si sigue llegando, se avisa en el registro en vez de tragárselo:
// un cliente viejo que crea que está guardando tipos tiene que salir en algún sitio.
func (s *Servidor) guardarAjustes(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	var c cuerpoAjustes
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	if len(c.TiposVehiculo) > 0 && string(c.TiposVehiculo) != "null" {
		httpx.Registro(r).Warn("llegó tiposVehiculo a /api/settings: ese campo ya no está, usa /api/vehicle-types")
	}

	ajustes, err := a.ActualizarAjustes(r.Context(), sqlc.ActualizarAjustesParams{
		Currency: c.Currency.Puntero(),
		CupRate:  c.CupRate.Puntero(),
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	for _, m := range c.Currencies {
		code := strings.ToUpper(strings.TrimSpace(m.Code))
		if code == "" {
			continue
		}
		// `rate` son unidades de esta moneda por 1 USD: CUP = 320, no al revés. Al
		// revés, todos los importes salen divididos por cien mil y parecen céntimos.
		if _, err := a.GuardarMoneda(r.Context(), sqlc.GuardarMonedaParams{
			Code:   code,
			Rate:   m.Rate,
			Activa: m.Activa.Con(true),
		}); err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
	}

	monedas, err := a.ListarMonedas(r.Context(), nil)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	rastroDeQuien(r, "ajustes guardados", "moneda", ajustes.Currency, "tasa_cup", ajustes.CupRate,
		"monedas_tocadas", len(c.Currencies))
	avisarCambioDeAjustes(r.Context())
	httpx.JSON(w, r, http.StatusOK, deAjustes(ajustes, monedas))
}

func deAjustes(s sqlc.Setting, monedas []sqlc.Currency) AjustesSalida {
	salida := AjustesSalida{
		SyncBarridoDia:   s.SyncBarridoDia,
		CatalogoTraidoAt: hora(s.CatalogoTraidoAt),
		Currency:         s.Currency,
		CupRate:          s.CupRate,
		CupRateUpdatedAt: hora(s.CupRateUpdatedAt),
		CreatedAt:        hora(s.CreatedAt),
		UpdatedAt:        hora(s.UpdatedAt),
		Currencies:       make([]MonedaSalida, 0, len(monedas)),
	}
	for _, m := range monedas {
		salida.Currencies = append(salida.Currencies, MonedaSalida{
			Code: m.Code, Rate: m.Rate, Activa: m.Activa, UpdatedAt: hora(m.UpdatedAt),
		})
	}
	return salida
}

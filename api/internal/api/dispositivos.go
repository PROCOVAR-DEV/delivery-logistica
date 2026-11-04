package api

// EL DISTRIBUIDOR TRABAJA POR ENLACE, SIN CUENTA (04/11/2026, Jose: «el distribuidor solo necesita el link que le van a enviar por WhatsApp… una vez
// asignada a un dispositivo no entra en otro lado… sin necesidad de login ni de rol»).
//
//	POST /api/d/reclamar            SIN sesión. El teléfono presenta el token del enlace y su identidad; si la ruta está libre (o ya es suya) queda
//	                                asignada a ese teléfono y recibe su `acceso`: un JWT largo que firma Reparto con rol DISTRIBUIDOR y su `dispositivo`.
//	POST /api/d/renovar             SIN sesión. El teléfono renueva su acceso con su secreto.
//	POST /api/routes/{id}/enlace    la OFICINA: crea (o devuelve) el enlace de la ruta; `renovar: true` suelta la ruta del teléfono y da uno nuevo.
//	GET  /api/routes/{id}/enlace    la OFICINA: el estado del enlace (sin reclamar / reclamado por qué teléfono).
//
// Una ruta tiene UN enlace vivo y UN teléfono; un teléfono acumula las rutas que va reclamando. Reclamar es atómico: si dos teléfonos abren el
// mismo enlace a la vez, gana uno y el otro recibe 403.

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// duracionDelAccesoDelDistribuidor: el token que firma Reparto para un teléfono. Largo a propósito: el distribuidor pasa horas sin conexión y
// «no se le cierra la sesión». Se renueva con el secreto del teléfono; dar de baja el teléfono lo corta al instante (se mira en cada llamada).
const duracionDelAccesoDelDistribuidor = 180 * 24 * time.Hour

const (
	codigoEnlaceNoValido    = "enlace_no_valido"
	codigoEnlaceRevocado    = "enlace_revocado"
	codigoRutaDeOtroTelf    = "ruta_de_otro_dispositivo"
	codigoSecretoIncorrecto = "secreto_incorrecto"
	codigoRutaCerrada       = "ruta_cerrada"
)

func (s *Servidor) rutasDeDispositivos(rt *httpx.Router, sesion []httpx.Medio) {
	rt.ManejarFunc(http.MethodPost, "/api/d/reclamar", s.reclamarEnlace)
	rt.ManejarFunc(http.MethodPost, "/api/d/renovar", s.renovarAccesoDelDispositivo)
	rt.ManejarFunc(http.MethodPost, "/api/routes/{id}/enlace", s.crearEnlaceDeRuta, sesion...)
	rt.ManejarFunc(http.MethodGet, "/api/routes/{id}/enlace", s.verEnlaceDeRuta, sesion...)
}

func hashDelSecreto(secreto string) []byte {
	h := sha256.Sum256([]byte(secreto))
	return h[:]
}

func aleatorio(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

// firmarAccesoDelDispositivo firma el JWT (HS256, el mismo secreto con que verifica la API y el sync) del teléfono: rol DISTRIBUIDOR, la sucursal de
// su ruta, la llave de entrar a Reparto y su `dispositivo`. El `sub` NO es una persona de Accesos: `disp-<id>`.
func (s *Servidor) firmarAccesoDelDispositivo(id uuid.UUID, nombre string, sucursal uuid.UUID, ahora time.Time) (string, time.Time, error) {
	if s.cfg == nil || len(s.cfg.JWTSecret) == 0 {
		return "", time.Time{}, errors.New("JWT_SECRET no está configurada")
	}
	caduca := ahora.Add(duracionDelAccesoDelDistribuidor)
	reclamos := map[string]any{
		"sub": "disp-" + id.String(), "id": "disp-" + id.String(), "name": nombre,
		"role": "DISTRIBUIDOR", "roles": []string{"DISTRIBUIDOR"},
		"branchId": sucursal.String(), "sucursal": sucursal.String(),
		"entradas": []string{"delivery.entrar"}, "dispositivo": id.String(),
		"iat": ahora.Unix(), "exp": caduca.Unix(),
	}
	cabecera, _ := json.Marshal(map[string]string{"alg": "HS256", "typ": "JWT"})
	cuerpo, err := json.Marshal(reclamos)
	if err != nil {
		return "", time.Time{}, err
	}
	sinFirmar := base64.RawURLEncoding.EncodeToString(cabecera) + "." + base64.RawURLEncoding.EncodeToString(cuerpo)
	mac := hmac.New(sha256.New, s.cfg.JWTSecret)
	mac.Write([]byte(sinFirmar))
	return sinFirmar + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil)), caduca, nil
}

func errorConCodigo(w http.ResponseWriter, r *http.Request, estado int, mensaje, codigo string) {
	httpx.ErrorConCodigo(w, r, estado, mensaje, codigo)
}

// POST /api/d/reclamar
func (s *Servidor) reclamarEnlace(w http.ResponseWriter, r *http.Request) {
	var c struct {
		Token         string `json:"token"`
		DispositivoID string `json:"dispositivoId"`
		Nombre        string `json:"nombre"`
		Secreto       string `json:"secreto"`
	}
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	token := strings.TrimSpace(c.Token)
	disp, err := uuid.Parse(strings.TrimSpace(c.DispositivoID))
	if err != nil || disp.Version() != 7 {
		httpx.Error(w, r, http.StatusBadRequest, "dispositivoId tiene que ser un UUID v7 (lo pone la app).")
		return
	}
	if token == "" || len(token) > 200 {
		errorConCodigo(w, r, http.StatusNotFound, "Ese enlace no es válido.", codigoEnlaceNoValido)
		return
	}
	nombre := strings.TrimSpace(c.Nombre)
	if len(nombre) > 80 {
		nombre = nombre[:80]
	}

	q := s.porteria.SinAlcance()
	e, err := q.EnlaceDeRutaPorToken(r.Context(), token)
	if errors.Is(err, pgx.ErrNoRows) {
		errorConCodigo(w, r, http.StatusNotFound, "Ese enlace no es válido.", codigoEnlaceNoValido)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if e.RevocadoAt.Valid {
		errorConCodigo(w, r, http.StatusGone, "Ese enlace ya no vale: pide a tu logístico que te mande uno nuevo.", codigoEnlaceRevocado)
		return
	}
	if e.Status == sqlc.RouteStatusCompleted || e.Status == sqlc.RouteStatusCancelled {
		errorConCodigo(w, r, http.StatusConflict, "Esa ruta ya está cerrada.", codigoRutaCerrada)
		return
	}
	if e.DispositivoID.Valid && uuid.UUID(e.DispositivoID.Bytes) != disp {
		errorConCodigo(w, r, http.StatusForbidden, "Esta ruta ya está asignada a otro teléfono.", codigoRutaDeOtroTelf)
		return
	}
	if !e.BranchID.Valid {
		httpx.Error(w, r, http.StatusConflict, "La ruta no tiene sucursal: avisa a tu logístico.")
		return
	}
	sucursal := uuid.UUID(e.BranchID.Bytes)

	// EL TELÉFONO: nuevo (se crea y se le da su secreto, una sola vez) o conocido (tiene que traer su secreto).
	var secretoNuevo string
	dev, err := q.SecretoDelDispositivo(r.Context(), disp)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		secretoNuevo, err = aleatorio(32)
		if err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
		var nom *string
		if nombre != "" {
			nom = &nombre
		}
		if _, err := q.CrearDispositivoDistribuidor(r.Context(), sqlc.CrearDispositivoDistribuidorParams{
			ID: disp, Nombre: nom, Sucursal: sucursal, Distribuidor: e.DistribuidorID, SecretoHash: hashDelSecreto(secretoNuevo),
		}); err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
	case err != nil:
		httpx.ErrorInterno(w, r, err)
		return
	default:
		if subtle.ConstantTimeCompare(dev.SecretoHash, hashDelSecreto(c.Secreto)) != 1 {
			errorConCodigo(w, r, http.StatusUnauthorized, "Este teléfono no se reconoce.", codigoSecretoIncorrecto)
			return
		}
		if !dev.Activo {
			errorConCodigo(w, r, http.StatusForbidden, "Este teléfono fue dado de baja.", codigoRutaDeOtroTelf)
			return
		}
		if dev.BranchID != sucursal {
			errorConCodigo(w, r, http.StatusForbidden, "Este teléfono es de otra sucursal.", codigoRutaDeOtroTelf)
			return
		}
	}

	// RECLAMAR, ATÓMICO: gana quien lo encuentre libre. Dos teléfonos con el mismo enlace a la vez: uno recibe 403.
	var perdio bool
	err = s.porteria.EnTxSinAlcance(r.Context(), func(tx sqlc.Querier) error {
		n, err := tx.ReclamarEnlaceDeRuta(r.Context(), sqlc.ReclamarEnlaceDeRutaParams{ID: e.ID, Dispositivo: pgtype.UUID{Bytes: disp, Valid: true}})
		if err != nil {
			return err
		}
		if n == 0 {
			perdio = true
			return nil
		}
		return tx.AsignarRutaADispositivo(r.Context(), sqlc.AsignarRutaADispositivoParams{Dispositivo: pgtype.UUID{Bytes: disp, Valid: true}, Ruta: e.RutaID})
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if perdio {
		errorConCodigo(w, r, http.StatusForbidden, "Esta ruta ya está asignada a otro teléfono.", codigoRutaDeOtroTelf)
		return
	}

	acceso, caduca, err := s.firmarAccesoDelDispositivo(disp, nombre, sucursal, time.Now())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	salida := map[string]any{"acceso": acceso, "expira": caduca.UTC(), "rutaId": e.RutaID, "sucursal": sucursal}
	if secretoNuevo != "" {
		salida["secreto"] = secretoNuevo
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// POST /api/d/renovar
func (s *Servidor) renovarAccesoDelDispositivo(w http.ResponseWriter, r *http.Request) {
	var c struct {
		DispositivoID string `json:"dispositivoId"`
		Secreto       string `json:"secreto"`
	}
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	disp, err := uuid.Parse(strings.TrimSpace(c.DispositivoID))
	if err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "dispositivoId no es un uuid.")
		return
	}
	dev, err := s.porteria.SinAlcance().SecretoDelDispositivo(r.Context(), disp)
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && subtle.ConstantTimeCompare(dev.SecretoHash, hashDelSecreto(c.Secreto)) != 1) {
		errorConCodigo(w, r, http.StatusUnauthorized, "Este teléfono no se reconoce.", codigoSecretoIncorrecto)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if !dev.Activo {
		errorConCodigo(w, r, http.StatusForbidden, "Este teléfono fue dado de baja.", codigoRutaDeOtroTelf)
		return
	}
	d, err := s.porteria.SinAlcance().DispositivoDistribuidor(r.Context(), disp)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	nombre := ""
	if d.Nombre != nil {
		nombre = *d.Nombre
	}
	acceso, caduca, err := s.firmarAccesoDelDispositivo(disp, nombre, dev.BranchID, time.Now())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, http.StatusOK, map[string]any{"acceso": acceso, "expira": caduca.UTC()})
}

func (s *Servidor) enlaceSalida(r *http.Request, token string, creado time.Time, dispositivo pgtype.UUID, nombre *string, reclamado pgtype.Timestamptz) map[string]any {
	salida := map[string]any{
		"token": token, "url": origenPublico(r) + "/r/" + token, "creadoAt": creado.UTC(),
		"estado": "sin_reclamar",
	}
	if dispositivo.Valid {
		salida["estado"] = "reclamado"
		salida["dispositivoId"] = uuid.UUID(dispositivo.Bytes)
		salida["dispositivo"] = nombre
		salida["reclamadoAt"] = hora(reclamado)
	}
	return salida
}

// POST /api/routes/{id}/enlace — la oficina. Crea el enlace de la ruta (o devuelve el que ya hay); `renovar: true` suelta la ruta de su teléfono y da uno nuevo.
func (s *Servidor) crearEnlaceDeRuta(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	var c struct {
		Renovar bool `json:"renovar"`
	}
	_ = json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024)).Decode(&c)
	ruta, err := a.ObtenerRuta(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if ruta.Status == sqlc.RouteStatusCompleted || ruta.Status == sqlc.RouteStatusCancelled {
		httpx.Error(w, r, http.StatusConflict, "Esa ruta ya está cerrada: no se le manda enlace.")
		return
	}
	existente, err := a.EnlaceVivoDeUnaRuta(r.Context(), id)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if err == nil && !c.Renovar {
		httpx.JSON(w, r, http.StatusOK, s.enlaceSalida(r, existente.Token, existente.CreatedAt.Time, existente.DispositivoID, existente.DispositivoNombre, existente.ReclamadoAt))
		return
	}
	token, err := aleatorio(18)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	var creada sqlc.CrearEnlaceDeRutaRow
	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		if _, err := tx.BloquearRuta(r.Context(), id); err != nil {
			return err
		}
		if err := tx.RevocarEnlacesDeUnaRuta(r.Context(), id); err != nil {
			return err
		}
		if err := tx.SoltarRutaDeSuDispositivo(r.Context(), id); err != nil {
			return err
		}
		var e error
		creada, e = tx.CrearEnlaceDeRuta(r.Context(), id, token, a.ActorRef())
		return e
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, http.StatusCreated, s.enlaceSalida(r, creada.Token, creada.CreatedAt.Time, pgtype.UUID{}, nil, pgtype.Timestamptz{}))
}

// GET /api/routes/{id}/enlace — la oficina.
func (s *Servidor) verEnlaceDeRuta(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	if _, err := a.ObtenerRuta(r.Context(), id); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
			return
		}
		httpx.ErrorInterno(w, r, err)
		return
	}
	e, err := a.EnlaceVivoDeUnaRuta(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.JSON(w, r, http.StatusOK, map[string]any{"estado": "sin_enlace"})
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, http.StatusOK, s.enlaceSalida(r, e.Token, e.CreatedAt.Time, e.DispositivoID, e.DispositivoNombre, e.ReclamadoAt))
}

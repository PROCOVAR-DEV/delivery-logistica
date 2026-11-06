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
	"github.com/jackc/pgx/v5/pgconn"
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

	codigoRutaSinVehiculo        = "ruta_sin_vehiculo"
	codigoVehiculoDeOtroTelf     = "vehiculo_de_otro_dispositivo"
	codigoTelefonoDeOtroVehiculo = "dispositivo_de_otro_vehiculo"
)

// Errores internos del reclamar (dentro de la transacción) que salen como 403 con su código.
var (
	errVehiculoOcupado   = errors.New("vehiculo ocupado por otro telefono")
	errTelefonoOcupado   = errors.New("telefono vinculado a otro vehiculo")
	errCarreraDelVinculo = errors.New("otro telefono vinculo el vehiculo a la vez")
	errTelefonoYaCreado  = errors.New("el telefono nuevo ya fue creado por otro toque")
	errPerdioElEnlace    = errors.New("otro telefono reclamo el enlace antes")
)

func (s *Servidor) rutasDeDispositivos(rt *httpx.Router, sesion []httpx.Medio) {
	rt.ManejarFunc(http.MethodPost, "/api/d/reclamar", s.reclamarEnlace)
	rt.ManejarFunc(http.MethodPost, "/api/d/renovar", s.renovarAccesoDelDispositivo)
	rt.ManejarFunc(http.MethodPost, "/api/routes/{id}/enlace", s.crearEnlaceDeRuta, sesion...)
	rt.ManejarFunc(http.MethodGet, "/api/routes/{id}/enlace", s.verEnlaceDeRuta, sesion...)
	rt.ManejarFunc(http.MethodPost, "/api/vehicles/{id}/desvincular", s.desvincularVehiculo, sesion...)
	rt.ManejarFunc(http.MethodGet, "/api/vehicles/{id}/vinculos", s.vinculosDeVehiculo, sesion...)
	rt.ManejarFunc(http.MethodGet, "/api/dispositivos", s.listarDispositivos, sesion...)
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
func (s *Servidor) firmarAccesoDelDispositivo(id uuid.UUID, vinculo uuid.UUID, nombre string, sucursal uuid.UUID, ahora time.Time) (string, time.Time, error) {
	if s.cfg == nil || len(s.cfg.JWTSecret) == 0 {
		return "", time.Time{}, errors.New("JWT_SECRET no está configurada")
	}
	caduca := ahora.Add(duracionDelAccesoDelDistribuidor)
	reclamos := map[string]any{
		"sub": "disp-" + id.String(), "id": "disp-" + id.String(), "name": nombre,
		"role": "DISTRIBUIDOR", "roles": []string{"DISTRIBUIDOR"},
		"branchId": sucursal.String(), "sucursal": sucursal.String(),
		"entradas": []string{"delivery.entrar"}, "dispositivo": id.String(), "vinculo": vinculo.String(),
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
	// EL ENLACE LLEVA EL VEHÍCULO (Jose, 04/11/2026): una ruta sin vehículo no se puede reclamar, porque el teléfono se vincula al vehículo de la ruta.
	if !e.VehicleID.Valid {
		errorConCodigo(w, r, http.StatusConflict, "Esta ruta todavía no tiene vehículo: avisa a tu logístico.", codigoRutaSinVehiculo)
		return
	}
	vehiculo := uuid.UUID(e.VehicleID.Bytes)
	sucursal := uuid.UUID(e.BranchID.Bytes)

	// EL TELÉFONO: nuevo (se crea y se le da su secreto, una sola vez) o conocido (tiene que traer su secreto).
	var secretoNuevo string
	var crearTelefono *sqlc.CrearDispositivoDistribuidorParams
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
		// El teléfono NUEVO se crea DENTRO de la transacción del reclamo (auditoría 04/11/2026): si el reclamo falla (vehículo ocupado, enlace
		// perdido) no queda un teléfono con un secreto que su dueño nunca recibió, y reintentar con el mismo id vuelve a ser un teléfono nuevo.
		crearTelefono = &sqlc.CrearDispositivoDistribuidorParams{
			ID: disp, Nombre: nom, Sucursal: sucursal, Distribuidor: e.DistribuidorID, SecretoHash: hashDelSecreto(secretoNuevo),
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

	// RECLAMAR, ATÓMICO: gana quien lo encuentre libre. Dos teléfonos con el mismo enlace a la vez: uno recibe 403. Y el teléfono se VINCULA al vehículo
	// de la ruta: un vehículo en un solo teléfono y un teléfono en un solo vehículo (se cambia desvinculando desde Reparto).
	var vinculo uuid.UUID
	err = s.porteria.EnTxSinAlcance(r.Context(), func(tx sqlc.Querier) error {
		if crearTelefono != nil {
			if _, err := tx.CrearDispositivoDistribuidor(r.Context(), *crearTelefono); err != nil {
				var pgErr *pgconn.PgError
				if errors.As(err, &pgErr) && pgErr.Code == "23505" {
					return errTelefonoYaCreado // otro toque del mismo teléfono nuevo se adelantó: este no tiene su secreto
				}
				return err
			}
		}
		n, err := tx.ReclamarEnlaceDeRuta(r.Context(), sqlc.ReclamarEnlaceDeRutaParams{ID: e.ID, Dispositivo: pgtype.UUID{Bytes: disp, Valid: true}})
		if err != nil {
			return err
		}
		if n == 0 {
			return errPerdioElEnlace // deshace también el alta del teléfono nuevo
		}
		if v, err := tx.VinculoVivoDeVehiculo(r.Context(), vehiculo); err == nil {
			if v.DispositivoID != disp {
				return errVehiculoOcupado
			}
			vinculo = v.ID
		} else if !errors.Is(err, pgx.ErrNoRows) {
			return err
		} else {
			if _, err := tx.VinculoVivoDeDispositivo(r.Context(), disp); err == nil {
				return errTelefonoOcupado
			} else if !errors.Is(err, pgx.ErrNoRows) {
				return err
			}
			vinculo, err = tx.CrearVinculoDeVehiculo(r.Context(), sqlc.CrearVinculoDeVehiculoParams{Vehiculo: vehiculo, Dispositivo: disp, Sucursal: sucursal, Por: nil})
			if err != nil {
				var pgErr *pgconn.PgError
				if errors.As(err, &pgErr) && pgErr.Code == "23505" {
					return errCarreraDelVinculo
				}
				return err
			}
		}
		return tx.AsignarRutaADispositivo(r.Context(), sqlc.AsignarRutaADispositivoParams{Dispositivo: pgtype.UUID{Bytes: disp, Valid: true}, Ruta: e.RutaID})
	})
	switch {
	case errors.Is(err, errTelefonoYaCreado):
		errorConCodigo(w, r, http.StatusConflict, "Este teléfono se está dando de alta en otro toque: espera un momento y vuelve a abrir el enlace.", "telefono_en_alta")
		return
	case errors.Is(err, errPerdioElEnlace):
		errorConCodigo(w, r, http.StatusForbidden, "Esta ruta ya está asignada a otro teléfono.", codigoRutaDeOtroTelf)
		return
	case errors.Is(err, errVehiculoOcupado), errors.Is(err, errCarreraDelVinculo):
		errorConCodigo(w, r, http.StatusForbidden, "Este vehículo ya está vinculado a otro teléfono: pide a tu logístico que lo desvincule.", codigoVehiculoDeOtroTelf)
		return
	case errors.Is(err, errTelefonoOcupado):
		errorConCodigo(w, r, http.StatusForbidden, "Este teléfono ya está vinculado a otro vehículo: pide a tu logístico que lo desvincule.", codigoTelefonoDeOtroVehiculo)
		return
	case err != nil:
		httpx.ErrorInterno(w, r, err)
		return
	}

	acceso, caduca, err := s.firmarAccesoDelDispositivo(disp, vinculo, nombre, sucursal, time.Now())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	salida := map[string]any{"acceso": acceso, "expira": caduca.UTC(), "rutaId": e.RutaID, "sucursal": sucursal, "vinculoId": vinculo, "vehiculoId": vehiculo}
	if v, err := q.ObtenerVehiculo(r.Context(), sqlc.ObtenerVehiculoParams{ID: vehiculo}); err == nil {
		salida["vehiculo"] = map[string]any{"id": vehiculo, "nombre": v.Name, "placa": v.Plate, "tipo": v.TipoNombre}
	}
	// Lo que alimenta el enlace: la ruta, el vehículo y quien reparte. Sin cuentas: todo viaja con el enlace y, con conexión, el sync lo lleva todo.
	if e.DistribuidorID.Valid {
		salida["distribuidor"] = map[string]any{"id": uuid.UUID(e.DistribuidorID.Bytes), "nombre": e.DistribuidorNombre}
	}
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
	// Sin vínculo vivo (desvinculado desde Reparto) no hay acceso que renovar: la APK se vacía.
	vinculo, err := s.porteria.SinAlcance().VinculoVivoDeDispositivo(r.Context(), disp)
	if errors.Is(err, pgx.ErrNoRows) {
		errorConCodigo(w, r, http.StatusForbidden, "Este teléfono fue desvinculado de su vehículo: pide a tu logístico un enlace nuevo.", alcance.CodigoDesvinculado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	acceso, caduca, err := s.firmarAccesoDelDispositivo(disp, vinculo.ID, nombre, dev.BranchID, time.Now())
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
	if !ruta.VehicleID.Valid {
		httpx.Error(w, r, http.StatusConflict, "Asigna un vehículo a la ruta antes de mandar el enlace: el teléfono se vincula a ese vehículo.")
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

// POST /api/vehicles/{id}/desvincular — la oficina. Cierra el vínculo vehículo<->teléfono: el teléfono pierde el acceso (403 `dispositivo_desvinculado`) y
// su APK se vacía; sus rutas planificadas o en curso quedan sin dueño y sin enlace (se mandan a otro con uno nuevo). El servidor NO borra nada: las
// rutas completadas, los puntos de GPS y el vínculo quedan de historia con el id del dispositivo.
func (s *Servidor) desvincularVehiculo(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	var c struct {
		Motivo string `json:"motivo"`
	}
	_ = json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&c)
	var motivo *string
	if m := strings.TrimSpace(c.Motivo); m != "" {
		if len(m) > 300 {
			m = m[:300]
		}
		motivo = &m
	}
	if _, err := a.ObtenerVehiculo(r.Context(), id); errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	} else if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	var cerrado sqlc.CerrarVinculoDeVehiculoRow
	var sueltas []uuid.UUID
	err := a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		var err error
		cerrado, err = tx.CerrarVinculoDeVehiculo(r.Context(), id, motivo)
		if err != nil {
			return err
		}
		sueltas, err = tx.SoltarRutasAbiertasDeUnDispositivo(r.Context(), cerrado.DispositivoID)
		return err
	})
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusConflict, "Ese vehículo no está vinculado a ningún teléfono.")
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisarCambioDeVehiculos(r.Context(), deLaFilaPg(a.SucursalDeAlta()))
	avisarCambioDeRutas(r.Context(), deLaFilaPg(a.SucursalDeAlta()))
	if sueltas == nil {
		sueltas = []uuid.UUID{}
	}
	httpx.JSON(w, r, http.StatusOK, map[string]any{"desvinculado": true, "dispositivoId": cerrado.DispositivoID, "rutasSueltas": sueltas})
}

// GET /api/vehicles/{id}/vinculos — la oficina: la historia de teléfonos que ha llevado este vehículo.
func (s *Servidor) vinculosDeVehiculo(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	if _, err := a.ObtenerVehiculo(r.Context(), id); errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	} else if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	filas, err := a.ListarVinculosDeVehiculo(r.Context(), id)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	salida := make([]map[string]any, 0, len(filas))
	for _, f := range filas {
		salida = append(salida, map[string]any{
			"id": f.ID, "dispositivoId": f.DispositivoID, "dispositivo": f.DispositivoNombre,
			"desde": hora(f.Desde), "hasta": hora(f.Hasta), "vinculadoPor": f.VinculadoPor, "desvinculadoPor": f.DesvinculadoPor, "motivo": f.Motivo,
		})
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// GET /api/dispositivos — la oficina: los teléfonos de los distribuidores de su sucursal (vinculados primero), con su vehículo, su distribuidor y cuándo se vieron
// por última vez. Desvincular se hace por el vehículo (POST /api/vehicles/{id}/desvincular).
func (s *Servidor) listarDispositivos(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	filas, err := a.ListarDispositivos(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	salida := make([]map[string]any, 0, len(filas))
	for _, f := range filas {
		d := map[string]any{
			"id": f.ID, "nombre": f.Nombre, "sucursalId": f.BranchID, "sucursal": f.SucursalNombre, "activo": f.Activo,
			"creadoAt": hora(f.CreatedAt), "ultimaVezAt": hora(f.LastSeenAt), "vinculadoAt": hora(f.VinculadoAt),
			"rutasAbiertas": f.RutasAbiertas, "vehiculo": nil, "distribuidor": nil,
		}
		if f.VehiculoID.Valid {
			d["vehiculo"] = map[string]any{"id": uuid.UUID(f.VehiculoID.Bytes), "nombre": f.VehiculoNombre, "placa": f.VehiculoPlaca}
		}
		if f.DistribuidorID != uuid.Nil {
			d["distribuidor"] = map[string]any{"id": f.DistribuidorID, "nombre": f.DistribuidorNombre}
		}
		salida = append(salida, d)
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

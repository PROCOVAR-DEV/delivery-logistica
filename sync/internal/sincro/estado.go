package sincro

import (
	"math"
	"net/http"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/httpx"
	"procovar/reparto-sync/internal/identidad"
)

// GET /sync/estado — lo que ve el panel.
//
// Esto es lo que hoy no existe y es lo más valioso de todo: un logístico cierra el día, se
// va a su casa y deja el cierre de la ruta sin subir, y nadie se entera hasta que no cuadra
// el inventario. De aquí sale «Palma lleva desde el martes sin subir», y se le puede
// llamar.

type filaAparato struct {
	Aparato  uuid.UUID `json:"aparato"`
	Persona  string    `json:"persona"`
	Sucursal uuid.UUID `json:"sucursal"`
	Nombre   *string   `json:"nombre"`

	Visto *time.Time `json:"visto"`
	Alta  *time.Time `json:"alta"`

	Bajada      *time.Time `json:"bajada"`
	BajadaHasta *time.Time `json:"bajada_hasta"`
	Subida      *time.Time `json:"subida"`

	Pendientes int32 `json:"pendientes"`
	Rechazados int32 `json:"rechazados"`

	// Vacío quiere decir «no ha subido NUNCA», que no es «0 horas». Es el peor caso de
	// todos y por eso esas filas vienen las primeras.
	HorasSinSubir *int64 `json:"horas_sin_subir"`
}

type filaRechazo struct {
	Rechazo  uuid.UUID  `json:"rechazo"`
	Aparato  uuid.UUID  `json:"aparato"`
	Persona  string     `json:"persona"`
	Sucursal uuid.UUID  `json:"sucursal"`
	Nombre   *string    `json:"nombre"`
	Clave    string     `json:"clave"`
	Motivo   string     `json:"motivo"`
	Metodo   string     `json:"metodo"`
	Ruta     string     `json:"ruta"`
	Hecho    *time.Time `json:"hecho"`
	Cuando   *time.Time `json:"rechazado"`
	Cuerpo   *string    `json:"cuerpo"`
}

type contadorSucursal struct {
	Sucursal   uuid.UUID `json:"sucursal"`
	SinAtender int64     `json:"sin_atender"`
}

// EL SEGUNDO NÚMERO ROJO: lo entregado a revisión que sigue esperando a una persona (en_revision,
// aplicando, rechazado), por sucursal. Con el alcance de siempre.
type contadorRevision struct {
	Sucursal   uuid.UUID `json:"sucursal"`
	EnRevision int64     `json:"en_revision"`
}

type estadoSalida struct {
	Aparatos []filaAparato `json:"aparatos"`
	// La bandeja: lo rechazado que sigue esperando a que una persona decida.
	Bandeja []filaRechazo `json:"bandeja"`
	// El número rojo de la cabecera, por sucursal.
	SinAtender []contadorSucursal `json:"sin_atender"`
	// Lo entregado a revisión sin decidir, por sucursal (la bandeja de revisión).
	EnRevision []contadorRevision `json:"en_revision"`
}

func (s *Servicio) estado(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	quien, hay := identidad.De(ctx)
	if !hay {
		httpx.Fallo(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	// REGLA 6, también en el panel. El alcance NO sale del parámetro: sale de quién
	// pregunta. Si viniera del parámetro, el logístico de Camagüey vería la cola y los
	// rechazos de las otras nueve sucursales con sólo cambiarlo. El Super Admin es el
	// único que ve todas, y puede estrechar a una si quiere mirarla.
	sucursal := quien.Alcance()
	if quien.EsSuperAdmin {
		if v := r.URL.Query().Get("sucursal"); v != "" {
			pedida, err := uuid.Parse(v)
			if err != nil {
				httpx.Fallo(w, http.StatusBadRequest, "La sucursal no es un identificador válido")
				return
			}
			sucursal = &pedida
		}
	}
	filtro := alcance(sucursal)

	panel, err := s.datos.PanelDeEstado(ctx, filtro)
	if err != nil {
		s.log.Error("no se pudo leer el panel", "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo leer el estado")
		return
	}
	bandeja, err := s.datos.RechazosSinAtender(ctx, filtro)
	if err != nil {
		s.log.Error("no se pudo leer la bandeja de rechazos", "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo leer el estado")
		return
	}
	contadores, err := s.datos.RechazosSinAtenderPorSucursal(ctx, filtro)
	if err != nil {
		s.log.Error("no se pudieron contar los rechazos", "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo leer el estado")
		return
	}

	enRevision, err := s.datos.RevisionSinDecidirPorSucursal(ctx, filtro)
	if err != nil {
		s.log.Error("no se pudo contar la bandeja de revisión", "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo leer el estado")
		return
	}

	ahora := s.ahora()
	salida := estadoSalida{
		Aparatos:   make([]filaAparato, 0, len(panel)),
		Bandeja:    make([]filaRechazo, 0, len(bandeja)),
		SinAtender: make([]contadorSucursal, 0, len(contadores)),
		EnRevision: make([]contadorRevision, 0, len(enRevision)),
	}
	for _, f := range panel {
		subida := hora(f.SubidaAt)
		salida.Aparatos = append(salida.Aparatos, filaAparato{
			Aparato:     f.ID,
			Persona:     f.Persona,
			Sucursal:    f.BranchID,
			Nombre:      f.Nombre,
			Visto:       hora(f.VistoAt),
			Alta:        hora(f.AltaAt),
			Bajada:      hora(f.BajadaAt),
			BajadaHasta: hora(f.BajadaHasta),
			Subida:      subida,
			Pendientes:  f.Pendientes,
			Rechazados:  f.Rechazados,
			// Las horas se cuentan aquí y no se lee la columna calculada de la consulta:
			// esa viene vacía justo para el aparato que nunca subió —el que más importa—
			// y el tipo generado no admite vacío. Ver la nota del README.
			HorasSinSubir: horasSinSubir(ahora, subida),
		})
	}
	for _, f := range bandeja {
		salida.Bandeja = append(salida.Bandeja, filaRechazo{
			Rechazo:  f.ID,
			Aparato:  f.AparatoID,
			Persona:  f.Persona,
			Sucursal: f.BranchID,
			Nombre:   f.Nombre,
			Clave:    f.Clave,
			Motivo:   f.Motivo,
			Metodo:   f.Metodo,
			Ruta:     f.Ruta,
			Hecho:    hora(f.HechoAt),
			Cuando:   hora(f.RechazadoAt),
			Cuerpo:   f.Cuerpo,
		})
	}
	for _, c := range contadores {
		salida.SinAtender = append(salida.SinAtender, contadorSucursal{
			Sucursal:   c.BranchID,
			SinAtender: c.SinAtender,
		})
	}

	for _, c := range enRevision {
		salida.EnRevision = append(salida.EnRevision, contadorRevision{Sucursal: c.BranchID, EnRevision: c.EnRevision})
	}

	httpx.JSON(w, http.StatusOK, salida)
}

func horasSinSubir(ahora time.Time, subida *time.Time) *int64 {
	if subida == nil {
		return nil
	}
	h := int64(math.Floor(ahora.Sub(*subida).Hours()))
	if h < 0 {
		h = 0
	}
	return &h
}

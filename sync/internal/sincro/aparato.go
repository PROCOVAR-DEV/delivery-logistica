package sincro

import (
	"net/http"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/httpx"
	"procovar/reparto-sync/internal/identidad"
	"procovar/reparto-sync/internal/store/sqlc"
)

// POST /sync/aparato — el alta de una INSTALACIÓN.
//
// El identificador lo pone la base y el aparato lo guarda; nunca se lo inventa él. Uno
// inventado por el teléfono podría repetirse entre dos instalaciones, y entonces dos
// aparatos compartirían cola, claves de idempotencia y marca de bajada.
//
// Se da de alta con conexión, que no es una limitación: para entrar hace falta conexión
// (ver `docs/identidad.md`), así que en el momento del alta siempre la hay.

type altaEntrada struct {
	// Cómo lo llama la gente («el Samsung de Palma»). Para poder decir por teléfono cuál
	// de los dos aparatos es el que no ha subido.
	Nombre *string `json:"nombre"`
	// Sólo la mira el Super Admin, que es el único que puede dar de alta un aparato de
	// otra sucursal. Para el resto manda su propia sucursal, venga lo que venga aquí.
	Sucursal *uuid.UUID `json:"sucursal"`
}

type altaSalida struct {
	Aparato  uuid.UUID `json:"aparato"`
	Persona  string    `json:"persona"`
	Sucursal uuid.UUID `json:"sucursal"`
	Nombre   *string   `json:"nombre"`
}

func (s *Servicio) alta(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	quien, hay := identidad.De(ctx)
	if !hay {
		httpx.Fallo(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var entrada altaEntrada
	if !httpx.Leer(w, r, &entrada) {
		return
	}

	// La sucursal del aparato sale de la sesión, no del cuerpo: si viniera del cuerpo, el
	// alcance por sucursal se lo saltaría cualquiera dándose de alta en otra y bajando
	// desde ahí. El Super Admin es la excepción de siempre, y tiene que decir cuál.
	sucursal := quien.Sucursal
	if quien.EsSuperAdmin {
		if entrada.Sucursal == nil || *entrada.Sucursal == uuid.Nil {
			httpx.Fallo(w, http.StatusBadRequest, "Falta la sucursal del aparato")
			return
		}
		sucursal = *entrada.Sucursal
	} else if entrada.Sucursal != nil && *entrada.Sucursal != sucursal {
		httpx.Fallo(w, http.StatusForbidden, "Sucursal no válida")
		return
	}

	// EL NOMBRE LO MANDA EL APARATO, o sea que se limpia y se recorta (auditoría M3, 09/10/2026): sin tope
	// llegaba entero —hasta los 32 MiB del cuerpo— al panel y a la bandeja del revisor. La base lo acota
	// también (00004). Vacío después de limpiar es «sin nombre».
	var nombre *string
	if entrada.Nombre != nil {
		nombre = textoOpcional(*entrada.Nombre, topeNombreDeAparato)
	}
	aparato, err := s.datos.AltaAparato(ctx, sqlc.AltaAparatoParams{
		Persona:  quien.Persona,
		BranchID: sucursal,
		Nombre:   nombre,
	})
	if err != nil {
		s.log.Error("no se pudo dar de alta el aparato", "persona", quien.Persona, "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo registrar el aparato")
		return
	}

	// La fila de estado se abre aquí, vacía, para que el panel enseñe al aparato recién
	// dado de alta como «nunca ha subido» en vez de no enseñarlo. Un aparato que no
	// aparece es un aparato del que nadie se acuerda.
	if err := s.datos.AbrirEstado(ctx, aparato.ID); err != nil {
		s.log.Error("no se pudo abrir el estado del aparato", "aparato", aparato.ID, "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo registrar el aparato")
		return
	}

	httpx.JSON(w, http.StatusCreated, altaSalida{
		Aparato:  aparato.ID,
		Persona:  aparato.Persona,
		Sucursal: aparato.BranchID,
		Nombre:   aparato.Nombre,
	})
}

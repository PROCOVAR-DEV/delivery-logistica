package sincro

import (
	"fmt"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"

	"procovar/reparto-sync/internal/store/sqlc"
)

// LOS LÍMITES DE LA BANDEJA DE REVISIÓN — `docs/bandeja-de-revision.md`, B.2 «Límites».
//
// Todos tienen un literal que dice QUÉ HACER, porque lo lee una persona con el teléfono en la mano. Y todos
// existen por lo mismo: el token de entrega es de 10 minutos y de una persona SIN permiso, y lo único que
// abre es un buzón. Aun así, un buzón sin tope se llena (spam) o se usa para colar una ruta (autoridad
// prestada): ver «Aplicar: lo que NO puede pasar», punto 5. La lista blanca de método y ruta es la defensa
// de esa autoridad prestada y se vuelve a pasar al aplicar (S2).

const (
	// Lo que cabe en UNA petición de entrega. La app manda 1; una jornada son ~12 apuntes de pocos KB.
	topeCuerpoDeApunte    = 128 << 10
	topePeticionDeEntrega = 512 << 10
	topeApuntesPorEntrega = 25
	topeRutaDeRevision    = 300
	topeResumenDelAparato = 200
	topeTextoDeAuditoria  = 200
	topeDeFilasEnMias     = 1000
	// El nombre de un aparato lo manda el aparato al darse de alta: se recorta a 80 al guardarlo y, por si hay
	// uno viejo más largo, a 200 al enseñarlo al revisor (y la base lo acota a 200 en las filas nuevas: 00004).
	topeNombreDeAparato     = 80
	topeNombreEnLaBandeja   = 200
	topePeticionesPorMinuto = 60

	// Lo VIVO (en_revision, aplicando, rechazado) que puede tener cada quien.
	topeVivosPorPersona      = 500
	topeBytesVivosPorPersona = 8 << 20
	topeVivosPorSucursal     = 3000

	// Un reloj roto no mete el año 1970, ni el 2099.
	hechoMaximoEnElFuturo = 24 * time.Hour
	hechoMaximoEnElPasado = 60 * 24 * time.Hour
)

// metodoAdmitidoEnRevision: los únicos cuatro que la cola del aparato emite para escribir.
func metodoAdmitidoEnRevision(m string) bool {
	switch m {
	case "POST", "PUT", "PATCH", "DELETE":
		return true
	}
	return false
}

// LA LISTA BLANCA DE RUTAS, POR FORMA (auditoría final, B3, 09/10/2026). La cola SÓLO emite estas, que son las
// ÚNICAS rutas de escritura de `reparto-api` sobre rutas y tablero (`api/internal/api/rutas.go` y `tablero.go`),
// con el `/api` que pone `reparto.Aplicar`:
//
//	/routes                       /routes/{id}            /routes/{id}/stops/{pedido}     /routes/{id}/results
//	/board/columns                /board/columns/{id}     /board/columns/{id}/route
//	/board/placements/{pedido}
//
// `{id}` es un uuid o un `local-…` (lo que armó el aparato sin conexión) —también `orden`, que es
// `/board/columns/orden`—: letras, números, `_` y `-`; NUNCA un punto. La forma es la profundidad exacta, no un
// «lo que venga detrás»: antes valía `^/(routes|board)(/…)*`, y `/routes/.` o `/routes/a/b/c/d` pasaban la entrega,
// el reparto contestaba 404 con una página que no era suya y `Aplicar` lo tomaba por una CAÍDA (502) que paraba
// «Aplicar todo en orden» en un apunte que jamás va a entrar. Ahora se rechazan en la entrega con su 422.
// Tras la ruta, opcionalmente, una query de pares simples (`?branchId=…`, `?destino=…`).
//
// Es **la defensa contra la autoridad prestada** y se vuelve a pasar al aplicar.
const idDeRutaEnRevision = `[A-Za-z0-9_-]+`

var reRutaDeRevision = regexp.MustCompile(`^(?:` +
	`/routes(?:/` + idDeRutaEnRevision + `(?:/stops/` + idDeRutaEnRevision + `|/results)?)?` +
	`|/board/columns(?:/` + idDeRutaEnRevision + `(?:/route)?)?` +
	`|/board/placements/` + idDeRutaEnRevision +
	`)(?:\?[A-Za-z0-9._~=&,+:-]*)?$`)

// Ojo: `..` y `//` ya los rechaza la forma en el camino (un segmento no lleva puntos ni va vacío), pero `..` sigue
// importando en la QUERY (`?x=..` está en el alfabeto de la query): ese rechazo explícito lo ata
// `TestLaListaBlancaDeMetodoYRuta`. El de `//` es cinturón y tirantes: quitarlo no pone ninguna prueba en rojo
// (mutación EQUIVALENTE, y no se inventa una prueba que la finja).
func rutaAdmitidaEnRevision(ruta string) bool {
	return len(ruta) <= topeRutaDeRevision &&
		!strings.Contains(ruta, "..") && !strings.Contains(ruta, "//") &&
		reRutaDeRevision.MatchString(ruta)
}

var (
	reClaveDeRevision = regexp.MustCompile(`^[A-Za-z0-9_.:-]{1,100}$`)
	// EL PROVISIONAL, ALINEADO CON LA SUBIDA NORMAL. La subida no valida su forma (`valido()` sólo pide clave,
	// método, ruta y hora): lo guarda tal cual en `ids_provisionales` y sólo TRADUCE los `local-…` que
	// encuentre en una ruta o un cuerpo (`reProvisional`). Aquí había `^local-[A-Za-z0-9]+$`, más estrecho que
	// lo que la app manda: el UUIDv7 con el que el Tablero crea una zona es un id DEFINITIVO que puso el
	// aparato (`Provisionales.nuevoIdReal`), la subida lo acepta y lo anota, y la entrega entera salía 422.
	// Vale lo que la app emite: un `local-…` (letras y números, que es lo único que la subida traduce) o un UUID
	// de cualquier versión; hasta 100 caracteres, que es lo que se guarda sin recortar. Cualquier otra forma
	// sigue siendo un fallo de la app y no una cola que guardar. `TestElProvisionalDeLaRevisionEsComoElDeLaSubida`
	// ata las dos reglas: lo que la subida sabe traducir NO puede quedar fuera de aquí.
	reProvisionalDeRevision = regexp.MustCompile(`^(?:local-[A-Za-z0-9]{1,94}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})$`)
)

// limpio deja un texto de auditoría o de ayuda en algo que Postgres acepta y una persona puede leer: sin
// caracteres de control (un NUL en un `text` es un 500), UTF-8 válido y recortado a `max` letras.
func limpio(s string, max int) string {
	if !utf8.ValidString(s) {
		s = strings.ToValidUTF8(s, "")
	}
	s = strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return -1
		}
		return r
	}, s)
	s = strings.TrimSpace(s)
	if r := []rune(s); len(r) > max {
		s = string(r[:max])
	}
	return s
}

// cupoExcedido dice, con el literal que va a leer la persona, si meter `nuevos` apuntes (de `bytesNuevos`
// bytes) rebasa algún cupo. Vacío = cabe. Son TRES cupos y cada uno es suyo: el de la persona por número, el
// de la persona por peso y el de la sucursal.
func cupoExcedido(cupo sqlc.CupoDeRevisionRow, nuevos int, bytesNuevos int64) string {
	switch {
	case cupo.DeLaPersona+int64(nuevos) > topeVivosPorPersona:
		return fmt.Sprintf("Ya tienes %d cambios esperando revisión y el máximo son %d. No se ha entregado nada: "+
			"pide a un administrador de tu sucursal que revise los que ya entregaste.",
			cupo.DeLaPersona, topeVivosPorPersona)
	case cupo.BytesDeLaPersona+bytesNuevos > topeBytesVivosPorPersona:
		return fmt.Sprintf("Lo que tienes esperando revisión ya pesa %d KiB y el máximo son %d MiB. No se ha entregado "+
			"nada: pide a un administrador de tu sucursal que revise los que ya entregaste.",
			cupo.BytesDeLaPersona>>10, topeBytesVivosPorPersona>>20)
	case cupo.DeLaSucursal+int64(nuevos) > topeVivosPorSucursal:
		return fmt.Sprintf("La bandeja de revisión de tu sucursal está llena (%d cambios esperando; el máximo son %d). "+
			"No se ha entregado nada: avisa a un administrador para que la vacíe.",
			cupo.DeLaSucursal, topeVivosPorSucursal)
	}
	return ""
}

// limitador es una ventana por persona: como mucho `max` peticiones por `ventana`. En memoria, porque
// `sync` es UN proceso y esto frena a quien gira el botón, no es contabilidad; si se reinicia, se vacía.
// El reloj es el del servicio (`Opciones.Ahora`) para poder probarlo.
type limitador struct {
	mu      sync.Mutex
	max     int
	ventana time.Duration
	ahora   func() time.Time
	cubos   map[string]*cuboDeTasa
}

type cuboDeTasa struct {
	desde time.Time
	n     int
}

func nuevoLimitador(max int, ventana time.Duration, ahora func() time.Time) *limitador {
	return &limitador{max: max, ventana: ventana, ahora: ahora, cubos: map[string]*cuboDeTasa{}}
}

// permitir cuenta una petición de `quien`. Si no cabe, dice cuánto falta para que se abra otra ventana.
func (l *limitador) permitir(quien string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	ahora := l.ahora()
	if len(l.cubos) > 1024 { // lo caducado se va: el mapa no crece para siempre
		for k, c := range l.cubos {
			if ahora.Sub(c.desde) >= l.ventana {
				delete(l.cubos, k)
			}
		}
	}
	c := l.cubos[quien]
	if c == nil || ahora.Sub(c.desde) >= l.ventana {
		c = &cuboDeTasa{desde: ahora}
		l.cubos[quien] = c
	}
	c.n++
	if c.n > l.max {
		return false, c.desde.Add(l.ventana).Sub(ahora)
	}
	return true, 0
}

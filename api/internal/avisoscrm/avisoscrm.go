// Package avisoscrm oye el aviso «cambiaron los almacenes» que publica el CRM.
//
// LOS ALMACENES VIVEN EN ACCESOS Y SE GESTIONAN DESDE EL CRM (Jose, 20/10/2026): el CRM edita
// llamando a Accesos y, DESPUÉS de que Accesos acepta el cambio, publica en el Redis de la casa
//
//	PUBLISH procovar:crm:almacenes {"v":1,"tipo":"almacenes-cambiados","sucursal":"STG","tms":1792512000000}
//
// Accesos no avisa de sus propios cambios, y Reparto guarda una caché de 5 minutos de la lista
// (`ALMACENES_CACHE_MS`) y su aparato los vuelve a pedir cada hora. Sin este aviso, un punto
// corregido en el CRM se seguiría midiendo desde el punto viejo hasta 5 minutos, y eso es dinero:
// con el punto del almacén se mide la distancia que se le cobra al cliente.
//
// Esto SÓLO OYE y le pasa a `alAvisar` el código de la sucursal. Qué se hace con él (tirar la caché
// y avisar a las pantallas) es de `internal/api`: aquí no se sabe nada de almacenes.
package avisoscrm

import (
	"context"
	"encoding/json"
	"log/slog"
	"strings"
	"time"
)

// Canal es el canal de Redis donde publica el CRM.
const Canal = "procovar:crm:almacenes"

// versionDelAviso y tipoDelAviso son lo único que se entiende. Cualquier otra cosa se trata como
// «algo cambió y no sé qué»: ver [Entender].
const (
	versionDelAviso = 1
	tipoDelAviso    = "almacenes-cambiados"
)

// Fuente es de dónde llegan los avisos. Interfaz para que las pruebas no necesiten un Redis.
type Fuente interface {
	// Suscribir abre una suscripción viva, o falla.
	Suscribir(ctx context.Context) (Suscripcion, error)
	Cerrar() error
}

// Suscripcion es una vida entera de la conexión.
type Suscripcion interface {
	// Siguiente bloquea hasta el próximo mensaje. Un error la da por muerta.
	Siguiente(ctx context.Context) (string, error)
	Cerrar() error
}

// Los plazos de reconexión. Variables para que las pruebas no esperen segundos.
var (
	esperaMin = time.Second
	esperaMax = time.Minute
)

type aviso struct {
	V        int    `json:"v"`
	Tipo     string `json:"tipo"`
	Sucursal string `json:"sucursal"`
	Tms      int64  `json:"tms"`
}

// Entender lee un mensaje y devuelve el código de sucursal del cambio, normalizado (mayúsculas y
// sin espacios, como los guarda Reparto). `entendido` es false si no es JSON, si la versión no es la 1
// o si el tipo no es «almacenes-cambiados».
//
// UN MENSAJE QUE NO SE ENTIENDE NO SE IGNORA: quien llama debe tratarlo como «cambió algo, no sé qué
// sucursal» y tirar todo («ante la duda, tira todas», acordado con la sesión del CRM). Ignorarlo sería
// medir con el punto viejo justo cuando alguien acaba de corregirlo, sin que nada lo diga. El
// código vacío con `entendido == true` (un aviso bueno sin sucursal) significa lo mismo: de todas.
func Entender(crudo string) (codigo string, entendido bool) {
	var a aviso
	if err := json.Unmarshal([]byte(crudo), &a); err != nil {
		return "", false
	}
	if a.V != versionDelAviso || a.Tipo != tipoDelAviso {
		return "", false
	}
	return strings.ToUpper(strings.TrimSpace(a.Sucursal)), true
}

// Correr suscribe, oye y, si algo falla, espera (con retroceso) y vuelve a empezar. Bloquea hasta que
// ctx se cancela. Sin fuente avisa y vuelve en el acto: la API sirve igual.
//
// `alAvisar` se llama una vez por mensaje, con el código de la sucursal o con "" si es de todas o no se
// entendió. Se llama en el mismo hilo que lee: tiene que ser rápido y no bloquear.
func Correr(ctx context.Context, fuente Fuente, log *slog.Logger, alAvisar func(ctx context.Context, codigo string)) {
	if fuente == nil {
		log.Warn("avisos del CRM: sin Redis configurado (REDIS_CENTINELAS / REDIS_DIRECCION / REDIS_URL): " +
			"la API sirve igual, pero un almacén que se corrija en el CRM tardará hasta 5 minutos en " +
			"medirse bien en el cotizador (ALMACENES_CACHE_MS) y hasta 1 hora en llegar a una APK")
		return
	}
	defer fuente.Cerrar()

	espera := esperaMin
	for ctx.Err() == nil {
		err := unaConexion(ctx, fuente, log, alAvisar, func() { espera = esperaMin })
		if ctx.Err() != nil {
			return
		}
		log.Warn("avisos del CRM: se perdió la suscripción; la API sigue sirviendo y reintento",
			"err", err, "reintento_en", espera.String())
		t := time.NewTimer(espera)
		select {
		case <-ctx.Done():
			t.Stop()
			return
		case <-t.C:
		}
		if espera *= 2; espera > esperaMax {
			espera = esperaMax
		}
	}
}

// unaConexion es una vida entera de la suscripción. Siempre vuelve con error: o murió, o se canceló ctx.
func unaConexion(ctx context.Context, fuente Fuente, log *slog.Logger, alAvisar func(context.Context, string), conectada func()) error {
	sus, err := fuente.Suscribir(ctx)
	if err != nil {
		return err
	}
	defer sus.Cerrar()
	conectada()
	log.Info("avisos del CRM: escuchando", "canal", Canal)

	for {
		crudo, err := sus.Siguiente(ctx)
		if err != nil {
			return err
		}
		codigo, entendido := Entender(crudo)
		if !entendido {
			log.Warn("avisos del CRM: mensaje que no entiendo; se trata como un cambio de todas las sucursales",
				"mensaje", recortar(crudo, 200))
		}
		alAvisar(ctx, codigo)
	}
}

func recortar(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

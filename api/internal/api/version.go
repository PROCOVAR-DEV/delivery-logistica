package api

import (
	"net/http"

	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
)

// El anuncio de versión, que es lo que mira cada aparato al arrancar.
//
// DOS NÚMEROS QUE NO SON EL MISMO, y confundirlos es el error que hay que evitar leyendo
// esto:
//
//   - `version` es la de ESTE servicio, la que incrusta el compilador con `-ldflags`. Es
//     un latido: sirve para saber qué se desplegó. Ya estaba y no cambia.
//   - `ultima` es la de la APLICACIÓN que hay colgada para descargar — el APK, el `.exe`,
//     el escritorio de Linux. Es lo que el logístico tendría que tener instalado.
//
// La api y la aplicación se despliegan por separado y sus números no tienen por qué
// coincidir nunca. Si el aparato comparase lo suyo con `version`, cada despliegue de la
// api mandaría a diez personas a reinstalar una aplicación que no ha cambiado.
//
// `ultima` es `null` mientras no se anuncie nada (§ `config.Publicada`), y entonces
// ningún aparato avisa. Un anuncio a medias no existe: la configuración no arranca.

// versionSalida es el contrato. Tipo declarado y no un `map`, como los demás manejadores:
// el mapa se cambia sin querer al tocar cualquier línea y el cliente se entera en el
// patio de un almacén.
type versionSalida struct {
	Version *string       `json:"version"`
	Ultima  *ultimaSalida `json:"ultima"`
	// Distribuidor es lo mismo para la app «Reparto Distribuidor», que va aparte de Reparto (otra APK y otra cuenta de versiones). Las APK de Reparto ya
	// instaladas no leen esta clave (es aditiva); la app del chofer lee ESTA y no `ultima`.
	Distribuidor *ultimaSalida `json:"distribuidor"`
}

type ultimaSalida struct {
	Version string `json:"version"`
	// Compilacion es el `versionCode` de Android — el número de después del `+`. Se manda
	// aparte porque es lo ÚNICO que Android compara de verdad al instalar encima.
	Compilacion *int    `json:"compilacion"`
	Notas       *string `json:"notas"`
	PublicadaAt *string `json:"publicadaAt"`
	// Descargas lleva sólo las plataformas que tienen fichero colgado. Una clave con
	// cadena vacía sería un enlace roto en la pantalla de alguien.
	//
	// NO hay clave `web` y no la va a haber: la web se actualiza sola al recargar y no
	// descarga nada. Ver `docs/actualizaciones.md`.
	Descargas map[string]string `json:"descargas"`

	// Ficheros dice, por plataforma, cuánto pesa y qué huella tiene lo que hay en esa
	// URL.
	//
	// VA APARTE DE `descargas` A PROPÓSITO, Y ESO NO ES INDECISIÓN. Las APK que ya
	// están instaladas leen `descargas` esperando una cadena por clave, y su lector es
	// defensivo: si el valor deja de ser cadena, **se la salta sin decir nada**
	// (`app/lib/nucleo/actualizacion/version_publicada.dart`). O sea que convertir
	// `descargas` en objetos no daría un error, daría teléfonos que dejan de ofrecer la
	// actualización en silencio — y sin poder actualizarse para arreglarlo. Se añade al
	// lado; lo viejo sigue leyéndose igual.
	Ficheros map[string]ficheroSalida `json:"ficheros"`
}

type ficheroSalida struct {
	Bytes  int64  `json:"bytes"`
	SHA256 string `json:"sha256"`
}

// GET /version  (y /api/version, que es la ruta del contrato)
//
// SIN SESIÓN: la APK la consulta antes de entrar, para saber si tiene que actualizarse.
// Con token no serviría para eso.
//
// SÍNCRONO Y SIN BASE: los diez aparatos llaman aquí al arrancar, a la vez, la mañana que
// vuelve la señal. Todo sale de la configuración, que se leyó una vez al arrancar.
func (s *Servidor) version(w http.ResponseWriter, r *http.Request) {
	salida := versionSalida{Ultima: ultimaDe(s.cfg.Publicada), Distribuidor: ultimaDe(s.cfg.Distribuidor)}
	if s.cfg.Version != "" {
		v := s.cfg.Version
		salida.Version = &v
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// ultimaDe traduce la configuración al contrato. Aparte del manejador para poder probarla
// sin levantar un router.
func ultimaDe(p *config.Publicada) *ultimaSalida {
	if !p.HayAlguna() {
		return nil
	}
	u := &ultimaSalida{
		Version:   p.Version,
		Descargas: map[string]string{},
		Ficheros:  map[string]ficheroSalida{},
	}
	if p.Compilacion > 0 {
		c := p.Compilacion
		u.Compilacion = &c
	}
	if p.Notas != "" {
		n := p.Notas
		u.Notas = &n
	}
	if p.PublicadaAt != "" {
		f := p.PublicadaAt
		u.PublicadaAt = &f
	}
	for clave, url := range map[string]string{
		"android": p.Android,
		"windows": p.Windows,
		"linux":   p.Linux,
	} {
		if url == "" {
			continue
		}
		u.Descargas[clave] = url
		// La configuración no deja pasar una URL sin sus dos números (`config.go`), así
		// que aquí no hay caso de «hay enlace pero no hay tamaño». Se comprueba igual:
		// anunciar un fichero con cero bytes sería enseñar «0 B» en la pantalla de
		// alguien, que es un número creíble y equivocado.
		if f, hay := p.Ficheros[clave]; hay && f.Bytes > 0 && f.SHA256 != "" {
			u.Ficheros[clave] = ficheroSalida{Bytes: f.Bytes, SHA256: f.SHA256}
		}
	}
	return u
}

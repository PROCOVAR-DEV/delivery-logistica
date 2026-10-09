package config

import (
	"net/url"
	"strings"
)

// Redis es por dónde se llega al Redis de la casa: EL MISMO (con centinela, `procovar-sentinel`)
// que lee el espejo, y con LOS MISMOS NOMBRES DE VARIABLE que él (`internal/espejo/opciones.go`).
//
// # Para qué lo usa la API — 08/10/2026
//
// Para enterarse de que Accesos cerró una sesión o cambió permisos (`internal/sesiones`). Jose:
// «Accesos debe afectar a las otras sesiones... nada de polling: para eso tenemos SSE y
// Sentinel». Antes la cookie de la web valía siete días sin volver a preguntar a nadie.
//
// # Qué se lee, y qué NO
//
//	REDIS_CENTINELAS  host:puerto,host:puerto   (si hay, se va por centinela)
//	REDIS_MAESTRO     el nombre del maestro que dicen los centinelas
//	REDIS_CLAVE       la contraseña
//	REDIS_DIRECCION   host:puerto, sin centinela (lo que hace falta en local)
//	REDIS_URL         redis://[:clave@]host:puerto[/base] — de ella se toma host y clave
//
// **La base de la URL y `REDIS_BASE` NO se leen**: las marcas de Accesos viven en la DB 6
// (`sesiones.BaseDeLasMarcas`), fija por contrato; la 2 del espejo es la de su cola de PEDIDO y
// leer de ahí una marca sería leer de ninguna parte, sin un solo error.
//
// SIN NADA CONFIGURADO LA API ARRANCA Y SIRVE IGUAL, sin el empuje (se dice al arrancar).
type Redis struct {
	Direccion  string
	Centinelas []string
	Maestro    string
	Clave      string
}

// Hay dice si se puede hablar con Redis. Mismo criterio que `espejo.Opciones.HayRedis`.
func (r Redis) Hay() bool { return r.Direccion != "" || len(r.Centinelas) > 0 }

// leerRedis aplica el MISMO orden que el espejo: la URL primero y las sueltas encima.
func leerRedis(entorno func(string) string) Redis {
	var r Redis
	if v := strings.TrimSpace(entorno("REDIS_URL")); v != "" {
		if u, err := url.Parse(v); err == nil {
			r.Direccion = u.Host
			if pw, hay := u.User.Password(); hay {
				r.Clave = pw
			}
		}
	}
	if v := strings.TrimSpace(entorno("REDIS_DIRECCION")); v != "" {
		r.Direccion = v
	}
	if v := strings.TrimSpace(entorno("REDIS_MAESTRO")); v != "" {
		r.Maestro = v
	}
	if v := strings.TrimSpace(entorno("REDIS_CLAVE")); v != "" {
		r.Clave = v
	}
	if v := strings.TrimSpace(entorno("REDIS_CENTINELAS")); v != "" {
		for _, parte := range strings.Split(v, ",") {
			if p := strings.TrimSpace(parte); p != "" {
				r.Centinelas = append(r.Centinelas, p)
			}
		}
	}
	return r
}

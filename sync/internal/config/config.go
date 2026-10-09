// Package config lee el entorno una sola vez, al arrancar, y falla ahí mismo si falta algo.
//
// El porqué de fallar al arrancar y no al primer uso: este servicio vive en un VPS y se
// despliega con Dokploy. Una variable mal puesta que sólo se note cuando un logístico
// intenta subir la cola del día es un fallo que se descubre en el peor momento posible —en
// la calle, con el trabajo dentro del teléfono—. Al arrancar, en cambio, lo ve el que
// despliega.
package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	// Dónde escucha. Detrás va un proxy que termina TLS.
	Direccion string

	// La base del sincronizador. Aquí NO viven los datos del reparto: sólo la
	// contabilidad de la sincronización.
	BaseDeDatos   string
	MaxConexiones int32

	// El reparto (`reparto-api`), que es el dueño de los datos. La bajada le pide
	// diferencias y la subida le manda cada apunte: este servicio no escribe pedidos.
	RepartoURL    string
	RepartoClave  string
	RepartoTiempo time.Duration

	// De dónde sale quién está llamando. Ver `internal/identidad`.
	Identidad string

	// El secreto con el que auth firma los tokens. Sólo con `SYNC_IDENTIDAD=token`.
	JWTSecreto string

	// El Redis de la casa, el mismo que lee el espejo y `reparto-api`: sólo sirve para enterarse de
	// que Accesos cortó las sesiones de alguien (`internal/sesiones`). Vacío = se sirve sin ese
	// empuje, y se dice al arrancar. Ver [Redis].
	Redis Redis

	// Cuántas filas como mucho en una tanda de la bajada antes de contestar
	// `truncado: true`. Existe porque la primera bajada de una sucursal grande no cabe
	// de una vez en la conexión de allá.
	TopeBajada int32

	EsperaLectura   time.Duration
	EsperaEscritura time.Duration
}

// Cargar junta TODOS los fallos antes de devolver, en vez de parar en el primero: quien
// despliega ve de una vez todo lo que le falta y no arranca cinco veces seguidas.
func Cargar() (Config, error) {
	var fallos []string

	c := Config{
		Direccion:       texto("SYNC_ADDR", ":8081"),
		BaseDeDatos:     os.Getenv("DATABASE_URL"),
		RepartoURL:      strings.TrimRight(os.Getenv("REPARTO_URL"), "/"),
		RepartoClave:    os.Getenv("REPARTO_API_KEY"),
		Identidad:       os.Getenv("SYNC_IDENTIDAD"),
		JWTSecreto:      os.Getenv("JWT_SECRET"),
		Redis:           leerRedis(os.Getenv),
		MaxConexiones:   entero("SYNC_DB_MAX_CONNS", 10),
		TopeBajada:      entero("SYNC_TOPE_BAJADA", 500),
		RepartoTiempo:   espera("SYNC_REPARTO_TIMEOUT", 30*time.Second),
		EsperaLectura:   espera("SYNC_READ_TIMEOUT", 15*time.Second),
		EsperaEscritura: espera("SYNC_WRITE_TIMEOUT", 60*time.Second),
	}

	if c.BaseDeDatos == "" {
		fallos = append(fallos, "falta DATABASE_URL")
	}
	if c.RepartoURL == "" {
		fallos = append(fallos, "falta REPARTO_URL (el sincronizador no es dueño de los datos: se los pide al reparto)")
	}
	// La clave de servicio no es opcional: las rutas de `reparto-api` que se llaman desde
	// aquí van con `x-api-key` y sin ella todo respondería 401 apunte por apunte, que el
	// aparato leería como diez rechazos seguidos.
	if c.RepartoClave == "" {
		fallos = append(fallos, "falta REPARTO_API_KEY")
	}
	// DE DÓNDE SALE QUIÉN LLAMA. Dos modos, y `token` es el bueno.
	//
	// `cabeceras` confía en `X-Persona`, que debía poner un proxy que verificara el token
	// delante de este servicio. **Ese proxy nunca existió**: Traefik enruta
	// `reparto.procovar.cloud/sync` directo al contenedor, así que la cabecera llegaba
	// vacía y esto contestaba 401 a TODO. Nada se subió nunca, y peor: un 401 que
	// sobrevive a renovar es, para el cliente, «la sesión murió», así que echaba a la
	// persona justo cuando volvía la señal.
	//
	// El modo se deja escrito a mano y sin valor por defecto a propósito, porque elegir
	// `cabeceras` es aceptar que nadie más puede llegar a este puerto — y eso es una
	// decisión de despliegue que alguien tiene que tomar mirándola.
	switch c.Identidad {
	case "token":
		if strings.TrimSpace(c.JWTSecreto) == "" {
			fallos = append(fallos,
				"falta JWT_SECRET (el MISMO con el que firma auth.procovar.cloud; sin él no se puede validar a nadie)")
		} else if len(c.JWTSecreto) < 32 {
			fallos = append(fallos, "JWT_SECRET tiene menos de 32 caracteres")
		}
	case "cabeceras":
		// NO SE ADMITE SIN UNA VARIABLE EXPLÍCITA — auditoría de seguridad, 08/10/2026.
		//
		// En este modo la identidad sale de `X-Persona`/`X-Sucursal`/`X-Super-Admin`, que
		// puede escribir CUALQUIERA que llegue al puerto, y el token no existe: no hay roles
		// que comprobar, así que el control de «quién entra a Reparto» (SUPER ADMIN,
		// DESARROLLADOR, ADMINISTRADOR, LOGISTICO) NO se aplica. Un valor de entorno que
		// alguien copia de un ejemplo viejo apagaría en silencio la regla de Jose.
		// En producción es `SYNC_IDENTIDAD=token` (medido el 08/10/2026).
		if os.Getenv("SYNC_PERMITIR_CABECERAS") != "1" {
			fallos = append(fallos,
				"SYNC_IDENTIDAD=cabeceras NO comprueba roles (cualquiera que llegue al puerto entra "+
					"a Reparto sin control): usa SYNC_IDENTIDAD=token; sólo si de verdad hay un "+
					"proxy que verifica el token delante, añade SYNC_PERMITIR_CABECERAS=1")
		}
	default:
		fallos = append(fallos,
			`falta SYNC_IDENTIDAD=token (=cabeceras sólo con SYNC_PERMITIR_CABECERAS=1 y un proxy que verifique el token delante; ver internal/identidad)`)
	}
	if c.TopeBajada <= 0 {
		fallos = append(fallos, "SYNC_TOPE_BAJADA tiene que ser mayor que cero")
	}

	if len(fallos) > 0 {
		return Config{}, errors.New("configuración incompleta: " + strings.Join(fallos, "; "))
	}
	return c, nil
}

func texto(clave, porDefecto string) string {
	if v := os.Getenv(clave); v != "" {
		return v
	}
	return porDefecto
}

func entero(clave string, porDefecto int32) int32 {
	v := os.Getenv(clave)
	if v == "" {
		return porDefecto
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return porDefecto
	}
	return int32(n)
}

func espera(clave string, porDefecto time.Duration) time.Duration {
	v := os.Getenv(clave)
	if v == "" {
		return porDefecto
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return porDefecto
	}
	return d
}

func (c Config) String() string {
	// Sin la clave de servicio ni la cadena de la base: esto se registra al arrancar.
	return fmt.Sprintf("direccion=%s reparto=%s identidad=%s tope_bajada=%d",
		c.Direccion, c.RepartoURL, c.Identidad, c.TopeBajada)
}

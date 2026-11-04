package api

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"

	"github.com/google/uuid"
)

// EL ID DE UNA RUTA ES UN UUIDv7 Y SU CÓDIGO SALE DE ÉL — Jose, 04/11/2026: «no puedo tener rutas con códigos repetidos, para eso está
// el UUIDv7, hazlo corto, y nada de prefijos: las tablas ya separan una cosa de otra».
//
// Antes era `RT-YYYYMMDD-NNN`, y el NNN salía de CONTAR las rutas del día +1: al borrar una ruta, el siguiente código se repetía (el
// 03/11/2026 hubo tres `RT-20261103-004` en La Habana, creadas desde la web minutos aparte, sin carrera de por medio).
//
// Ahora la ruta nace con un UUIDv7 y el código son 6 caracteres de su parte ALEATORIA, en el alfabeto de Crockford (sin I, L, O ni U:
// no se confunden por teléfono), SIN prefijo. **Quien crea la ruta pone el id:** el aparato (con o sin conexión) manda el suyo y de él
// salen el mismo código en el aparato y en el servidor (`codigoDeRutaDe`, gemela de `app/lib/nucleo/codigo_de_ruta.dart`); la web, que no
// tiene aparato, lo deja al servidor. Tres capas contra la repetición, en este orden:
//
//  1. el id es un UUIDv7: dos rutas, aunque entren a la vez desde cualquier aparato o por la web, no comparten id;
//  2. al llegar, se MIRA que el código no exista (`ExisteCodigoDeRuta`); si choca (30 bits: con 7.000 rutas al año casi nunca), la ruta
//     CONSERVA su id y se le da otro código libre, que el aparato recibe en su siguiente bajada;
//  3. el índice único `routes_route_code_uniq` (00031) hace imposible, en la base, que dos rutas lo repitan.
//
// Los códigos viejos (`RT-YYYYMMDD-NNN`) se quedan como están, salvo los que ya estaban repetidos (los arregla la 00031).

// alfabetoDeCodigos es el de Crockford, 32 símbolos: 5 bits por carácter.
const alfabetoDeCodigos = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

const intentosDeCodigoDeRuta = 8

// errIdNoEsV7 es el id que manda el aparato cuando no es un UUIDv7 bien formado.
var errIdNoEsV7 = errors.New("el id de la ruta tiene que ser un UUID v7")

// codigoDeRutaDe saca el código de 6 caracteres de los 30 bits más bajos de un UUIDv7 (los últimos 4 bytes son aleatorios del todo).
func codigoDeRutaDe(id uuid.UUID) string {
	n := binary.BigEndian.Uint32(id[12:16]) & (1<<30 - 1)
	var c [6]byte
	for i := len(c) - 1; i >= 0; i-- {
		c[i] = alfabetoDeCodigos[n&31]
		n >>= 5
	}
	return string(c[:])
}

// idDeRutaDelAparato lee el `id` que manda el aparato: vacío = no mandó ninguno (`uuid.Nil`), y si viene tiene que ser un UUIDv7.
func idDeRutaDelAparato(crudo string) (uuid.UUID, error) {
	if crudo == "" {
		return uuid.Nil, nil
	}
	id, err := uuid.Parse(crudo)
	if err != nil || id.Version() != 7 {
		return uuid.Nil, errIdNoEsV7
	}
	return id, nil
}

// existeCodigoDeRuta es la pregunta a la base: ¿hay ya una ruta con este código?
type existeCodigoDeRuta func(ctx context.Context, codigo string) (bool, error)

// idYCodigoDeRuta da el id de la ruta y su código libre. [propuesto] es el que mandó el aparato (`uuid.Nil` = ninguno: el servidor
// genera un UUIDv7 nuevo). Con id propuesto, el id NUNCA cambia: si su código ya está ocupado, se busca otro código libre y se devuelve
// `cambio = true` para que quien llama lo AVISE (log y respuesta) y el aparato actualice el que tenía.
// Respetar lo que el aparato ya hizo es la regla (Jose, 04/11/2026): solo se cambia si de verdad coincide.
func idYCodigoDeRuta(ctx context.Context, existe existeCodigoDeRuta, propuesto uuid.UUID) (uuid.UUID, string, bool, error) {
	id := propuesto
	for i := 0; i < intentosDeCodigoDeRuta; i++ {
		if id == uuid.Nil {
			nuevo, err := uuid.NewV7()
			if err != nil {
				return uuid.Nil, "", false, err
			}
			id = nuevo
		}
		codigo := codigoDeRutaDe(id)
		if i > 0 && propuesto != uuid.Nil {
			// El id es del aparato y no se toca: el código de repuesto sale de un UUIDv7 nuevo.
			otro, err := uuid.NewV7()
			if err != nil {
				return uuid.Nil, "", false, err
			}
			codigo = codigoDeRutaDe(otro)
		}
		ocupado, err := existe(ctx, codigo)
		if err != nil {
			return uuid.Nil, "", false, err
		}
		if !ocupado {
			// `cambio` = el aparato mandó su id y SU código (el que salía de él) chocó: se le dio otro y hay que AVISAR.
			return id, codigo, propuesto != uuid.Nil && codigo != codigoDeRutaDe(propuesto), nil
		}
		if propuesto == uuid.Nil {
			id = uuid.Nil // sin id propuesto, se prueba con otro UUIDv7
		}
	}
	return uuid.Nil, "", false, fmt.Errorf("no salió un código de ruta libre tras %d intentos", intentosDeCodigoDeRuta)
}

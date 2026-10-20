package api

import (
	"context"

	"github.com/google/uuid"
)

// CambiaronLosAlmacenes es lo que hace Reparto cuando el CRM avisa por Redis (`internal/avisoscrm`)
// de que se corrigieron los almacenes de una sucursal. Dos cosas, y las dos importan:
//
//  1. TIRA EL RECUERDO de la lista que guarda el cliente de Accesos (5 min, `ALMACENES_CACHE_MS`).
//     Sin eso, durante cinco minutos se seguiría midiendo —y cobrando— desde el punto ANTERIOR, que es
//     justo el que acaban de corregir por estar mal.
//  2. AVISA a las pantallas de ESA sucursal (`CambioAlmacenes`) para que se repinten: el Tablero y
//     Clientes miden desde el almacén. No a las ocho: el aviso sale con la sucursal del cambio (trampa
//     del 01/10/2026, un aviso sin sucursal mandaba a las otras siete a pedir la lista por nada).
//
// `sucursalDe` traduce el código del aviso (`STG`) a NUESTRO id de sucursal, que es lo que reparte el bus.
// Lo pone `main` con la portería (como el drenador del buzón); aquí no se toca la base.
//
// AVISA DE TODAS, y tira todo, cuando el código es "" (un aviso que no se entendió, o sin sucursal) o
// cuando Reparto no conoce esa sucursal (p. ej. `MOA` o `PLS`, que existen en Accesos y no en Reparto):
// ante la duda, tira todas. Equivocarse hacia «avisé de más» cuesta una petición; hacia «no avisé», un
// punto viejo en el cobro.
func CambiaronLosAlmacenes(ctx context.Context, sucursalDe func(ctx context.Context, codigo string) (uuid.UUID, bool), codigo string) {
	if o, ok := Accesos.(interface{ Olvidar() }); ok {
		o.Olvidar()
	}
	sucursal := DeTodasLasSucursales
	if codigo != "" {
		if id, ok := sucursalDe(ctx, codigo); ok {
			sucursal = deLaFila(id)
		}
	}
	avisarCambioDeAlmacenes(ctx, sucursal)
}

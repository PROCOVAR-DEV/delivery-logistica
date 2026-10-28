package alcance

// LA PUERTA A LAS LÁPIDAS DE LA BAJADA.
//
// Vale la misma regla que en `consultas.go`, `rutas.go` y `tablero.go`: es ESTE fichero
// —y no el manejador— quien rellena el parámetro `sucursal`, así que el manejador no
// puede olvidarlo. Va en fichero aparte por lo mismo que los otros dos: para no pisarle
// el fichero a nadie.
//
// Las lápidas de PEDIDOS no están aquí: tienen su propio método en `tablero.go`
// (`EspejoPedidosQueSalieron`), sobre su propia tabla de 00003. Esto es para las demás
// colecciones, sobre `bajas_de_la_bajada` de 00006.

import (
	"context"
	"time"

	"procovar/reparto-api/internal/store/sqlc"
)

// EspejoBajas: lo que se fue de una colección dentro de la ventana.
//
// NO SE LLAMA EN LA CARGA INICIAL, y por eso no tiene sentido sin `Desde`: al aparato que
// empieza vacío no hay nada que quitarle, y mandarle los borrados de los últimos dos años
// es gastarle la conexión en decirle que borre lo que nunca tuvo. Es la misma regla que
// `EspejoPedidosQueSalieron`, y quien llama la cumple igual.
//
// LOS DOS PARÁMETROS DE SUCURSAL SON DISTINTOS Y NO SOBRA NINGUNO, como en el tablero:
//
//   - el ALCANCE lo pone este método y no se negocia;
//   - `v.Sucursal` es la sucursal PEDIDA, y sólo la llenan las colecciones que se sirven
//     por sucursal —las dos del tablero—. Las demás la dejan nil porque sus listas
//     tampoco la miran, y una lápida acotada distinto que su lista es exactamente cómo se
//     borra de más.
//
// `sinSucursalTambien` copia el `OR v.branch_id IS NULL` que lleva `ListarVehiculos` y no
// lleva `ListarRutas`: dice si un aparato acotado a una sucursal ve también lo que no
// tiene ninguna. Va en `true` para vehículos y en `false` para el resto.
func (a *Acotado) EspejoBajas(
	ctx context.Context,
	coleccion sqlc.ColeccionDeLaBajada,
	v VentanaDeBajada,
	sinSucursalTambien bool,
	cursorMarca *time.Time,
	cursorClave *string,
) ([]sqlc.BajasDeLaBajadaRow, error) {
	desde := v.Desde
	if cursorMarca != nil {
		desde = nil // con cursor, el `desde` no se mira (como en `TandaDelPadron`)
	}
	return a.q.BajasDeLaBajada(ctx, sqlc.BajasDeLaBajadaParams{
		Coleccion:          coleccion,
		CursorMarca:        marcaPg(cursorMarca),
		CursorClave:        cursorClave,
		Desde:              marcaPg(desde),
		Hasta:              marcaPg(&v.Hasta),
		Sucursal:           a.sucursalPg(), // el alcance, que aquí no se negocia
		BranchID:           aPg(v.Sucursal),
		SinSucursalTambien: sinSucursalTambien,
		Tope:               v.Tope,
	})
}

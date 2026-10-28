package api

import (
	"net/http"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// TopeDelCuadre: cuántos ids se sirven POR COLECCIÓN. Una sucursal tiene cientos de facturas vivas y unos
// miles de clientes; pasarse de aquí es un ERROR para el aparato (`truncado`), que NO borra nada con una lista
// a medias.
const TopeDelCuadre = 50000

// CuadreSalida es la respuesta de `GET /api/sync/cuadre`.
type CuadreSalida struct {
	// Colecciones: por el MISMO nombre con el que viajan en `cambios` de la bajada (`orders`, `routes`,
	// `customers`…), los ids de TODO lo que el aparato debería tener. Cada una es siempre un array, nunca null.
	Colecciones map[string][]string `json:"colecciones"`
	// Truncado: las colecciones a las que no les cupieron todos los ids. El aparato NO cuadra una colección
	// truncada: quitaría filas vivas.
	Truncado []string `json:"truncado"`
	// Faltan: colecciones que no se pudieron dar (el tablero sin sucursal). El aparato no las toca.
	Faltan []string `json:"faltan"`
	// Hasta: la hora del servidor a la que se hizo la lista.
	Hasta time.Time `json:"hasta"`
}

// GET /api/sync/cuadre — la red de seguridad de la bajada (28/10/2026, Jose: «el sync no lleva solo facturas»).
//
// La bajada por diferencias solo borra lo que le dicen en `quitados`; una lápida que no llega deja filas
// FANTASMA en el aparato para siempre (el 21/10/2026 se perdieron 828 facturas de Santiago). Este endpoint da
// los ids de TODO lo que el aparato debería tener, de cada colección que guarda, y él quita lo que sobre.
// Mismo alcance y MISMAS listas que la bajada: cada colección sale de la misma llamada que la sirve.
func (s *Servidor) cuadreDeFacturas(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	ctx := r.Context()
	hasta := time.Now().UTC()
	sucursal := sucursalDeLaBajada(r, a)
	salida := CuadreSalida{
		Colecciones: map[string][]string{}, Truncado: []string{}, Faltan: []string{}, Hasta: hasta,
	}
	fallo := func(err error) { httpx.ErrorInterno(w, r, err) }
	poner := func(nombre string, ids []string) {
		if len(ids) > TopeDelCuadre {
			salida.Truncado = append(salida.Truncado, nombre)
			ids = ids[:TopeDelCuadre]
		}
		if ids == nil {
			ids = []string{}
		}
		salida.Colecciones[nombre] = ids
	}

	// Las facturas: lo que una carga completa bajaría (no archivadas y anuladas de los últimos días).
	pedidos, err := a.EspejoIdsParaElCuadre(ctx, alcance.VentanaDeBajada{Hasta: hasta, Sucursal: sucursal, Tope: TopeDelCuadre + 1})
	if err != nil {
		fallo(err)
		return
	}
	poner("orders", cadenas(pedidos))

	sucursales, err := a.ListarSucursalesVisibles(ctx)
	if err != nil {
		fallo(err)
		return
	}
	ids := make([]string, 0, len(sucursales))
	for _, x := range sucursales {
		ids = append(ids, x.ID.String())
	}
	poner("branches", ids)

	vehiculos, err := a.ListarVehiculos(ctx)
	if err != nil {
		fallo(err)
		return
	}
	ids = make([]string, 0, len(vehiculos))
	for _, x := range vehiculos {
		ids = append(ids, x.ID.String())
	}
	poner("vehicles", ids)

	tipos, err := a.ListarTiposDeVehiculo(ctx, nil)
	if err != nil {
		fallo(err)
		return
	}
	ids = make([]string, 0, len(tipos))
	for _, x := range tipos {
		ids = append(ids, x.ID.String())
	}
	poner("vehicle_types", ids)

	distribuidores, err := a.ListarDistribuidores(ctx, nil)
	if err != nil {
		fallo(err)
		return
	}
	ids = make([]string, 0, len(distribuidores))
	for _, x := range distribuidores {
		ids = append(ids, x.ID.String())
	}
	poner("distribuidores", ids)

	rutas, err := a.EspejoListarRutas(ctx)
	if err != nil {
		fallo(err)
		return
	}
	ids = make([]string, 0, len(rutas))
	for _, x := range rutas {
		ids = append(ids, x.ID.String())
	}
	poner("routes", ids)

	productos, err := a.EspejoDiferenciasDeProductos(ctx, alcance.TandaDelPadron{Hasta: hasta, Tope: TopeDelCuadre + 1})
	if err != nil {
		fallo(err)
		return
	}
	ids = make([]string, 0, len(productos))
	for _, x := range productos {
		ids = append(ids, x.ID.String())
	}
	poner("products", ids)

	clientes, err := a.EspejoDiferenciasDeClientes(ctx, alcance.TandaDelPadron{Hasta: hasta, Tope: TopeDelCuadre + 1})
	if err != nil {
		fallo(err)
		return
	}
	ids = make([]string, 0, len(clientes))
	for _, x := range clientes {
		ids = append(ids, x.ID.String())
	}
	poner("customers", ids)

	// El tablero es de UNA sucursal: sin ella no se puede dar y el aparato no lo toca.
	if sucursal == nil {
		salida.Faltan = append(salida.Faltan, "boardColumns", "boardPlacements")
	} else {
		columnas, err := a.ListarColumnasDelTablero(ctx, *sucursal, true)
		if err != nil {
			fallo(err)
			return
		}
		todas := incluirInactivas(r)
		ids = make([]string, 0, len(columnas))
		for _, c := range columnas {
			if c.Activa || todas {
				ids = append(ids, c.ID.String())
			}
		}
		poner("boardColumns", ids)

		colocados, err := a.ListarPedidosColocados(ctx, sqlc.ListarPedidosColocadosParams{BranchID: *sucursal})
		if err != nil {
			fallo(err)
			return
		}
		ids = make([]string, 0, len(colocados))
		for _, p := range colocados {
			ids = append(ids, p.OrderID.String())
		}
		poner("boardPlacements", ids)
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

func cadenas(ids []uuid.UUID) []string {
	salida := make([]string, 0, len(ids))
	for _, id := range ids {
		salida = append(salida, id.String())
	}
	return salida
}

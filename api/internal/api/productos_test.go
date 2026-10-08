package api

// El catálogo. El montaje común está en `clientes_test.go`.

import (
	"context"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/store/sqlc"
)

// --------------------------------------------------------------------------- el doble

// ListarProductos repite el WHERE de `products.sql`: aquí el filtro es ESTRICTO, sin la
// excepción de los que no tienen código que sí tienen los clientes. Un producto sin
// sucursal no tiene ni precio ni existencias de ningún sitio.
func (d *dobleDatos) ListarProductos(_ context.Context, arg sqlc.ListarProductosParams) ([]sqlc.Product, error) {
	d.codigoPedidoAProductos = append(d.codigoPedidoAProductos, arg.Sucursal)
	var salida []sqlc.Product
	for _, p := range d.productos {
		if arg.Sucursal != nil && (p.SucursalCodigo == nil || *p.SucursalCodigo != *arg.Sucursal) {
			continue
		}
		if arg.Q != nil && !strings.Contains(strings.ToLower(p.Name), strings.ToLower(*arg.Q)) {
			continue
		}
		salida = append(salida, p)
	}
	return salida, nil
}

func (d *dobleDatos) UsoDeProductos(_ context.Context, _ sqlc.UsoDeProductosParams) ([]sqlc.UsoDeProductosRow, error) {
	return []sqlc.UsoDeProductosRow{{ProductID: pgDeDatos(datProdStg), Unidades: 7}}, nil
}

func (d *dobleDatos) ObtenerProductoDelAlcance(_ context.Context, arg sqlc.ObtenerProductoDelAlcanceParams) (sqlc.Product, error) {
	for _, p := range d.productos {
		if p.ID != arg.ID {
			continue
		}
		if arg.Sucursal != nil && (p.SucursalCodigo == nil || *p.SucursalCodigo != *arg.Sucursal) {
			return sqlc.Product{}, pgx.ErrNoRows
		}
		return p, nil
	}
	return sqlc.Product{}, pgx.ErrNoRows
}

// ObtenerProducto va SIN alcance a propósito: es la del Super Admin, que corrige el
// catálogo de toda la empresa.
func (d *dobleDatos) ObtenerProducto(_ context.Context, id uuid.UUID) (sqlc.Product, error) {
	for _, p := range d.productos {
		if p.ID == id {
			return p, nil
		}
	}
	return sqlc.Product{}, pgx.ErrNoRows
}

func (d *dobleDatos) ActualizarProducto(_ context.Context, arg sqlc.ActualizarProductoParams) (sqlc.ActualizarProductoRow, error) {
	for i := range d.productos {
		p := &d.productos[i]
		if p.ID != arg.ID {
			continue
		}
		if arg.Name != nil {
			p.Name = *arg.Name
		}
		if arg.Weight != nil {
			p.Weight = *arg.Weight
		}
		if arg.TocarPackaging {
			p.Packaging = arg.Packaging
		}
		if arg.TocarCategory {
			p.Category = arg.Category
		}
		if arg.TocarUnits {
			p.UnitsPerPackage = arg.UnitsPerPackage
		}
		return sqlc.ActualizarProductoRow{
			ID: p.ID, Name: p.Name, Weight: p.Weight, Packaging: p.Packaging,
			UnitsPerPackage: p.UnitsPerPackage, Category: p.Category, Sku: p.Sku,
			SucursalCodigo: p.SucursalCodigo, Price: p.Price, Stock: p.Stock, Unit: p.Unit,
		}, nil
	}
	return sqlc.ActualizarProductoRow{}, pgx.ErrNoRows
}

func (d *dobleDatos) BorrarProducto(_ context.Context, id uuid.UUID) (int64, error) {
	for i, p := range d.productos {
		if p.ID == id {
			d.productos = append(d.productos[:i], d.productos[i+1:]...)
			return 1, nil
		}
	}
	return 0, nil
}

// --------------------------------------------------------------------------- pruebas

// LA PRUEBA QUE IMPORTA, y no es de permisos: el PRECIO es por sucursal. El mismo arroz
// vale 100 en Santiago y 250 en Holguín, así que enseñar el catálogo de Holguín a quien
// vende en Santiago es cotizar un pedido con un precio que allí no se cobra. El fallo se
// descubre con la factura delante, cuando ya no se puede deshacer.
func TestProductosNoSeVeElCatalogoDeOtraSucursalNiPidiendoloEnLaQuery(t *testing.T) {
	d := datosDePrueba()
	h := montarDeDatos(t, d)

	// `?sucursal=HOL` es lo que en delivery TENÍA PRIORIDAD sobre el alcance: bastaba
	// escribirlo en la barra del navegador.
	w := pedirDeDatos(t, h, http.MethodGet, "/api/products?sucursal=HOL", logisticoDeSantiago(t), "", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var lista []ProductoSalida
	leerJSONDeDatos(t, w, &lista)
	if len(lista) != 1 || lista[0].ID != datProdStg {
		t.Fatalf("Santiago vio otro catálogo: %s", w.Body.String())
	}
	if lista[0].Price == nil || *lista[0].Price != 100 {
		t.Fatalf("le llegó el precio de otra sucursal: %s", w.Body.String())
	}
	if n := len(d.codigoPedidoAProductos); n == 0 || d.codigoPedidoAProductos[n-1] == nil ||
		*d.codigoPedidoAProductos[n-1] != "STG" {
		t.Fatalf("a la consulta le llegó %v en vez del código del alcance", d.codigoPedidoAProductos)
	}
	// Y la cabecera tampoco: la sucursal de la persona manda sobre lo que pida el
	// navegador.
	w = pedirDeDatos(t, h, http.MethodGet, "/api/products", logisticoDeSantiago(t), "",
		map[string]string{alcance.CabeceraSucursal: datSucHol.String()})
	if strings.Contains(w.Body.String(), `"price":250`) {
		t.Fatalf("por cabecera se coló el catálogo de Holguín: %s", w.Body.String())
	}
}

// El `sucursal` de la query sí vale cuando NO hay alcance: es el Super Admin mirando
// «todas» que arma un pedido para una sucursal concreta.
func TestProductosElSuperAdminSiPuedePedirUnaSucursal(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())
	w := pedirDeDatos(t, h, http.MethodGet, "/api/products?sucursal=HOL", superAdminDeDatos(t), "", nil)

	var lista []ProductoSalida
	leerJSONDeDatos(t, w, &lista)
	if len(lista) != 1 || lista[0].ID != datProdHol {
		t.Fatalf("el Super Admin no pudo elegir sucursal: %s", w.Body.String())
	}
}

// `usageCount` sale de los pedidos del alcance: es lo que ordena el buscador por lo que la
// gente mueve de verdad.
func TestProductosTraenCuantoSeHanPedido(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())
	w := pedirDeDatos(t, h, http.MethodGet, "/api/products", logisticoDeSantiago(t), "", nil)

	var lista []ProductoSalida
	leerJSONDeDatos(t, w, &lista)
	if len(lista) != 1 || lista[0].UsageCount != 7 {
		t.Fatalf("no llegó el uso: %s", w.Body.String())
	}
}

// La ficha de un producto de otra sucursal es 404, no 403: desde fuera, «no es tuyo» y «no
// existe» tienen que ser lo mismo o se aprende qué ids hay probando.
func TestProductosLaFichaDeOtraSucursalEs404(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())

	w := pedirDeDatos(t, h, http.MethodGet, "/api/products/"+datProdHol.String(), logisticoDeSantiago(t), "", nil)
	if w.Code != http.StatusNotFound {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if got := strings.TrimSpace(w.Body.String()); got != `{"error":"No encontrado"}` {
		t.Fatalf("el literal del contrato es «No encontrado»; salió %q", got)
	}

	// Y el suyo sí se ve.
	w = pedirDeDatos(t, h, http.MethodGet, "/api/products/"+datProdStg.String(), logisticoDeSantiago(t), "", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("no vio ni el suyo: %d %s", w.Code, w.Body.String())
	}
}

// Un id que no es un uuid es 404 y no 400: por fuera no hay diferencia entre «mal escrito»
// y «no está», y contar cuál de las dos es sólo sirve para que alguien pruebe formatos.
func TestProductosUnIdQueNoEsUuidEs404(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())
	w := pedirDeDatos(t, h, http.MethodGet, "/api/products/no-es-un-uuid", logisticoDeSantiago(t), "", nil)
	if w.Code != http.StatusNotFound {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
}

// El catálogo lo lee todo el mundo y lo TOCA sólo el Super Admin: una fila corregida aquí
// la ven las ocho sucursales a la vez, así que no es cosa de quien manda en una.
func TestProductosSoloElSuperAdminToca(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())

	// Un ADMINISTRADOR de sucursal tampoco: es admin, pero de una sola.
	adminDeSucursal := tokenDeDatos(t, map[string]any{
		"sub": "p-adm", "role": "ADMINISTRADOR", "branchId": datSucStg.String(),
	})

	for _, quien := range []string{logisticoDeSantiago(t), adminDeSucursal} {
		for _, metodo := range []string{http.MethodPatch, http.MethodDelete} {
			w := pedirDeDatos(t, h, metodo, "/api/products/"+datProdStg.String(), quien, `{"weight":9}`, nil)
			if w.Code != http.StatusForbidden {
				t.Fatalf("%s: código %d %s", metodo, w.Code, w.Body.String())
			}
			if got := strings.TrimSpace(w.Body.String()); got != `{"error":"Solo el Super Admin puede tocar el catálogo"}` {
				t.Fatalf("%s: mensaje %q", metodo, got)
			}
		}
	}
}

// El PATCH corrige lo que Ventra no da bien, y NO toca lo que no le mandaron: un PATCH que
// sólo quería cambiar el peso no puede borrar el envase.
func TestProductosElPatchNoBorraLoQueNoLeMandaron(t *testing.T) {
	d := datosDePrueba()
	envase, categoria := "saco", "granos"
	d.productos[0].Packaging = &envase
	d.productos[0].Category = &categoria
	h := montarDeDatos(t, d)

	w := pedirDeDatos(t, h, http.MethodPatch, "/api/products/"+datProdStg.String(), superAdminDeDatos(t),
		`{"weight":9.5}`, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var p ProductoSalida
	leerJSONDeDatos(t, w, &p)
	if p.Weight != 9.5 {
		t.Fatalf("no cambió el peso: %+v", p)
	}
	if p.Packaging == nil || *p.Packaging != "saco" {
		t.Fatalf("un PATCH del peso borró el envase: %+v", p)
	}
	if p.Category == nil || *p.Category != "granos" {
		t.Fatalf("un PATCH del peso borró la categoría: %+v", p)
	}

	// Y mandarlo como null SÍ lo borra: es la otra mitad del tri-estado.
	w = pedirDeDatos(t, h, http.MethodPatch, "/api/products/"+datProdStg.String(), superAdminDeDatos(t),
		`{"packaging":null}`, nil)
	leerJSONDeDatos(t, w, &p)
	if p.Packaging != nil {
		t.Fatalf("un null tiene que borrar: %+v", p)
	}
}

// El precio y las existencias NO se corrigen a mano: son de Ventra y la siguiente pasada
// del espejo los vuelve a pisar. Dejarlos editar es prometer un cambio que dura doce horas.
func TestProductosElPrecioNoSeCorrigeAMano(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())
	w := pedirDeDatos(t, h, http.MethodPatch, "/api/products/"+datProdStg.String(), superAdminDeDatos(t),
		`{"price":1,"stock":999}`, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var p ProductoSalida
	leerJSONDeDatos(t, w, &p)
	if p.Price == nil || *p.Price != 100 {
		t.Fatalf("el precio se dejó tocar a mano: %+v", p)
	}
	if p.Stock != nil {
		t.Fatalf("las existencias se dejaron tocar a mano: %+v", p)
	}
}

func TestProductosElBorradoDelSuperAdminFunciona(t *testing.T) {
	h := montarDeDatos(t, datosDePrueba())

	w := pedirDeDatos(t, h, http.MethodDelete, "/api/products/"+datProdStg.String(), superAdminDeDatos(t), "", nil)
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"success":true`) {
		t.Fatalf("%d %s", w.Code, w.Body.String())
	}
	// Y borrar dos veces es 404: no se puede inventar que se borró algo que ya no estaba.
	w = pedirDeDatos(t, h, http.MethodDelete, "/api/products/"+datProdStg.String(), superAdminDeDatos(t), "", nil)
	if w.Code != http.StatusNotFound {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
}

// El alta manual está retirada y se dice POR QUÉ: un 405 pelado parece un fallo del
// servidor, y un cliente viejo seguiría intentándolo.
func TestProductosElAltaManualContesta410ConElPorque(t *testing.T) {
	w := pedirDeDatos(t, montarDeDatos(t, datosDePrueba()), http.MethodPost, "/api/products", superAdminDeDatos(t), `{"name":"x"}`, nil)
	if w.Code != http.StatusGone {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	esperado := `{"error":"El catálogo se trae solo de Ventra (a través de PEDIDO). No hay alta manual de productos."}`
	if got := strings.TrimSpace(w.Body.String()); got != esperado {
		t.Fatalf("mensaje %q", got)
	}
}

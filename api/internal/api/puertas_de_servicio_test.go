package api

import (
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
)

// TODA PERSONA SINTÉTICA DE SERVICIO TIENE QUE VER LAS OCHO SUCURSALES.
//
// Hay tres puertas que no abre una persona sino la llave de servicio: el lote de PEDIDO
// (`/api/quote/batch`), el espejo de productos y el alta de pedidos. Las tres cuelgan del
// contexto un `auth.Usuario` inventado, porque la portería necesita alguien de quien
// partir, y las tres traen datos de LAS OCHO sucursales por definición.
//
// El 16/09/2026 `VeTodasLasSucursales` dejó de ser «no tiene sucursal» y pasó a mirar el
// ROL — que es como tenía que haber sido siempre: «sin sucursal no es por el tipo de
// usuario… un usuario sin sucursal ve todas, eso está malísimo». Dos de las tres puertas
// se actualizaron. La tercera, la de `cotizacion.go`, se quedó sin rol y desde ese momento
// no veía ninguna sucursal: **84 rechazos con 403 en quince minutos**, el lote de PEDIDO
// sin entrar, y ni una línea en la aplicación que lo dijera. Se encontró leyendo el
// registro del servidor.
//
// Esta prueba mira el CÓDIGO y no una petición, a propósito: lo que hay que impedir es que
// alguien añada una puerta más y se le olvide el rol. Montar las rutas conocidas no cazaría
// la siguiente.
//
// ## Y BARRE TODO `api/`, que es la corrección de su primera versión
//
// Nació con una lista de tres ficheros escrita a mano —`cotizacion.go`, `espejo.go`,
// `pedidos.go`— y un suelo de `encontradas < 3`. Su propio comentario decía «lo que hay
// que impedir es que alguien añada una cuarta puerta y se le olvide el rol»… y **la cuarta
// ya existía, ya estaba sin rol, y la prueba estaba verde**: `cmd/espejo/main.go`, el
// proceso del espejo, que no vive bajo `internal/api` y por eso no lo miraba nadie.
//
// Habría muerto en su siguiente despliegue: sin rol la portería devuelve `ErrSinAlcance` y
// el proceso no arranca. Sin espejo no entran clientes, ni catálogo, ni pedidos de PEDIDO.
//
// Una prueba que lee una lista escrita a mano comprueba esa lista, no la regla. Ahora
// recorre el árbol entero desde la raíz del módulo.
func TestLasPersonasSinteticasDeServicioLlevanSuRol(t *testing.T) {
	// `ID: "servicio…"` es la marca: sólo las inventadas se llaman así.
	patron := regexp.MustCompile(`auth\.Usuario\{[^}]*\}`)
	ficheros := ficherosGoDe(t, "..", "..")
	encontradas := 0
	for _, nombre := range ficheros {
		crudo, err := os.ReadFile(nombre)
		if err != nil {
			t.Fatalf("no se pudo leer %s: %v", nombre, err)
		}
		for _, hallado := range patron.FindAllString(string(crudo), -1) {
			if !strings.Contains(hallado, `"servicio`) {
				continue
			}
			encontradas++
			if !strings.Contains(hallado, "Rol:") {
				t.Errorf("%s: esta persona de servicio no lleva Rol, así que "+
					"VeTodasLasSucursales dice que no y la portería contesta 403 a "+
					"todo lo que entre por ahí:\n  %s", nombre, hallado)
				continue
			}
			if !strings.Contains(hallado, "SUPER ADMIN") &&
				!strings.Contains(hallado, "DESARROLLADOR") {
				t.Errorf("%s: el rol de esta persona de servicio no es de los que ven "+
					"las ocho:\n  %s", nombre, hallado)
			}
		}
	}
	// EL SUELO. Sin él, un cambio en cómo se escriben estas personas —otro nombre, otra
	// forma de construirlas— dejaría la prueba recorriendo el árbol sin encontrar nada y
	// pasando en verde para siempre. Son SIETE hoy: las tres de `internal/api`, la de
	// `cmd/espejo`, la del drenaje del buzón hacia PEDIDO (`cmd/api`, 26/09/2026), la de la
	// puerta por donde PEDIDO toca (`webhook_de_pedido.go`, 26/09/2026) y la del aviso del CRM
	// de que cambiaron los almacenes (`servicio:avisos-crm`, `cmd/api`, 20/10/2026: busca la
	// sucursal del aviso con la portería). Si añades una, sube el número; si quitas una, bájalo.
	//
	// Esta prueba cazó la del buzón en el mismo momento de escribirla, que es para lo que
	// está: sin rol, la portería le habría contestado 403 y el trabajador no habría
	// mandado un solo aviso — en silencio, porque nadie mira el registro de una tarea de
	// fondo hasta que alguien pregunta por qué PEDIDO no se entera.
	//
	// Y a la del webhook le habría pasado lo MISMO pero peor: PEDIDO habría recibido un 403,
	// que es de los que descarta a la primera, así que cada aviso se habría tirado al primer
	// intento — y en su pantalla se vería «fallados», sin decir de qué lado está el fallo.
	const hay = 7
	if encontradas != hay {
		t.Fatalf("se encontraron %d puertas de servicio y hay %d: o se añadió una (sube "+
			"el número), o se borró una sin quitar su ruta, o cambió la forma de "+
			"escribirlas y esta prueba dejó de mirar lo que cree", encontradas, hay)
	}
}

// ficherosGoDe recorre el árbol y devuelve los `.go` que NO son pruebas.
//
// Se excluyen las pruebas a propósito: ahí sí se construyen usuarios de mentira llamados
// «servicio» para comprobar justo estas reglas, y contarlos haría fallar el suelo por una
// razón que no es la de verdad.
func ficherosGoDe(t *testing.T, partes ...string) []string {
	t.Helper()
	raiz := filepath.Join(partes...)
	var salida []string
	err := filepath.WalkDir(raiz, func(ruta string, d fs.DirEntry, err error) error {
		switch {
		case err != nil:
			return err
		case d.IsDir() && (d.Name() == "sqlc" || d.Name() == "vendor"):
			// Generado. No se escribe a mano, así que no hay nada que se pueda olvidar.
			return fs.SkipDir
		case d.IsDir(), !strings.HasSuffix(ruta, ".go"),
			strings.HasSuffix(ruta, "_test.go"):
			return nil
		}
		salida = append(salida, ruta)
		return nil
	})
	if err != nil {
		t.Fatalf("no se pudo recorrer %s: %v", raiz, err)
	}
	if len(salida) == 0 {
		t.Fatalf("no se encontró ni un fichero .go bajo %s: la prueba no está mirando "+
			"donde cree", raiz)
	}
	return salida
}

// Y la otra mitad: que el rol que llevan puesto SIRVA de verdad. Una prueba que sólo mire
// el texto se quedaría verde el día que `VeTodasLasSucursales` cambie de criterio.
func TestElRolDeServicioAbreLasOchoSucursales(t *testing.T) {
	// Escritos a mano y no importados: `auth` los tiene en minúscula y sin exportar, y lo
	// que hay que comprobar es LA CADENA que viaja en el token, tal como la escribe
	// Accesos. Una constante compartida taparía el día en que una de las dos se cambie.
	for _, rol := range []string{"SUPER ADMIN", "DESARROLLADOR"} {
		u := &auth.Usuario{ID: "servicio:pedido", Nombre: "servicio", Rol: rol}
		if !alcance.VeTodasLasSucursales(u) {
			t.Errorf("con el rol %q la persona de servicio no ve las ocho: el lote de "+
				"PEDIDO entraría con 403", rol)
		}
	}
	// Y sin rol NO, que es justo el fallo: sin esto la prueba de arriba no significa nada.
	sinRol := &auth.Usuario{ID: "servicio:pedido", Nombre: "servicio"}
	if alcance.VeTodasLasSucursales(sinRol) {
		t.Error("una persona sin rol y sin sucursal NO puede ver las ocho: es la regla 1 " +
			"de la casa, y que la de servicio pase tiene que ser por su rol")
	}
}

// EL LECTOR DE VENTRA: de dónde sale el catálogo de productos.
//
// Ventra es el ERP del que vive la empresa. Aquí se lee, nunca se escribe: es una API
// HTTP de sólo lectura (`docs/API-VENTRA.md`), no un MySQL al que uno se conecte, y vive
// al otro lado de la VPN de WireGuard —desde fuera de la red 10.188.2.0/24 no contesta—.
//
// LAS TRES COSAS QUE HAY QUE SABER ANTES DE TOCAR ESTE FICHERO:
//
//  1. EL PRECIO Y LAS EXISTENCIAS VARÍAN POR SUCURSAL. Sin `?database=` Ventra devuelve
//     un consolidado que no es de ninguna sucursal en concreto, y guardarlo como si lo
//     fuera es peor que no tenerlo: en Camagüey se ofrecería mercancía que sólo hay en La
//     Habana, al precio de La Habana. Por eso `Catalogo` exige la base y por eso la tabla
//     `products` tiene `sucursal_codigo`.
//
//  2. UN CATÁLOGO VACÍO NUNCA ES UNA RESPUESTA BUENA. Una base de Ventra caída contesta
//     con una lista vacía y SIN error (lo dice su propia documentación). Si eso se
//     devolviera como un catálogo bueno, el espejo escribiría cero productos, marcaría la
//     hora y el logístico se quedaría medio día cotizando pedidos sin peso —y el
//     pre-despacho mintiendo— sin un solo aviso. Aquí un vacío se devuelve como ERROR, con
//     el nombre de la base dentro, y el que llama ya sabe no tocar lo que hay guardado.
//
//  3. LOS SLUGS DE LAS BASES SE PREGUNTAN, NO SE ADIVINAN. `granma` es BAYAMO, `sspiritus`
//     es Sancti Spíritus, `tunas` es Las Tunas. Adivinar falla en cuatro de diez y deja una
//     sucursal entera sin catálogo sin que salte nada. Se piden a `/axis/databases` y sólo
//     después se emparejan con NUESTROS códigos de sucursal.
package ventra

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
	"unicode"

	"procovar/reparto-api/internal/api"
	"procovar/reparto-api/internal/config"
)

// Que el compilador avise si la interfaz de `api` cambia y este cliente deja de valer.
// Es la razón de que este paquete importe `api` en vez de declarar su propia fila y
// adaptarla en el arranque: un adaptador a mano se queda viejo en silencio.
var _ api.LectorDeVentra = (*Cliente)(nil)

// PlazoPorDefecto: 30 s. Es un ERP al otro lado de una VPN, no una API de al lado; con
// cinco segundos se corta la bajada del catálogo de una sucursal a media lista.
const PlazoPorDefecto = 30 * time.Second

// Rutas de Ventra. `/products/weights` es la misma que `/axis/products`, pero con
// `database` trae ADEMÁS precio y existencias de esa sucursal, que es lo que hace falta.
const (
	rutaBases    = "/axis/databases"
	rutaCatalogo = "/products/weights"
)

// Cliente lee el catálogo de Ventra. Se construye una vez al arrancar y lo comparten
// todas las peticiones: no guarda estado, así que es seguro usarlo desde varias a la vez.
type Cliente struct {
	base  string
	token string
	plazo time.Duration
	// alias: texto normalizado (el slug de la base o el nombre que Ventra le da a la
	// sucursal) -> NUESTRO código de sucursal.
	alias map[string]string
	http  *http.Client
	reg   *slog.Logger
}

// Nuevo arma el cliente con lo que hay en el entorno.
//
// NO comprueba aquí que estén la URL y el token: quien decide si se enchufa o no es el
// arranque (`cmd/api/main.go`), que sin ellas NO llama a `PonerLectorDeVentra` y deja el
// lector en nil, que es lo que hace que `products/sync` conteste 502 diciendo que no está
// configurado. Aun así cada petición lo vuelve a mirar y lo dice ANTES de salir a la red:
// un «401 de Ventra» es mucho más difícil de relacionar con una variable que falta.
func Nuevo(cfg *config.Config, reg *slog.Logger) *Cliente {
	if reg == nil {
		reg = slog.Default()
	}
	c := &Cliente{
		plazo: PlazoPorDefecto,
		alias: map[string]string{},
		reg:   reg.With("componente", "ventra"),
	}
	for texto, codigo := range codigosConocidos {
		c.alias[texto] = codigo
	}
	if cfg != nil {
		c.base = strings.TrimRight(strings.TrimSpace(cfg.VentraURL), "/")
		c.token = strings.TrimSpace(cfg.VentraToken)
		if cfg.VentraPlazo > 0 {
			c.plazo = cfg.VentraPlazo
		}
		// Lo del entorno PISA a la tabla de aquí dentro: el día que Ventra añada una base
		// o renombre una, se arregla con una variable y un reinicio en vez de con un
		// despliegue de código.
		for codigo, slug := range cfg.VentraBases {
			c.alias[clave(slug)] = strings.ToUpper(strings.TrimSpace(codigo))
		}
	}
	// El plazo va TAMBIÉN en el http.Client y no sólo en el contexto: el del contexto no
	// cubre el tiempo que tarda en establecerse la conexión si el transporte se queda
	// esperando, que por la VPN es justo lo que pasa cuando el túnel está caído.
	c.http = &http.Client{Timeout: c.plazo}
	return c
}

// ---------------------------------------------------------------------------
// Las dos preguntas de `api.LectorDeVentra`
// ---------------------------------------------------------------------------

// Bases devuelve, por CÓDIGO de sucursal nuestro (STG, HOL, CAM...), el slug de la base de
// Ventra que le corresponde.
//
// Devuelve error —y no un mapa a medias— cuando Ventra no contesta o cuando contesta bases
// que no cuadran con ninguna sucursal: las dos cosas dejan sin catálogo a alguien, y el
// espejo tiene que poder decir POR QUÉ.
func (c *Cliente) Bases(ctx context.Context) (map[string]string, error) {
	crudo, err := c.pedir(ctx, rutaBases, nil)
	if err != nil {
		return nil, err
	}
	fs, err := filasDe(crudo, rutaBases)
	if err != nil {
		return nil, err
	}
	if len(fs) == 0 {
		return nil, fmt.Errorf(
			"Ventra no devolvió ninguna base en %s: sin bases no hay catálogo de nadie "+
				"(¿el token tiene el scope axis.read?)", rutaBases)
	}

	bases := make(map[string]string, len(fs))
	var sinCuadrar, caidas []string
	for _, f := range fs {
		slug := texto(f, "database")
		if slug == "" {
			continue // una fila sin slug no se puede pedir: no hay qué poner en ?database=
		}
		nombre := texto(f, "branchName", "name")
		codigo := c.codigoDe(slug, nombre)
		if codigo == "" {
			// Ni error ni invento. `moa` y `palmasoriano` son sucursales de Ventra que no
			// son nuestras, y son diez bases para ocho sucursales: emparejar a la fuerza
			// metería los precios de Moa en Holguín.
			sinCuadrar = append(sinCuadrar, slug)
			continue
		}
		if ya, hay := bases[codigo]; hay {
			c.reg.Warn("dos bases de Ventra para el mismo código de sucursal: se usa la primera",
				"codigo", codigo, "usada", ya, "descartada", slug)
			continue
		}
		if b, hayB := f["connected"].(bool); hayB && !b {
			// Se deja en el mapa igualmente: si se quitara, el espejo diría «sin base de
			// Ventra que le cuadre», que es un motivo falso. Que lo intente y que el
			// vacío de `Catalogo` cuente la verdad.
			caidas = append(caidas, slug)
		}
		bases[codigo] = slug
	}

	if len(bases) == 0 {
		return nil, fmt.Errorf(
			"Ventra devolvió %d bases y ninguna cuadra con un código de sucursal nuestro (%s): "+
				"se empareja con VENTRA_BASES, por ejemplo VENTRA_BASES=STG=santiago,HOL=holguinmoa",
			len(fs), strings.Join(sinCuadrar, ", "))
	}
	if len(sinCuadrar) > 0 {
		c.reg.Info("bases de Ventra sin sucursal nuestra que les cuadre (normal: moa y palmasoriano no son nuestras)",
			"bases", strings.Join(sinCuadrar, ", "))
	}
	if len(caidas) > 0 {
		c.reg.Warn("Ventra dice que estas bases NO están conectadas: su catálogo va a venir vacío",
			"bases", strings.Join(caidas, ", "))
	}
	return bases, nil
}

// Catalogo lee el catálogo de UNA base: nombre, peso, precio y existencias.
//
// `base` no es opcional ni por comodidad: sin `?database=` llega el consolidado de las
// diez, y guardar eso como catálogo de una sucursal concreta es el error caro de aquí.
func (c *Cliente) Catalogo(ctx context.Context, base string) ([]api.FilaDeVentra, error) {
	base = strings.TrimSpace(base)
	if base == "" {
		return nil, errors.New(
			"se pidió el catálogo sin decir de qué base de Ventra: sin ?database= el precio y las " +
				"existencias no son de ninguna sucursal en concreto")
	}
	crudo, err := c.pedir(ctx, rutaCatalogo, url.Values{"database": {base}})
	if err != nil {
		return nil, err
	}
	fs, err := filasDe(crudo, rutaCatalogo)
	if err != nil {
		return nil, err
	}
	// EL VACÍO ES UN ERROR. Ver el encabezado del fichero: una base caída contesta así, sin
	// dar error, y un catálogo vacío tratado como bueno deja los pedidos sin peso.
	if len(fs) == 0 {
		return nil, fmt.Errorf(
			"Ventra devolvió el catálogo vacío para la base %q: una base caída contesta así, sin dar "+
				"error, y tomarlo por bueno dejaría a esa sucursal sin pesos ni precios", base)
	}

	salida := make([]api.FilaDeVentra, 0, len(fs))
	for _, f := range fs {
		salida = append(salida, api.FilaDeVentra{
			Sku:       texto(f, "sku", "productCode", "code"),
			Nombre:    texto(f, "name", "productName", "descripcion"),
			PesoKg:    numero(f, "weightKg", "weight", "pesoKg"),
			Categoria: texto(f, "category", "categoria"),
			Unidad:    texto(f, "unit", "unidad"),
			Envase:    texto(f, "packaging", "envase", "presentacion"),
			UnidadesPorEnvase: numero(f, "unitsPerPackage", "unidadesPorEnvase",
				"unitsPerPack", "unidadesPorBulto"),
			// Los nombres de verdad son `existencias` y `precioUsd`; los demás quedan de
			// red por si un día renombran la columna. Perder TODOS los precios en silencio
			// por un nombre cambiado es el fallo que no se ve: el catálogo sigue entrando,
			// con el mismo número de filas, y todo vale cero.
			Existencias: numero(f, "existencias", "stock", "quantity", "onHand"),
			Precio:      numero(f, "precioUsd", "price", "unitPrice", "salePrice", "precio"),
			// SIN `isActive` SE DA POR ACTIVO. El espejo se salta lo inactivo, así que dar
			// por retirado lo que Ventra no clasifica tiraría el catálogo entero —cero
			// productos escritos— el día que quiten ese campo.
			Activo: booleano(f, true, "isActive", "activo", "active"),
		})
	}
	return salida, nil
}

// ---------------------------------------------------------------------------
// La petición
// ---------------------------------------------------------------------------

// pedir hace el GET y devuelve el cuerpo crudo, o un error que dice qué pasó EN CASTELLANO
// y con la ruta dentro: este mensaje acaba en la respuesta de `products/sync` y lo lee
// quien le dio al botón, no quien escribió esto.
func (c *Cliente) pedir(ctx context.Context, ruta string, q url.Values) ([]byte, error) {
	// Con tope: el catálogo son ~128 productos por sucursal, y si algún día contesta otra
	// cosa —una página de error de un proxy— no se traga la memoria del servicio.
	return c.pedirConTope(ctx, ruta, q, 16<<20)
}

// pedirConTope es [Cliente.pedir] con el tope de lectura a elección. Pasarse del tope es un
// ERROR y no un cuerpo cortado: antes se leía `tope` bytes y se seguía, y un JSON cortado a la
// mitad falla al decodificarse con un mensaje que no dice que el problema fue el tamaño.
func (c *Cliente) pedirConTope(ctx context.Context, ruta string, q url.Values, tope int64) ([]byte, error) {
	// Antes de salir a la red, que es donde se pierde el rastro de una variable que falta.
	if c.base == "" {
		return nil, errors.New("WAREHOUSE_API_URL no está configurada")
	}
	if c.token == "" {
		return nil, errors.New("WAREHOUSE_API_TOKEN no está configurado")
	}

	destino := c.base + ruta
	if len(q) > 0 {
		destino += "?" + q.Encode()
	}
	ctx, cancelar := context.WithTimeout(ctx, c.plazo)
	defer cancelar()

	pet, err := http.NewRequestWithContext(ctx, http.MethodGet, destino, nil)
	if err != nil {
		return nil, fmt.Errorf("WAREHOUSE_API_URL no vale como dirección (%q): %w", c.base, err)
	}
	pet.Header.Set("authorization", "Bearer "+c.token)
	pet.Header.Set("accept", "application/json")

	res, err := c.http.Do(pet)
	if err != nil {
		// Aquí es donde cae la VPN caída, y por eso el «(¿VPN?)» va en el mensaje: es la
		// primera cosa que hay que mirar y la que resuelve nueve de cada diez.
		return nil, fmt.Errorf("no se pudo llegar a Ventra en %s (¿VPN?): %w", ruta, err)
	}
	defer res.Body.Close()

	crudo, err := io.ReadAll(io.LimitReader(res.Body, tope+1))
	if err != nil {
		return nil, fmt.Errorf("Ventra cortó la respuesta de %s a medias (¿VPN?): %w", ruta, err)
	}
	if int64(len(crudo)) > tope {
		return nil, fmt.Errorf("Ventra contestó más de %d MB en %s: no se lee a medias", tope>>20, ruta)
	}
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return nil, fmt.Errorf("Ventra %d en %s: %s", res.StatusCode, ruta, recorte(string(crudo), 200))
	}
	return crudo, nil
}

// ---------------------------------------------------------------------------
// Emparejar las bases con nuestras sucursales
// ---------------------------------------------------------------------------

// codigosConocidos: lo que Ventra contestó el 04/09/2026, probado contra producción y
// escrito en `docs/API-VENTRA.md`. Se mira por el slug y también por el nombre, porque los
// dos han cambiado alguna vez y con los dos hay más posibilidades de acertar.
//
// LO QUE NO ESTÁ AQUÍ ESTÁ FUERA A PROPÓSITO: `moa` y `palmasoriano` son sucursales de
// Ventra que no son nuestras —diez bases para ocho sucursales—. Emparejar MOA con HOL
// «porque cae en Holguín» metería las existencias y los precios de Moa en el catálogo de
// Holguín, y nadie lo notaría hasta cobrar mal un domicilio.
var codigosConocidos = map[string]string{
	// Por el slug que se manda en ?database=
	"CAMAGUEY":   "CAM",
	"GRANMA":     "GR",
	"GUANTANAMO": "GTO",
	"HABANA":     "HAB",
	"HOLGUINMOA": "HOL",
	"SANTIAGO":   "STG",
	"SSPIRITUS":  "SS",
	"TUNAS":      "TUN",
	// Por el nombre que Ventra le da a la sucursal. Ojo con `granma`, que se llama BAYAMO.
	"BAYAMO":           "GR",
	"LA HABANA":        "HAB",
	"HOLGUIN":          "HOL",
	"SANTIAGO DE CUBA": "STG",
	"SANCTI SPIRITUS":  "SS",
	"LAS TUNAS":        "TUN",
}

// codigoDe empareja una base con nuestro código de sucursal. Primero por el slug —que es
// lo único que Ventra garantiza estable— y después por el nombre. Cadena vacía significa
// «ésta no es de ninguna sucursal nuestra», que es un estado normal y no un fallo.
func (c *Cliente) codigoDe(slug, nombre string) string {
	if v, hay := c.alias[clave(slug)]; hay {
		return v
	}
	if v, hay := c.alias[clave(nombre)]; hay {
		return v
	}
	return ""
}

// clave normaliza para comparar: sin tildes, en mayúsculas, sin puntuación y con los
// espacios colapsados. Así "Sancti Spíritus", "SANCTI SPIRITUS" y "sancti  spiritus" son
// la misma cosa, que es como las escribe la gente y como las escriben los ERP.
func clave(s string) string {
	var b strings.Builder
	espacio := false
	for _, r := range strings.TrimSpace(s) {
		r = sinTilde(r)
		switch {
		case unicode.IsLetter(r) || unicode.IsDigit(r):
			if espacio && b.Len() > 0 {
				b.WriteRune(' ')
			}
			espacio = false
			b.WriteRune(unicode.ToUpper(r))
		default:
			espacio = true
		}
	}
	return b.String()
}

// sinTilde quita el acento de las vocales castellanas y la diéresis. Se hace a mano —son
// siete— para no meter una dependencia por esto.
func sinTilde(r rune) rune {
	switch r {
	case 'á', 'à', 'ä', 'â', 'Á', 'À', 'Ä', 'Â':
		return 'a'
	case 'é', 'è', 'ë', 'ê', 'É', 'È', 'Ë', 'Ê':
		return 'e'
	case 'í', 'ì', 'ï', 'î', 'Í', 'Ì', 'Ï', 'Î':
		return 'i'
	case 'ó', 'ò', 'ö', 'ô', 'Ó', 'Ò', 'Ö', 'Ô':
		return 'o'
	case 'ú', 'ù', 'ü', 'û', 'Ú', 'Ù', 'Ü', 'Û':
		return 'u'
	case 'ñ', 'Ñ':
		return 'n'
	}
	return r
}

// ---------------------------------------------------------------------------
// Leer el JSON de un ERP sin fiarse de la forma
// ---------------------------------------------------------------------------
//
// Es la misma lectura tolerante que hace `delivery/src/lib/warehouse.ts` en producción, y
// por la misma razón: Ventra a veces contesta un array pelado y a veces lo envuelve en
// `rows`, `items` o `data`, y los nombres de las columnas han cambiado ya alguna vez. Un
// decodificador con una struct fija y un solo nombre por campo devolvería una lista llena
// de ceros, sin error, y el catálogo entraría «bien» con todos los precios a cero.

// filasDe decodifica el cuerpo y saca la lista de filas, venga como venga.
func filasDe(crudo []byte, ruta string) ([]map[string]any, error) {
	var cuerpo any
	if err := json.Unmarshal(crudo, &cuerpo); err != nil {
		return nil, fmt.Errorf("Ventra contestó algo que no es JSON en %s: %s",
			ruta, recorte(string(crudo), 120))
	}
	return filas(cuerpo), nil
}

func filas(d any) []map[string]any {
	switch v := d.(type) {
	case []any:
		salida := make([]map[string]any, 0, len(v))
		for _, e := range v {
			if m, ok := e.(map[string]any); ok {
				salida = append(salida, m)
			}
		}
		return salida
	case map[string]any:
		for _, envoltorio := range []string{"rows", "items", "data", "products", "databases"} {
			if dentro, hay := v[envoltorio]; hay {
				if fs := filas(dentro); len(fs) > 0 {
					return fs
				}
			}
		}
	}
	return nil
}

// texto: el primer campo que sea una cadena con algo dentro, ya recortado.
func texto(f map[string]any, nombres ...string) string {
	for _, n := range nombres {
		if s, ok := f[n].(string); ok {
			if s = strings.TrimSpace(s); s != "" {
				return s
			}
		}
	}
	return ""
}

// numero: el primer campo con un número dentro, como PUNTERO.
//
// Nil y cero NO son lo mismo y por eso se devuelve puntero: un peso de cero es «pesa
// cero» —que no existe— y un precio de cero es «se regala». Los dos son mentiras
// distintas de «Ventra no lo dijo», y sólo el nil se puede tratar como «no lo sé».
func numero(f map[string]any, nombres ...string) *float64 {
	for _, n := range nombres {
		switch v := f[n].(type) {
		case float64:
			x := v
			return &x
		case json.Number:
			if x, err := v.Float64(); err == nil {
				return &x
			}
		case string:
			// La cadena vacía se descarta ANTES de convertir: en JavaScript `Number('')`
			// es 0, y así es como en delivery se colaban ceros que parecían precios.
			s := strings.TrimSpace(v)
			if s == "" {
				continue
			}
			if x, err := strconv.ParseFloat(s, 64); err == nil {
				return &x
			}
		}
	}
	return nil
}

// booleano: el primer campo booleano, y `porDefecto` si no viene ninguno. También lee
// "true"/"false" y 1/0, que es como lo manda un ERP que pasó por una hoja de cálculo.
func booleano(f map[string]any, porDefecto bool, nombres ...string) bool {
	for _, n := range nombres {
		switch v := f[n].(type) {
		case bool:
			return v
		case float64:
			return v != 0
		case string:
			if b, err := strconv.ParseBool(strings.TrimSpace(v)); err == nil {
				return b
			}
		}
	}
	return porDefecto
}

// recorte deja el mensaje en algo que quepa en una pantalla: una página de error entera
// dentro de la respuesta de `products/sync` no ayuda a nadie.
func recorte(s string, n int) string {
	s = strings.Join(strings.Fields(s), " ")
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}

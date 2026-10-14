package config_test

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"procovar/reparto-api/internal/config"
)

// Lo que se prueba aquí no es que lea variables: es que NO ARRANQUE cuando falta algo.
// Un servicio que se levanta a medias pasa la comprobación de salud del desplegador y da
// 500 a media tarde, en la pantalla de alguien que está cargando un camión.

const secretoBueno = "un-secreto-de-pruebas-de-al-menos-32-caracteres"

func TestSinVariablesObligatoriasNoArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "")
	t.Setenv("JWT_SECRET", "")

	_, err := config.Cargar("dev")
	if err == nil {
		t.Fatal("tenía que fallar")
	}
	// Las dos en el MISMO mensaje: ir de una en una son dos despliegues para descubrir
	// dos variables.
	if !strings.Contains(err.Error(), "DATABASE_URL") || !strings.Contains(err.Error(), "JWT_SECRET") {
		t.Fatalf("el mensaje tiene que nombrar las dos que faltan: %v", err)
	}
}

func TestSecretoCortoNoArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", "corto")

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "JWT_SECRET") {
		t.Fatalf("un secreto corto se rompe fuera de línea y abre la sucursal entera: %v", err)
	}
}

func TestCadenaDeConexionQueNoLoEsNoArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "localhost")
	t.Setenv("JWT_SECRET", secretoBueno)

	if _, err := config.Cargar("dev"); err == nil {
		t.Fatal("tenía que fallar antes de intentar conectarse")
	}
}

func TestValorMalFormadoNoArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)

	casos := map[string]map[string]string{
		"puerto que no es número":    {"PUERTO": "ocho mil"},
		"entorno inventado":          {"ENTORNO": "casi-produccion"},
		"duración sin unidad":        {"TIEMPO_LECTURA": "30"},
		"conexiones en negativo":     {"POOL_MAX_CONNS": "-1"},
		"mínimo mayor que el máximo": {"POOL_MIN_CONNS": "50", "POOL_MAX_CONNS": "10"},
	}
	for nombre, vars := range casos {
		t.Run(nombre, func(t *testing.T) {
			for k, v := range vars {
				t.Setenv(k, v)
			}
			if _, err := config.Cargar("dev"); err == nil {
				t.Fatal("tenía que fallar al arrancar")
			}
		})
	}
}

func TestConLoObligatorioArrancaConLosValoresDeLaCasa(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)

	c, err := config.Cargar("v1.2.3")
	if err != nil {
		t.Fatalf("tenía que arrancar: %v", err)
	}
	if c.Direccion() != ":8080" {
		t.Fatalf("puerto por defecto: %q", c.Direccion())
	}
	if c.Version != "v1.2.3" {
		t.Fatalf("la versión la incrusta el compilador: %q", c.Version)
	}
	if c.EnProduccion() {
		t.Fatal("por defecto NO es producción: quien despliega tiene que decirlo")
	}
}

// ---------------------------------------------------------------------------
// Las variables de las otras aplicaciones de la casa
// ---------------------------------------------------------------------------

// Las URLs mal escritas se cazan AL ARRANCAR. Una `PEDIDO_API_URL` sin esquema no falla al
// concatenar: falla al hacer la petición, dentro de una goroutine de fondo, y lo único que
// se ve es un aviso que no llegó a nadie.
func TestUnaUrlSinEsquemaNoArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)

	casos := map[string]map[string]string{
		"PEDIDO_API_URL sin esquema":     {"PEDIDO_API_URL": "pedido.procovar.cloud"},
		"DELIVERY_URL sin esquema":       {"DELIVERY_URL": "localhost:8080"},
		"PROCOVAR_AUTH_URL sin esquema":  {"PROCOVAR_AUTH_URL": "auth.procovar.cloud"},
		"milisegundos que no son número": {"CATALOGO_CADA_MS": "doce horas"},
		"milisegundos en negativo":       {"ALMACENES_CACHE_MS": "-5"},
	}
	for nombre, vars := range casos {
		t.Run(nombre, func(t *testing.T) {
			for k, v := range vars {
				t.Setenv(k, v)
			}
			if _, err := config.Cargar("dev"); err == nil {
				t.Fatal("tenía que fallar al arrancar")
			}
		})
	}
}

// Sin ellas SÍ arranca, y con los valores de la casa. `PEDIDO_API_URL` no es obligatoria a
// propósito: sin ella el servicio hace todo lo demás y las dos cosas que la necesitan —el
// canal y el recosteo— lo DICEN en vez de callarse.
func TestSinLasDeFueraArrancaConLosValoresDeLaCasa(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)

	c, err := config.Cargar("dev")
	if err != nil {
		t.Fatalf("tenía que arrancar sin las de fuera: %v", err)
	}
	if c.PedidoAPIURL != "" || c.DeliveryURL != "" || c.AuthSigningKey != "" {
		t.Fatalf("no se inventa ninguna: %q %q %q", c.PedidoAPIURL, c.DeliveryURL, c.AuthSigningKey)
	}
	if c.AuthURL != "https://auth.procovar.cloud" {
		t.Fatalf("la URL de Accesos por defecto es la de la casa, y salió %q", c.AuthURL)
	}
	if c.AuthPublicURL != c.AuthURL {
		t.Fatalf("sin PROCOVAR_AUTH_PUBLIC_URL la pública es la misma, y salió %q", c.AuthPublicURL)
	}
	if c.AuthClientID != "delivery" {
		t.Fatalf("el cliente por defecto es \"delivery\", y salió %q", c.AuthClientID)
	}
	if c.CatalogoCada != 12*time.Hour {
		t.Fatalf("el catálogo se baja cada 12 h por defecto, y salió %s", c.CatalogoCada)
	}
	if c.AlmacenesCache != 5*time.Minute {
		t.Fatalf("los almacenes se recuerdan 5 min por defecto, y salió %s", c.AlmacenesCache)
	}
}

// La barra final se quita AQUÍ y no en cada sitio que concatena: una de más produce
// `//integration/orders/status`, que unos servidores toleran y otros contestan con un 404
// que nadie sabe explicar.
func TestALasUrlsSeLesQuitaLaBarraFinal(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	t.Setenv("PEDIDO_API_URL", "https://pedido.procovar.cloud/")
	t.Setenv("CATALOGO_CADA_MS", "60000")

	c, err := config.Cargar("dev")
	if err != nil {
		t.Fatalf("tenía que arrancar: %v", err)
	}
	if c.PedidoAPIURL != "https://pedido.procovar.cloud" {
		t.Fatalf("no se le quitó la barra: %q", c.PedidoAPIURL)
	}
	if c.CatalogoCada != time.Minute {
		t.Fatalf("CATALOGO_CADA_MS viene en milisegundos: %s", c.CatalogoCada)
	}
}

// --------------------------------------------------------------- versión publicada

// Lo normal: nadie ha colgado nada todavía. No es un error y no hay anuncio.
func TestSinNadaPublicadoArrancaYNoAnuncia(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)

	c, err := config.Cargar("dev")
	if err != nil {
		t.Fatalf("tenía que arrancar: %v", err)
	}
	if c.Publicada.HayAlguna() {
		t.Fatalf("no se colgó nada y aun así hay anuncio: %+v", c.Publicada)
	}
}

// Media configuración es la peor: el enlace puesto y la versión no. No se avisaría nunca,
// sin un solo error a la vista. Tiene que parar el arranque, que es cuando lo ve quien
// despliega.
func TestDescargaSinVersionNoArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	t.Setenv("APP_DESCARGA_ANDROID", "https://descargas.procovar.cloud/reparto.apk")

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "APP_ULTIMA_VERSION") {
		t.Fatalf("el mensaje tiene que nombrar la variable que falta: %v", err)
	}
}

// Y al revés: versión anunciada sin ningún sitio de donde bajarla son diez personas
// enteradas de que tienen que actualizar y ningún enlace.
func TestVersionSinDescargaNoArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	t.Setenv("APP_ULTIMA_VERSION", "1.5.0")

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "APP_DESCARGA") {
		t.Fatalf("tenía que exigir de dónde se baja: %v", err)
	}
}

func TestDescargaSinEsquemaNoArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	t.Setenv("APP_ULTIMA_VERSION", "1.5.0")
	t.Setenv("APP_DESCARGA_ANDROID", "descargas.procovar.cloud/reparto.apk")

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "http://") {
		t.Fatalf("una URL sin esquema no se puede abrir: %v", err)
	}
}

// La compilación es el `versionCode`. Una errata ahí —«12a», «v12»— haría que el aparato
// comparase contra cero y no avisara nunca.
func TestCompilacionQueNoEsNumeroNoArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	t.Setenv("APP_ULTIMA_VERSION", "1.5.0")
	t.Setenv("APP_ULTIMA_COMPILACION", "v12")
	t.Setenv("APP_DESCARGA_ANDROID", "https://descargas.procovar.cloud/reparto.apk")

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "APP_ULTIMA_COMPILACION") {
		t.Fatalf("tenía que quejarse del número: %v", err)
	}
}

func TestLaFechaSeNormaliza(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	t.Setenv("APP_ULTIMA_VERSION", "1.5.0")
	t.Setenv("APP_ULTIMA_PUBLICADA", "2026-09-15")
	t.Setenv("APP_DESCARGA_LINUX", "https://descargas.procovar.cloud/reparto-linux.tar.gz")
	t.Setenv("APP_DESCARGA_LINUX_BYTES", "77646816")
	t.Setenv("APP_DESCARGA_LINUX_SHA256", huellaDeEjemplo)

	c, err := config.Cargar("dev")
	if err != nil {
		t.Fatalf("tenía que arrancar: %v", err)
	}
	if c.Publicada.PublicadaAt != "2026-09-15T00:00:00Z" {
		t.Fatalf("fecha %q", c.Publicada.PublicadaAt)
	}
}

// --------------------------------------------- El canal muerto tiene que DECIRSE
//
// Hasta el 24/09/2026 `APP_ULTIMA_VERSION` vacía era un `Warn` en el registro y nada más:
// la api arrancaba verde y `/api/version` contestaba `ultima: null`, que desde fuera no se
// distingue de «no hay ninguna versión nueva». Los aparatos están en la calle y casi todo
// el día sin señal, así que ese silencio les cuesta semanas de versión vieja.

// EN PRODUCCIÓN NO ARRANCA. Es el momento en que lo ve quien despliega, igual que todo lo
// demás de esta configuración.
func TestEnProduccionSinAnuncioNoArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	t.Setenv("ENTORNO", "produccion")
	t.Setenv("APP_ULTIMA_VERSION", "")
	t.Setenv("APP_SIN_ANUNCIO", "")

	_, err := config.Cargar("dev")
	if err == nil {
		t.Fatal("el canal de actualización estaría muerto y la api arrancaría verde")
	}
	// El mensaje tiene que nombrar la variable Y la salida, o quien lo lea a las once de
	// la noche no sabe qué hacer con él.
	for _, quiero := range []string{"APP_ULTIMA_VERSION", "APP_SIN_ANUNCIO"} {
		if !strings.Contains(err.Error(), quiero) {
			t.Fatalf("el mensaje tiene que nombrar %s: %v", quiero, err)
		}
	}
}

// Y se puede decir que no se anuncia nada, pero hay que ESCRIBIRLO: así queda en el
// Environment de Dokploy como una decisión y no como un descuido.
func TestEnProduccionSePuedeDecirQueNoSeAnunciaNada(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	t.Setenv("ENTORNO", "produccion")
	t.Setenv("APP_ULTIMA_VERSION", "")
	t.Setenv("APP_SIN_ANUNCIO", "si")

	c, err := config.Cargar("dev")
	if err != nil {
		t.Fatalf("dicho a propósito, tiene que arrancar: %v", err)
	}
	if c.Publicada.HayAlguna() {
		t.Fatalf("no se anuncia nada y aun así hay anuncio: %+v", c.Publicada)
	}
}

// Un valor raro NO vale por «sí». Si valiera, un `APP_SIN_ANUNCIO=no` apagaría la guarda
// diciendo justo lo contrario de lo que dice, y nadie miraría dos veces esa línea.
func TestAppSinAnuncioConValorRaroNoArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	t.Setenv("ENTORNO", "produccion")
	t.Setenv("APP_ULTIMA_VERSION", "")
	t.Setenv("APP_SIN_ANUNCIO", "no")

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "APP_SIN_ANUNCIO") {
		t.Fatalf("`no` no puede significar `si`: %v", err)
	}
}

// En DESARROLLO sigue arrancando sin decir nada: levantar el reparto en el portátil para
// mirar una pantalla no puede depender de que haya un APK publicado.
func TestEnDesarrolloSinAnuncioArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	t.Setenv("ENTORNO", "desarrollo")
	t.Setenv("APP_ULTIMA_VERSION", "")
	t.Setenv("APP_SIN_ANUNCIO", "")

	if _, err := config.Cargar("dev"); err != nil {
		t.Fatalf("en desarrollo tiene que arrancar igual: %v", err)
	}
}

// ------------------------------------------- Y el canal VIVO, del compose al anuncio
//
// EL CAMINO ENTERO, con los valores de verdad. `docker-compose.yml` es el único sitio del
// repositorio donde el canal de actualización se lee completo, y los MISMOS tres datos son
// los que van al Environment de `reparto-api` en Dokploy. Si alguien vacía una de esas
// líneas —o cuelga un APK y se olvida de los bytes o de la huella—, esto se pone rojo aquí
// en vez de dejar diez aparatos sin enterarse durante semanas.
//
// Se lee el fichero y no se copian los valores a mano: dos sitios con el mismo número se
// separan sin que salte nada (CLAUDE.md §3-bis).
func TestElComposeAnunciaUnaVersionCompleta(t *testing.T) {
	compose := leerCompose(t)

	version := compose["APP_ULTIMA_VERSION"]
	if version == "" {
		t.Fatal("APP_ULTIMA_VERSION está vacía en docker-compose.yml: el canal de " +
			"actualización está muerto y un aparato en la calle no se entera nunca de que " +
			"hay una versión nueva. Si es a propósito, se dice con APP_SIN_ANUNCIO=si y se " +
			"cambia esta prueba a mano, con el motivo escrito")
	}

	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	for _, nombre := range []string{
		"APP_ULTIMA_VERSION", "APP_ULTIMA_COMPILACION", "APP_ULTIMA_PUBLICADA",
		"APP_DESCARGA_ANDROID", "APP_DESCARGA_ANDROID_BYTES", "APP_DESCARGA_ANDROID_SHA256",
	} {
		t.Setenv(nombre, compose[nombre])
	}

	c, err := config.Cargar("dev")
	if err != nil {
		t.Fatalf("lo que hay en docker-compose.yml no arranca: %v", err)
	}
	if !c.Publicada.HayAlguna() || c.Publicada.Version != version {
		t.Fatalf("no se anuncia la versión del compose (%q): %+v", version, c.Publicada)
	}
	// La compilación es lo ÚNICO que Android compara de verdad al instalar encima. Sin
	// ella se comparan los números del `1.0.1` y la 1.10 no se anunciaría nunca.
	if c.Publicada.Compilacion <= 0 {
		t.Fatalf("falta APP_ULTIMA_COMPILACION (el versionCode): %+v", c.Publicada)
	}
	if c.Publicada.Android == "" {
		t.Fatal("se avisaría de una versión nueva sin decir de dónde bajarla")
	}
	f, hay := c.Publicada.Ficheros["android"]
	if !hay {
		t.Fatalf("la descarga va sin tamaño ni huella: %+v", c.Publicada.Ficheros)
	}
	// Sin bytes la pantalla enseña «30 MB/?» por datos móviles —Cloudflare quita el
	// Content-Length— y sin huella una descarga cortada pasa por buena.
	if f.Bytes <= 0 {
		t.Fatalf("bytes %d", f.Bytes)
	}
	if len(f.SHA256) != 64 {
		t.Fatalf("huella %q", f.SHA256)
	}
	if f.SHA256 != strings.ToLower(compose["APP_DESCARGA_ANDROID_SHA256"]) {
		t.Fatalf("la huella que se anuncia no es la del compose: %q", f.SHA256)
	}
}

// leerCompose saca los valores por defecto de las `APP_*` de `docker-compose.yml`, o sea
// el `X` de `APP_LO_QUE_SEA: ${APP_LO_QUE_SEA:-X}`.
//
// El fichero vive FUERA de `api/`, así que el `Dockerfile.api` lo copia a la misma ruta
// relativa que tiene en el repositorio — igual que `docs/orden-de-paradas.casos.json`.
// «Una imagen no es esta máquina» (CLAUDE.md §4-bis): esto pasaba en el portátil y tiraba
// la construcción sin ese COPY.
func leerCompose(t *testing.T) map[string]string {
	t.Helper()
	ruta := filepath.Join("..", "..", "..", "docker-compose.yml")
	crudo, err := os.ReadFile(ruta)
	if err != nil {
		t.Fatalf("no se pudo leer %s: %v", ruta, err)
	}
	patron := regexp.MustCompile(`(?m)^\s*(APP_[A-Z0-9_]+):\s*\$\{[A-Z0-9_]+:-(.*)\}\s*$`)
	valores := map[string]string{}
	for _, m := range patron.FindAllStringSubmatch(string(crudo), -1) {
		valores[m[1]] = strings.TrimSpace(m[2])
	}
	if len(valores) == 0 {
		t.Fatal("no se encontró ninguna APP_* en docker-compose.yml: o se movieron de sitio " +
			"o cambió la forma de escribirlas, y esta prueba dejaría de mirar nada")
	}
	return valores
}

// --------------------------------------------------------------------------- Ventra

// SIN VENTRA SE ARRANCA IGUAL. Es el mismo trato que PEDIDO_API_URL: el servicio hace todo
// lo demás y `POST /api/products/sync` contesta 502 diciendo que no hay lector. Morir aquí
// dejaría el reparto entero parado por no poder bajar el catálogo, que es una parte.
func TestSinLoDeVentraSeArrancaIgual(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	t.Setenv("WAREHOUSE_API_URL", "")
	t.Setenv("WAREHOUSE_API_TOKEN", "")

	c, err := config.Cargar("dev")
	if err != nil {
		t.Fatalf("tenía que arrancar sin Ventra: %v", err)
	}
	if c.VentraURL != "" || c.VentraToken != "" {
		t.Fatalf("tenían que quedar vacías: %q %q", c.VentraURL, c.VentraToken)
	}
	// Y con el plazo de la casa puesto: es un ERP al otro lado de una VPN.
	if c.VentraPlazo != 30*time.Second {
		t.Fatalf("plazo %v", c.VentraPlazo)
	}
}

// La barra final se quita AQUÍ y no en cada sitio que concatena: una de más produce
// `//axis/databases`, que unos servidores toleran y otros contestan con un 404 que nadie
// sabe explicar.
func TestLaURLDeVentraPierdeLaBarraFinal(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	t.Setenv("WAREHOUSE_API_URL", "http://10.188.2.2:3001/api/external-api/")
	t.Setenv("WAREHOUSE_API_TOKEN", "  un-token  ")

	c, err := config.Cargar("dev")
	if err != nil {
		t.Fatalf("%v", err)
	}
	if c.VentraURL != "http://10.188.2.2:3001/api/external-api" {
		t.Fatalf("url %q", c.VentraURL)
	}
	if c.VentraToken != "un-token" {
		t.Fatalf("el token va recortado, que un espacio de más en un Bearer es un 401: %q", c.VentraToken)
	}
}

// Una URL sin esquema no falla al arrancar ni al concatenar: falla al hacer la petición, y
// lo único que se ve entonces es un catálogo que no baja.
func TestURLDeVentraSinEsquemaNoArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	t.Setenv("WAREHOUSE_API_URL", "10.188.2.2:3001/api/external-api")

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "WAREHOUSE_API_URL") {
		t.Fatalf("tenía que quejarse al desplegar: %v", err)
	}
}

// VENTRA_BASES es lo que empareja nuestras sucursales con las bases de Ventra el día que
// añadan una. Mal escrita e ignorada en silencio, esa sucursal se queda sin catálogo.
func TestVentraBasesSeLeeYSeValida(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	t.Setenv("VENTRA_BASES", "stg=santiago, HOL = holguinmoa")

	c, err := config.Cargar("dev")
	if err != nil {
		t.Fatalf("%v", err)
	}
	if c.VentraBases["STG"] != "santiago" || c.VentraBases["HOL"] != "holguinmoa" {
		t.Fatalf("mapa %v", c.VentraBases)
	}

	t.Setenv("VENTRA_BASES", "STG santiago")
	if _, err := config.Cargar("dev"); err == nil || !strings.Contains(err.Error(), "VENTRA_BASES") {
		t.Fatalf("un par mal escrito tiene que verse al desplegar: %v", err)
	}
}

// El sha256 de mentira que usan las pruebas de aquí abajo. 64 hexadecimales, que es lo
// único que se comprueba al arrancar.
const huellaDeEjemplo = "565647928d03200b2eda25ef28bde55e0f0d3e034f99d561f38b33a6aa47c49e"

func conLoMinimo(t *testing.T) {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	t.Setenv("APP_ULTIMA_VERSION", "1.5.0")
	t.Setenv("APP_DESCARGA_ANDROID", "https://archivos.procovar.cloud/reparto/apk/reparto-1.5.0.apk")
}

// LA PRUEBA DEL DÍA — 22/09/2026. Jose se puso a bajar la APK por datos móviles y la
// pantalla decía «30 MB/?»: no sabía cuánto le iba a costar. El tamaño venía del
// `Content-Length`, y Cloudflare lo quita de la respuesta completa (MinIO sí lo manda;
// se comprobó desde dentro del servidor). Así que ahora el tamaño y la huella se
// anuncian, y anunciar la URL sin ellos para el arranque.
func TestLaDescargaSinBytesNiHuellaNoArranca(t *testing.T) {
	conLoMinimo(t)

	_, err := config.Cargar("dev")
	if err == nil {
		t.Fatal("una descarga sin tamaño ni huella tenía que parar el arranque: sin tamaño " +
			"se baja a ciegas por datos móviles y sin huella un fichero a medias pasa por bueno")
	}
	for _, quiero := range []string{"APP_DESCARGA_ANDROID_BYTES", "APP_DESCARGA_ANDROID_SHA256"} {
		if !strings.Contains(err.Error(), quiero) {
			t.Fatalf("el mensaje tiene que nombrar %s para poder arreglarlo sin adivinar: %v", quiero, err)
		}
	}
}

// Una sola de las dos tampoco vale: con tamaño y sin huella se baja sabiendo lo que
// cuesta y sin poder comprobar que llegó entero, que es el peor de los dos mundos.
func TestSoloElTamanoNoBasta(t *testing.T) {
	conLoMinimo(t)
	t.Setenv("APP_DESCARGA_ANDROID_BYTES", "77646816")

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "APP_DESCARGA_ANDROID_SHA256") {
		t.Fatalf("faltando la huella tenía que quejarse de ella: %v", err)
	}
}

// Un hash con un carácter de menos rechaza TODAS las descargas, para siempre, y desde
// fuera se ve como «la actualización no baja nunca».
func TestUnSha256CortoNoArranca(t *testing.T) {
	conLoMinimo(t)
	t.Setenv("APP_DESCARGA_ANDROID_BYTES", "77646816")
	t.Setenv("APP_DESCARGA_ANDROID_SHA256", huellaDeEjemplo[:63])

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "64") {
		t.Fatalf("tenía que decir cuántos caracteres son un sha256: %v", err)
	}
}

func TestUnSha256QueNoEsHexadecimalNoArranca(t *testing.T) {
	conLoMinimo(t)
	t.Setenv("APP_DESCARGA_ANDROID_BYTES", "77646816")
	t.Setenv("APP_DESCARGA_ANDROID_SHA256", strings.Repeat("z", 64))

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "hexadecimal") {
		t.Fatalf("64 caracteres no bastan si no son hexadecimales: %v", err)
	}
}

func TestBytesQueNoEsNumeroNoArranca(t *testing.T) {
	conLoMinimo(t)
	t.Setenv("APP_DESCARGA_ANDROID_BYTES", "77 MB")
	t.Setenv("APP_DESCARGA_ANDROID_SHA256", huellaDeEjemplo)

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "APP_DESCARGA_ANDROID_BYTES") {
		t.Fatalf("tenía que quejarse del número: %v", err)
	}
}

// Y al revés: el tamaño de una plataforma que no tiene URL es un fichero colgado del que
// nadie se va a enterar. Se dice, en vez de ignorarlo en silencio.
func TestTamanoSueltoSinURLSeDice(t *testing.T) {
	conLoMinimo(t)
	t.Setenv("APP_DESCARGA_ANDROID_BYTES", "77646816")
	t.Setenv("APP_DESCARGA_ANDROID_SHA256", huellaDeEjemplo)
	t.Setenv("APP_DESCARGA_WINDOWS_BYTES", "12345")

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "APP_DESCARGA_WINDOWS") {
		t.Fatalf("un tamaño sin su URL tenía que decirse: %v", err)
	}
}

// El camino bueno, que es el que de verdad se despliega.
func TestLaDescargaCompletaLlegaAlaConfiguracion(t *testing.T) {
	conLoMinimo(t)
	t.Setenv("APP_DESCARGA_ANDROID_BYTES", "77646816")
	t.Setenv("APP_DESCARGA_ANDROID_SHA256", strings.ToUpper(huellaDeEjemplo))

	c, err := config.Cargar("dev")
	if err != nil {
		t.Fatalf("tenía que arrancar: %v", err)
	}
	f, hay := c.Publicada.Ficheros["android"]
	if !hay {
		t.Fatal("la descarga de android tenía que traer su fichero")
	}
	if f.Bytes != 77646816 {
		t.Fatalf("bytes %d", f.Bytes)
	}
	// En minúsculas SIEMPRE: `sha256sum` las escribe así y el aparato compara texto. Una
	// huella en mayúsculas no cuadraría nunca con la que calcula, y el fichero bueno se
	// rechazaría una y otra vez sin que nadie entienda por qué.
	if f.SHA256 != huellaDeEjemplo {
		t.Fatalf("la huella tiene que guardarse en minúsculas: %q", f.SHA256)
	}
}

// Accesos por la red interna de Docker: el servidor usa la interna y el navegador la pública.
func TestAccesosInternoYPublicoVanPorSeparado(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	t.Setenv("PROCOVAR_AUTH_URL", "http://procovar-auth-kx6aey:3500/")
	t.Setenv("PROCOVAR_AUTH_PUBLIC_URL", "https://auth.procovar.cloud/")

	c, err := config.Cargar("dev")
	if err != nil {
		t.Fatal(err)
	}
	if c.AuthURL != "http://procovar-auth-kx6aey:3500" || c.AuthPublicURL != "https://auth.procovar.cloud" {
		t.Fatalf("interna %q, pública %q", c.AuthURL, c.AuthPublicURL)
	}

	t.Setenv("PROCOVAR_AUTH_PUBLIC_URL", "auth.procovar.cloud")
	if _, err := config.Cargar("dev"); err == nil {
		t.Fatal("una pública sin esquema tenía que fallar al arrancar")
	}
}

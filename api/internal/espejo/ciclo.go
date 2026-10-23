package espejo

import (
	"context"
	"errors"
	"log/slog"
	"net/url"
	"strconv"
	"time"
)

// EL CICLO. Lo que pasa en cada vuelta, en este orden y por estas razones.
//
//  1. El catálogo de Ventra, si toca. Aislado: que Ventra no conteste no puede parar los
//     pedidos.
//  2. Los clientes. También aislado.
//  3. LO QUE SE MOVIÓ desde la marca de agua. Es lo que hace que un ciclo cueste nada.
//  4. Los recién cotizados. Es lo que se está mirando en pantalla ahora mismo.
//  5. Un repaso corto a los últimos días, SIEMPRE. Tapa el único agujero del incremental.
//  6. Y se estira el histórico un poco más hacia atrás, si toca.
//
// NINGÚN PASO PUEDE TUMBAR AL SIGUIENTE. Un ciclo que se rinde a la primera es un espejo
// que se queda parado porque una sucursal no contestó, y eso desde fuera no se ve: no hay
// error, simplemente los pedidos dejan de llegar.

// Espejo es el proceso. Todo lo que habla con el mundo entra por interfaz, así que el ciclo
// entero se prueba sin PEDIDO, sin la API del reparto y sin base de datos.
type Espejo struct {
	Opciones Opciones
	Pedido   FuenteDePedidos
	Reparto  DestinoDeLotes
	Base     Base
	Reg      *slog.Logger

	// Facturas y BaseF son la segunda fuente (issue 20, `SYNC_FUENTE=factura|ambas`). NIL
	// cuando la fuente es sólo PEDIDO, que es el valor por defecto: el ciclo ni las mira.
	Facturas FuenteDeFacturas
	BaseF    BaseDeFacturas

	// AvisarCancelada: gancho para avisar a PEDIDO de una factura cancelada. nil = nada. Ver
	// [Espejo.avisarCancelada].
	AvisarCancelada func(ctx context.Context, e EntregaCancelada)

	// Ahora es el reloj. Se puede cambiar en las pruebas: los tramos son fechas contadas
	// hacia atrás desde hoy, y una prueba que dependa del día en que se corra es una prueba
	// que falla sola algún martes.
	Ahora func() time.Time
	// Pausa es el respiro entre peticiones. Sin él, veinte lotes seguidos ahogan a la API
	// del reparto, que está atendiendo además a las personas. En las pruebas va a cero.
	Pausa time.Duration

	// ultimoBarrido es del proceso y no de la base a propósito: es «cuándo barrí yo la
	// última vez», y al reiniciar tiene que barrer pronto. Por dónde iba sí se guarda, que
	// es otra cosa.
	ultimoBarrido time.Time

	// ultimoDePedido: cuándo hizo el trabajo de PEDIDO el último ciclo. Con `SYNC_FUENTE=ambas`
	// el ciclo gira cada minuto por la factura, y esto es lo que deja a PEDIDO en su ritmo.
	ultimoDePedido time.Time
	// ultimoBarridoDeFacturas: por sucursal, cuándo se barrió su histórico de facturas con ÉXITO.
	// Si falla no se apunta, y el ciclo siguiente vuelve a intentarlo en vez de esperar un día.
	ultimoBarridoDeFacturas map[string]time.Time
}

// Nuevo arma el espejo con los clientes de verdad.
func Nuevo(o Opciones, base Base, reg *slog.Logger) *Espejo {
	if reg == nil {
		reg = slog.Default()
	}
	e := &Espejo{
		Opciones: o,
		Pedido:   NuevoClientePedido(o.PedidoURL, o.Clave),
		Reparto:  NuevoClienteDelivery(o.DeliveryURL, o.Clave),
		Base:     base,
		Reg:      reg,
		Ahora:    time.Now,
		Pausa:    150 * time.Millisecond,
	}
	// La base de verdad sabe hacer las dos cosas; un doble de pruebas sólo la mitad de PEDIDO.
	if bf, ok := base.(BaseDeFacturas); ok {
		e.BaseF = bf
	}
	return e
}

// ConFacturas enchufa el lector de Ventra. Sin llamarlo, `SYNC_FUENTE=factura|ambas` no puede
// arrancar (`Correr` lo comprueba): un espejo «de facturas» sin Ventra parecería sano sin traer
// una sola.
func (e *Espejo) ConFacturas(f FuenteDeFacturas) *Espejo {
	e.Facturas = f
	return e
}

// Correr da vueltas hasta que se cancele el contexto.
//
// EL MODO «POR AVISOS» VOLVIÓ el 26/09/2026, y esta vez con quien publica al otro lado.
//
// Se había quitado porque escuchaba una cola donde PEDIDO ya no publicaba: un proceso
// esperando avisos que nunca llegan no da error —simplemente no hace nada—, y eso es peor
// que no tenerlo porque parece que funciona. Ahora PEDIDO sí escribe
// (`DELIVERY_EVENTS=true`, stream `procovar-delivery:in:orders`), y el escuchador vive
// aparte, en `escuchar_a_pedido.go`, corriendo EN PARALELO con este bucle.
//
// ESTE CICLO NO SE QUITA, y ésa es la mitad que importa: es la red debajo del trapecio. Si
// Redis se cae, si un aviso se pierde, o si alguien corrige la base por SQL sin tocar
// `updatedAt`, esto lo recoge igual. Lo que cambia es que puede ir mucho más despacio
// —`SYNC_POLL_MS`— porque ya no es quien se entera de las cosas, sino quien comprueba que
// nada se quedó por el camino.
func (e *Espejo) Correr(ctx context.Context) error {
	// EL RITMO DEPENDE DE SI A ALGUIEN LE AVISAN. Con una de las dos puertas puesta, el
	// ciclo deja de ser quien se entera y pasa a ser quien comprueba: tres horas. Sin
	// ninguna sigue cada minuto, porque entonces es lo ÚNICO que trae los cambios y dejarlo
	// lento pondría al reparto tres horas por detrás sin que nada lo diga.
	if e.Opciones.LeeFactura() && (e.Facturas == nil || e.BaseF == nil) {
		return errors.New("SYNC_FUENTE=" + e.Opciones.Fuente + " pero el espejo no tiene el lector de Ventra o " +
			"su base: no se arranca, porque parecería sano sin traer una sola factura")
	}
	ritmo := e.Opciones.RitmoDelCiclo(e.Opciones.PollDelEntorno)
	// SE DICEN LAS DOS PUERTAS POR SEPARADO, y no un «con avisos» que las resume.
	//
	// Es la única línea que contesta «¿por qué va a este ritmo?» cuando alguien lo pregunta
	// dentro de tres semanas. Con el resumen, un ciclo lento porque lee la cola y uno lento
	// porque le tocan la puerta se ven idénticos — y si lo que falla es la puerta, saber que
	// estaba puesta es justo el dato que hace falta.
	e.Reg.Info("espejo arrancado",
		"pedido", e.Opciones.PedidoURL, "reparto", e.Opciones.DeliveryURL,
		"cada", ritmo,
		"lee la cola", e.Opciones.EscuchaLosAvisos(),
		"hay redis", e.Opciones.HayRedis(),
		"le tocan la puerta", e.Opciones.TocanLaPuerta,
		"fuente", e.Opciones.Fuente,
		"sucursal", e.sucursalODejarTodas())

	temporizador := time.NewTimer(0)
	defer temporizador.Stop()
	for {
		select {
		case <-ctx.Done():
			// Apagado ordenado: se sale entre vueltas y no a mitad de una. Un ciclo
			// cortado por la mitad no deja nada roto —cada lote es su propia
			// transacción—, pero sí deja medio tramo sin traer y un registro que no
			// cuadra con lo que hay.
			e.Reg.Info("espejo parado")
			return nil
		case <-temporizador.C:
		}

		if err := e.Ciclo(ctx); err != nil {
			if ctx.Err() != nil {
				e.Reg.Info("espejo parado")
				return nil
			}
			// Un ciclo que falla NO para el proceso: lo que no entró hoy entra en la
			// vuelta siguiente, y morirse aquí obligaría a que alguien lo levantara.
			e.Reg.Error("el ciclo falló entero", "err", err)
		}
		temporizador.Reset(ritmo)
	}
}

// Ciclo es una pasada. Es lo que corre `--once`.
func (e *Espejo) Ciclo(ctx context.Context) error {
	e.catalogo(ctx)
	// LOS CLIENTES SE QUEDAN EN PEDIDO con cualquier fuente (Jose, 20/10/2026): de su espejo
	// salen las coordenadas de las entregas que nacen de una factura.
	e.clientes(ctx)

	total := 0
	var marca *time.Time

	// LO DE PEDIDO, si la fuente lo incluye y si le toca. Con `SYNC_FUENTE=ambas` el ciclo gira
	// al ritmo de la factura (cada minuto) y PEDIDO conserva el suyo (`RitmoDePedido`): sin esta
	// puerta, tener las dos fuentes costaría 1.440 repasos al día de PEDIDO que con avisos eran 8.
	if e.Opciones.LeePedido() && e.lePuedeTocarAPedido() {
		e.ultimoDePedido = e.Ahora()
		n, m := e.pedidos(ctx)
		total += n
		marca = m
	}

	// --- 5. La factura de Ventra, si la fuente la incluye -----------------------
	if e.Opciones.LeeFactura() {
		total += e.facturas(ctx)
	}

	if total == 0 {
		desde := "el principio"
		if marca != nil {
			desde = marca.Format(time.RFC3339)
		}
		e.Reg.Info("sin cambios", "desde", desde)
	} else {
		e.Reg.Info("pedidos guardados", "pedidos", total)
	}
	return ctx.Err()
}

// lePuedeTocarAPedido: ¿ya pasó el ritmo propio de PEDIDO desde la última vez? Con la fuente
// `pedido` (la de siempre) el ciclo ya gira a ese ritmo y esto es siempre verdad.
func (e *Espejo) lePuedeTocarAPedido() bool {
	if !e.Opciones.LeeFactura() {
		return true
	}
	return e.Ahora().Sub(e.ultimoDePedido) >= e.Opciones.RitmoDePedido(e.Opciones.PollDelEntorno)
}

// pedidos es el trabajo de PEDIDO de un ciclo: lo incremental, los recién cotizados, el repaso
// corto y el barrido. Devuelve cuántos guardó y la marca de agua con la que arrancó.
func (e *Espejo) pedidos(ctx context.Context) (int, *time.Time) {
	total := 0

	// --- 1. Lo que se movió desde la última vez ------------------------------
	marca, err := e.Base.MarcaDeAgua(ctx)
	if err != nil {
		// Sin marca de agua no se puede hacer lo incremental, pero el repaso y el barrido
		// sí: se avisa y se sigue, que trae menos pero trae.
		e.Reg.Error("no se pudo leer la marca de agua: este ciclo va sin incremental", "err", err)
	} else if marca != nil {
		n, err := e.porCambios(ctx, *marca)
		total += n
		if err != nil {
			e.Reg.Error("el sincronizado incremental falló", "desde", marca.Format(time.RFC3339), "err", err)
		}
	}

	// --- 2. Los recién cotizados --------------------------------------------
	if n, err := e.recienCotizados(ctx); err != nil {
		e.Reg.Error("no se pudieron traer los recién cotizados", "err", err)
	} else if n > 0 {
		e.Reg.Info("recién cotizados", "pedidos", n)
		total += n
	}

	// --- 3. El repaso corto, siempre ----------------------------------------
	total += e.porTramos(ctx, e.Opciones.RepasoDias, 0, "repaso")

	// --- 4. El histórico, si toca -------------------------------------------
	total += e.barrido(ctx)
	return total, marca
}

// ---------------------------------------------------------------------------
// Los pasos
// ---------------------------------------------------------------------------

// catalogo pide el catálogo de Ventra. SI TOCA O NO LO DECIDE EL PROPIO ENDPOINT: aquí no
// se lleva la cuenta a propósito, para que el botón de «traer ahora» de la pantalla y este
// sondeo compartan la misma regla en vez de tener dos que se puedan contradecir.
func (e *Espejo) catalogo(ctx context.Context) {
	r, err := e.Reparto.SincronizarCatalogo(ctx)
	switch {
	case err != nil:
		e.Reg.Error("el catálogo de Ventra falló", "err", err)
	case r == nil || r.Saltado:
		// La última foto es reciente. No es noticia.
	default:
		e.Reg.Info("catálogo de Ventra", "productos", r.Escritos, "sucursalesConFallo", r.ConError)
	}
}

// clientes copia el espejo de clientes.
//
// EL RECORRIDO SE COMPLETA ANTES DE TOCAR NADA: el borrado de abajo usa la lista entera de
// ids. Si el recorrido fallara a mitad, se sale sin borrar — vaciar el espejo por una
// página perdida sería el peor final posible, y encima con un 200 y sin un solo error.
func (e *Espejo) clientes(ctx context.Context) {
	var todos []ClienteDeFuera
	cursor := ""
	for vuelta := 0; ; vuelta++ {
		pagina, siguiente, err := e.Pedido.Clientes(ctx, cursor, e.Opciones.PaginaClientes)
		if err != nil {
			e.Reg.Error("el espejo de clientes falló: no se borra nada", "err", err)
			return
		}
		todos = append(todos, pagina...)
		if siguiente == "" || siguiente == cursor {
			// Cursor que no avanza: se para en vez de girar en el sitio. Un PEDIDO
			// anterior a la paginación no manda cursor y devuelve todo de una vez.
			break
		}
		cursor = siguiente
		if vuelta > 1000 {
			e.Reg.Error("el espejo de clientes no deja de paginar: se corta y no se borra nada")
			return
		}
	}

	ids := make([]string, 0, len(todos))
	puestos := 0
	for _, c := range todos {
		// Defensa: SÓLO los geolocalizados. Sin coordenadas no hay parada que visitar, y
		// además la columna no admite nulos.
		if c.Latitud == nil || c.Longitud == nil {
			continue
		}
		if err := e.Base.GuardarCliente(ctx, c); err != nil {
			// Un cliente que no entra no se lleva por delante a los otros siete mil.
			e.Reg.Warn("un cliente no se pudo copiar", "cliente", c.ID, "err", err)
			continue
		}
		ids = append(ids, c.ID)
		puestos++
	}

	quitados, err := e.Base.BorrarClientesQueYaNoVienen(ctx, ids)
	if err != nil {
		e.Reg.Error("no se pudieron quitar los clientes que ya no vienen", "err", err)
	}
	if puestos > 0 || quitados > 0 {
		e.Reg.Info("espejo de clientes", "copiados", puestos, "quitados", quitados)
	}
}

// porCambios trae lo que se movió desde la marca de agua, por páginas.
//
// SE PAGINA POR LA PROPIA MARCA: se pide `since`, se procesa, y la siguiente petición
// arranca del `updatedAt` más nuevo de lo que acaba de llegar. Sin eso, una tanda de más de
// `limit` pedidos devolvería siempre los mismos y el bucle no avanzaría nunca.
func (e *Espejo) porCambios(ctx context.Context, desde time.Time) (int, error) {
	marca := desde
	total := 0
	// Tope de vueltas: si hay más cambios que esto, se sigue en el próximo ciclo. Un bucle
	// sin tope es un proceso que se queda toda la noche en el mismo paso.
	for vuelta := 0; vuelta < TopeDeVueltas; vuelta++ {
		q := e.parametrosBase()
		q.Set("since", marca.UTC().Format(time.RFC3339))
		q.Set("limit", strconv.Itoa(TopeDePagina))

		pedidos, err := e.Pedido.Pedidos(ctx, q)
		if err != nil {
			return total, err
		}
		if len(pedidos) == 0 {
			return total, nil
		}
		total += e.guardar(ctx, pedidos, "cambios desde "+marca.UTC().Format(time.RFC3339))

		nuevo, hay := MasNuevo(pedidos)
		// Sin avance no hay nada más que traer, o PEDIDO no manda `updatedAt`: se para en
		// vez de girar en el sitio hasta el tope de vueltas.
		if !hay || !nuevo.After(marca) {
			return total, nil
		}
		marca = nuevo
		if err := e.dormir(ctx); err != nil {
			return total, err
		}
	}
	e.Reg.Warn("el incremental dio todas las vueltas y sigue habiendo cambios: se sigue en el proximo ciclo",
		"vueltas", TopeDeVueltas)
	return total, nil
}

// recienCotizados pregunta por los que llevan costo y se movieron hace poco.
//
// El incremental por `since` ya los traería, pero sólo cuando la marca de agua avanza; esto
// pregunta directamente. Son cuatro filas y llegan en la vuelta siguiente — y es lo único
// que la gente mira esperando a que cambie: se cotiza en el teléfono y aquí tiene que
// aparecer.
func (e *Espejo) recienCotizados(ctx context.Context) (int, error) {
	q := e.parametrosBase()
	q.Set("soloDomicilio", "1")
	q.Set("conCosto", "1")
	q.Set("since", e.Ahora().Add(-time.Duration(e.Opciones.CotizadosMin)*time.Minute).UTC().Format(time.RFC3339))
	q.Set("limit", "500")

	pedidos, err := e.Pedido.Pedidos(ctx, q)
	if err != nil || len(pedidos) == 0 {
		return 0, err
	}
	return e.guardar(ctx, pedidos, "recién cotizados"), nil
}

// porTramos recorre un intervalo de días trozo a trozo. Cada trozo se procesa y se suelta:
// NO se acumulan cincuenta mil pedidos en memoria para mandarlos al final, que es
// exactamente lo que tiró el proceso la vez anterior.
func (e *Espejo) porTramos(ctx context.Context, desdeDias, hastaDias int, de string) int {
	total := 0
	for _, t := range Tramos(e.Ahora(), desdeDias, hastaDias, e.Opciones.TramoDias) {
		if ctx.Err() != nil {
			return total
		}
		total += e.unTramo(ctx, t, de)
		if err := e.dormir(ctx); err != nil {
			return total
		}
	}
	return total
}

// unTramo trae UN trozo de días ENTERO, y no su primera página y a otra cosa.
//
// Aqui estaba el agujero: se pedia `limit=5000`, se guardaba lo que llegara y nadie miraba
// cuantos habian venido. `/integration/orders` recorta por su cuenta y NO lo anuncia —200 y
// sin una palabra de que falte nada—, asi que cualquier tramo con mas pedidos de los que
// sirve de una vez perdia el resto EN SILENCIO. El logistico veia menos de lo que hay y no
// habia nada en ningun sitio que se lo dijera.
//
// SE ENCADENA IGUAL QUE EL INCREMENTAL, con el dato que llega en vez de con un cursor.
// Comprobado en el codigo de PEDIDO: `/integration/orders` no tiene paginacion ninguna —ni
// cursor, ni `offset`, ni `nextCursor`: es un `take` sobre un `ORDER BY fecha DESC` y nada
// mas—. Lo unico con lo que se puede avanzar es la propia fecha de lo que acaba de llegar,
// asi que si la pagina vino llena se estrecha el borde nuevo del tramo hasta el dia del
// pedido MAS VIEJO que llego y se vuelve a pedir. Partir el tramo por dias es lo que hay;
// las otras formas de partirlo no existen en ese endpoint.
//
// El dia del corte se vuelve a pedir ENTERO, asi que sus pedidos llegan dos veces. Es a
// proposito: el upsert es idempotente y un dia repetido cuesta una peticion, mientras que
// cortar por el pedido exacto se comeria a los que comparten fecha con el.
//
// Y CUANDO YA NO SE PUEDE ESTRECHAR MAS —un solo dia con mas pedidos de los que PEDIDO
// sirve— se dice con nivel WARN y con el tramo dentro. Un tramo truncado en silencio es
// justo el fallo que esto viene a cerrar, y callarselo lo deja igual de invisible que
// antes: un aviso que no nombra el tramo no sirve para ir a buscar lo que falta.
func (e *Espejo) unTramo(ctx context.Context, t Tramo, de string) int {
	total := 0
	tramo := t.Desde + ".." + t.Hasta
	hasta := t.Hasta
	// Tope de vueltas, como en el incremental: un tramo no puede tener mas cortes que dias,
	// pero un PEDIDO que conteste cualquier cosa no puede dejar al ciclo girando aqui toda
	// la noche sin llegar nunca al barrido.
	for vuelta := 0; vuelta < TopeDeVueltas; vuelta++ {
		q := e.parametrosBase()
		q.Set("desde", t.Desde)
		q.Set("hasta", hasta)
		q.Set("limit", strconv.Itoa(TopeDePagina))

		pedidos, err := e.Pedido.Pedidos(ctx, q)
		if err != nil {
			// UN TRAMO QUE FALLA NO TUMBA EL RESTO: se recogerá en la próxima pasada, que
			// para eso el histórico se repasa en bucle.
			e.Reg.Warn("un tramo falló", "de", de, "desde", t.Desde, "hasta", hasta, "err", err)
			return total
		}
		if len(pedidos) > 0 {
			total += e.guardar(ctx, pedidos, de+" "+t.Desde+".."+hasta)
		}
		// LA GUARDA. La pagina no vino llena, luego no habia mas: el tramo esta entero.
		// Quitar esta linea es volver al fallo de antes, con la diferencia de que ahora se
		// pediria de mas en vez de de menos.
		if len(pedidos) < TopeDePagina {
			return total
		}

		dia, hay := DiaMasViejo(pedidos)
		if !hay || dia >= hasta {
			// O PEDIDO no manda fecha legible, o la pagina entera cae en el mismo dia. En
			// los dos casos el borde no se puede mover: seguir pidiendo traeria lo mismo.
			e.Reg.Warn("tramo truncado: hay mas pedidos de los que PEDIDO sirve de una vez y el dia ya no se puede partir",
				"de", de, "tramo", tramo, "corteEn", hasta, "traidos", len(pedidos))
			return total
		}
		hasta = dia
		if err := e.dormir(ctx); err != nil {
			return total
		}
	}
	e.Reg.Warn("tramo truncado: se dieron todas las vueltas y la pagina seguia viniendo llena",
		"de", de, "tramo", tramo, "corteEn", hasta, "vueltas", TopeDeVueltas)
	return total
}

// barrido estira el histórico un poco más hacia atrás, y NO en cada vuelta.
//
// Un trozo por ciclo, no el año de una sentada: lo reciente ya está desde el primer ciclo,
// y si el proceso se reinicia a mitad, la próxima vuelta sigue POR DONDE IBA. Y eso lo dice
// la posición guardada, no los datos: el espejo ya tenía pedidos sueltos de hace un año, así
// que «el más antiguo que tengo» no significa «tengo todo hasta ahí» — el barrido arrancaba
// a 357 días y se saltaba entero el año de en medio, que era justo lo que faltaba.
func (e *Espejo) barrido(ctx context.Context) int {
	if e.Ahora().Sub(e.ultimoBarrido) < e.Opciones.RitmoDelBarrido() {
		return 0
	}
	e.ultimoBarrido = e.Ahora()

	posicion, err := e.Base.PosicionDelBarrido(ctx)
	if err != nil {
		e.Reg.Error("no se pudo leer por dónde iba el barrido: este ciclo se queda sin histórico", "err", err)
		return 0
	}
	desde, hasta := SiguienteBarrido(posicion, e.Opciones.RepasoDias, e.Opciones.HistoricoPorCiclo, e.Opciones.HistoricoDias)
	total := e.porTramos(ctx, hasta, desde, "histórico")

	// La posición se avanza AUNQUE algún tramo haya fallado, y es deliberado: lo que se
	// mueva sigue llegando por `since` en cada ciclo, y el barrido da la vuelta al año una y
	// otra vez, así que un tramo saltado se recoge en la pasada siguiente. Quedarse clavado
	// en un tramo que falla siempre sería no recuperar nunca el resto del año.
	if err := e.Base.FijarBarrido(ctx, AvanzarBarrido(hasta, e.Opciones.HistoricoDias)); err != nil {
		e.Reg.Error("el barrido avanzó pero no se pudo guardar la posición", "err", err)
	}
	e.Reg.Info("histórico barrido", "desdeDias", desde, "hastaDias", hasta, "pedidos", total)
	return total
}

// ---------------------------------------------------------------------------
// Lo común
// ---------------------------------------------------------------------------

// guardar trocea la tanda y la manda al lote.
//
// UN LOTE QUE FALLA NO SE LLEVA A LOS OTROS: se cuenta, se dice, y el resto entra. Lo que
// no entró hoy vuelve por el repaso o por el barrido, que pasan por todo otra vez.
func (e *Espejo) guardar(ctx context.Context, pedidos []PedidoDeFuera, de string) int {
	guardados := 0
	for i, trozo := range Trozos(pedidos, e.Opciones.Lote) {
		r, err := e.Reparto.Cotizar(ctx, trozo)
		if err != nil {
			e.Reg.Warn("un lote falló", "de", de, "lote", i+1, "pedidos", len(trozo), "err", err)
			continue
		}
		guardados += r.Persisted

		// LO QUE NO ENTRÓ SE DICE CON SU MOTIVO. Un lote que contesta 200 y guarda cero es
		// lo más parecido que hay a que todo vaya bien, y es justo cuando hay que mirar.
		for motivo, cuantos := range motivosDeNoEntrar(r) {
			if motivo == MotivoYaAdoptado {
				// La convivencia de las dos fuentes (`SYNC_FUENTE=ambas`): el pedido ya es una
				// entrega de factura y no se crea otra fila. NO es un fallo, y se cuenta aparte
				// para que no se confunda con los que de verdad no entraron.
				e.Reg.Info("pedidos ya adoptados por una factura (no es un fallo)",
					"de", de, "motivo", motivo, "pedidos", cuantos)
				continue
			}
			e.Reg.Warn("pedidos que no entraron", "de", de, "motivo", motivo, "pedidos", cuantos)
		}
		if err := e.dormir(ctx); err != nil {
			return guardados
		}
	}
	e.Reg.Info("lote procesado", "de", de, "pedidos", len(pedidos), "guardados", guardados)
	return guardados
}

// motivosDeNoEntrar cuenta los que no se guardaron, por motivo.
//
// `sucursal-no-mapeada`, `sucursal-sin-punto-de-partida` y `sin-domicilio-y-sin-factura` no
// son fallos del pedido: son cosas que hay que configurar en el reparto, y se arreglan
// solas en cuanto alguien lo hace. Pero `espejo-no-montado` o `falta-customerName` sí son
// para mirar, y sin este recuento no se ven en ningún sitio.
func motivosDeNoEntrar(r RespuestaDelLote) map[string]int {
	cuenta := map[string]int{}
	for _, res := range r.Results {
		if res.Entro() {
			continue
		}
		motivo := res.Reason
		if motivo == "" {
			continue
		}
		cuenta[motivo]++
	}
	return cuenta
}

// parametrosBase son los filtros que comparten TODAS las peticiones a PEDIDO.
//
// Los archivados entran también, dentro de lo repartible: un pedido facturado que ya se
// archivó en PEDIDO sigue teniendo que poder repartirse.
func (e *Espejo) parametrosBase() url.Values {
	q := url.Values{}
	if e.Opciones.SoloRepartibles {
		q.Set("soloRepartibles", "1")
	}
	if e.Opciones.SoloDomicilio {
		q.Set("soloDomicilio", "1")
	}
	if e.Opciones.SoloCotizados {
		q.Set("conCosto", "1")
	}
	if e.Opciones.SucursalCodigo != "" {
		q.Set("sucursalCodigo", e.Opciones.SucursalCodigo)
	}
	return q
}

func (e *Espejo) sucursalODejarTodas() string {
	if e.Opciones.SucursalCodigo == "" {
		return "todas"
	}
	return e.Opciones.SucursalCodigo
}

// dormir es el respiro entre peticiones, y además el sitio por donde el ciclo se entera de
// que lo están parando: devuelve error en cuanto se cancela el contexto, y quien lo llama
// sale ordenadamente en vez de terminarse el histórico entero.
func (e *Espejo) dormir(ctx context.Context) error {
	if e.Pausa <= 0 {
		return ctx.Err()
	}
	t := time.NewTimer(e.Pausa)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.C:
		return nil
	}
}

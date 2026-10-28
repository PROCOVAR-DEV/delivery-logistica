package espejo

import "testing"

// LA FACTURA SIN PUNTO SE COMPARA CON LOS CLIENTES QUE YA TENEMOS (28/10/2026, Jose: «si el cliente de la
// factura existe le pones su dirección sin que tenga que ponerla él»). Casos reales de Santiago:
//
//   - 47636: Ventra manda la referencia «YANEIDIS GONZALES RIOS» (el vendedor tecleó una S) y el cliente
//     «Yaneidis Gonzalez Rios», que el padrón tiene como «YANEIDIS GONZALEZ RIOS» → punto por el nombre;
//   - 47544: cliente «Yunier Sierra Ross» sin referencia, y el padrón lo tiene como «KIOSKO YUNIER SIERRA ROSS»:
//     NO se adivina (otro nombre) y se ubica a mano.
func entregaConCliente(nombre, referencia string) EntregaDeFactura {
	f := factura("47636", "2026-10-26", "2", "PYZ26-261025-1425", cerveza(1), domicilio(0.56))
	f.Cliente.Nombre, f.ReferenciaDelCliente = nombre, referencia
	return UnaEntregaPorFactura("STG", []FacturaDeVentra{f})[0]
}

func TestSiLaReferenciaNoLoHallaSeBuscaPorElNombreDelCliente(t *testing.T) {
	puntos := NuevosPuntos([]PuntoDeCliente{
		{Codigo: "SC02TCP0084", Nombre: "YANEIDIS GONZALEZ RIOS", Lat: 19.97, Lng: -76.40},
		{Codigo: "SC02TCP0016", Nombre: "YANEIDIS GONZALEZ MORAN", Lat: 19.97, Lng: -76.40},
	})
	p, inf := entregaConCliente("Yaneidis Gonzalez Rios", "YANEIDIS GONZALES RIOS").
		APedido(ContextoDeMapeo{Puntos: puntos, Productos: productosDePrueba()})
	if inf.Punto != PuntoPorNombre || p.Cliente.Latitud == nil || *p.Cliente.Latitud != 19.97 {
		t.Fatalf("la 47636 tenía que hallar el punto por el nombre del cliente: %q %+v", inf.Punto, p.Cliente)
	}
}

func TestUnNombreDistintoNoSeAdivina(t *testing.T) {
	puntos := NuevosPuntos([]PuntoDeCliente{{Codigo: "SC06TCP0578", Nombre: "KIOSKO YUNIER SIERRA ROSS", Lat: 20.0, Lng: -75.76}})
	p, inf := entregaConCliente("Yunier Sierra Ross", "").
		APedido(ContextoDeMapeo{Puntos: puntos, Productos: productosDePrueba()})
	if inf.Punto != PuntoNoEncontrado || p.Cliente.Latitud != nil {
		t.Fatalf("otro nombre no es el mismo cliente: no se le inventa punto (%q)", inf.Punto)
	}
}

func TestLaReferenciaSiempreMandaSobreElNombre(t *testing.T) {
	puntos := NuevosPuntos([]PuntoDeCliente{
		{Codigo: "SC06TCP0158", Nombre: "OTRO", Lat: 1, Lng: 2},
		{Codigo: "X", Nombre: "CLIENTE DE PRUEBA UNO", Lat: 3, Lng: 4},
	})
	p, inf := entregaConCliente("Cliente de Prueba Uno", "SC06TCP0158").
		APedido(ContextoDeMapeo{Puntos: puntos, Productos: productosDePrueba()})
	if inf.Punto != PuntoPorCodigo || *p.Cliente.Latitud != 1 {
		t.Fatalf("la referencia (código) tenía que mandar: %q", inf.Punto)
	}
}

func TestLasTildesNoHacenOtroNombre(t *testing.T) {
	if ClaveDeCliente("Yelina Leocadia Acuña Deroncel") != ClaveDeCliente("YELINA LEOCADIA ACUNA  DERONCEL") {
		t.Fatal("Acuña y ACUNA son el mismo nombre")
	}
	if ClaveDeCliente("GONZALES") == ClaveDeCliente("GONZALEZ") {
		t.Fatal("una letra distinta ES otro nombre: no se adivina")
	}
}

// LO QUE EL LOGÍSTICO UBICÓ A MANO MANDA sobre el padrón con el mismo nombre, y lo demás del padrón se queda.
func TestElPuntoGuardadoMandaSobreElDelPadron(t *testing.T) {
	padron := []PuntoDeCliente{
		{Codigo: "A", Nombre: "Pedro Perez", Lat: 1, Lng: 1},
		{Codigo: "B", Nombre: "PEDRO PÉREZ", Lat: 2, Lng: 2}, // dudoso: dos puntos para el mismo nombre
		{Codigo: "C", Nombre: "Otra Persona", Lat: 3, Lng: 3},
	}
	f := FusionarPuntos(padron, []PuntoDeCliente{{Nombre: "pedro perez", Lat: 9, Lng: 9}})
	lat, _, como := NuevosPuntos(f).Buscar("Pedro Perez")
	if como != PuntoPorNombre || lat != 9 {
		t.Fatalf("el punto guardado tenía que mandar: %v %q", lat, como)
	}
	if _, _, como := NuevosPuntos(f).Buscar("C"); como != PuntoPorCodigo {
		t.Fatalf("el resto del padrón se queda: %q", como)
	}
	if len(FusionarPuntos(padron, nil)) != 3 {
		t.Fatal("sin guardados, el padrón queda igual")
	}
}

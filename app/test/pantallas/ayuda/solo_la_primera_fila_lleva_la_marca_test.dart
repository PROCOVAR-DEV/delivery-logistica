// CUANDO UN CONTROL SE REPITE POR FILA, SOLO EL PRIMERO LLEVA LA MARCA.
//
// `ControlSenalado` no es un `GlobalKey` a proposito, y la contrapartida esta
// escrita en `vista/control_senalado.dart`: dos instancias con el MISMO nombre
// montadas a la vez no se pueden distinguir, asi que `RegistroDeControles.donde`
// devuelve `null` y el recorrido dice «esto no se puede señalar aquí». No revienta
// nada — **y eso es justo el problema**: la lista se pinta igual, las pruebas de
// la pantalla siguen verdes, y el unico sintoma es un paso de la Guia sin foco.
//
// Por eso la decision es de la pantalla (`senalable: cual == 0`), y por eso hace
// falta una prueba por lista: quitar ese `cual == 0` no pone nada en rojo en
// ningun otro sitio.
//
// Aqui va la lista de Clientes, que es la de «Consultar un cliente» y la unica que
// tiene DOS formas del mismo paso —tarjetas en el telefono, `DataTable` en una
// pantalla ancha—, asi que son dos sitios donde se puede olvidar. Las otras tres
// listas marcadas van con sus pantallas: las baldosas de «Ir a» en
// `navegacion/menu_de_cuenta_test.dart`, los rechazos en
// `pantallas/entregar_el_dia/pantalla_test.dart` y los niveles del mapa en
// `mapa/pantalla_mapa_test.dart`.
//
// Sin Drift: los `Cliente` se construyen a mano. Dentro de un `testWidgets` una
// consulta de Drift cuelga la prueba en vez de fallar (CLAUDE.md §5).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/ayuda/datos/controles_senalados.dart';
import 'package:reparto/pantallas/ayuda/vista/control_senalado.dart';
import 'package:reparto/pantallas/clientes/datos/repositorio_clientes.dart';
import 'package:reparto/pantallas/clientes/vista/tabla_clientes.dart';

void main() {
  const anchoDelTelefono = 390.0;
  const anchoDeEscritorio = 1440.0;
  const alto = 844.0;

  ClienteConKm cliente(String id, String nombre) => ClienteConKm(
    Cliente(
      id: id,
      name: nombre,
      lat: 20.02,
      lng: -75.82,
      address: 'calle 5 nº 12',
      municipio: 'Santiago de Cuba',
      zona: 'Zona 1',
      codigo: 'CL-$id',
      vendedor: 'Marta Díaz',
      phone: '+53 5555 1234',
      source: 'pedido',
      sucursalCodigo: 'STG',
    ),
    null,
  );

  /// TRES clientes, no uno: con uno solo la prueba sale verde aunque la marca
  /// este en todas las filas, que es exactamente la averia que se viene a cazar.
  final tres = [
    cliente('1', 'Ferretería La Esquina'),
    cliente('2', 'Bodega El Puente'),
    cliente('3', 'Panadería Doña Eva'),
  ];

  Future<void> pintar(WidgetTester tester, {required double ancho}) async {
    RegistroDeControles.vaciar();
    addTearDown(RegistroDeControles.vaciar);
    tester.view.physicalSize = Size(ancho, alto);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TablaClientes(clientes: tres, conDistancia: false),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Donde cae el foco, y que sea el de la PRIMERA fila y no el de otra.
  ///
  /// Se compara al reves de lo que parece: el foco es la fila (o la celda) entera
  /// y el nombre es un trozo de dentro, asi que lo que hay que comprobar es que
  /// **el nombre esta dentro del foco**. Con el nombre de la segunda o la tercera
  /// no se cumple, que es lo que lo convierte en una prueba.
  void laMarcaCaeEnLaPrimera(WidgetTester tester, Finder primera) {
    final puesto = RegistroDeControles.donde(Senalado.clientesAbrirElCliente);
    expect(
      puesto,
      isNotNull,
      reason:
          'con tres clientes a la vista no hay a quien señalar: el nombre está '
          'marcado en más de una fila y las dos a la vez no se distinguen, así '
          'que el paso «Toca la tarjeta del cliente» sale SIN FOCO y nada falla.',
    );
    final suyo = tester.getRect(primera);
    expect(
      puesto!.rect.contains(suyo.center),
      isTrue,
      reason:
          'el foco cae en ${puesto.rect} y la primera fila está en $suyo: se '
          'está señalando otra fila, que es peor que no señalar ninguna.',
    );
  }

  /// Y la contraparte, sin la cual la de arriba se cumpliria con la marca en
  /// CUALQUIER fila si las filas midieran lo mismo: el foco no puede contener el
  /// nombre de la tercera.
  void laMarcaNoCaeEnLaTercera(WidgetTester tester) {
    final puesto = RegistroDeControles.donde(Senalado.clientesAbrirElCliente)!;
    expect(
      puesto.rect.contains(
        tester.getRect(find.text('Panadería Doña Eva')).center,
      ),
      isFalse,
      reason: 'el foco abarca también la tercera fila: no está señalando una.',
    );
  }

  testWidgets('en el teléfono, la marca está en la primera tarjeta', (
    tester,
  ) async {
    await pintar(tester, ancho: anchoDelTelefono);
    // Que de verdad son tarjetas y no la tabla: si cambiara la forma, esta
    // prueba estaría comprobando la otra mitad sin enterarse.
    expect(find.byType(DataTable), findsNothing);

    laMarcaCaeEnLaPrimera(tester, find.text('Ferretería La Esquina'));
    laMarcaNoCaeEnLaTercera(tester);
  });

  testWidgets('en pantalla ancha, la marca está en la primera fila', (
    tester,
  ) async {
    await pintar(tester, ancho: anchoDeEscritorio);
    expect(find.byType(DataTable), findsOneWidget);

    laMarcaCaeEnLaPrimera(tester, find.text('Ferretería La Esquina'));
    laMarcaNoCaeEnLaTercera(tester);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/vehiculos/vista/pantalla_vehiculos.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo_vehiculos.dart';

/// Lo que ve una persona cuando abre Vehiculos sin red.
///
/// El cartel no es decoracion: es lo que evita que alguien se ponga a dar de
/// alta camiones en la calle creyendo que se estan guardando.
void main() {
  /// Se monta con **la base del banco**, no con una nueva.
  ///
  /// La pantalla mira ahora la copia bajada para poder decir si el aparato tiene
  /// la flota dentro o no la ha descargado nunca. Sin este override, el
  /// `baseProvider` abriria una base de verdad en medio del test —con su timer,
  /// que deja la prueba en rojo— y ademas se estaria comprobando otra base
  /// distinta de la que el banco siembra.
  Future<void> pintar(WidgetTester tester, Banco banco) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(banco.base),
          // LA WEB: sin base local ni cola (el aparato: la_flota_sin_conexion_test.dart).
          trabajaSinConexionProvider.overrideWithValue(false),
          clienteApiProvider.overrideWithValue(
            banco.contenedor.read(clienteApiProvider),
          ),
        ],
        // El `Scaffold` lo pone el armazon, no la pantalla (el contrato esta
        // en `lib/navegacion/pantalla_registrada.dart`). Montada a pelo no hay
        // ningun `Material` debajo y el buscador revienta al construirse.
        child: const MaterialApp(home: Scaffold(body: PantallaVehiculos())),
      ),
    );
    // Tope corto a proposito: el de por defecto son diez minutos, y una
    // pantalla que no se asienta dejaria la prueba colgada sin decir por que.
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }

  /// Desmonta el arbol DENTRO de la prueba: los `Stream` de Drift dejan un
  /// temporizador de cero al cerrarse, y si el arbol muere despues de que la
  /// prueba termine, falla por «queda un Timer» sin que haya nada roto.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('sin red lo dice, y dice que aquí no se guarda nada', (
    tester,
  ) async {
    final banco = Banco.sinRed();
    addTearDown(banco.cerrar);
    await pintar(tester, banco);

    // LA WEB: el servidor no contesta (si la pagina cargo, conexion hay).
    expect(find.textContaining('El servidor no contesta.'), findsOneWidget);
    // Y NO el vacio de «no hay vehiculos», que diria otra cosa muy distinta.
    expect(find.text('Sin vehículos'), findsNothing);
    expect(find.text('Reintentar'), findsOneWidget);

    // (El cartel «este aparato no ha descargado la flota» es del APARATO y vive en
    // `la_flota_sin_conexion_test.dart`: en la web no hay copia de la que hablar.)
    expect(find.text('Agregar Vehículo'), findsOneWidget); // sólo el de arriba

    await desmontar(tester);
  });

  testWidgets('con red y sin flota: el vacío del pliego', (tester) async {
    final banco = Banco(
      (p) async => p.ruta.endsWith('/settings')
          ? RespuestaFalsa(200, const <String, Object?>{})
          : RespuestaFalsa(200, const <Object?>[]),
    );
    addTearDown(banco.cerrar);
    await pintar(tester, banco);

    expect(find.text('Sin vehículos'), findsOneWidget);
    expect(
      find.text('Agrega tu primer vehículo para asignarlo a rutas'),
      findsOneWidget,
    );
    expect(find.textContaining('Sin conexión.'), findsNothing);

    // EL VACIO INVITA: dice que es esto en el idioma de quien reparte y que se
    // rompe mientras siga vacio. «Sin vehículos» a secas no decia ninguna de
    // las dos.
    expect(
      find.textContaining('Aquí van los camiones con los que se reparte'),
      findsOneWidget,
    );
    expect(
      find.textContaining('no se puede terminar de armar una ruta'),
      findsOneWidget,
    );
    // Y NO el texto de «no se ha descargado»: el servidor contesto y dijo que
    // no hay ninguno. Eso es un dato, no un fallo.
    expect(
      find.textContaining('no ha descargado la flota todavía'),
      findsNothing,
    );

    await desmontar(tester);
  });

  testWidgets('con flota: la tarjeta con sus literales', (tester) async {
    final banco = Banco(
      (p) async => p.ruta.endsWith('/settings')
          ? RespuestaFalsa(200, const <String, Object?>{})
          : RespuestaFalsa(200, const <Object?>[
              <String, Object?>{
                'id': 'v1',
                'name': 'Camión #1',
                'plate': 'ABC-1234',
                'capacity': 2500,
                'status': 'in_use',
                'type': 'truck',
                '_count': <String, Object?>{'routes': 4, 'orders': 12},
                // La ruta ABIERTA del camión, con SU estado. El servidor la
                // manda desde el 28/09/2026 (`RutasAbiertasDeLaFlota`): hasta
                // entonces este campo no existía y la caja azul de la tarjeta
                // no salía nunca.
                'routes': <Object?>[
                  <String, Object?>{
                    'id': 'r1',
                    'routeCode': 'STG-0007',
                    'status': 'in_progress',
                  },
                ],
              },
            ]),
    );
    addTearDown(banco.cerrar);
    await pintar(tester, banco);

    expect(find.text('Camión #1'), findsOneWidget);
    expect(find.text('ABC-1234'), findsOneWidget);
    // LA INSIGNIA SALE DE LA RUTA, no de `status`. Antes decía «En uso» leyendo
    // el campo guardado; ahora dice «En ruta» porque lleva una ruta `in_progress`
    // encima, que es la pregunta que de verdad se hace quien mira la flota.
    //
    // Son DOS: la insignia de la tarjeta y el contador de la franja de arriba.
    // Que digan lo mismo es el punto: un resumen que cuenta distinto de las
    // tarjetas que tiene debajo es el §3-bis.
    expect(find.text('En ruta'), findsNWidgets(2));
    expect(find.text('En uso'), findsNothing);
    expect(find.text('2500 kg'), findsOneWidget);
    expect(find.text('12 órdenes asignadas'), findsOneWidget);
    // Sin nombre, la ruta activa se identifica por su codigo.
    expect(find.text('Ruta activa'), findsOneWidget);
    // Y DE UN VISTAZO, LA FLOTA. Es lo que Jose pidió: «saber de la flota».
    expect(find.text('Libres'), findsOneWidget);
    expect(find.text('STG-0007'), findsOneWidget);
    // Sin marcar para domicilio sale el boton, no el chip.
    expect(find.text('Usar para domicilio'), findsOneWidget);
    // `Marcar disponible` sólo aparece cuando esta en uso.
    expect(find.text('Marcar disponible'), findsOneWidget);

    await desmontar(tester);
  });
}

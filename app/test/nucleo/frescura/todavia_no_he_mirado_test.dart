// «SIN DATOS» Y «TODAVÍA NO HE MIRADO» SON DOS COSAS — 28/09/2026.
//
// Jose, abriendo la aplicación sin señal en un SM-A165M: el renglón de frescura
// decía que no había nada durante unos **cuatro segundos** y después se asentaba
// en la hora de la última bajada. O sea que enseñaba «no hay nada» encima de una
// base que sí tenía cosas — y en ámbar, que es la señal de «mira esto», encima
// del gesto de traer un día que ya estaba dentro.
//
// Es el §3-ter en su forma más corta: un estado vacío que se lee como otro. Que
// dure cuatro segundos no lo hace menor: es justo el momento en que alguien abre
// la aplicación y decide si le hace falta traer el día antes de salir.
//
// LA FORMA DE ESTAS PRUEBAS, que es la que manda el §3-ter y la que hace que
// sirvan: se monta con **NADA** y lo que hay llega **DESPUÉS**, sin volver a
// montar. Sembrar antes de montar es justo el caso que el código roto resolvía
// bien, y por eso no cazaba nada.
//
// Son dos pruebas y hacen falta las dos:
//
//  1. la del reloj, con la respuesta en la mano, que es donde se decide si
//     «no he mirado» se pinta como «no hay nada»;
//  2. la de la base de verdad, que comprueba que al asentarse dice lo que toca
//     — sin ella, «no digas que no hay nada» se cumple no diciéndolo nunca.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/frescura/reloj_de_datos.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/pedidos/vista/kit.dart';

import '../../apoyo/base_de_prueba.dart';

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  final ahora = DateTime(2026, 9, 28, 15, 20);
  final bajada = DateTime(2026, 9, 28, 15, 3);
  const colecciones = ColeccionesDePantalla.pedidos;

  testWidgets(
    'mientras la consulta no contesta NO se dice que no hay nada, y en cuanto '
    'contesta se dice lo que sea, sin volver a montar',
    (tester) async {
      // La consulta de frescura, en la mano. No es un atajo: es el único modo
      // de parar el reloj justo en el instante que se vio en el teléfono —los
      // cuatro segundos en los que la base todavía no ha contestado— y de
      // comprobarlo sin depender de lo que tarde un sqlite.
      final consulta = StreamController<EstadoFrescura>();
      addTearDown(consulta.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            frescuraDePantallaProvider(
              colecciones,
            ).overrideWith((ref) => consulta.stream),
            sinSubirProvider.overrideWith((ref) => Stream.value(0)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: BarraDeDatos(colecciones: colecciones),
            ),
          ),
        ),
      );
      await tester.pump();

      // 1. TODAVÍA NADIE HA CONTESTADO. Aquí no se sabe si hay datos, así que
      //    no se puede afirmar que no los haya.
      expect(
        find.text(const SinMirarTodavia().texto),
        findsOneWidget,
        reason:
            'mientras la base no contesta no se sabe si hay datos; decir que no '
            'los hay es afirmar algo que no se ha mirado',
      );
      expect(
        find.text(const SinDescargar().texto),
        findsNothing,
        reason:
            'ESTE es el fallo del 28/09/2026: «Sin descargar todavía» no es una '
            'reserva prudente, es una afirmación —«este aparato no ha bajado '
            'nunca»—, va en ámbar y enciende el gesto de traer un día que ya '
            'estaba dentro',
      );

      // 2. CONTESTA Y DE VERDAD NO HAY NADA. Ahora sí se dice, y en ámbar,
      //    porque eso se arregla trayendo el día. Sin esta mitad, el arreglo de
      //    arriba se cumple callando para siempre el aviso que importa.
      consulta.add(const SinDescargar());
      await tester.pump();
      await tester.pump();
      expect(find.text(const SinDescargar().texto), findsOneWidget);
      expect(find.text(const SinMirarTodavia().texto), findsNothing);

      // 3. Y CUANDO HAY DATOS, la hora — con la pantalla ya delante y sin que
      //    nadie la vuelva a montar.
      consulta.add(DatosRecientes(bajada));
      await tester.pump();
      await tester.pump();
      expect(find.text('Datos de las 15:03'), findsOneWidget);
      expect(find.text(const SinMirarTodavia().texto), findsNothing);
    },
  );

  // LA OTRA MITAD, CONTRA LA BASE DE VERDAD: montada vacía, sembrada después.
  //
  // La de arriba comprueba la decisión; ésta comprueba que la consulta que hay
  // detrás llega y se asienta. Una sin la otra deja media cosa: se puede dejar
  // de mentir sin llegar nunca a decir la verdad.
  group('contra la base', () {
    late BaseLocal base;

    // La base se ABRE aquí y se ESCRIBE dentro del cuerpo (§5): lo que Drift
    // deja empezado en el `setUp` corre fuera del reloj falso y no avanza
    // dentro, y eso no falla — se cuelga, que es peor.
    setUp(() => base = baseDePrueba());
    // Cerrar dos veces no molesta: es lo que recoge la base si la prueba se
    // corta antes de llegar al cierre de dentro.
    tearDown(() => base.close());

    testWidgets('la bajada llega con la barra delante y se ve la hora', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(base),
            relojProvider.overrideWithValue(() => ahora),
            // La cola no pinta nada aquí y trae su propio reloj detrás: sin
            // esto queda un temporizador vivo cuando el árbol ya se desmontó.
            sinSubirProvider.overrideWith((ref) => Stream.value(0)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: BarraDeDatos(colecciones: colecciones),
            ),
          ),
        ),
      );

      // Base vacía y ya mirada: «sin descargar» es un estado de verdad.
      await asentar(tester);
      expect(find.text(const SinDescargar().texto), findsOneWidget);

      // Y ahora la bajada, sin volver a montar nada.
      final frescura = RegistroDeFrescura(base, reloj: () => ahora);
      for (final coleccion in colecciones) {
        await frescura.marcar(coleccion, hasta: null, bajadaAt: bajada);
      }
      await asentar(tester);

      expect(
        find.text('Datos de las 15:03'),
        findsOneWidget,
        reason: 'es donde se asentaba después de los cuatro segundos',
      );
      expect(find.text(const SinDescargar().texto), findsNothing);

      // La base se cierra DENTRO del cuerpo: Drift deja programado un aviso de
      // cero milisegundos por cada consulta viva, y el `tearDown` corre después
      // de que el banco de pruebas compruebe que no quedan temporizadores.
      await base.close();
      await tester.pump();
    });
  });

  // Y LA REGLA SUELTA, sin pintar nada: «todavía no he mirado» NO va en ámbar.
  //
  // El ámbar es «mira esto» y enciende el gesto de traer el día. Encenderlo
  // mientras no se sabe nada es pedirle a alguien que arregle algo que a lo
  // mejor no está roto, y un aviso que sale siempre deja de leerse.
  test('«todavía no he mirado» va en gris, y «no hay nada» en ámbar', () {
    expect(const SinMirarTodavia().enAmbar, isFalse);
    expect(const SinDescargar().enAmbar, isTrue);
    expect(
      const SinMirarTodavia().texto,
      isNot(const SinDescargar().texto),
      reason: 'dos estados distintos no se pueden decir con las mismas palabras',
    );
  });
}

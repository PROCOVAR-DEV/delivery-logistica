// LA WEB NO PUEDE ACUSAR DE UN PROBLEMA QUE NO EXISTE MIENTRAS LA PRIMERA
// BAJADA ESTA EN CAMINO.
//
// Jose, 17/09/2026, entrando a `reparto.procovar.cloud`:
//
// > «cuando entraste a la web me salia un mensaje de que habia que configurar un
// > almacen en esa sucursal y despues aparecieron las cosas. Eso no puede pasar
// > mi loco»
//
// El almacen existia. Lo que pasa es que **la web ya no tiene base en disco**:
// su base es en memoria, asi que nace VACIA en cada carga de la pagina y el
// ciclo la llena un segundo despues. En ese segundo cada pantalla miraba su
// copia, la veia vacia, y sacaba una conclusion que era falsa.
//
// ## Por que cada prueba va en tres tiempos
//
// Las tres mitades son las que fijan la linea, y ninguna sirve sola:
//
//  1. **Web con la base vacia**: NO sale el diagnostico falso. Sola se cumpliria
//     igual borrando la pantalla entera.
//  2. **Los datos entran DESPUES, sin volver a montar nada**: sale lo bueno. Es
//     lo que pasa en un navegador de verdad, donde nadie recarga — y es la
//     mitad que caza un `FutureProvider` congelado en el instante del montaje.
//  3. **Aparato con la base vacia**: el texto de siempre SI sale. Sola se
//     cumpliria igual quitando el `if` de la plataforma, y la web volveria a
//     mentir sin que nadie se enterara.
//
// Y encima de las tres, **el suelo**: la espera no puede durar para siempre. Si
// la bajada falla de verdad la web tiene que acabar diciendolo y dejando entrar.
// Una rueda que no para nunca es peor que el mensaje falso.
//
// No se compila para web para probar esto: la plataforma se pregunta por
// `Destino` (`nucleo/plataforma.dart`), asi que `Destino.comoSiFueraWeb` es
// exactamente el mismo interruptor que mira el codigo.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/diseno/estado_vacio.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/primera_bajada.dart';
import 'package:reparto/nucleo/frescura/reloj_de_datos.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/nucleo/sincro/ciclo.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/almacenes/vista/pantalla_almacenes.dart';
import 'package:reparto/pantallas/clientes/vista/pantalla_clientes.dart';
import 'package:reparto/pantallas/informes/vista/pantalla_informes.dart';
import 'package:reparto/pantallas/panel/datos/configuracion_pendiente.dart';
import 'package:reparto/pantallas/panel/vista/paso_a_paso.dart';
import 'package:reparto/pantallas/vehiculos/vista/pantalla_vehiculos.dart';
import 'package:reparto/idioma.dart';

import 'apoyo/base_de_prueba.dart';
import 'pantallas/almacenes/apoyo_almacenes.dart' as alm;
import 'pantallas/clientes/apoyo_clientes.dart';
import 'pantallas/vehiculos/apoyo_vehiculos.dart' as veh;

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  final ahora = DateTime(2026, 9, 17, 10, 36);

  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// Unos cuantos fotogramas en vez de `pumpAndSettle`: aqui siempre hay algo
  /// girando —un `CircularProgressIndicator` es una animacion sin fin— y
  /// `pumpAndSettle` se quedaria esperando a que no quedara ninguna.
  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Desmonta DENTRO de la prueba. Dos cosas dejan temporizadores vivos: los
  /// streams de Drift, que al cerrarse ponen uno de duracion cero, y el suelo de
  /// la espera (`EstadoDeLaPrimeraBajada.elSuelo`), que se cancela al tirar el
  /// `ProviderScope`. Sin esto la prueba acaba en rojo por «queda un Timer» sin
  /// que haya nada roto.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> pintar(WidgetTester tester, Widget pantalla) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: Scaffold(body: pantalla),
        ),
      ),
    );
    await asentar(tester);
  }

  // ───────────────────────── sembrar ─────────────────────────

  Future<void> bajada(String coleccion) => base
      .into(base.frescura)
      .insertOnConflictUpdate(
        FrescuraCompanion.insert(
          coleccion: coleccion,
          bajadaAt: Value(ahora.subtract(const Duration(minutes: 1))),
          completa: const Value(true),
        ),
      );

  Future<void> sucursalConPunto() => base
      .into(base.branches)
      .insertOnConflictUpdate(
        BranchesCompanion.insert(
          id: 'b1',
          name: 'Santiago',
          lat: 20.02,
          lng: -75.82,
          externalId: const Value('STG'),
          originConfigured: const Value(true),
          cupRate: const Value(700),
          cupRateTraidoAt: Value(ahora.subtract(const Duration(hours: 1))),
        ),
      );

  Future<void> unVehiculo() => base
      .into(base.vehicles)
      .insertOnConflictUpdate(
        VehiclesCompanion.insert(
          id: 'v1',
          name: 'Camión #1',
          branchId: const Value('b1'),
        ),
      );

  Future<void> unAlmacen() => base
      .into(base.warehouses)
      .insertOnConflictUpdate(
        WarehousesCompanion.insert(
          id: 'a1',
          sucursalCodigo: 'STG',
          nombre: 'Almacén central',
          lat: const Value(20.02),
          lng: const Value(-75.82),
          principal: const Value(true),
        ),
      );

  /// LA FOTO EXACTA DEL FALLO: la bajada va por la mitad.
  ///
  /// Sucursales, vehiculos y ajustes ya entraron; los almacenes todavia no.
  /// Es el estado en el que el Panel decia «Falta configurar esta sucursal» y
  /// señalaba el almacen — el almacen que existe y estaba de camino.
  Future<void> laBajadaAMedias() async {
    await sucursalConPunto();
    await unVehiculo();
    await bajada(Colecciones.sucursales);
    await bajada(Colecciones.vehiculos);
    await bajada(Colecciones.ajustes);
  }

  /// Y el resto entra: los almacenes, con el suyo dentro.
  Future<void> yLlegaElResto() async {
    await unAlmacen();
    await bajada(Colecciones.almacenes);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 0 · EL SUELO DE VERDAD: el ciclo que acaba
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // El temporizador de 20 s es la red de seguridad. El camino normal es este: un
  // ciclo termina —haya salido bien o mal— y la web deja de esperar. Con la red
  // muerta eso pasa en menos de un minuto, muchisimo antes del suelo.

  group('0 · el ciclo que acaba cierra la espera', () {
    test('un ciclo que se cayó por red basta: se deja de esperar', () async {
      await Destino.comoSiFueraWeb(() async {
        final contenedor = ProviderContainer(
          overrides: [baseProvider.overrideWithValue(base)],
        );
        addTearDown(contenedor.dispose);

        expect(
          contenedor.read(porQueEstaVacioProvider),
          PorQueEstaVacio.todaviaBajando,
          reason: 'la web abre con la base vacía y sin saber nada todavía',
        );

        // Un ciclo SIN SESION no cuenta: no se intento nada, ni una peticion.
        contenedor.read(alAcabarElCicloProvider)(
          ResumenDelCiclo.sinNadaQueHacer,
        );
        expect(
          contenedor.read(porQueEstaVacioProvider),
          PorQueEstaVacio.todaviaBajando,
        );

        // Uno que se cayo por red SI: se intento, y no llego.
        contenedor.read(alAcabarElCicloProvider)(
          const ResumenDelCiclo(fallo: FalloDeRed()),
        );
        expect(
          contenedor.read(porQueEstaVacioProvider),
          PorQueEstaVacio.noPudoBajar,
          reason:
              'si no se anota aquí, la única salida sería el temporizador de '
              '20 s y la web se pasaría ese rato girando en balde',
        );
        // Y la franja de arriba se entera por el mismo sitio: si alguien deja
        // una de las dos anotaciones fuera, la otra no lo tapa.
        expect(contenedor.read(saludDeLaRedProvider).fallosSeguidos, 1);
      });
    });

    test('en el APARATO no hay nada que esperar: nace ya decidido', () {
      final contenedor = ProviderContainer(
        overrides: [baseProvider.overrideWithValue(base)],
      );
      addTearDown(contenedor.dispose);

      expect(
        contenedor.read(porQueEstaVacioProvider),
        PorQueEstaVacio.noSeDescargo,
        reason:
            'la base del aparato es un fichero: lo que tenga dentro es lo que '
            'hay, y «no se ha descargado» es un estado de verdad',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 1 · EL PANEL — el paso a paso de la puesta en marcha
  // ═══════════════════════════════════════════════════════════════════════════

  group('1 · el Panel no acusa a la sucursal de lo que no ha mirado', () {
    testWidgets(
      'en WEB, con la bajada a medias, NO dice que falte configurar nada; y '
      'cuando llega el resto, aparece solo',
      (tester) async {
        await Destino.comoSiFueraWeb(() async {
          // 1. Como abre la web: base vacia del todo.
          await pintar(tester, const SingleChildScrollView(child: PasoAPaso()));
          expect(find.text('Falta configurar esta sucursal'), findsNothing);

          // 2. EL INSTANTE DEL FALLO. Media bajada dentro, los almacenes aun de
          //    camino. Aqui es donde salia el mensaje que vio Jose.
          await laBajadaAMedias();
          await asentar(tester);

          expect(
            find.text('Falta configurar esta sucursal'),
            findsNothing,
            reason:
                'el almacén existe y viene de camino: acusar a la sucursal de '
                'no tenerlo manda a alguien a dar de alta uno que ya está',
          );
          expect(
            find.text('Al menos un almacén con su punto puesto'),
            findsNothing,
          );
          expect(
            find.text(
              tituloDeLoQueFaltaPorBajar(PorQueEstaVacio.todaviaBajando),
            ),
            findsNothing,
            reason:
                'mientras baja no se pinta NADA: un recuadro que aparece y se '
                'va empuja el Panel entero debajo del dedo',
          );
          // Y ni una palabra del mundo del aparato.
          expect(
            find.textContaining('Este aparato'),
            findsNothing,
            reason: 'en un navegador no hay aparato al que traerle el día',
          );

          // 3. Llega el resto, con la pantalla delante y sin recargar nada.
          await yLlegaElResto();
          await asentar(tester);

          expect(
            find.text('Falta configurar esta sucursal'),
            findsNothing,
            reason: 'ahora está todo: el paso a paso no tiene nada que decir',
          );

          await desmontar(tester);
        });
      },
    );

    testWidgets(
      'en WEB, bajado y de verdad SIN almacén, sí se dice lo que falta',
      (tester) async {
        await Destino.comoSiFueraWeb(() async {
          await pintar(tester, const SingleChildScrollView(child: PasoAPaso()));

          // Bajo TODO, almacenes incluidos, y no hay ninguno. Eso ya no es «de
          // camino»: es un hueco de verdad y se dice con todas las letras.
          await laBajadaAMedias();
          await bajada(Colecciones.almacenes);
          await asentar(tester);

          expect(find.text('Falta configurar esta sucursal'), findsOneWidget);
          expect(
            find.text('Al menos un almacén con su punto puesto'),
            findsOneWidget,
          );
          expect(find.text('Poner el almacén'), findsOneWidget);

          await desmontar(tester);
        });
      },
    );

    testWidgets('en APARATO, con la bajada a medias, el texto de siempre SÍ '
        'sale', (tester) async {
      await pintar(tester, const SingleChildScrollView(child: PasoAPaso()));
      await laBajadaAMedias();
      await asentar(tester);

      // Aqui «no se ha descargado» es un estado de verdad —el aparato se queda
      // asi hasta que alguien trae el dia— y se dice con sus palabras.
      expect(
        find.text(PasoDeConfiguracion.textoSinDescargar),
        findsOneWidget,
        reason:
            'en la APK esto no es un momento de paso: es el estado en el que '
            'se queda el aparato hasta que se trae el día',
      );
      expect(
        find.text('Al menos un almacén con su punto puesto'),
        findsOneWidget,
      );
      // Y NO se ofrece dar de alta nada: esto se arregla trayendo el dia.
      expect(find.text('Poner el almacén'), findsNothing);

      await desmontar(tester);
    });

    testWidgets(
      'EL SUELO: si el resto no llega, el Panel lo dice —y no acusa a la '
      'sucursal ni nombra ningún aparato',
      (tester) async {
        await Destino.comoSiFueraWeb(() async {
          await pintar(tester, const SingleChildScrollView(child: PasoAPaso()));
          await laBajadaAMedias();
          await asentar(tester);
          expect(find.byType(FilledButton), findsNothing);

          // Los almacenes no llegan nunca. Pasa el suelo de la espera.
          await tester.pump(
            EstadoDeLaPrimeraBajada.elSuelo + const Duration(seconds: 1),
          );
          await asentar(tester);

          // Se dice, y se deja entrar: el paso sale, pero NO como algo que
          // haya que dar de alta.
          expect(
            find.text(tituloDeLoQueFaltaPorBajar(PorQueEstaVacio.noPudoBajar)),
            findsOneWidget,
          );
          expect(find.text('Falta configurar esta sucursal'), findsNothing);
          expect(
            find.text(PasoDeConfiguracion.textoNoLlego),
            findsOneWidget,
            reason: 'no es que el almacén no esté: es que no llegó',
          );
          expect(
            find.text(PasoDeConfiguracion.textoSinDescargar),
            findsNothing,
            reason: 'ahí dentro va «este aparato» y «trayendo el día»',
          );
          expect(find.text('Poner el almacén'), findsNothing);

          await desmontar(tester);
        });
      },
    );

    testWidgets(
      'el título tampoco acusa: con todo lo pendiente sin mirar, lo que falta '
      'es la bajada, no la configuración',
      (tester) async {
        await pintar(tester, const SingleChildScrollView(child: PasoAPaso()));
        await laBajadaAMedias();
        await asentar(tester);

        expect(
          find.text('Falta configurar esta sucursal'),
          findsNothing,
          reason:
              'no se ha mirado ni un almacén: no hay nada que se sepa que '
              'falte configurar',
        );
        expect(
          find.text(tituloDeLoQueFaltaPorBajar(PorQueEstaVacio.noSeDescargo)),
          findsOneWidget,
        );

        await desmontar(tester);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2 · REPORTES
  // ═══════════════════════════════════════════════════════════════════════════

  group('2 · Reportes no habla del «aparato»', () {
    Future<void> bajadaEntera() async {
      for (final coleccion in Colecciones.todas) {
        await bajada(coleccion);
      }
    }

    testWidgets(
      'en WEB, con la base vacía, dice «cargando» y no «no hay nada '
      'descargado»; y al llegar la bajada, cuadra sin nombrar ningún aparato',
      (tester) async {
        await Destino.comoSiFueraWeb(() async {
          await pintar(tester, const PantallaInformes());

          expect(
            find.text(TextosNuevosDeInformes.sinNadaQueCuadrar),
            findsNothing,
            reason:
                '«Con conexión baja sola» delante de alguien que tiene '
                'conexión es explicarle algo que en su caso no pasa',
          );
          expect(find.byType(PantallaSinDescargar), findsNothing);
          expect(
            find.text(TextosNuevosDeInformes.cargandoElReporte),
            findsOneWidget,
            reason: 'lo honesto mientras no se ha mirado nada es cargando',
          );

          // Llega la bajada, con la pantalla delante.
          await bajadaEntera();
          await asentar(tester);

          expect(
            find.textContaining('datos del aparato'),
            findsNothing,
            reason: 'en la web no hay aparato, y conexión hay siempre',
          );
          expect(
            find.textContaining('Con conexión sale el del servidor'),
            findsNothing,
          );
          expect(
            find.text(TextosNuevosDeInformes.cuadradoConLoQueBajo('10:35')),
            findsOneWidget,
          );

          await desmontar(tester);
        });
      },
    );

    testWidgets('en APARATO, con la base vacía, el texto de siempre SÍ sale', (
      tester,
    ) async {
      await pintar(tester, const PantallaInformes());

      expect(
        find.text(TextosNuevosDeInformes.sinNadaQueCuadrar),
        findsOneWidget,
      );
      expect(find.byType(PantallaSinDescargar), findsOneWidget);

      await bajadaEntera();
      await asentar(tester);

      expect(
        find.text(
          TextosNuevosDeInformes.cuadradoConElAparato('17/9/2026, 10:35'),
        ),
        findsOneWidget,
        reason:
            'en la APK el informe SÍ sale del aparato, y eso hay que decirlo',
      );

      await desmontar(tester);
    });

    testWidgets(
      'EL SUELO: si la bajada no llega, la web deja de esperar y lo dice',
      (tester) async {
        await Destino.comoSiFueraWeb(() async {
          await pintar(tester, const PantallaInformes());
          expect(
            find.text(TextosNuevosDeInformes.cargandoElReporte),
            findsOneWidget,
          );

          // Nadie baja nada. Pasa el suelo de la espera y la pantalla tiene que
          // acabar diciendolo: una rueda que no para nunca es peor que el
          // mensaje falso.
          await tester.pump(
            EstadoDeLaPrimeraBajada.elSuelo + const Duration(seconds: 1),
          );
          await asentar(tester);

          expect(
            find.text(TextosNuevosDeInformes.cargandoElReporte),
            findsNothing,
            reason: 'la espera tiene suelo: no puede durar para siempre',
          );
          expect(
            find.text(TextosNuevosDeInformes.noLlegoElReporte),
            findsWidgets,
          );
          // Y sin mandar a nadie a mirar la señal que ya tiene.
          expect(find.textContaining('Sin conexión'), findsNothing);
          expect(find.textContaining('aparato'), findsNothing);

          await desmontar(tester);
        });
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3 · CLIENTES
  // ═══════════════════════════════════════════════════════════════════════════

  group('3 · Clientes no dice «no se ha descargado» mientras baja', () {
    testWidgets(
      'en WEB, con la base vacía, dice «cargando»; y los clientes que entran '
      'después salen solos',
      (tester) async {
        await Destino.comoSiFueraWeb(() async {
          await pintar(tester, const PantallaClientes());

          expect(
            find.text(SinDescargar.textoDeLaPantallaVacia),
            findsNothing,
            reason:
                'los clientes vienen de camino: decir que no se han '
                'descargado es acusar al servidor de algo que no pasa',
          );
          expect(
            find.text('Sin descargar todavía'),
            findsNothing,
            reason: 'el reloj en ámbar repetía el mismo mensaje falso, arriba',
          );
          expect(find.text('Cargando…'), findsOneWidget);

          // Entra la bajada, sin volver a montar nada.
          await sembrarSucursal(base);
          await sembrarCliente(
            base,
            id: 'c1',
            nombre: 'Bodega La Estrella',
            lat: almacenLat,
            lng: almacenLng,
          );
          await marcarBajada(
            base,
            ahora,
            colecciones: const [Colecciones.clientes, Colecciones.almacenes],
          );
          await asentar(tester);

          expect(find.text('Cargando…'), findsNothing);
          expect(find.text('Bodega La Estrella'), findsOneWidget);

          await desmontar(tester);
        });
      },
    );

    testWidgets('en APARATO, con la base vacía, el texto de siempre SÍ sale', (
      tester,
    ) async {
      await sembrarSucursal(base);
      await pintar(tester, const PantallaClientes());

      expect(find.text(SinDescargar.textoDeLaPantallaVacia), findsOneWidget);
      expect(find.text('Sin descargar todavía'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('EL SUELO: si no llega, Clientes lo dice y deja entrar', (
      tester,
    ) async {
      await Destino.comoSiFueraWeb(() async {
        await pintar(tester, const PantallaClientes());
        await tester.pump(
          EstadoDeLaPrimeraBajada.elSuelo + const Duration(seconds: 1),
        );
        await asentar(tester);

        expect(find.text('Cargando…'), findsNothing);
        expect(
          find.text(TextosDeLaWeb.noPudoBajar('los clientes')),
          findsOneWidget,
        );
        // Los filtros siguen ahi: se dice lo que pasa y se deja entrar.
        expect(find.text('Clientes'), findsOneWidget);

        await desmontar(tester);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4 · VEHICULOS y ALMACENES — las dos que viven de la red
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // Estas dos no leen la base: preguntan al servidor. Su mensaje falso es otro y
  // sale cuando la peticion se cae — le cuentan a quien esta en la web lo que
  // tiene «el aparato» dentro y le mandan a traer el dia desde el Panel. En un
  // navegador no hay ni una cosa ni la otra: la copia local nace vacia en cada
  // carga y el gesto de traer el dia ni siquiera existe alli (regla 1).

  group('4 · Vehículos y Almacenes, cuando el servidor no contesta', () {
    Future<void> pintarConBanco(
      WidgetTester tester,
      ProviderContainer contenedor,
      BaseLocal suBase,
      Widget pantalla,
    ) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(suBase),
            clienteApiProvider.overrideWithValue(
              contenedor.read(clienteApiProvider),
            ),
            relojProvider.overrideWithValue(() => ahora),
          ],
          child: MaterialApp(home: Scaffold(body: pantalla)),
        ),
      );
      await asentar(tester);
    }

    testWidgets('en WEB, Vehículos no habla del aparato ni de la señal', (
      tester,
    ) async {
      await Destino.comoSiFueraWeb(() async {
        final banco = veh.Banco.sinRed();
        addTearDown(banco.cerrar);
        await pintarConBanco(
          tester,
          banco.contenedor,
          banco.base,
          const PantallaVehiculos(),
        );

        expect(
          find.textContaining('no ha descargado la flota todavía'),
          findsNothing,
          reason:
              'en la web la copia local nace vacía en cada carga: decirlo no '
              'informa de nada y manda a traer un día que allí no existe',
        );
        expect(find.textContaining('Sin conexión.'), findsNothing);
        expect(find.textContaining('en el aparato'), findsNothing);
        // Lo que SI se dice: quien no contesta es el servidor, y se puede
        // volver a intentar.
        expect(
          find.textContaining('La página cargó, así que conexión hay'),
          findsOneWidget,
        );
        expect(find.text('Reintentar'), findsOneWidget);

        await desmontar(tester);
      });
    });

    testWidgets('en APARATO, Vehículos sigue diciendo lo de siempre', (
      tester,
    ) async {
      final banco = veh.Banco.sinRed();
      addTearDown(banco.cerrar);
      await pintarConBanco(
        tester,
        banco.contenedor,
        banco.base,
        const PantallaVehiculos(),
      );

      // Issue 14 (16/10/2026): en el aparato la flota sale de la BASE LOCAL, no
      // del servidor, así que ya no hay «Sin conexión.» (no se preguntó a nadie);
      // lo que sigue diciéndose, y es lo que esta prueba vigila, es que el aparato
      // no la ha descargado: no «no hay vehículos».
      expect(
        find.textContaining('no ha descargado la flota todavía'),
        findsOneWidget,
      );
      expect(find.textContaining('Sin conexión.'), findsNothing);
      expect(find.text('Sin vehículos'), findsNothing);

      await desmontar(tester);
    });

    testWidgets('en WEB, Almacenes tampoco', (tester) async {
      await Destino.comoSiFueraWeb(() async {
        final banco = alm.Banco.sinRed();
        addTearDown(banco.cerrar);
        await pintarConBanco(
          tester,
          banco.contenedor,
          banco.base,
          const PantallaAlmacenes(),
        );

        expect(
          find.textContaining('no ha descargado los almacenes todavía'),
          findsNothing,
        );
        expect(
          find.textContaining('traer el día desde el Panel'),
          findsNothing,
          reason: 'en la web no hay ningún día que traer a mano',
        );
        expect(find.textContaining('Sin conexión.'), findsNothing);
        expect(
          find.textContaining('La página cargó, así que conexión hay'),
          findsOneWidget,
        );

        await desmontar(tester);
      });
    });

    testWidgets('en APARATO, Almacenes sigue diciendo lo de siempre', (
      tester,
    ) async {
      final banco = alm.Banco.sinRed();
      addTearDown(banco.cerrar);
      await pintarConBanco(
        tester,
        banco.contenedor,
        banco.base,
        const PantallaAlmacenes(),
      );

      expect(find.textContaining('Sin conexión.'), findsOneWidget);
      expect(
        find.textContaining('no ha descargado los almacenes todavía'),
        findsOneWidget,
      );

      await desmontar(tester);
    });
  });
}

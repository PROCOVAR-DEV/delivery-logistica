import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/sincro/bajada.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

/// LA BAJADA DEL DIA. Lo que se comprueba aqui es lo unico que importa de esta
/// pieza: que las filas quedan en la base y que la frescura queda marcada. De lo
/// segundo sale «Datos de las 9:14» en la franja, y sin ello la pantalla sigue
/// diciendo «no se ha descargado todavia» con los datos ya puestos.
void main() {
  late BaseLocal base;
  late RegistroDeFrescura frescura;
  final ahora = DateTime(2026, 9, 15, 8, 30);

  setUp(() {
    base = baseDePrueba();
    frescura = RegistroDeFrescura(base, reloj: () => ahora);
  });
  tearDown(() => base.close());

  Bajada conRespuestas(List<Map<String, Object?>> respuestas) {
    var vuelta = 0;
    return Bajada(
      cliente: clienteFalso((p) async {
        if (p.ruta.endsWith('/almacenes')) {
          return RespuestaFalsa(200, <String, Object?>{
            'sucursales': <Object?>[
              <String, Object?>{
                'codigo': 'STG',
                'almacenes': <Object?>[
                  <String, Object?>{
                    'id': 'alm-1',
                    'nombre': 'Central',
                    'latitud': 20.02,
                    'longitud': -75.82,
                    'principal': true,
                  },
                ],
              },
            ],
          });
        }
        final cuerpo = respuestas[vuelta.clamp(0, respuestas.length - 1)];
        vuelta++;
        return RespuestaFalsa(200, cuerpo);
      }),
      base: base,
      frescura: frescura,
      reloj: () => ahora,
    );
  }

  Map<String, Object?> conjunto({
    List<Object?> puestos = const [],
    List<String> quitados = const [],
  }) => <String, Object?>{'puestos': puestos, 'quitados': quitados};

  Map<String, Object?> unPedido(String id) => <String, Object?>{
    'id': id,
    'operationNumber': 'X-2992',
    'customerName': 'Ferretería del Centro',
    'address': 'Calle 3 #45',
    'weight': 120.5,
    'status': 'pending',
    'branchId': 'suc-stg',
    'sucursalCodigo': 'STG',
    'municipio': 'Santiago',
    'updatedAt': '2026-09-15T07:00:00.000Z',
    'items': <Object?>[
      <String, Object?>{
        'id': '$id-l1',
        'linea': 1,
        'description': 'Cemento gris',
        'quantity': 20,
        'packs': 2,
      },
    ],
  };

  test('la carga completa deja pedidos, renglones y la marca de frescura', () async {
    final resumen = await conRespuestas([
      <String, Object?>{
        'hasta': '2026-09-15T08:00:00.000Z',
        'completa': true,
        'truncado': false,
        'cambios': <String, Object?>{
          'orders': conjunto(puestos: [unPedido('p-1')]),
          // Desde la 00019 la api la manda siempre; sin ella no se marca (bajada.dart).
          'distribuidores': conjunto(),
          'vehicle_types': conjunto(),
          'branches': conjunto(
            puestos: [
              <String, Object?>{
                'id': 'suc-stg',
                'name': 'Santiago',
                'externalId': 'STG',
                'lat': 20.02,
                'lng': -75.82,
              },
            ],
          ),
          'vehicles': conjunto(
            puestos: [
              <String, Object?>{
                'id': 'v-1',
                'name': 'Camión 1',
                'capacity': 3000,
                'status': 'available',
                'branchId': 'suc-stg',
              },
            ],
          ),
        },
      },
    ]).ciclo();

    expect(resumen.puestos, 3);
    expect(resumen.completa, isTrue);

    final pedidos = await base.select(base.orders).get();
    expect(pedidos, hasLength(1));
    expect(pedidos.single.operationNumber, 'X-2992');
    expect(pedidos.single.weight, 120.5);

    final renglones = await base.select(base.orderItems).get();
    expect(renglones, hasLength(1));
    expect(renglones.single.description, 'Cemento gris');
    expect(renglones.single.packs, 2);

    expect(await base.select(base.branches).get(), hasLength(1));
    expect(await base.select(base.vehicles).get(), hasLength(1));

    // La marca, en TODAS las colecciones que sirve la bajada mas los renglones.
    for (final coleccion in [...Bajada.colecciones, Colecciones.renglones]) {
      expect(
        await frescura.seDescargo(coleccion),
        isTrue,
        reason: 'sin marca, la pantalla dice «sin descargar» con datos puestos',
      );
    }
    expect(
      await frescura.desde(Colecciones.pedidos),
      '2026-09-15T08:00:00.000Z',
    );
  });

  test('la segunda bajada pide DESDE la marca que dio el servidor', () async {
    final peticiones = <PeticionVista>[];
    var vuelta = 0;
    final bajada = Bajada(
      cliente: clienteFalso((p) async {
        peticiones.add(p);
        vuelta++;
        return RespuestaFalsa(200, <String, Object?>{
          'hasta': '2026-09-15T0$vuelta:00:00.000Z',
          'completa': vuelta == 1,
          'truncado': false,
          'cambios': <String, Object?>{'orders': conjunto()},
        });
      }),
      base: base,
      frescura: frescura,
      reloj: () => ahora,
    );

    await bajada.ciclo();
    await bajada.ciclo();

    expect(peticiones.first.ruta, endsWith('/sync/cambios'));
    expect(
      peticiones.first.parametros['desde'],
      isNull,
      reason: 'la primera vez es la carga completa',
    );
    expect(
      peticiones.last.parametros['desde'],
      '2026-09-15T01:00:00.000Z',
      reason: 'la marca la pone el SERVIDOR, no el reloj del aparato',
    );
  });

  // 1.0.35: la bajada empieza a leer `facturaAt`, y por diferencias un pedido que no cambia no
  // vuelve a viajar. EN PAREJA: el aparato que YA tenía la copia la baja entera UNA vez (sin
  // `desde`), y después vuelve a pedir por diferencias; el que ya lo hizo no lo repite nunca.
  group(
    'la copia de antes de la 1.0.35 se vuelve a bajar entera, una sola vez',
    () {
      Bajada contando(List<PeticionVista> peticiones) {
        var vuelta = 0;
        return Bajada(
          cliente: clienteFalso((p) async {
            peticiones.add(p);
            vuelta++;
            return RespuestaFalsa(200, <String, Object?>{
              'hasta': '2026-10-15T0$vuelta:00:00.000Z',
              'completa': false,
              'truncado': false,
              'cambios': <String, Object?>{'orders': conjunto()},
            });
          }),
          base: base,
          frescura: frescura,
          reloj: () => ahora,
        );
      }

      test('un aparato con la copia vieja pide sin `desde` la primera vez y luego por diferencias', () async {
        await frescura.marcar(
          Colecciones.pedidos,
          hasta: '2026-10-01T00:00:00.000Z',
        );
        final peticiones = <PeticionVista>[];
        final bajada = contando(peticiones);

        await bajada.ciclo();
        await bajada.ciclo();

        expect(
          peticiones.first.parametros['desde'],
          isNull,
          reason:
              'la copia de antes de la 1.0.35 no tiene la fecha de factura de los pedidos que no '
              'cambiaron: tiene que bajarlos ENTEROS una vez, o «Sin colocar» sale en otro orden '
              'que en la web',
        );
        expect(
          peticiones.last.parametros['desde'],
          '2026-10-15T01:00:00.000Z',
          reason: 'después de la vez, vuelve a pedir por diferencias: no es una bajada entera siempre',
        );
      });

      test('el aparato que ya la hizo no la repite', () async {
        await frescura.rebajarLosPedidosUnaVez();
        await frescura.rebajarLasRutasUnaVez();
        await frescura.rebajarLosPedidosPorSuAlmacen();
        await frescura.rebajarLosPedidosPorSuFolio();
        await frescura.rebajarLosPedidosPorLaFacturaDeSusRenglones();
        await frescura.rebajarLasFacturasAnuladas();
        await frescura.marcar(
          Colecciones.pedidos,
          hasta: '2026-10-14T00:00:00.000Z',
        );
        final peticiones = <PeticionVista>[];

        await contando(peticiones).ciclo();

        expect(
          peticiones.first.parametros['desde'],
          '2026-10-14T00:00:00.000Z',
        );
      });

      // Issue 7: las rutas que ya estaban no traen su `distribuidorId` por diferencias. EN
      // PAREJA: quien ya hizo la de la factura (1.0.35) hace ESTA una vez, y luego no.
      test('las rutas se rebajan enteras una vez aunque ya se hiciera la de la factura', () async {
        await frescura.rebajarLosPedidosUnaVez();
        await frescura.rebajarLosPedidosPorSuAlmacen();
        await frescura.rebajarLosPedidosPorSuFolio();
        await frescura.rebajarLosPedidosPorLaFacturaDeSusRenglones();
        await frescura.rebajarLasFacturasAnuladas();
        await frescura.marcar(
          Colecciones.pedidos,
          hasta: '2026-10-14T00:00:00.000Z',
        );
        final peticiones = <PeticionVista>[];
        final bajada = contando(peticiones);

        await bajada.ciclo();
        await bajada.ciclo();

        expect(
          peticiones.first.parametros['desde'],
          isNull,
          reason:
              'el `desde` de /sync/cambios es UNO para todas (el de pedidos): sin olvidarlo, '
              'las rutas que ya estaban se quedan sin su distribuidor para siempre',
        );
        expect(
          peticiones.last.parametros['desde'],
          '2026-10-15T01:00:00.000Z',
          reason: 'una sola vez: luego, por diferencias',
        );
      });

      // 21/10/2026 (esquema 13): las facturas que ya estaban no traen su `folio` por diferencias.
      // EN PAREJA: quien ya hizo todas las demás hace ESTA una vez, y luego no.
      test('los pedidos se rebajan enteros una vez por el folio aunque ya se hicieran las demás', () async {
        await frescura.rebajarLosPedidosUnaVez();
        await frescura.rebajarLasRutasUnaVez();
        await frescura.rebajarLosPedidosPorSuAlmacen();
        await frescura.marcar(
          Colecciones.pedidos,
          hasta: '2026-10-14T00:00:00.000Z',
        );
        final peticiones = <PeticionVista>[];
        final bajada = contando(peticiones);

        await bajada.ciclo();
        await bajada.ciclo();

        expect(
          peticiones.first.parametros['desde'],
          isNull,
          reason:
              'la copia de antes del esquema 13 no tiene el folio de las facturas que no cambiaron: '
              'tiene que bajarlas ENTERAS una vez, o la columna «Pedido» sale en blanco para siempre',
        );
        expect(
          peticiones.last.parametros['desde'],
          '2026-10-15T01:00:00.000Z',
          reason: 'una sola vez: luego, por diferencias',
        );
      });

      // 23/10/2026 (esquema 15): las facturas canceladas de la última semana no llegan por diferencias
      // a un aparato cuya marca ya pasó de la hora en que se anularon. EN PAREJA: quien ya hizo todas
      // las demás hace ESTA una vez, y luego no.
      test('los pedidos se rebajan enteros una vez por las facturas anuladas aunque ya se hicieran las demás', () async {
        await frescura.rebajarLosPedidosUnaVez();
        await frescura.rebajarLasRutasUnaVez();
        await frescura.rebajarLosPedidosPorSuAlmacen();
        await frescura.rebajarLosPedidosPorSuFolio();
        await frescura.rebajarLosPedidosPorLaFacturaDeSusRenglones();
        await frescura.marcar(
          Colecciones.pedidos,
          hasta: '2026-10-14T00:00:00.000Z',
        );
        final peticiones = <PeticionVista>[];
        final bajada = contando(peticiones);

        await bajada.ciclo();
        await bajada.ciclo();

        expect(
          peticiones.first.parametros['desde'],
          isNull,
          reason:
              'sin la carga entera, una factura anulada ANTES de la marca de este aparato no se '
              'avisa nunca: la cancelada sigue sin decirse',
        );
        expect(
          peticiones.last.parametros['desde'],
          '2026-10-15T01:00:00.000Z',
          reason: 'una sola vez: luego, por diferencias',
        );
      });

      // 22/10/2026 (esquema 14, issue 22 de Maikel): los renglones que ya estaban no traen su
      // `facturaNumero` por diferencias. EN PAREJA: quien ya hizo todas las demás hace ESTA una
      // vez, y luego no.
      test('los pedidos se rebajan enteros una vez por la factura de sus renglones aunque ya se hicieran las demás', () async {
        await frescura.rebajarLosPedidosUnaVez();
        await frescura.rebajarLasRutasUnaVez();
        await frescura.rebajarLosPedidosPorSuAlmacen();
        await frescura.rebajarLosPedidosPorSuFolio();
        await frescura.marcar(
          Colecciones.pedidos,
          hasta: '2026-10-14T00:00:00.000Z',
        );
        final peticiones = <PeticionVista>[];
        final bajada = contando(peticiones);

        await bajada.ciclo();
        await bajada.ciclo();

        expect(
          peticiones.first.parametros['desde'],
          isNull,
          reason:
              'la copia de antes del esquema 14 no tiene la factura de los renglones que no '
              'cambiaron: tiene que bajarlos ENTEROS una vez, o «Por producto y factura» deja '
              'juntas las facturas de una entrega PARA SIEMPRE',
        );
        expect(
          peticiones.last.parametros['desde'],
          '2026-10-15T01:00:00.000Z',
          reason: 'una sola vez: luego, por diferencias',
        );
      });

      // 15/10/2026: los pedidos que ya estaban no traen su `almacenSalidaCodigo` por
      // diferencias, y sin él «Sin colocar» no pone primero los del almacén elegido arriba en
      // la APK. EN PAREJA: quien ya hizo las otras dos hace ESTA una vez, y luego no.
      test('los pedidos se rebajan enteros una vez por su almacén aunque ya se hicieran las otras', () async {
        await frescura.rebajarLosPedidosUnaVez();
        await frescura.rebajarLasRutasUnaVez();
        await frescura.marcar(
          Colecciones.pedidos,
          hasta: '2026-10-14T00:00:00.000Z',
        );
        final peticiones = <PeticionVista>[];
        final bajada = contando(peticiones);

        await bajada.ciclo();
        await bajada.ciclo();

        expect(
          peticiones.first.parametros['desde'],
          isNull,
          reason:
              'sin olvidar el cursor, los pedidos que ya estaban se quedan sin su almacén para '
              'siempre y la APK ordena «Sin colocar» distinto que la web',
        );
        expect(
          peticiones.last.parametros['desde'],
          '2026-10-15T01:00:00.000Z',
          reason: 'una sola vez: luego, por diferencias',
        );
      });
    },
  );

  test('`truncado` encadena otra tanda, y sin `hasta` se para', () async {
    final resumen = await conRespuestas([
      <String, Object?>{
        'hasta': '2026-09-15T07:00:00.000Z',
        'completa': true,
        'truncado': true,
        'cambios': <String, Object?>{
          'orders': conjunto(puestos: [unPedido('p-1')]),
        },
      },
      <String, Object?>{
        'hasta': '2026-09-15T08:00:00.000Z',
        'completa': false,
        'truncado': false,
        'cambios': <String, Object?>{
          'orders': conjunto(puestos: [unPedido('p-2')]),
        },
      },
    ]).ciclo();

    expect(resumen.tandas, 2);
    expect(await base.select(base.orders).get(), hasLength(2));
  });

  test('`quitados` borra el pedido Y sus renglones', () async {
    final bajada = conRespuestas([
      <String, Object?>{
        'hasta': '2026-09-15T07:00:00.000Z',
        'completa': true,
        'truncado': false,
        'cambios': <String, Object?>{
          'orders': conjunto(puestos: [unPedido('p-1')]),
        },
      },
      <String, Object?>{
        'hasta': '2026-09-15T08:00:00.000Z',
        'completa': false,
        'truncado': false,
        'cambios': <String, Object?>{
          'orders': conjunto(quitados: ['p-1']),
        },
      },
    ]);

    await bajada.ciclo();
    expect(await base.select(base.orderItems).get(), hasLength(1));

    await bajada.ciclo();
    expect(await base.select(base.orders).get(), isEmpty);
    expect(
      await base.select(base.orderItems).get(),
      isEmpty,
      reason:
          'un renglon huerfano sale en el post-despacho de un pedido que ya '
          'no existe',
    );
  });

  test('los almacenes se bajan aparte y marcan su coleccion', () async {
    final bajada = conRespuestas([
      <String, Object?>{
        'hasta': '2026-09-15T08:00:00.000Z',
        'completa': true,
        'truncado': false,
        'cambios': <String, Object?>{},
      },
    ]);

    expect(await bajada.almacenes(), 1);

    final almacenes = await base.select(base.warehouses).get();
    expect(almacenes.single.nombre, 'Central');
    expect(almacenes.single.sucursalCodigo, 'STG');
    expect(almacenes.single.principal, isTrue);
    expect(await frescura.seDescargo(Colecciones.almacenes), isTrue);
  });

  group('las tandas: el caso de los 2.000 clientes', () {
    // EL FALLO DEL 15/09/2026, contra produccion. Se leyo la base del aparato
    // despues de la bajada: `clientes = 2000`, `productos = 912`,
    // `pedidos = 535`. Con esa cuenta (Super Admin) los clientes son 8.034.
    // Dos mil redondos es el tope de una tanda del servidor
    // (`api/internal/api/espejo.go`, `TopeDeBajada`) que no siguio pidiendo las
    // siguientes — y la bajada se dio por buena. **Nadie se entero.**
    //
    // Estas pruebas son las que fallan si eso vuelve a pasar.

    Map<String, Object?> unCliente(String id) => <String, Object?>{
      'id': id,
      'name': 'Cliente $id',
      'address': 'Calle 1',
      'lat': 20.0,
      'lng': -75.0,
      'sucursalCodigo': 'STG',
      'syncedAt': '2026-09-15T07:00:00.000Z',
    };

    /// Un servidor que sirve [total] clientes de [porTanda] en [porTanda], como
    /// el de verdad: con `truncado` y con la marca de la ULTIMA FILA SERVIDA.
    Bajada enTandasDe({required int total, required int porTanda}) {
      var servidos = 0;
      return Bajada(
        cliente: clienteFalso((p) async {
          if (p.ruta.endsWith('/almacenes')) {
            return RespuestaFalsa(200, <String, Object?>{
              'sucursales': <Object?>[],
            });
          }
          final hasta = servidos + porTanda;
          final lote = <Object?>[
            for (var i = servidos; i < hasta && i < total; i++)
              unCliente('c-$i'),
          ];
          servidos += lote.length;
          return RespuestaFalsa(200, <String, Object?>{
            // La marca AVANZA, que es lo que hace que la tanda siguiente pida
            // lo que falta y no lo mismo otra vez.
            'hasta':
                '2026-09-15T07:00:${servidos.toString().padLeft(2, "0")}.000Z',
            'completa': servidos == lote.length,
            'truncado': servidos < total,
            'cambios': <String, Object?>{'customers': conjunto(puestos: lote)},
          });
        }),
        base: base,
        frescura: frescura,
        reloj: () => ahora,
      );
    }

    test('una tanda truncada SIGUE encadenando hasta el final', () async {
      // Cinco tandas de 20 para 100 clientes. Si alguien rompe el encadenado
      // —quita el `if (datos[\'truncado\'] != true) break;`, sale del bucle
      // antes, o deja de pasar el `hasta` nuevo— esto se queda en 20 y falla.
      final resumen = await enTandasDe(total: 100, porTanda: 20).ciclo();

      expect(await base.select(base.customers).get(), hasLength(100));
      expect(resumen.tandas, 5);
      expect(resumen.puestos, 100);
      expect(resumen.entera, isTrue);
      expect(resumen.quedoPor, isNull);
    });

    test('con UNA sola tanda no se pide una segunda de balde', () async {
      final resumen = await enTandasDe(total: 10, porTanda: 20).ciclo();
      expect(resumen.tandas, 1);
      expect(resumen.entera, isTrue);
    });

    test('el cursor que SI avanza deja seguir aunque la marca no cambie', () async {
      // Los pedidos se continuan por la marca y el padron de clientes por el
      // cursor. Una tanda que solo mueve el cursor SI avanza, y cortarla ahi
      // seria volver a dejarse clientes atras — el fallo de partida, otra vez.
      var vuelta = 0;
      final bajada = Bajada(
        cliente: clienteFalso((p) async {
          if (p.ruta.endsWith('/almacenes')) {
            return RespuestaFalsa(200, <String, Object?>{
              'sucursales': <Object?>[],
            });
          }
          vuelta++;
          return RespuestaFalsa(200, <String, Object?>{
            // LA MISMA marca en las tres tandas, a proposito.
            'hasta': '2026-09-15T07:00:00.000Z',
            'completa': vuelta == 1,
            'truncado': vuelta < 3,
            'continuar': vuelta < 3 ? 'cursor-$vuelta' : null,
            'cambios': <String, Object?>{
              'customers': conjunto(puestos: [unCliente('c-$vuelta')]),
            },
          });
        }),
        base: base,
        frescura: frescura,
        reloj: () => ahora,
      );

      final resumen = await bajada.ciclo();

      expect(resumen.tandas, 3);
      expect(resumen.entera, isTrue);
      expect(await base.select(base.customers).get(), hasLength(3));
    });

    test(
      'el cursor viaja de vuelta tal cual, sin mirarlo por dentro',
      () async {
        final pedidas = <PeticionVista>[];
        var vuelta = 0;
        final bajada = Bajada(
          cliente: clienteFalso((p) async {
            if (p.ruta.endsWith('/almacenes')) {
              return RespuestaFalsa(200, <String, Object?>{
                'sucursales': <Object?>[],
              });
            }
            pedidas.add(p);
            vuelta++;
            return RespuestaFalsa(200, <String, Object?>{
              'hasta': '2026-09-15T0$vuelta:00:00.000Z',
              'completa': vuelta == 1,
              'truncado': vuelta < 2,
              'continuar': vuelta < 2 ? 'eyJjIjoyMDAwfQ' : null,
              'cambios': <String, Object?>{'customers': conjunto()},
            });
          }),
          base: base,
          frescura: frescura,
          reloj: () => ahora,
        );

        await bajada.ciclo();

        expect(pedidas.first.parametros['continuar'], isNull);
        expect(
          pedidas.last.parametros['continuar'],
          'eyJjIjoyMDAwfQ',
          reason: 'el cursor es del servidor y vuelve entero',
        );
      },
    );

    test('`truncado` con la MISMA marca Y el mismo cursor se para y LO DICE', () async {
      // Este es el caso exacto de los 2.000 clientes: el servidor contesta
      // «queda mas» y devuelve la marca de siempre, asi que la tanda siguiente
      // pediria exactamente lo mismo. Lo que no puede pasar es lo que pasaba:
      // dar vueltas escribiendo las mismas filas y salir con cara de haber
      // terminado.
      final resumen = await conRespuestas([
        <String, Object?>{
          'hasta': '2026-09-15T07:00:00.000Z',
          'completa': true,
          'truncado': true,
          'cambios': <String, Object?>{
            'customers': conjunto(puestos: [unCliente('c-1')]),
          },
        },
      ]).ciclo();

      expect(resumen.entera, isFalse, reason: 'se quedo a medias y se dice');
      expect(resumen.quedoPor, contains('no avanzo ni la marca'));
      expect(
        resumen.tandas,
        2,
        reason: 'se para en cuanto se ve que la marca no avanza, no en el tope',
      );
    });

    test('`truncado` sin `hasta` se para y LO DICE', () async {
      final resumen = await conRespuestas([
        <String, Object?>{
          'completa': true,
          'truncado': true,
          'cambios': <String, Object?>{
            'customers': conjunto(puestos: [unCliente('c-1')]),
          },
        },
      ]).ciclo();

      expect(resumen.entera, isFalse);
      expect(resumen.quedoPor, contains('no mando la marca'));
      expect(resumen.tandas, 1);
    });

    test('llegar al tope de tandas NO se da por bueno', () async {
      // Un servidor que siempre dice que queda mas, avanzando la marca. Se para
      // en el tope, y el resumen lo dice: quedarse a medias por el tope es
      // distinto de haber terminado, y la pantalla de configuracion se planta
      // en «faltó» en vez de entrar.
      final resumen = await enTandasDe(total: 100000, porTanda: 1).ciclo();

      expect(resumen.tandas, Bajada.maximoDeTandas);
      expect(resumen.entera, isFalse);
      expect(resumen.quedoPor, contains('tope de ${Bajada.maximoDeTandas}'));
    });
  });
  // LA TASA BAJA DENTRO DE LA SUCURSAL, Y SE QUEDA EN EL APARATO.
  //
  // Es lo que hace que los importes se puedan ver en CUP sin conexion. Antes no
  // bajaba por ningun lado: la barra leia la tabla `currencies`, que no llenaba
  // nadie, y el selector se quedaba en ambar para siempre.
  test('la tasa de cambio baja con la sucursal y queda guardada', () async {
    final bajada = conRespuestas([
      <String, Object?>{
        'hasta': '2026-09-15T08:00:00.000Z',
        'completa': true,
        'cambios': <String, Object?>{
          'branches': conjunto(
            puestos: <Object?>[
              <String, Object?>{
                'id': 'suc-stg',
                'name': 'Santiago',
                'externalId': 'STG',
                'lat': 20.02,
                'lng': -75.82,
                'originConfigured': true,
                'updatedAt': '2026-09-15T07:00:00.000Z',
                'cupRate': 700,
                'cupRateFuente': 'entrega',
                'cupRateTraidoAt': '2026-09-09T22:03:04.076Z',
                'cupRateFresca': false,
              },
              // Y una SIN tasa: los cuatro campos en null. Es el estado de seis
              // de las ocho sucursales hoy, y tiene que llegar tan explicito
              // como el otro.
              <String, Object?>{
                'id': 'suc-gr',
                'name': 'Granma',
                'externalId': 'GR',
                'lat': 20.38,
                'lng': -76.64,
                'updatedAt': '2026-09-15T07:00:00.000Z',
                'cupRate': null,
                'cupRateFuente': null,
                'cupRateTraidoAt': null,
                'cupRateFresca': null,
              },
            ],
          ),
        },
      },
    ]);

    await bajada.ciclo();

    final santiago = await (base.select(
      base.branches,
    )..where((b) => b.id.equals('suc-stg'))).getSingle();
    expect(santiago.cupRate, 700);
    expect(santiago.cupRateFuente, 'entrega');
    expect(santiago.cupRateFresca, isFalse);
    // LA MARCA DE CUANDO, que es lo unico que demuestra que la tasa existe.
    expect(santiago.cupRateTraidoAt, isNotNull);
    expect(santiago.cupRateTraidoAt!.toUtc().day, 9);

    // A la que no tiene NO se le pone la tasa de la otra ni un 320 por defecto:
    // se queda sin nada, y la barra lo dice con su nombre delante.
    final granma = await (base.select(
      base.branches,
    )..where((b) => b.id.equals('suc-gr'))).getSingle();
    expect(
      granma.cupRate,
      isNull,
      reason: 'a Granma se le metio una tasa que no es suya',
    );
    expect(granma.cupRateTraidoAt, isNull);
    expect(granma.cupRateFresca, isNull);

    // Y AHORA SIN CONEXION: lo guardado se lee de la base, no de la red. Esta es
    // la mitad del sentido de que la tasa baje: a las cuatro de la tarde, en el
    // patio del almacen, no hay a quien preguntarle.
    final deLaBase = await (base.select(
      base.branches,
    )..where((b) => b.id.equals('suc-stg'))).getSingle();
    expect(deLaBase.cupRate, 700);
  });
}

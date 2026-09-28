// EL PESO DE UN RENGLON SE RESUELVE UNA VEZ, EN EL SERVIDOR, Y AQUI SE LEE.
//
// ## DE DONDE VIENE ESTE FICHERO — 28/09/2026
//
// El mismo pre-despacho abierto dos veces, medido en la APK 1.0.13 de un
// SM-A165M, con lo unico que cambia arriba:
//
//     Santiago de Cuba (426 pedidos)
//       15 producto(s) · 10197 empaques · ≥ 17318.8 kg (462 renglones sin peso)
//     Todas (8) (1331 pedidos)
//       26 producto(s) · 24741 empaques · ≥ 17318.8 kg (1572 renglones sin peso)
//
// Los empaques y las unidades si cambiaban; los kilos no, **hasta el decimal**.
// La causa era una cascada del peso escrita a medias aqui... y la razon de que
// estuviera escrita aqui es que estaba escrita TRES VECES: en el servidor
// (`PesosDeRenglones`, `api/internal/cotizar/pesos.go`), en la ficha del pedido
// y en esta hoja. Las tres tenian que decir lo mismo y no lo decian: la ficha
// decia «40,0 kg» y la hoja del almacen ponia «—» sobre los mismos 20 empaques.
//
// Jose, el mismo dia: «era mas facil ponerlo en el api y ya q lo consuman una
// cada uno». Y el proyecto ya estaba hecho asi desde la 00004, que añadio
// `peso_linea_kg` «precisamente para no tener que recalcular el peso con el
// catalogo de hoy sobre un pedido de hace tres meses».
//
// ## LO QUE ESTE FICHERO VIGILA AHORA
//
// Queda UNA implementacion —la del servidor— y dos lectores. Lo que se ata aqui
// son las cuatro cosas que costaron aquel dia y que una simplificacion se puede
// llevar por delante sin que nada se ponga rojo:
//
//   1. un CERO no es un peso: es «no se sabe», y la celda no puede decir «0.0 kg»;
//   2. un renglon que SI trae peso no puede contarse como «sin peso»;
//   3. la ficha y el pre-despacho pesan igual el mismo renglon (§3-bis);
//   4. un total a medias sale con `≥` y con cuantos renglones faltan.
//
// Y una quinta, que es la del encargo: **el aparato NO recalcula**. Un renglon
// que trae el peso del empaque pero al que el servidor no le resolvio la linea
// se cuenta como «sin peso» y se dice, en vez de inventarse aqui un numero que
// el servidor no firma.
//
// Las pruebas van con numeros a mano y con DOS sucursales: la mitad del valor de
// la hoja es que el total cambie cuando cambia lo que se mira.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/impresion/hoja.dart' as papel;
import 'package:reparto/impresion/pre_despacho.dart'
    show pesoDeLosProductosEnPapel;
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/pedidos/datos/filtros_pedidos.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/pantalla_pedidos.dart'
    show hojaDePreDespacho;
import 'package:reparto/pantallas/pedidos/vista/vista_pre_despacho.dart'
    show pesoDelPreDespacho;

import '../../apoyo/base_de_prueba.dart';
import 'sembrar.dart';

/// El producto de la medida de Jose. Va SIN emparejar con el catalogo, que es
/// como esta en produccion: el catalogo local no trae el peso de nadie.
const malta = 'MALTA GUAJIRA 330 ML BLISTER 6U';

/// Dos sucursales con el mismo producto, tal como los deja el servidor: cada
/// renglon con su `peso_linea_kg` ya resuelto.
///
///  - `o-stg-1` (B1): 10 empaques ->  100 kg
///  - `o-stg-2` (B1): 20 empaques ->   40 kg  (el servidor resolvio 20 × 2)
///  - `o-hab-1` (B2): 30 empaques ->   60 kg  (el servidor resolvio 30 × 2)
///
/// Con eso, B1 pesa 140 kg y las dos juntas 200 kg, y todo esta contado a mano.
/// Los dos ultimos llevan ademas el peso del EMPAQUE, que es la constancia que
/// guarda la 00004 y que el aparato **no** usa para calcular: esta ahi para que
/// se vea que no se usa.
Future<void> sembrarDosSucursales(BaseLocal base) async {
  await sembrarCatalogo(base);

  await sembrarPedido(base, id: 'o-stg-1', cliente: 'Ana', sucursal: 'B1');
  await sembrarPedido(base, id: 'o-stg-2', cliente: 'Beto', sucursal: 'B1');
  await sembrarPedido(base, id: 'o-hab-1', cliente: 'Cira', sucursal: 'B2');

  await sembrarRenglon(
    base,
    id: 'r1',
    pedidoId: 'o-stg-1',
    producto: malta,
    unidades: 60,
    empaques: 10,
    pesoLinea: 100,
  );
  await sembrarRenglon(
    base,
    id: 'r2',
    pedidoId: 'o-stg-2',
    producto: malta,
    unidades: 120,
    empaques: 20,
    pesoLinea: 40,
    pesoEmpaque: 2,
  );
  await sembrarRenglon(
    base,
    id: 'r3',
    pedidoId: 'o-hab-1',
    producto: malta,
    unidades: 180,
    empaques: 30,
    pesoLinea: 60,
    pesoEmpaque: 2,
  );
}

void main() {
  late BaseLocal base;
  late ConsultasPedidos consultas;

  setUp(() async {
    base = baseDePrueba();
    consultas = ConsultasPedidos(base);
    await sembrarDosSucursales(base);
  });

  tearDown(() => base.close());

  Future<TotalesPreDespacho> preDespachoDe(String? sucursal) =>
      consultas.preDespachoDeLoFiltrado(
        const FiltrosPedidos(),
        sucursalId: sucursal,
      );

  const clavado =
      'EL PESO SE QUEDO CLAVADO AL CAMBIAR DE SUCURSAL. Es la hoja con la que '
      'alguien baja al almacen y mide si la carga cabe en el camion: un numero '
      'que no se mueve cuando el alcance se duplica es creible y esta mal.';

  test(
    'el peso cambia al ensanchar el alcance, igual que los empaques',
    () async {
      final unaSucursal = await preDespachoDe('B1');
      final todas = await preDespachoDe(null);

      // Lo que ya funcionaba, y que es lo que hace visible el fallo: si esto
      // tambien se quedara quieto, seria un problema de cache y no del peso.
      expect(unaSucursal.empaques, 30);
      expect(todas.empaques, 60);
      expect(unaSucursal.unidades, 180);
      expect(todas.unidades, 360);

      // Y lo que no se movia.
      expect(unaSucursal.pesoKg, 140, reason: '100 + 40');
      expect(todas.pesoKg, 200, reason: '140 de B1 + 60 de B2');
      expect(todas.pesoKg, isNot(unaSucursal.pesoKg), reason: clavado);
    },
  );

  // ---------------------------------------------------------------------------
  // GUARDA 2: UN RENGLON CON PESO NO SE CUENTA COMO «SIN PESO»
  // ---------------------------------------------------------------------------
  test(
    'ningun renglon con peso se cuenta como «sin peso»',
    () async {
      // El sintoma de Jose eran las dos mitades a la vez: la cifra quieta Y el
      // contador creciendo. Meter en el contador un renglon que trae su peso
      // manda a alguien a buscar un dato que ya esta.
      for (final sucursal in <String?>['B1', null]) {
        final totales = await preDespachoDe(sucursal);
        expect(
          totales.sinPeso,
          0,
          reason:
              'con alcance «${sucursal ?? 'todas'}» los tres renglones traen '
              'el peso de su linea resuelto, asi que no hay ninguno que falte '
              'por saber',
        );
        expect(totales.pesoCompleto, isTrue);
      }
    },
  );

  // ---------------------------------------------------------------------------
  // GUARDA 1: UN CERO NO ES UN PESO
  // ---------------------------------------------------------------------------
  test(
    'un peso en cero no es un peso: es «no se sabe», y no dice 0.0 kg',
    () async {
      // UN CERO NO ES UN DATO. El servidor lo dice con `Positivo()` en cada
      // escalon de su cascada y por eso deja la columna VACIA cuando no resolvio
      // nada. Pero los renglones que dejo la migracion del delivery viejo
      // (`api/db/migracion/02_pedidos.sql`) copian el JSON tal cual, cero
      // incluido: si ese cero se colara, la hoja del almacen diria «0.0 kg»
      // sobre un renglon que nadie ha pesado, y eso se lee como «no pesa».
      await base.delete(base.orderItems).go();
      await sembrarRenglon(
        base,
        id: 'r1',
        pedidoId: 'o-stg-1',
        producto: malta,
        unidades: 60,
        empaques: 10,
        pesoLinea: 0,
      );

      final totales = await preDespachoDe('B1');
      expect(
        totales.pesoKg,
        isNull,
        reason:
            'un cero no puede salir como peso: la raya dice «no se sabe» y el '
            '0.0 kg dice «no pesa», que son cosas distintas',
      );
      expect(totales.lineas.single.pesoKg, isNull);
      expect(
        totales.sinPeso,
        1,
        reason: 'y el renglon del cero cuenta entre los que faltan por saber',
      );
      expect(totales.pesoCompleto, isFalse);

      // Y en la ficha, lo mismo y con las mismas palabras.
      final ficha = (await consultas.renglonesDe(['o-stg-1']))['o-stg-1']!;
      expect(ficha.single.pesoLinea, isNull);
    },
  );

  // ---------------------------------------------------------------------------
  // LA DEL ENCARGO: EL APARATO NO RECALCULA
  // ---------------------------------------------------------------------------
  test(
    'el aparato NO rehace la cascada: sin peso de linea, no se inventa uno',
    () async {
      // El renglon trae el peso del EMPAQUE (2 kg × 10) y ademas esta emparejado
      // con un producto del catalogo local (Arroz, 25 kg por empaque). Las dos
      // cosas son escalones de la cascada DEL SERVIDOR, y el servidor no los
      // resolvio: la linea llego sin `peso_linea_kg`.
      //
      // Aqui no se resuelve por su cuenta. Si esta prueba empieza a ver 20 o
      // 250, es que la cascada volvio al aparato — y con ella los tres sitios
      // que se desincronizaron el 28/09/2026.
      await base.delete(base.orderItems).go();
      await sembrarRenglon(
        base,
        id: 'r1',
        pedidoId: 'o-stg-1',
        producto: 'Arroz',
        unidades: 100,
        empaques: 10,
        productoId: 'p1',
        pesoEmpaque: 2,
      );

      final totales = await preDespachoDe('B1');
      expect(
        totales.pesoKg,
        isNull,
        reason:
            'el peso lo resuelve el servidor y lo escribe en `peso_linea_kg`; '
            'si aqui sale 20 (el empaque) o 250 (el catalogo), hay dos sitios '
            'contestando otra vez la misma pregunta',
      );
      expect(
        totales.sinPeso,
        1,
        reason:
            'y se DICE: un renglon que el servidor no supo pesar se cuenta, '
            'que es como se sabe que hay que reespejarlo',
      );

      // Y la ficha dice exactamente lo mismo, que es la guarda 3.
      final ficha = (await consultas.renglonesDe(['o-stg-1']))['o-stg-1']!;
      expect(ficha.single.pesoLinea, isNull);
    },
  );

  // ---------------------------------------------------------------------------
  // GUARDA 3 (§3-bis): DOS SITIOS QUE CONTESTAN LO MISMO SE ATAN CON UNA PRUEBA
  // ---------------------------------------------------------------------------
  //
  // La ficha del pedido y el pre-despacho hablan del mismo renglon. Ahora leen
  // los dos la misma columna, pero cada uno por su camino —Dart en la ficha, SQL
  // en la hoja— y el `> 0` esta escrito dos veces. Un comentario no falla; esto
  // si.

  test(
    'la ficha del pedido y el pre-despacho pesan igual el mismo renglon',
    () async {
      // Con un cero por medio, que es donde los dos se pueden volver a separar:
      // uno se queda con el cero y el otro lo descarta.
      await sembrarRenglon(
        base,
        id: 'r4',
        pedidoId: 'o-hab-1',
        producto: 'Arroz',
        unidades: 20,
        empaques: 2,
        productoId: 'p1',
        linea: 2,
        pesoLinea: 0,
      );

      final porPedido = await consultas.renglonesDe([
        'o-stg-1',
        'o-stg-2',
        'o-hab-1',
      ]);
      final deLaFicha = porPedido.values
          .expand((renglones) => renglones)
          .fold<double>(0, (suma, r) => suma + (r.pesoLinea ?? 0));

      final todas = await preDespachoDe(null);
      expect(
        todas.pesoKg,
        deLaFicha,
        reason:
            'la ficha del pedido y la hoja del almacen cuentan el mismo peso '
            'de los mismos renglones: si se separan, una de las dos manda a '
            'alguien al almacen con un numero que la otra desmiente',
      );
      expect(todas.pesoKg, 200);

      // Y LA SUMA NO BASTA, que es el §3-bis entero: un cero suma lo mismo que
      // un «no se sabe», asi que dos lecturas que discrepan sobre ese cero dan
      // el MISMO total y dicen cosas distintas en la celda. Lo que las separa
      // de verdad es cuantos renglones da cada una por sabidos.
      final sinPesoEnLaFicha = porPedido.values
          .expand((renglones) => renglones)
          .where((r) => r.pesoLinea == null)
          .length;
      expect(
        sinPesoEnLaFicha,
        todas.sinPeso,
        reason:
            'la ficha dice que $sinPesoEnLaFicha renglones no tienen peso y la '
            'hoja del almacen dice que ${todas.sinPeso}, sobre los mismos '
            'renglones: una de las dos pinta un numero donde la otra pinta una '
            'raya',
      );
      expect(sinPesoEnLaFicha, 1, reason: 'el del cero, y solo ese');
    },
  );

  // ---------------------------------------------------------------------------
  // GUARDA 4 Y EL PAPEL: UN TOTAL A MEDIAS SE MARCA
  // ---------------------------------------------------------------------------
  //
  // La hoja imprimible no hace su propia cuenta: `hojaDePreDespacho` le pasa los
  // pesos que salen de aqui, asi que compartia el fallo entero —se imprimia y se
  // bajaba al almacen con el. Esto lo ata al ORIGEN, que es lo que
  // `los_dos_pesos_del_pre_despacho_test.dart` no mira: aquel compara el papel
  // con la pantalla, y los dos pueden estar de acuerdo en un numero equivocado.

  test(
    'la hoja imprimible tambien cambia de peso al cambiar de sucursal',
    () async {
      String enElPapel(TotalesPreDespacho totales) => pesoDeLosProductosEnPapel(
        papel.TotalesPreDespacho.de(
          hojaDePreDespacho(totales: totales, sucursal: 'STG', dia: null),
        ),
      );

      final unaSucursal = await preDespachoDe('B1');
      final todas = await preDespachoDe(null);

      expect(enElPapel(unaSucursal), '140.0 kg');
      expect(enElPapel(todas), '200.0 kg', reason: clavado);
      // Y letra por letra lo que dice la pantalla del mismo filtro, que es la
      // regla del §3-bis y la que ya estaba escrita.
      expect(enElPapel(todas), pesoDelPreDespacho(todas));
    },
  );

  test(
    'un total a medias sale con `≥` y diciendo cuantos renglones faltan',
    () async {
      // El renglon que el servidor no supo pesar no borra la hoja ni se cuela
      // dentro del total: el peso que SI se sabe se da, marcado con `≥` y con la
      // cuenta de lo que falta al lado. Sin las dos cifras juntas, 200 kg se
      // firma como el peso entero de la hoja.
      await sembrarRenglon(
        base,
        id: 'r5',
        pedidoId: 'o-hab-1',
        producto: 'VODKA REGIO BLISTER 6U',
        unidades: 12,
        empaques: 2,
        linea: 3,
      );

      final todas = await preDespachoDe(null);
      expect(todas.pesoKg, 200, reason: 'lo que se sabe se da');
      expect(todas.sinPeso, 1, reason: 'y lo que falta se cuenta, por RENGLONES');
      expect(
        todas.pesoCompleto,
        isFalse,
        reason:
            'con un renglon sin pesar, la hoja NO esta completa: en `true` los '
            '200 kg se firman como el peso entero y el `≥` desaparece del '
            'papel y de la pantalla',
      );

      final enElPapel = pesoDeLosProductosEnPapel(
        papel.TotalesPreDespacho.de(
          hojaDePreDespacho(totales: todas, sucursal: 'STG', dia: null),
        ),
      );
      expect(
        enElPapel,
        startsWith('≥ '),
        reason:
            'sin el `≥` el papel firma 200.0 kg como el total de la hoja y '
            'alguien carga el camion contando con eso',
      );
      expect(enElPapel, pesoDelPreDespacho(todas));
    },
  );

  test(
    'empaques, unidades y kilos salen del MISMO conjunto de renglones',
    () async {
      // El renglon de B2 entra o no entra, pero entra en las TRES cuentas a la
      // vez. Lo que se compara es la diferencia entre los dos alcances: 30
      // empaques, 180 unidades y 60 kg, que son los de `o-hab-1` y de nadie
      // mas.
      final unaSucursal = await preDespachoDe('B1');
      final todas = await preDespachoDe(null);

      expect(todas.empaques - unaSucursal.empaques, 30);
      expect(todas.unidades! - unaSucursal.unidades!, 180);
      expect(
        todas.pesoKg! - unaSucursal.pesoKg!,
        60,
        reason:
            'lo que entra de mas al ensanchar el alcance tiene que entrar en '
            'las tres columnas; si una se queda quieta, hay dos caminos donde '
            'deberia haber uno',
      );
    },
  );
}

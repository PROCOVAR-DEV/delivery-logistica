// LAS TRES HOJAS DEL REPORTE, con los importes EN LA MONEDA QUE SE ESTA
// MIRANDO.
//
// El patron es `src/app/(dashboard)/reports/page.tsx` de delivery (Next),
// `exportExcel`, lineas 94-134: tres hojas —`Resumen`, `Por Vehículo` y
// `Detalle de Órdenes`—, el fichero `reporte-procovar-AAAA-MM-DD.xlsx` y su
// `conv()`, que pasa cada importe de USD a la moneda que la pantalla tiene
// puesta antes de escribirlo. El pliego lo exige igual en
// `docs/pantallas.md:602` y `:632-634`.
//
// ## Por que la conversion es la mitad de este fichero
//
// Los importes se GUARDAN en USD siempre y el CUP se calcula al pintarlo, con
// la tasa de ESA sucursal. Un Excel que escupiera los dolares crudos bajo una
// cabecera que dice `(CUP)` seria, con la tasa a 700, un numero 700 veces mas
// pequeño que el de verdad — y perfectamente legible. Es literalmente el fallo
// que el `CLAUDE.md` de este repo pone como «lo peor que puede pasarle a un
// numero que alguien va a cobrar».
//
// Por eso [ConversionDelInforme] lleva la moneda Y la tasa juntas, y pedir CUP
// sin tasa **lanza** en vez de escribir dolares. Sin fichero se ve; con un
// fichero mentiroso, no.
//
// ## Donde nos separamos del patron, y por que (CLAUDE.md §2)
//
//  1. **El Next redondea todo a 2 decimales, tambien en CUP.** Aqui no: en CUP
//     la pantalla enseña el importe SIN decimales (`TasaDeLaMirada.importe`,
//     «los precios reales van en cientos o en miles y el centimo solo ensucia
//     la lectura»). Si el Excel llevara dos, la hoja y la pantalla darian dos
//     numeros distintos para la misma suma, que es exactamente lo que esta
//     pantalla existe para evitar. El Excel redondea **como la pantalla**.
//  2. **Un importe que no se sabe deja la celda VACIA.** El Next escribe el
//     numero que tenga, y lo que tiene cuando no hay cotizacion es un `0`. En la
//     web de produccion, el 22/09/2026: `Pedidos` decia «sin cotizar» en todas
//     sus filas y esta misma hoja decia `0,00 USD` en las mismas. Un hueco se ve
//     al sumar; un cero se suma y baja el total sin decirlo. Lo hace
//     [ConversionDelInforme.convertir], y los totales de las dos tablas van por
//     [ConsultasInformes.sumaCompleta].
//  3. **El Next no pone fila de totales en las hojas.** Aqui si, en las dos
//     tablas, con los mismos totales que el pie de la pantalla. Sin ella, quien
//     cuadra caja tiene que volver a sumar 300 filas a mano; y una suma a mano
//     sobre una hoja que ya trae el total es de donde salen las diferencias.
//  4. **La factura (issue 9 de Amado).** `Detalle de Órdenes` lleva la columna
//     `Factura`, justo despues de la fecha, y `Por Vehículo` la lista de las de
//     cada camion (`Facturas`, la ultima). El numero lo resuelve
//     [NumeroDeFactura], el mismo que la pantalla y que `GET /api/reports`. La
//     lista de un camion va ENTERA aqui —la pantalla solo ensena las dos
//     primeras— con un techo: una celda de mas de 32.767 letras hace que Excel
//     no abra el fichero, y entonces se corta DICIENDO cuantas quedan fuera.

import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../../../nucleo/numero_de_factura.dart';
import 'consultas_informes.dart';
import 'hoja_de_calculo.dart';

/// La moneda en la que se escribe el fichero, con lo que hace falta para
/// llegar a ella.
///
/// Sale de `monedaEfectivaProvider` + `tasaDeLaMiradaProvider`, los dos de
/// `navegacion/estado_navegacion.dart`, que son **los mismos** que usa la
/// pantalla para pintar. Se pasa entera y no como dos parametros sueltos para
/// que no se pueda llamar con la moneda de una y la tasa de otra.
class ConversionDelInforme {
  const ConversionDelInforme({required this.moneda, this.cupPorUsd});

  /// Todo en dolares, que es como estan guardados los importes.
  static const usd = ConversionDelInforme(moneda: 'USD');

  /// `USD` o `CUP`.
  final String moneda;

  /// Cuantos CUP es un USD. `null` cuando no hay tasa de esta sucursal.
  final double? cupPorUsd;

  /// El importe de [usd] tal y como va a la celda: un NUMERO, no un texto.
  ///
  /// Un importe guardado como texto no se suma, y la columna da cero en la hoja
  /// de quien la abra sin decir por que.
  ///
  /// **`null` entra y `null` sale: la celda se queda VACIA, no en cero.** Es la
  /// linea que mas importa de este fichero, porque es el que alguien abre para
  /// cobrar. Una celda vacia se ve al sumar —y al ordenar, y al hacer un
  /// promedio—; un cero se suma sin que nadie se entere, y baja el total tanto
  /// como valga lo que faltaba. Ya se hacia asi con `Km desde partida`
  /// (`_detalle`), y el importe es justo el que no lo hacia.
  ///
  /// Lanza si se pide CUP sin tasa. No se cae a dolares: la tasa es por
  /// sucursal y sin la suya no se convierte nada. Quien llama lo enseña en
  /// pantalla (regla 4: nada falla en silencio). Un importe que no se sabe **no
  /// llega a pedir tasa**: no hay nada que convertir, asi que un informe sin
  /// cotizar no se convierte en un error de tasa que despiste.
  num? convertir(double? importeEnUsd) {
    if (importeEnUsd == null) return null;
    if (moneda == 'CUP') {
      final tasa = cupPorUsd;
      if (tasa == null || tasa <= 0) {
        throw StateError(
          'Se pidió el Excel en CUP y esta sucursal no tiene tasa de cambio: '
          'no se convierte ningún importe con la tasa de otra.',
        );
      }
      // SIN DECIMALES, igual que la pantalla.
      return (importeEnUsd * tasa).round();
    }
    // Dos decimales, igual que `Numeros.importe`.
    return (importeEnUsd * 100).round() / 100;
  }
}

/// El libro de Reportes: sus tres hojas, su nombre y su conversion.
abstract final class ExcelDelInforme {
  /// LOS NOMBRES DE LAS TRES HOJAS, los del pliego (`docs/pantallas.md:632`) y
  /// los mismos que las tres pestañas de la pantalla.
  static const hojaResumen = 'Resumen';
  static const hojaPorVehiculo = 'Por Vehículo';
  static const hojaDetalle = 'Detalle de Órdenes';

  /// En este orden, que es el de las pestañas.
  static const nombresDeLasHojas = [hojaResumen, hojaPorVehiculo, hojaDetalle];

  /// El titulo de la primera celda, literal del pliego.
  static const titulo = 'Reporte de transportación — ProCovar';

  /// `reporte-procovar-AAAA-MM-DD.xlsx`, como el patron.
  static String nombreDeFichero(DateTime cuando) {
    final aaaa = cuando.year.toString().padLeft(4, '0');
    final mm = cuando.month.toString().padLeft(2, '0');
    final dd = cuando.day.toString().padLeft(2, '0');
    return 'reporte-procovar-$aaaa-$mm-$dd.xlsx';
  }

  /// Las tres hojas, en orden. Separado de [armar] para que las pruebas puedan
  /// mirar las celdas sin abrir un zip.
  static List<Hoja> hojas({
    required Informe informe,
    required FiltroDeInforme filtro,
    required ConversionDelInforme conversion,
    required DateTime generado,
  }) => [
    _resumen(informe, filtro, conversion, generado),
    _porVehiculo(informe, conversion),
    _detalle(informe, conversion),
  ];

  /// El fichero entero.
  static Uint8List armar({
    required Informe informe,
    required FiltroDeInforme filtro,
    required ConversionDelInforme conversion,
    required DateTime generado,
  }) => armarXlsx(
    hojas(
      informe: informe,
      filtro: filtro,
      conversion: conversion,
      generado: generado,
    ),
  );

  // --- Las tres hojas -------------------------------------------------------

  static Hoja _resumen(
    Informe informe,
    FiltroDeInforme filtro,
    ConversionDelInforme c,
    DateTime generado,
  ) {
    final r = informe.resumen;
    final m = '(${c.moneda})';
    return Hoja(
      nombre: hojaResumen,
      filas: [
        [titulo],
        ['Generado', _fechaYHora(generado)],
        ['Filtro fecha', '${_dia(filtro.desde)} - ${_dia(filtro.hasta)}'],
        ['Moneda', c.moneda],
        [],
        ['Total Órdenes', r.totalOrdenes],
        ['Ingresos Totales $m', c.convertir(r.ingresos)],
        ['Precio Promedio $m', c.convertir(r.precioPromedio)],
        ['Peso Total (kg)', _kg(r.peso)],
        // CUANTAS FALTAN, Y SOLO SI FALTA ALGUNA.
        //
        // Las dos celdas de arriba salen VACIAS cuando falta el importe de
        // alguna orden, y una celda vacia sin explicacion se lee como un fallo
        // del fichero. Esta fila dice que no lo es y **cuantas** hay que
        // cotizar. Un `0 sin cotizar` no se escribe: un cero ahi se lee como
        // «ya se reviso», que es lo contrario de lo que esta fila significa.
        if (r.sinCotizar > 0)
          [
            'Órdenes sin cotizar',
            r.sinCotizar,
            'Ingresos Totales y Precio Promedio van vacíos a propósito: no se '
                'suma lo que falta.',
          ],
      ],
    );
  }

  static Hoja _porVehiculo(Informe informe, ConversionDelInforme c) {
    final m = '(${c.moneda})';
    var ordenes = 0;
    var peso = 0.0;
    var sinCotizar = 0;
    for (final v in informe.porVehiculo) {
      ordenes += v.ordenes;
      peso += v.peso;
      sinCotizar += v.sinCotizar;
    }
    final ingresos = ConsultasInformes.sumaCompleta(
      informe.porVehiculo.map((v) => v.ingresos),
    );
    return Hoja(
      nombre: hojaPorVehiculo,
      filas: [
        [
          'Vehículo',
          'Placa',
          'Órdenes',
          'Ingresos $m',
          'Peso (kg)',
          'Promedio/Orden $m',
          'Facturas',
        ],
        for (final v in informe.porVehiculo)
          [
            v.nombre,
            v.placa ?? '—',
            v.ordenes,
            c.convertir(v.ingresos),
            _kg(v.peso),
            c.convertir(v.promedioPorOrden),
            NumeroDeFactura.texto((
              facturas: v.facturas,
              sinFactura: v.sinFactura,
            ), maxCaracteres: _techoDeUnaCelda),
          ],
        // El pie de la pantalla, con las mismas palabras. Y si falta algun
        // importe, la celda del total va VACIA y el rotulo dice cuantos faltan:
        // un pie que parece completo es lo que alguien copia a su hoja.
        [
          sinCotizar == 0 ? 'Totales' : 'Totales ($sinCotizar sin cotizar)',
          '',
          ordenes,
          c.convertir(ingresos),
          _kg(peso),
          '',
          '',
        ],
      ],
    );
  }

  static Hoja _detalle(Informe informe, ConversionDelInforme c) {
    final m = '(${c.moneda})';
    var peso = 0.0;
    var sinCotizar = 0;
    for (final f in informe.filas) {
      peso += f.pesoKg;
      if (f.importe == null) sinCotizar++;
    }
    final total = ConsultasInformes.sumaCompleta(
      informe.filas.map((f) => f.importe),
    );
    return Hoja(
      nombre: hojaDetalle,
      filas: [
        [
          'Fecha',
          'Factura',
          'Cliente',
          'Ruta',
          'Destino',
          'Vehículo',
          'Km desde partida',
          'Peso (kg)',
          'Precio $m',
        ],
        for (final f in informe.filas)
          [
            _dia(f.fecha),
            // Sin numero, la raya como en `Ruta` y `Vehículo`: es texto, no un
            // importe, y un hueco aqui se leeria como una celda que se olvido.
            f.factura ?? '—',
            f.cliente,
            f.ruta ?? '—',
            f.destino,
            f.vehiculo ?? '—',
            // Sin `segment_km` se deja el HUECO, no un cero: un cero se lee
            // como «salió de la partida», que es otra cosa (CLAUDE.md §2).
            f.kmDesdePartida == null ? null : _km(f.kmDesdePartida!),
            _kg(f.pesoKg),
            // Y el importe igual: sin cotizar, HUECO. Es la columna que alguien
            // suma fuera, y un cero ahi dice «ese domicilio fue gratis».
            c.convertir(f.importe),
          ],
        [
          sinCotizar == 0 ? 'Totales:' : 'Totales: ($sinCotizar sin cotizar)',
          '',
          '',
          '',
          '',
          '',
          '',
          _kg(peso),
          c.convertir(total),
        ],
      ],
    );
  }

  /// Lo que cabe en una celda de Excel son 32.767 letras; se deja el resto para
  /// el «y N más» y los «sin número». Ver [NumeroDeFactura.texto].
  static const _techoDeUnaCelda = 30000;

  // --- Los formatos, los mismos que la pantalla -----------------------------

  /// `d/M/y`, como `_Detalle` y como los botones de fecha.
  static String _dia(DateTime? cuando) =>
      cuando == null ? '—' : DateFormat('d/M/y', 'es').format(cuando);

  /// `d/M/y, H:mm`, como el sello de «Cuadrado con los datos del aparato».
  static String _fechaYHora(DateTime cuando) =>
      DateFormat('d/M/y, H:mm', 'es').format(cuando);

  /// Un decimal, como `Numeros.kg`. Va como NUMERO y sin el ` kg` pegado: la
  /// unidad esta en la cabecera de la columna y un `12,3 kg` no se suma.
  static num _kg(double kg) => (kg * 10).round() / 10;

  /// Un decimal, como `Numeros.km`.
  static num _km(double km) => (km * 10).round() / 10;
}

// BAJAR UN FICHERO GRANDE: entero, comprobado y REANUDABLE.
//
// ## De donde sale este fichero
//
// De `mapa/descarga_de_mapa.dart`, donde vivia desde el 17/09/2026 y donde
// funciona. El 05/10/2026 hubo que bajar la actualizacion de la APK igual que se
// baja el mapa —Jose: «la APK me manda a descargarla al navegador en vez de
// actualizar ahi mismo en la aplicacion sin necesidad de salir»— y habia dos
// caminos: escribir otro descargador, o sacar este de donde estaba.
//
// **Se saco.** Dos descargadores que se separan es el fallo clasico de esta casa:
// el dia que uno aprenda algo —que un `206` puede empezar donde no toca, por
// ejemplo— el otro no lo sabra, y el que no lo sepa sera el que este corriendo en
// el telefono de alguien en Santiago. Lo que cambia entre el mapa y la APK son
// **las palabras** ([PalabrasDeLaDescarga]) y lo que se hace al terminar; lo que
// no cambia es todo lo de aqui.
//
// ## Las dos trampas que justifican cada linea
//
// ### 1. Una descarga que se corta y se da por buena
//
// Es el fallo de los 2.000 clientes otra vez (`CLAUDE.md` §3): se pidio un tope y
// nadie miro si se alcanzo. Aqui se mira **dos veces**, y las dos hacen falta:
//
//   - **los bytes**: al terminar tienen que ser exactamente los que anuncio el
//     servidor. Ni uno menos.
//   - **el `sha256`**: porque los bytes pueden cuadrar y el contenido no. Un
//     proxy que devuelve una pagina de error de 26 MB es absurdo, pero un
//     reanudado que empieza en el sitio equivocado no lo es nada, y deja un
//     fichero del tamaño justo lleno de basura en medio.
//
// El `sha256` no es adorno: **es lo unico que separa «bajado» de «bajado
// entero»**. Y con el APK es todavia mas caro callarselo que con el mapa: un
// `.apk` cortado **se baja bien y no instala**, y lo que ve la persona es «no se
// pudo instalar la aplicacion», que no explica nada y manda a mirar donde no es.
//
// ### 2. En la conexion de alla, 75 MB no entran de una vez
//
// Por eso lo bajado se guarda con otro nombre (`.parcial`) y se continua con
// `Range`. Y por eso hay una comprobacion que parece de mas y es la importante:
// **cuando se pide reanudar, se comprueba que de verdad se reanudo**. Un servidor
// que ignora `Range` contesta `200 OK` con el fichero entero, y añadirlo detras de
// lo que ya habia deja un fichero del doble de tamaño. Con los bytes y el
// `sha256` se cazaria al final, pero despues de haber gastado la descarga entera
// — que en Cuba es lo que hay que evitar.
//
// **Y los rangos FUNCIONAN**, medido contra produccion el 05/10/2026 sobre el APK
// colgado en MinIO:
//
//     Peticion completa:   HTTP 200 · SIN content-length · sin accept-ranges
//     Pidiendo un trozo:   HTTP 206 · content-range: bytes 0-1023/78485416
//
// O sea: lo que falla es que la respuesta completa no los **ofrece**, asi que el
// navegador no lo intenta nunca. Cuando la descarga la hace la aplicacion eso deja
// de importar, porque pide por trozos y punto. De la misma medida sale la otra
// mitad: **el tamaño no se saca de la respuesta**, que no lo trae; se saca de lo
// que anuncia la api ([LoQueSeBaja.bytes]).
//
// ## Lo que NO hace
//
// No baja nada solo. Lo mismo que el aviso de version (`docs/actualizaciones.md`
// §1.2): **se avisa, decide la persona**. Quien usa esto esta en el patio de un
// almacen con la señal justa; que la aplicacion decida por el que ahora toca
// bajarse 75 MB es peor que cualquier version vieja.

import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../registro/registro.dart';
import 'almacen_de_bajadas.dart';

/// Como va la descarga. Se reporta hacia arriba para que la pantalla lo diga con
/// un numero, no con una rueda.
typedef ComoVaLaBajada =
    void Function({required int bajados, required int total});

/// QUE SE BAJA: de donde, cuanto pesa y con que huella tiene que cuadrar.
///
/// Los tres datos vienen **del anuncio de la api**, nunca de las cabeceras de la
/// respuesta: `Content-Length` es justo lo que no llega (ver la cabecera de este
/// fichero), y una huella que diera el mismo que sirve el fichero no comprobaria
/// nada.
class LoQueSeBaja {
  const LoQueSeBaja({
    required this.url,
    required this.bytes,
    required this.sha256,
    required this.fichero,
  });

  final String url;

  /// Lo que pesa. **Se sabe antes de bajar nada**, y es lo que permite una barra
  /// de progreso de verdad en vez de una rueda que no distingue «va lenta» de
  /// «esta parada».
  final int bytes;

  /// Lo que separa «bajado» de «bajado entero».
  final String sha256;

  /// Como se llama dentro del almacen cuando ya vale.
  final String fichero;

  /// Y como se llama mientras no vale.
  ///
  /// **Se llama distinto a proposito.** Si lo que se esta bajando y lo que ya
  /// vale compartieran nombre, una descarga cortada dejaria lo bueno pisado a
  /// medias: en el mapa seria perder el mapa que ya se tenia por intentar
  /// actualizarlo, y en la APK seria quedarse sin el fichero que si instalaba.
  String get ficheroParcial => '$fichero.parcial';
}

/// LAS PALABRAS DE ESTA DESCARGA, una por cada forma de salir mal.
///
/// Esto es una clase y no un `String` con huecos porque **el motivo literal es
/// lo unico accionable** (`CLAUDE.md` §4): «se corto la conexion, toca para
/// seguir desde donde iba» le dice a alguien que hacer; «error al descargar» no
/// le dice nada. Y lo que hay que decir no es lo mismo para un mapa que para una
/// actualizacion, asi que cada quien escribe las suyas **en su fichero**, donde
/// se leen y se revisan, en vez de dejar que el motor invente prosa.
abstract class PalabrasDeLaDescarga {
  const PalabrasDeLaDescarga();

  /// No se pudo ni abrir la conexion. [motivo] es lo que dijo la red.
  String noSePudoConectar(String motivo);

  /// El servidor contesto algo que no es 200 ni 206.
  String elServidorContesto(int codigo);

  /// Contesto 206 pero el trozo empieza en otro sitio del que se pidio.
  String noContinuoDondeSePidio(String? rango, int desde);

  /// Se corto en medio de los bytes.
  String seCortoLaConexion();

  /// La persona pulso el boton de detener.
  String detenida();

  /// Termino sin llegar al tamaño anunciado.
  String llegoCortada(int bajados, int total);

  /// Llego entera y la huella no es la que el servidor dice tener.
  String laHuellaNoCuadra();
}

/// LO QUE SALE DE BAJAR. Sellado: quien llame tiene que tratar los dos casos.
sealed class FinDeLaBajada {
  const FinDeLaBajada();
}

/// El fichero esta en [LoQueSeBaja.fichero], con su tamaño y su huella
/// comprobados.
class BajadaCompleta extends FinDeLaBajada {
  const BajadaCompleta();
}

/// FALLO, **y se dice que falto y que se pierde sin ello** (`CLAUDE.md` §4).
class BajadaCortada extends FinDeLaBajada {
  const BajadaCortada(
    this.motivo, {
    required this.bajados,
    required this.total,
    required this.sePuedeReanudar,
  });

  /// El motivo literal, para la pantalla.
  final String motivo;
  final int bajados;
  final int total;

  /// `true` cuando lo bajado sigue sirviendo y la proxima vez continua donde se
  /// quedo. `false` cuando hubo que tirarlo, y entonces la pantalla lo dice en
  /// vez de dejar creer que se conserva.
  final bool sePuedeReanudar;
}

/// QUIEN BAJA.
class DescargaReanudable {
  const DescargaReanudable(this._cliente, this._almacen, this._palabras);

  final Dio _cliente;
  final AlmacenDeBajadas _almacen;
  final PalabrasDeLaDescarga _palabras;

  /// Baja [lo] entero, continuando lo que hubiera.
  ///
  /// [cancelar] deja el `.parcial` donde esta: cancelar no es tirar lo bajado.
  Future<FinDeLaBajada> bajar(
    LoQueSeBaja lo, {
    ComoVaLaBajada? comoVa,
    CancelToken? cancelar,
  }) async {
    final parcial = lo.ficheroParcial;
    var yaHay = await _almacen.bytes(parcial);

    // Lo que hay es MAS de lo que se anuncio: es de otra version, o de una
    // descarga que se fue de madre. No se puede reanudar encima.
    if (yaHay > lo.bytes) {
      Registro.aviso(
        'el parcial de ${lo.fichero} tiene $yaHay bytes y lo anunciado son '
        '${lo.bytes}: se empieza de cero',
      );
      await _almacen.borrar(parcial);
      yaHay = 0;
    }

    if (yaHay < lo.bytes) {
      final fallo = await _traer(lo, yaHay, comoVa, cancelar);
      if (fallo != null) return fallo;
    }

    // ── EL TOPE, COMPROBADO. Si se pide un tamaño, se mira si se alcanzo.
    final bajados = await _almacen.bytes(parcial);
    if (bajados != lo.bytes) {
      return BajadaCortada(
        _palabras.llegoCortada(bajados, lo.bytes),
        bajados: bajados,
        total: lo.bytes,
        sePuedeReanudar: true,
      );
    }

    // ── Y LA HUELLA, que es lo otro. Los bytes pueden cuadrar y el contenido no.
    final huella = await _huellaDe(parcial);
    if (huella != lo.sha256) {
      // Un fichero del tamaño justo y con otro contenido no se conserva: seguir
      // reanudando encima de el no arregla nada nunca.
      await _almacen.borrar(parcial);
      return BajadaCortada(
        _palabras.laHuellaNoCuadra(),
        bajados: lo.bytes,
        total: lo.bytes,
        sePuedeReanudar: false,
      );
    }

    // Solo AHORA se pisa el bueno. Hasta que la huella no cuadra, lo que ya habia
    // sigue intacto.
    await _almacen.renombrar(parcial, lo.fichero);
    return const BajadaCompleta();
  }

  /// La parte de red. Devuelve `null` si fue bien, o el fallo.
  Future<BajadaCortada?> _traer(
    LoQueSeBaja lo,
    int desde,
    ComoVaLaBajada? comoVa,
    CancelToken? cancelar,
  ) async {
    Response<ResponseBody> r;
    try {
      r = await _cliente.get<ResponseBody>(
        lo.url,
        cancelToken: cancelar,
        options: Options(
          responseType: ResponseType.stream,
          // `validateStatus` abierto para poder mirar el codigo nosotros: con el
          // de serie, un 416 llega como excepcion y se pierde el motivo.
          validateStatus: (_) => true,
          headers: {if (desde > 0) 'Range': 'bytes=$desde-'},
          // Sin plazo de recepcion: son decenas de MB por una conexion que va y
          // viene, y cortar a los 30 s es garantizar que no termine nunca.
          receiveTimeout: null,
        ),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        return BajadaCortada(
          _palabras.detenida(),
          bajados: await _almacen.bytes(lo.ficheroParcial),
          total: lo.bytes,
          sePuedeReanudar: true,
        );
      }
      return BajadaCortada(
        _palabras.noSePudoConectar(e.message ?? e.type.name),
        bajados: desde,
        total: lo.bytes,
        sePuedeReanudar: true,
      );
    }

    final codigo = r.statusCode ?? 0;
    if (codigo != 200 && codigo != 206) {
      return BajadaCortada(
        _palabras.elServidorContesto(codigo),
        bajados: desde,
        total: lo.bytes,
        sePuedeReanudar: true,
      );
    }

    // ══ SE PIDIO REANUDAR: ¿SE REANUDO DE VERDAD? ══════════════════════════
    //
    // Es la misma regla de siempre: **si pides un tope, comprueba si lo
    // alcanzaste** (`CLAUDE.md` §3). Aqui el tope es «empieza en el byte N», y
    // hay dos formas de que el servidor no lo cumpla, con arreglos distintos:
    var escritos = desde;
    if (desde > 0 && codigo != 206) {
      // 1. IGNORA `Range` y manda el fichero ENTERO con un 200. Pegarlo detras
      //    de lo que habia deja un fichero del doble de tamaño. Como lo que
      //    viene es el fichero completo, se tira lo que habia y se escribe este
      //    desde cero: se gasta la descarga entera, pero termina bien.
      Registro.aviso(
        'se pidio Range desde $desde y el servidor contesto $codigo: no sabe '
        'reanudar, se empieza de cero',
      );
      await _almacen.borrar(lo.ficheroParcial);
      escritos = 0;
    } else if (desde > 0 &&
        !_elRangoEmpiezaEn(r.headers.value('content-range'), desde)) {
      // 2. Contesta 206 pero **desde otro sitio**. Aqui lo que viene NO es el
      //    fichero entero: es un trozo que empieza donde le ha parecido, y
      //    pegarlo deja un agujero en medio. El fichero saldria del tamaño
      //    justo y roto, y lo cazaria el `sha256` — despues de haber gastado la
      //    descarga. Asi que no se escribe ni un byte: se tira el parcial y se
      //    dice, y el siguiente intento empieza limpio.
      final rango = r.headers.value('content-range');
      await _almacen.borrar(lo.ficheroParcial);
      return BajadaCortada(
        _palabras.noContinuoDondeSePidio(rango, desde),
        bajados: 0,
        total: lo.bytes,
        sePuedeReanudar: true,
      );
    }

    try {
      await for (final trozo in r.data!.stream) {
        // Se mira el boton de detener en cada trozo. No sobra: quien lo pulsa
        // esta mirando una barra que no avanza, y que siga bajando despues de
        // haberlo pulsado es lo que hace que nadie vuelva a fiarse del boton.
        if (cancelar?.isCancelled ?? false) {
          return BajadaCortada(
            _palabras.detenida(),
            bajados: await _almacen.bytes(lo.ficheroParcial),
            total: lo.bytes,
            sePuedeReanudar: true,
          );
        }
        await _almacen.anadir(lo.ficheroParcial, trozo);
        escritos += trozo.length;
        comoVa?.call(bajados: escritos, total: lo.bytes);
      }
    } on Object catch (e) {
      final bajados = await _almacen.bytes(lo.ficheroParcial);
      final cancelado = e is DioException && CancelToken.isCancel(e);
      return BajadaCortada(
        cancelado ? _palabras.detenida() : _palabras.seCortoLaConexion(),
        bajados: bajados,
        total: lo.bytes,
        sePuedeReanudar: true,
      );
    }
    return null;
  }

  /// El `sha256` **por trozos**: cargarse decenas de MB en la memoria de un
  /// telefono para calcular una huella es la forma de que la aplicacion muera
  /// justo al final de la descarga.
  Future<String> _huellaDe(String nombre) async {
    final recoge = _RecogeLaHuella();
    final entrada = sha256.startChunkedConversion(recoge);
    await for (final trozo in _almacen.porTrozos(nombre)) {
      entrada.add(trozo);
    }
    entrada.close();
    return recoge.huella?.toString() ?? '';
  }
}

/// `Content-Range: bytes 1000-2000/3000` tiene que empezar donde se pidio.
bool _elRangoEmpiezaEn(String? cabecera, int desde) {
  if (cabecera == null) return false;
  final trozos = cabecera.trim().split(RegExp(r'[\s-]+'));
  if (trozos.length < 2 || trozos[0] != 'bytes') return false;
  return int.tryParse(trozos[1]) == desde;
}

class _RecogeLaHuella implements Sink<Digest> {
  Digest? huella;

  @override
  void add(Digest d) => huella = d;

  @override
  void close() {}
}

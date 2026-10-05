// NINGUNA TAREA DE LA LISTA SE QUEDA SIN PODER LLEVARTE A ALGUN SITIO **SIN DECIR
// POR QUE**.
//
// Es la prueba que más importa de esta pantalla, y la razón está en el §4 de
// `CLAUDE.md`: nada se descarta en silencio. Una fila que al abrirse da texto y no
// explica por qué no te acompaña es la queja entera de Jose del 05/10/2026:
//
//     «me pusiste las tareas pero las tareas no me mueven a ningún lugar»
//     «todo me lo pusiste como documento, nada de q me llevara o me enseñara»
//
// Lo que se comprueba, sobre `docs/manual/` de verdad y para LAS TRES FORMAS:
//
//  1. toda tarea listada **o se puede recorrer, o la pantalla tiene un texto
//     escrito que dice por qué no** — nunca el silencio;
//  2. toda tarea que nombra una pantalla la nombra **como la nombra el menú** (eso
//     lo ata `el_manual_apunta_a_pantallas_que_existen_test.dart`), y aquí se
//     comprueba la consecuencia: que no haya ninguna con nombre de pantalla que
//     esta forma no registre **y además** sin motivo que dar;
//  3. y la cuenta de lo que queda sin señalar **está escrita aquí**, con número.
//     Es a propósito: bajar la cobertura no puede pasar sin tocar esta prueba, y
//     tocarla obliga a mirar el número. Subirla sí se puede sin más que aflojar
//     el tope, y eso es lo que se quiere.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/pantalla_registrada.dart';
import 'package:reparto/navegacion/pantallas.dart';
import 'package:reparto/pantallas/ayuda/datos/empaquetado.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';
import 'package:reparto/pantallas/ayuda/vista/pantalla_guia.dart';
import 'package:reparto/pantallas/ayuda/vista/recorrido_guiado.dart';

import '../../../herramientas/manual_del_repositorio.dart';

/// LO QUE SE EXIGE HOY, por forma: cuántos pasos de los que hay tienen que señalar
/// un control de verdad.
///
/// No es una nota: es un **suelo**. Está por debajo de lo que hay ahora mismo a
/// propósito, lo justo para que una tarea nueva sin marcar no ponga esto rojo, y lo
/// bastante alto para que **quitar marcas** sí lo ponga.
const _sueloDeSenalados = <FormaDeLaAplicacion, int>{
  // La APK es la del piloto de Santiago, y por eso es la que tiene el suelo alto.
  FormaDeLaAplicacion.apk: 78,
  FormaDeLaAplicacion.web: 78,
  // EL ESCRITORIO YA NO VA DETRAS — 94 % el 05/10/2026, contra el 48 % que tenía
  // cuando se escribió esto.
  //
  // Lo que le faltaba era una cosa y está hecha: su página del día
  // (`escritorio/2-el-dia-en-el-escritorio.md`) no tenía ni una tarea marcada, y
  // ahora tiene once. Lo que queda sin foco en esta forma son pasos de
  // `escritorio/3-tareas.md` y de `comun/` que no apuntan a un control porque no
  // lo tienen —una pantalla de Android, una consecuencia—, no marcas que falten.
  //
  // El suelo sube con ello, que es para lo que está: 85 deja sitio a una tarea
  // nueva sin marcar y no deja sitio a desmarcar la página del día.
  FormaDeLaAplicacion.escritorio: 85,
};

void main() {
  final paquete = empaquetarManual(leerElManualDelRepositorio());
  final registradas = pantallasDeLaAplicacion();
  final pantallas = <PantallaDelMenu>[
    for (final PantallaRegistrada p in registradas)
      PantallaDelMenu(p.ruta, p.titulo),
  ];

  test('el manual se lee y trae tareas de las tres formas', () {
    // «Una respuesta vacia no es una respuesta buena» (§3): sin esto, las pruebas
    // de abajo salen verdes sobre listas vacias.
    final todo = Manual.desdeElPaquete(paquete, pantallas: pantallas);
    expect(todo.tareas.length, greaterThan(50));
    for (final forma in FormaDeLaAplicacion.values) {
      expect(
        todo.paraLaForma(forma).tareas,
        isNotEmpty,
        reason: 'la guia de ${forma.comoSeLlama} no trae ni una tarea',
      );
    }
  });

  for (final forma in FormaDeLaAplicacion.values) {
    group('en ${forma.comoSeLlama}', () {
      final manual = Manual.desdeElPaquete(
        paquete,
        pantallas: pantallas,
      ).paraLaForma(forma);
      final tareas = manual.tareas;

      test('cada tarea o te acompana, o dice por que no', () {
        final mudas = <String>[];
        for (final tarea in tareas) {
          if (tarea.seAcompana) continue;

          // No se puede recorrer. Entonces la pantalla TIENE que tener un texto
          // para esta tarea. Son los dos unicos casos, y los dos estan escritos:
          final nombre = tarea.nombreDePantalla;
          final hayMotivo = tarea.pasos.isEmpty
              // «no se cuenta en pasos numerados»
              ? TextosDelRecorrido.noSePuedeGuiar(tarea.titulo).isNotEmpty
              // «esa pantalla no existe en esta forma»
              : (nombre != null &&
                    tarea.rutaDePantalla == null &&
                    TextosDeLaGuia.noHayEsaPantalla(nombre, forma).isNotEmpty);
          if (!hayMotivo) {
            mudas.add('${tarea.camino} «${tarea.titulo}»');
          }
        }
        expect(
          mudas,
          isEmpty,
          reason:
              'estas tareas salen en la lista, no se pueden recorrer y la pantalla '
              'no tiene ningun texto que lo explique. Una fila que al abrirse da '
              'texto sin decir por que es la queja de Jose otra vez.',
        );
      });

      /// LA PANTALLA QUE EN ESTA FORMA NO EXISTE NO SE PUEDE RECORRER.
      ///
      /// Es la mitad de `seAcompana` que el pie del cajon no ejercia: el pie ya
      /// cortaba antes por su cuenta, asi que romper `seAcompana` salia verde.
      /// Aqui se mira el dato, que es donde vive la regla.
      test('una tarea cuya pantalla no existe aqui NO se acompana', () {
        final deOtraForma = tareas.where(
          (t) => t.nombreDePantalla != null && t.rutaDePantalla == null,
        );
        for (final tarea in deOtraForma) {
          expect(
            tarea.seAcompana,
            isFalse,
            reason:
                '«${tarea.titulo}» se hace en «${tarea.nombreDePantalla}», que en '
                '${forma.comoSeLlama} no existe. Recorrerla pondria el foco encima '
                'de OTRA pantalla y senalaria cualquier cosa.',
          );
        }
        // Y que el caso exista de verdad en esta forma, o esto no comprueba nada.
        // En las tres hay alguna: el canal con PEDIDO no esta en la APK ni en el
        // escritorio, y lo de la franja de arriba no esta en la web.
        if (forma != FormaDeLaAplicacion.web) {
          expect(
            deOtraForma,
            isNotEmpty,
            reason:
                'en ${forma.comoSeLlama} no hay ninguna tarea con pantalla de otra '
                'forma, asi que esta prueba esta mirando una lista vacia',
          );
        }
      });

      test('la fila de la lista dice de antemano si te acompana', () {
        // Lo que se pinta debajo del nombre. Se mira desde aqui porque es lo que
        // evita el toque perdido: si la fila no lo dice, hay que abrirla para
        // descubrir que es un texto.
        for (final tarea in tareas) {
          final debajo = tarea.seAcompana
              ? '${tarea.pasos.length} pasos guiados'
              : TextosDeLaGuia.soloTexto;
          expect(debajo, isNotEmpty);
        }
        // Y que la lista NO sea toda de una clase: si todo se acompana o nada se
        // acompana, esta prueba no estaria comprobando el reparto.
        expect(
          tareas.where((t) => t.seAcompana),
          isNotEmpty,
          reason: 'ninguna tarea de ${forma.comoSeLlama} se puede recorrer',
        );
      });

      test('el recorrido llega al suelo de pasos senalados', () {
        final pasos = tareas.fold<int>(0, (a, t) => a + t.pasos.length);
        final senalados = tareas.fold<int>(0, (a, t) => a + t.pasosSenalados);
        final porCiento = pasos == 0 ? 0 : senalados * 100 ~/ pasos;
        expect(
          porCiento,
          greaterThanOrEqualTo(_sueloDeSenalados[forma]!),
          reason:
              'en ${forma.comoSeLlama} sólo $senalados de $pasos pasos senalan un '
              'control ($porCiento %), y el suelo es ${_sueloDeSenalados[forma]} %. '
              'Un paso sin control sale sin foco: la tarjeta lo dice, pero lo que '
              'Jose pidio es el foco. O le pones su `<!-- señala: … -->`, o el paso '
              'no es un paso y va como nota del anterior.',
        );
      });

      /// Y LAS DEL CAMINO PRINCIPAL VAN AL 100 %, una por una y con nombre.
      ///
      /// El suelo de arriba es una media, y una media se cumple dejando sin marcar
      /// justo las que mas se usan. Estas son las del dia de Jose —«el tablero es
      /// el camino principal», `CLAUDE.md`— y de estas no se admite ni un paso sin
      /// foco.
      test('las tareas del camino principal no tienen ni un paso sin foco', () {
        const delCamino = <String>{
          '3.1 Crear una zona',
          '3.2 Ponerle el camión a la zona — HAZLO AHORA',
          '3.3 Repartir los pedidos por zonas',
          '3.4 Mover, subir, bajar o sacar un pedido de una zona',
          '4. Armar la ruta',
          // LAS MISMAS, CON LOS NOMBRES QUE LLEVAN EN LA WEB Y EN EL ESCRITORIO.
          //
          // El día es el mismo y el trabajo es el mismo, pero cada página lo
          // numera por su cuenta —la web empieza por «Entrar» y la APK por
          // «Traer el día», asi que todo lo demás va corrido— y el gesto de
          // repartir **no es el mismo**: aquí se arrastra y en el teléfono se
          // toca, y por eso el título tampoco. Sin estas líneas, marcar la
          // página del día de la web o del escritorio y dejarse pasos sin foco
          // sólo bajaría la media, que es justo lo que este test está aquí para
          // no permitir en el camino principal.
          '4.1 Crear una zona',
          '4.2 Ponerle el camión a la zona — HAZLO AHORA',
          '4.3 Repartir los pedidos — arrastrando',
          '3.3 Repartir los pedidos — arrastrando',
          '4.4 Reordenar las zonas',
          '3.4 Reordenar las zonas',
          '5. Armar la ruta',
          'Renombrar, vaciar o borrar una zona',
          'Dar de alta un camión',
          'Poner o corregir un almacén',
          'Paso 2 — Al menos un vehículo',
          'Paso 3 — Al menos un almacén con su punto puesto',
        };
        final flojas = <String>[];
        for (final tarea in tareas) {
          if (!delCamino.contains(tarea.titulo)) continue;
          final sin = tarea.pasos.where((p) => !p.seSenala).toList();
          if (sin.isEmpty) continue;
          flojas.add(
            '${tarea.camino} «${tarea.titulo}»: '
            '${sin.map((p) => 'paso ${p.cual}').join(', ')}',
          );
        }
        expect(
          flojas,
          isEmpty,
          reason:
              'estas son las tareas con las que se arma el dia, y les falta el foco '
              'en algun paso. Aqui no vale «sale el texto»: es justo donde Jose dijo '
              '«quiere q le enseñes donde ir donde tocar para cada cosa».',
        );
      });
    });
  }
}

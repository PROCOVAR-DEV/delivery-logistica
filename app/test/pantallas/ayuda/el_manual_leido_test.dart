// EL MANUAL, LEIDO: tareas, formas, busqueda y el boton de «llévame ahí».
//
// Se prueba contra el paquete DE VERDAD (`assets/manual/manual.txt`, 39 paginas y
// 301 tareas el 05/10/2026) y no contra un manual de mentira, porque la mitad de
// lo que puede salir mal aqui sale de como esta escrito el manual: que un ancla
// no cuadre con el enlace que ya apunta a ella, que una pagina no tenga `# `, que
// una tarea nombre una pantalla que se renombro. Un manual de dos paginas
// inventadas no ensena nada de eso.
//
// Lo de mentira se usa para los casos que el manual de hoy no tiene —una pantalla
// que en esta forma no existe— y para las guardas que hay que poder romper.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/pantallas.dart';
import 'package:reparto/pantallas/ayuda/datos/empaquetado.dart';
import 'package:reparto/pantallas/ayuda/datos/manual.dart';
import 'package:reparto/pantallas/ayuda/datos/markdown.dart';
import 'package:reparto/pantallas/ayuda/datos/proveedores.dart';

void main() {
  final paquete = File(assetDelManual).readAsStringSync();
  final pantallas = pantallasParaLaGuia();
  final completo = Manual.desdeElPaquete(paquete, pantallas: pantallas);

  group('el paquete se lee', () {
    test('trae paginas, y cada una con titulo', () {
      expect(completo.paginas, isNotEmpty);
      for (final p in completo.paginas) {
        expect(
          p.titulo.trim(),
          isNotEmpty,
          reason:
              'la pagina «${p.camino}» se quedaria con el titulo en blanco en la '
              'lista, y una fila sin nombre no se puede ni pulsar a ciegas',
        );
      }
    });

    test('trae tareas, y cada una con nombre y con cuerpo', () {
      expect(completo.tareas.length, greaterThan(100));
      for (final t in completo.tareas) {
        expect(t.titulo.trim(), isNotEmpty, reason: t.id);
        expect(
          t.cuerpo.trim(),
          isNotEmpty,
          reason:
              'la tarea «${t.id}» no tiene pasos: se abriria un cajon en blanco, '
              'que es la pantalla verde del §4',
        );
      }
    });

    test('ninguna tarea repite su id', () {
      final ids = completo.tareas.map((t) => t.id).toList();
      final repetidos = <String>[];
      final vistos = <String>{};
      for (final id in ids) {
        if (!vistos.add(id)) repetidos.add(id);
      }
      expect(
        repetidos,
        isEmpty,
        reason:
            'dos tareas con el mismo id son dos filas que abren la misma, y la '
            'direccion `?tarea=` solo puede llevar a una',
      );
    });
  });

  /// LAS TAREAS SON TROZOS DE LA PAGINA, NO UNA SEGUNDA COPIA — §3-bis.
  ///
  /// Es la guarda que importa de todo este fichero. Jose pidio las dos cosas —«el
  /// documento oficial y las tareas y sus pasos»— y la trampa es montar las tareas
  /// como un segundo texto: dos sitios diciendo lo mismo que se separan sin que
  /// nada falle, que es literalmente el «Sin colocar (722)» encima de una lista de
  /// 293 del 17/09/2026.
  ///
  /// Aqui no hay segundo texto, y esto es lo que lo demuestra: **el cuerpo de cada
  /// tarea esta dentro del contenido de su pagina**, caracter por caracter. Si
  /// alguien escribe las tareas aparte, o les cambia una palabra «para que se lean
  /// mejor en el telefono», esto se pone rojo.
  group('las tareas salen de la pagina', () {
    test('el cuerpo de cada tarea esta DENTRO del texto de su pagina', () {
      for (final pagina in completo.paginas) {
        for (final tarea in pagina.tareas) {
          expect(
            pagina.contenido.contains(tarea.cuerpo),
            isTrue,
            reason:
                'el cuerpo de «${tarea.id}» no esta literalmente dentro de '
                '«${pagina.camino}». O se ha escrito un segundo texto para las '
                'tareas —y entonces los dos se van a separar— o el troceador le '
                'esta cambiando algo al pasar',
          );
        }
      }
    });

    test('y su titulo es un «## » de esa pagina', () {
      for (final pagina in completo.paginas) {
        final suyos = <String>[
          for (final renglon in pagina.contenido.split('\n'))
            if (renglon.startsWith('## ')) soloElTexto(renglon.substring(3).trim()),
        ];
        expect(
          pagina.tareas.map((t) => t.titulo).toList(),
          suyos,
          reason:
              'las tareas de «${pagina.camino}» no son sus `##`, ni en el mismo '
              'orden',
        );
      }
    });
  });

  /// EL ANCLA TIENE QUE SER LA QUE YA ESTA ESCRITA EN EL MANUAL.
  ///
  /// En `docs/manual/` hay enlaces puestos a mano con la forma de GitHub
  /// —`../web/2-tareas.md#buscar-un-pedido`—. Si el ancla se calculara de otra
  /// manera, esos enlaces no abririan nada dentro de la aplicacion: se tocarian
  /// tres veces y se dejarian de tocar.
  group('las anclas', () {
    test('se calculan como las escribe GitHub', () {
      expect(anclaDe('Buscar un pedido'), 'buscar-un-pedido');
      expect(anclaDe('Cambiar entre USD y CUP'), 'cambiar-entre-usd-y-cup');
      // Las tildes se QUEDAN, que es lo que hace GitHub y lo que esta escrito en
      // `docs/manual/comun/pantallas/almacenes.md`.
      expect(anclaDe('Poner o corregir un almacén'), 'poner-o-corregir-un-almacén');
      // La puntuacion se va, los espacios se juntan.
      expect(anclaDe('¿Y si no aparece? (mira esto)'), 'y-si-no-aparece-mira-esto');
      expect(anclaDe('Un **pedido** no me `aparece`'), 'un-pedido-no-me-aparece');
      // DOS GUIONES, y hace falta: `apk/3-tareas.md` ya enlaza a
      // `#paso-4--la-tasa-de-cambio-de-la-sucursal`. El `·` se va y deja dos
      // espacios, o sea dos guiones. Juntandolos, ese enlace no abre nada.
      expect(
        anclaDe('Paso 4 · La tasa de cambio de la sucursal'),
        'paso-4--la-tasa-de-cambio-de-la-sucursal',
      );
    });

    test('los titulos repetidos de una pagina se numeran como en GitHub', () {
      // `comun/puesta-en-marcha.md` repite «## Qué es» a proposito, uno por paso.
      // Son tareas distintas con el mismo nombre: sin numerar comparten id y dos
      // filas de la lista abririan la misma.
      final leido = Manual.desdeElPaquete(
        empaquetarManual({
          'comun/p.md': '# P\n\n## Qué es\n\nA.\n\n## Qué es\n\nB.\n\n'
              '## Qué es\n\nC.\n',
        }),
        pantallas: pantallas,
      );
      expect(
        leido.paginas.single.tareas.map((t) => t.ancla),
        ['qué-es', 'qué-es-1', 'qué-es-2'],
      );
    });

    test('los enlaces con ancla del manual apuntan a una tarea que existe', () {
      // Los `#ancla` que el manual escribe a mano, resueltos contra las tareas
      // que de verdad hay. Esta es la pareja de la de arriba: la de arriba dice
      // como se calcula, esta dice que lo calculado coincide con lo escrito.
      var comprobados = 0;
      final conAncla = RegExp(r'\]\(([^)\s]*\.md)#([^)\s]+)\)');
      for (final pagina in completo.paginas) {
        for (final enlace in conAncla.allMatches(pagina.contenido)) {
          final destino = _resolver(enlace.group(1)!, pagina.camino);
          final otra = completo.pagina(destino);
          if (otra == null) continue; // pagina que no existe: no es cosa del ancla
          final ancla = enlace.group(2)!;
          // TODOS los encabezados de la pagina, numerados como GitHub. Un ancla
          // puede apuntar a un `###`, que no es una tarea: se admite, porque la
          // aplicacion abre la pagina entera y ahi esta ese trozo.
          final anclas = <String>[];
          final vistas = <String, int>{};
          var enCodigo = false;
          for (final renglon in otra.contenido.split('\n')) {
            if (RegExp(r'^\s{0,3}`{3,}').hasMatch(renglon)) {
              enCodigo = !enCodigo;
              continue;
            }
            if (enCodigo || !renglon.startsWith('#')) continue;
            final base = anclaDe(renglon.replaceAll(RegExp(r'^#+\s*'), ''));
            final n = vistas.update(base, (v) => v + 1, ifAbsent: () => 0);
            anclas.add(n == 0 ? base : '\$base-\$n');
          }
          comprobados++;
          expect(
            anclas,
            contains(ancla),
            reason:
                '«${pagina.camino}» enlaza a «$destino#$ancla» y ahi no hay '
                'ningun encabezado con ese ancla',
          );
        }
      }
      expect(
        comprobados,
        greaterThan(0),
        reason:
            'esta prueba no ha comprobado ni un enlace: o el manual se quedo sin '
            'enlaces con ancla, o la expresion que los busca ya no los encuentra '
            '— y entonces esto esta verde sin probar nada',
      );
    });
  });

  /// CADA FORMA ENSENA LO SUYO. Es la regla 1 de `CLAUDE.md`.
  group('cada forma ensena lo suyo', () {
    for (final forma in FormaDeLaAplicacion.values) {
      test('${forma.name}: no ensena las paginas de las otras dos', () {
        final suyo = completo.paraLaForma(forma);
        expect(suyo.paginas, isNotEmpty);
        for (final otra in FormaDeLaAplicacion.values) {
          if (otra == forma) continue;
          expect(
            suyo.paginas.where((p) => p.camino.startsWith('${otra.carpeta}/')),
            isEmpty,
            reason:
                '${forma.name} esta ensenando paginas de ${otra.name}. «La APK no '
                'puede ensenar la guia del escritorio ni al reves»',
          );
        }
      });

      test('${forma.name}: SI ensena las suyas y las de todos', () {
        final suyo = completo.paraLaForma(forma);
        expect(
          suyo.paginas.where((p) => p.camino.startsWith('${forma.carpeta}/')),
          isNotEmpty,
          reason:
              'sin esto, «no ensenes lo de los otros» se cumpliria no ensenando '
              'nada, y la guia de ${forma.name} se quedaria vacia',
        );
        expect(
          suyo.paginas.where((p) => p.camino.startsWith('comun/')),
          isNotEmpty,
          reason: 'lo de `comun/` es de las tres',
        );
      });

      test('${forma.name}: lo primero que se lee es lo suyo', () {
        final suyo = completo.paraLaForma(forma);
        expect(
          suyo.paginas.first.camino.startsWith('${forma.carpeta}/'),
          isTrue,
          reason:
              'la primera pagina de la lista es «${suyo.paginas.first.camino}», '
              'que no es de ${forma.name}. El logistico abre su aparato y lo '
              'primero que tiene que ver es su guia',
        );
      });
    }
  });

  group('buscar', () {
    final guia = completo.paraLaForma(FormaDeLaAplicacion.apk);

    test('sin texto no devuelve nada', () {
      expect(guia.buscar(''), isEmpty);
      expect(guia.buscar('   '), isEmpty);
    });

    /// LO QUE JOSE PIDIO CON ESTE EJEMPLO: «buscar “almacén” tiene que encontrar
    /// la tarea de poner el almacén **y** la ficha de la pantalla de Almacenes».
    test('encuentra de las DOS, y dice de cual viene cada una', () {
      final encontrados = guia.buscar('almacen');
      expect(encontrados, isNotEmpty);
      expect(
        encontrados.where((r) => r.deDondeSale == DeDondeSale.tarea),
        isNotEmpty,
        reason: 'ninguna tarea; el catalogo del dia a dia no contesta',
      );
      expect(
        encontrados.where((r) => r.deDondeSale == DeDondeSale.pagina),
        isNotEmpty,
        reason: 'ninguna pagina; el documento oficial no sale en la busqueda',
      );
    });

    test('sin tildes encuentra con tildes, y al reves', () {
      // En el teclado de un telefono nadie escribe «camión» con tilde.
      expect(guia.buscar('camion'), isNotEmpty);
      expect(
        guia.buscar('camion').length,
        guia.buscar('camión').length,
        reason: 'las dos formas tienen que encontrar lo mismo',
      );
      // Y la ñ: el manual escribe «señal» y tiene una pagina `4-sin-senal.md`.
      expect(guia.buscar('senal'), isNotEmpty);
      expect(guia.buscar('señal').length, guia.buscar('senal').length);
    });

    test('los asteriscos de la negrita no esconden una palabra', () {
      // En el manual «**Necesita señal.**» va en negrita. Buscar «necesita
      // senal» tiene que encontrarlo igual.
      expect(guia.buscar('necesita senal'), isNotEmpty);
    });

    test('lo que coincide en el titulo va primero', () {
      final encontrados = guia.buscar('ruta');
      expect(encontrados.first.enElTitulo, isTrue);
      // Y una vez que empiezan los de cuerpo, no vuelve a salir uno de titulo.
      var yaVanLosDeCuerpo = false;
      for (final r in encontrados) {
        if (!r.enElTitulo) yaVanLosDeCuerpo = true;
        if (yaVanLosDeCuerpo) {
          expect(
            r.enElTitulo,
            isFalse,
            reason: 'el orden se ha mezclado: «${r.titulo}»',
          );
        }
      }
    });

    test('dos busquedas iguales dan el mismo orden', () {
      // `sort` de Dart no es estable; el orden se arma a mano por eso. Sin ello,
      // la misma busqueda puede salir distinta dos veces y nadie se fia de la
      // lista.
      expect(
        guia.buscar('pedido').map((r) => r.id).toList(),
        guia.buscar('pedido').map((r) => r.id).toList(),
      );
    });

    test('lo que no esta, no esta', () {
      expect(guia.buscar('xilofono'), isEmpty);
    });
  });

  /// «LLÉVAME AHÍ»: el boton que convierte un manual en una guia.
  group('la pantalla en la que empieza una tarea', () {
    test('sale de la etiqueta del menu que escribe el manual', () {
      final leido = Manual.desdeElPaquete(
        empaquetarManual({
          'apk/prueba.md':
              '# Prueba\n\n## Dar de alta un camión\n\n'
              '**Empieza en:** **Menú → «Vehículos»**. **Necesita señal.**\n\n'
              '1. Toca «Nuevo vehículo».\n',
        }),
        pantallas: pantallas,
      );
      final tarea = leido.tareas.single;
      expect(tarea.nombreDePantalla, 'Vehículos');
      expect(tarea.rutaDePantalla, '/vehicles');
      // Y el renglon SE QUEDA en el texto: lleva «**Necesita señal.**», que el
      // boton no puede decir.
      expect(tarea.cuerpo, contains('Necesita señal'));
      expect(tarea.cuerpo, contains('Empieza en'));
    });

    test('tambien con la forma de enlace, si alguien la escribe', () {
      final leido = Manual.desdeElPaquete(
        empaquetarManual({
          'apk/prueba.md':
              '# Prueba\n\n## Cambiar el camión\n\n'
              '**Empieza en:** [Rutas](/routes)\n\n1. Abre la ruta.\n',
        }),
        pantallas: pantallas,
      );
      expect(leido.tareas.single.rutaDePantalla, '/routes');
      expect(leido.tareas.single.nombreDePantalla, 'Rutas');
    });

    /// LA GUARDA QUE EVITA UN BOTON QUE NO LLEVA A NINGUN SITIO — Y QUE ADEMAS LO
    /// EXPLICA.
    ///
    /// Pasa de verdad: «Canal con PEDIDO» solo se registra en la web, asi que en
    /// la APK esa tarea no puede tener boton. Si se pusiera igual, llevaria a «No
    /// hay ninguna pantalla en /webhook», que no explica nada.
    ///
    /// Y la otra mitad, que es la que faltaba: **el nombre se queda**. Sin el, la
    /// tarea se quedaba sin pie y sin motivo, y quien la mirara no sabria por que
    /// esa no tiene boton y la de arriba si — un hueco en vez de una decision (§4).
    test('sin pantalla registrada en esta forma: sin boton, pero con motivo', () {
      final leido = Manual.desdeElPaquete(
        empaquetarManual({
          'comun/prueba.md':
              '# Prueba\n\n## Mirar el canal\n\n'
              '**Empieza en:** **Menú → «Canal con PEDIDO»**.\n',
        }),
        // La lista de la APK: sin el canal.
        pantallas: const [PantallaDelMenu('/orders', 'Pedidos')],
      );
      expect(leido.tareas.single.rutaDePantalla, isNull);
      expect(leido.tareas.single.nombreDePantalla, 'Canal con PEDIDO');
    });

    /// Y SU PAREJA: lo que NO lleva «Menú →» no se lee como una pantalla.
    ///
    /// Sin esta mitad, un `**Empieza en:** la pastilla de «STG»` diria «esa
    /// pantalla no existe en el teléfono» sobre algo que no es una pantalla. Un
    /// aviso falso es peor que no avisar: se deja de leer, y entonces tampoco se
    /// lee el dia que importa (§3-quinquies).
    test('unas comillas que no son una pantalla no inventan un aviso', () {
      final leido = Manual.desdeElPaquete(
        empaquetarManual({
          'comun/prueba.md':
              '# Prueba\n\n## Cambiar de sucursal\n\n'
              '**Empieza en:** la pastilla de «STG», arriba.\n',
        }),
        pantallas: pantallas,
      );
      expect(leido.tareas.single.nombreDePantalla, isNull);
      expect(leido.tareas.single.rutaDePantalla, isNull);
    });

    test('un sitio que no es una pantalla no pone boton y no se pierde', () {
      final leido = Manual.desdeElPaquete(
        empaquetarManual({
          'apk/prueba.md':
              '# Prueba\n\n## Traer el día\n\n'
              '**Empieza en:** la franja de arriba, desde cualquier pantalla.\n',
        }),
        pantallas: pantallas,
      );
      expect(leido.tareas.single.rutaDePantalla, isNull);
      expect(
        leido.tareas.single.cuerpo,
        contains('la franja de arriba'),
        reason:
            'ese renglon es la unica indicacion que tiene esa tarea; si se quita '
            'del texto por no haber podido poner boton, la tarea deja de decir '
            'donde empieza',
      );
    });

    /// EL BARRIDO SOBRE EL MANUAL DE VERDAD: todo lo que resuelve, resuelve a una
    /// pantalla registrada **y con el nombre que tiene el menu hoy**.
    test('en el manual de verdad, toda pantalla nombrada existe', () {
      final rutas = {for (final p in pantallas) p.ruta: p.titulo};
      var conBoton = 0;
      for (final tarea in completo.tareas) {
        final ruta = tarea.rutaDePantalla;
        if (ruta == null) continue;
        conBoton++;
        expect(
          rutas.containsKey(ruta),
          isTrue,
          reason: '«${tarea.id}» lleva a «$ruta», que no esta registrada',
        );
        expect(rutas[ruta], tarea.nombreDePantalla);
      }
      expect(
        conBoton,
        greaterThan(20),
        reason:
            'solo $conBoton tareas tienen pantalla, y el manual escribe «Empieza '
            'en: **Menú → «…»**» en bastantes mas. O el manual cambio de forma de '
            'escribirlo, o el lector dejo de entenderla — y entonces la guia se '
            'queda sin lo que la hace una guia',
      );
    });
  });

  group('lo que no se puede leer no se finge', () {
    test('un paquete en blanco da un manual sin paginas, no un error', () {
      final leido = Manual.desdeElPaquete('', pantallas: pantallas);
      expect(leido.paginas, isEmpty);
      expect(leido.tareas, isEmpty);
    });

    test('una pagina sin «# » coge el nombre del fichero', () {
      final leido = Manual.desdeElPaquete(
        empaquetarManual({'comun/a-medio-escribir.md': '## Algo\n\nPasos.\n'}),
        pantallas: pantallas,
      );
      expect(leido.paginas.single.titulo, 'a medio escribir');
    });

    test('un «## » dentro de un bloque de codigo no es una tarea', () {
      final leido = Manual.desdeElPaquete(
        empaquetarManual({
          'comun/a.md': '# A\n\n## De verdad\n\n```\n## de mentira\n```\n',
        }),
        pantallas: pantallas,
      );
      expect(leido.tareas.map((t) => t.titulo), ['De verdad']);
    });
  });

  group('el paquete, ida y vuelta', () {
    test('lo que se empaqueta se desempaqueta igual', () {
      final paginas = {
        'apk/a.md': '# A\n\n## Uno\n\nTexto.\n',
        'comun/b/c.md': '# C\n\nOtra cosa.\n',
      };
      expect(desempaquetarManual(empaquetarManual(paginas)), paginas);
    });

    test('se niega a empaquetar una pagina con la marca dentro', () {
      expect(
        () => empaquetarManual({'a.md': '# A\n\n${marcaDeFichero}trampa.md\n'}),
        throwsA(isA<ManualConMarcaDentro>()),
      );
    });

    test('el orden del paquete no depende del orden del mapa', () {
      expect(
        empaquetarManual({'b.md': '# B\n', 'a.md': '# A\n'}),
        empaquetarManual({'a.md': '# A\n', 'b.md': '# B\n'}),
      );
    });
  });

  /// La lista de pantallas de la guia sale del REGISTRO, no de una tabla aparte.
  test('las pantallas de la guia son las registradas', () {
    final registradas = pantallasDeLaAplicacion();
    expect(pantallasParaLaGuia().length, registradas.length);
    for (final p in registradas) {
      expect(
        pantallasParaLaGuia().where(
          (q) => q.ruta == p.ruta && q.titulo == p.titulo,
        ),
        hasLength(1),
        reason: p.ruta,
      );
    }
  });
}

/// El mismo resuelve-caminos que usa la aplicacion, repetido aqui a proposito:
/// esta prueba comprueba los enlaces ESCRITOS en el manual, y si usara la funcion
/// de produccion, un fallo en ella se taparia a si mismo.
String _resolver(String destino, String desdeLaPagina) {
  final trozos = desdeLaPagina.contains('/')
      ? desdeLaPagina.substring(0, desdeLaPagina.lastIndexOf('/')).split('/')
      : <String>[];
  for (final trozo in destino.split('/')) {
    if (trozo == '.' || trozo.isEmpty) continue;
    if (trozo == '..') {
      if (trozos.isNotEmpty) trozos.removeLast();
      continue;
    }
    trozos.add(trozo);
  }
  return trozos.join('/');
}

// LA PANTALLA DEL CANAL: SÓLO EN LA WEB, Y EN EL MENÚ SÓLO PARA DOS ROLES.
//
// Jose, 26/09/2026, y en este orden:
//
//  1. «eso me lo dejas en la web solamente, no lo pongas en más ningún lado»;
//  2. «que sólo lo pueda ver yo, eso no lo puede ver más nadie, sólo yo, el desarrollador»
//     — y se cerró a DESARROLLADOR, FUERA del menú;
//  3. «ponle para super admin también, de todas formas yo limpiaré eso después»;
//  4. y entrando por la dirección porque no la encontraba: **«tampoco agregaste el link en
//     el menú para poder verlo como super admin»**, «en el sidebar», «no lo veo».
//
// El paso 4 es el que corrige esta prueba: su versión anterior exigía `enElMenu == false` y
// lo llamaba «cerrojo». Estaba mal llamado desde el principio —esconder una entrada no
// cierra nada, la ruta sigue alcanzable escribiendo la dirección—, y encima dejaba a Jose
// sin poder llegar a su propia pantalla.
//
// LO QUE DE VERDAD CIERRA ES UNO SOLO: el servidor contesta 403 a cualquier rol que no sea
// DESARROLLADOR o SUPER ADMIN (`quien_ve_el_estado_del_webhook_test.go`, los siete roles uno
// a uno). Lo de aquí es para NO ESTORBAR, y por eso se prueba como lo que es.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/barra_lateral.dart';
import 'package:reparto/navegacion/pantalla_registrada.dart';
import 'package:reparto/navegacion/pantallas.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/pantallas/webhook/registro.dart';

Sesion _con({String rol = '', List<String> roles = const []}) => Sesion(
  token: 't',
  refresh: '',
  sub: 's',
  roles: roles,
  nombre: 'Quien sea',
  correo: '',
  rol: rol,
);

void main() {
  test('en la web se registra, y ahora SÍ va en el menú', () async {
    await Destino.comoSiFueraWeb(() async {
      final p = registrarWebhook();

      expect(p, isNotNull, reason: 'en la web tiene que existir: es donde Jose la mira');
      expect(
        p!.enElMenu,
        isTrue,
        reason:
            'sin entrada en el menú Jose no la encuentra, y eso ya pasó: entró '
            'escribiendo la dirección y dijo «no lo veo»',
      );
      expect(p.ruta, '/admin/webhook');
      expect(p.icono, isNotNull, reason: 'una entrada del menú sin icono sale coja');
    });
  });

  test('en la APK y en el escritorio NO existe', () {
    expect(
      registrarWebhook(),
      isNull,
      reason:
          'el repartidor está en la calle: una pantalla de tuberías entre dos '
          'sistemas no pinta nada ahí, y encima la APK trabaja sin señal, '
          'donde este dato no significa nada',
    );
  });

  test('en la APK no entra en la lista de pantallas', () {
    final rutas = pantallasDeLaAplicacion().map((p) => p.ruta).toList();

    expect(rutas, isNot(contains('/admin/webhook')));
    // Y LA OTRA MITAD: que la lista siga teniendo las de siempre. Sin esto, «no está» se
    // cumple con una lista vacía y la prueba pasaría con la aplicación entera rota.
    expect(rutas, contains('/tablero'));
    expect(rutas, contains('/facturas'));
  });

  test('en la web sí entra en la lista', () async {
    await Destino.comoSiFueraWeb(() async {
      final rutas = pantallasDeLaAplicacion().map((p) => p.ruta).toList();

      expect(rutas, contains('/admin/webhook'));
      expect(rutas, contains('/tablero'));
    });
  });

  // ------------------------------------------------------------------- quién la ve

  group('quién la ve en el menú', () {
    // LOS SIETE ROLES DE LA CASA, uno a uno, y no «un super admin sí y un operador no». Con
    // dos casos, cambiar la lista por `['ADMINISTRADOR']` sale verde.
    const entran = ['DESARROLLADOR', 'SUPER ADMIN'];
    const fuera = [
      'GERENTE',
      'ADMINISTRADOR',
      'SUPERVISOR',
      'GESTOR',
      'OPERADOR',
    ];

    late List<PantallaRegistrada> todas;

    setUp(() async {
      await Destino.comoSiFueraWeb(() async {
        todas = pantallasDeLaAplicacion();
      });
    });

    // SE COMPARA POR RUTA Y NO POR EL OBJETO. `PantallaRegistrada` no define `==`, así que
    // `contains(unaPantalla)` compara identidades y `registrarWebhook()` devuelve una
    // instancia NUEVA cada vez: la prueba salía roja diciendo que DESARROLLADOR no la ve,
    // cuando sí la veía. La ruta es lo que identifica una pantalla de verdad.
    List<String> rutasPara(Sesion? quien) =>
        BarraLateral.entradasPara(todas, quien).map((p) => p.ruta).toList();

    for (final rol in entran) {
      test('$rol la ve — y da igual en cuál de los dos campos venga', () {
        // EN EL SINGULAR. Es el caso de Jose: auth manda su rol por defecto en `role`.
        expect(
          rutasPara(_con(rol: rol)),
          contains(rutaDelWebhook),
          reason:
              'el rol venía en `role` y no en `roles`, y no la vio: es justo la '
              'forma de la cuenta de Jose, y es lo que le pasó',
        );
        // Y EN LA LISTA, que es por donde llegan las membresías.
        expect(rutasPara(_con(roles: [rol])), contains(rutaDelWebhook));
      });
    }

    for (final rol in fuera) {
      test('$rol no la ve', () {
        expect(
          rutasPara(_con(rol: rol, roles: [rol])),
          isNot(contains(rutaDelWebhook)),
          reason:
              '$rol no tiene nada que hacer en una pantalla de colas, reintentos '
              'y códigos HTTP de otro sistema: tropezar con ella es estorbo',
        );
      });
    }

    test('sin sesión todavía, no se enseña — el lado seguro', () {
      expect(rutasPara(null), isNot(contains(rutaDelWebhook)));
    });

    // LA OTRA MITAD, Y NO SOBRA: el resto del menú lo sigue viendo todo el mundo. Sin esto,
    // «el operador no ve el canal» se cumple con un menú vacío, y entonces nadie ve nada.
    test('lo demás del menú lo ve cualquiera, y también sin sesión', () {
      for (final quien in [null, _con(rol: 'OPERADOR')]) {
        final rutas = rutasPara(quien);

        expect(rutas, contains('/tablero'));
        expect(rutas, contains('/facturas'));
        expect(rutas, contains('/routes'));
      }
    });
  });
}

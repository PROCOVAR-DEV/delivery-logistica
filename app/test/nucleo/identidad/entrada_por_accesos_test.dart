import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/entrada_por_accesos.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';

import '../../apoyo/apoyo_accesos.dart';
import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/servidor_falso.dart';

/// LA PUERTA DE LA WEB, pieza a pieza.
///
/// Lo que se fija aqui es el contrato con `api/internal/api/auth_web.go`: las
/// direcciones a las que se manda a la persona y lo que se hace con cada una de
/// las tres respuestas de `/api/me`.
void main() {
  group('¿hay sesion? se lo pregunta al servidor', () {
    test('200 con persona y token: DENTRO, sin formulario', () async {
      final navegador = NavegadorFalso();
      final entrada = entradaFalsa(
        navegador,
        (p) async => RespuestaFalsa(
          200,
          respuestaDeApiMe(
            token: tokenDePrueba(sub: 'u-9', sucursal: 'HAB'),
            id: 'u-9',
          ),
        ),
      );

      final quien = await entrada.quienSoy();

      expect(quien, isA<HaySesion>());
      final sesion = (quien as HaySesion).sesion;
      expect(sesion.sub, 'u-9');
      expect(sesion.sucursalId, 'HAB');
      expect(sesion.nombre, 'Yasmani');
      expect(
        sesion.llevaPar,
        isFalse,
        reason:
            'la sesion de la web es la cookie: no hay par que renovar ni que '
            'revocar, y creer que lo hay es mandarle a auth un refresh vacio',
      );
      expect(
        navegador.ultimo,
        isNull,
        reason: 'con sesion no se manda a nadie a ninguna parte',
      );
    });

    test('401: NO hay sesion', () async {
      final entrada = entradaFalsa(
        NavegadorFalso(),
        (p) async => RespuestaFalsa(401, <String, Object?>{'user': null}),
      );

      expect(await entrada.quienSoy(), isA<NoHaySesion>());
    });

    test('200 con `user: null` tambien es que no hay sesion', () async {
      final entrada = entradaFalsa(
        NavegadorFalso(),
        (p) async => RespuestaFalsa(200, <String, Object?>{'user': null}),
      );

      expect(await entrada.quienSoy(), isA<NoHaySesion>());
    });

    test('sin red NO es «no hay sesion», y se dice', () async {
      // Es la tercera respuesta y es la que evita el bucle: la vuelta de Accesos
      // entra por esta misma API, asi que mandar alli a alguien cuya API esta
      // caida es mandarlo a dar la vuelta para volver al mismo sitio.
      final entrada = entradaFalsa(NavegadorFalso(), (p) async => null);

      final quien = await entrada.quienSoy();

      expect(quien, isA<NoContesta>());
      expect(
        entrada.motivo,
        EntradaPorAccesos.motivoNoContesta,
        reason: 'la puerta tiene que poder decir por que no se entro sola',
      );
    });
  });

  group('a donde se manda a la persona', () {
    test('al login unico, por la API y no por la aplicacion', () async {
      // El proxy se queda con `/api` antes que la aplicacion (`CLAUDE.md`
      // §3-quater): la puerta vive detras de ese prefijo.
      final navegador = NavegadorFalso();
      entradaFalsa(navegador, (p) async => null).aAccesos();

      expect(navegador.ultimo, '$baseApiDePrueba/auth/entrar');
    });

    test('se acuerda de a donde iba', () async {
      final navegador = NavegadorFalso(
        direccion: 'https://ejemplo.test/orders?municipio=Centro',
      );
      entradaFalsa(navegador, (p) async => null).aAccesos();

      expect(
        navegador.ultimo,
        '$baseApiDePrueba/auth/entrar?volverA='
        '${Uri.encodeQueryComponent('/orders?municipio=Centro')}',
      );
    });

    test('y tambien cuando el portero ya la guardo en `volverA`', () async {
      // Segun lo rapido que llegue el arranque, la direccion es la original o
      // la que el portero dejo mientras comprobaba. Mirar solo una es perder el
      // enlace la mitad de las veces.
      final navegador = NavegadorFalso(
        direccion:
            'https://ejemplo.test/arranque?volverA='
            '${Uri.encodeQueryComponent('/routes')}',
      );
      entradaFalsa(navegador, (p) async => null).aAccesos();

      expect(navegador.ultimo, contains(Uri.encodeQueryComponent('/routes')));
    });

    test('volver a la propia puerta seria un bucle: no se guarda', () {
      for (final puerta in ['/acceso', '/arranque', '/configurando', '/']) {
        final navegador = NavegadorFalso(
          direccion: 'https://ejemplo.test$puerta',
        );
        entradaFalsa(navegador, (p) async => null).aAccesos();
        expect(
          navegador.ultimo,
          '$baseApiDePrueba/auth/entrar',
          reason: puerta,
        );
      }
    });

    test('UNA sola redireccion, aunque la pantalla se repinte', () {
      // Dos `window.location` seguidos es una pantalla que pelea consigo misma.
      final navegador = NavegadorFalso();
      final entrada = entradaFalsa(navegador, (p) async => null);
      entrada.aAccesos();
      entrada.aAccesos();

      expect(navegador.visitados, hasLength(1));
    });

    test('salir pasa por Accesos y gana a la redireccion de la puerta', () {
      final navegador = NavegadorFalso();
      final entrada = entradaFalsa(navegador, (p) async => null);
      entrada.aSalir();
      // La pantalla de acceso se monta detras y querria irse al login: si ganara
      // ella, cerrar sesion acabaria volviendo a entrar.
      entrada.aAccesos();

      expect(navegador.visitados, ['$baseApiDePrueba/auth/logout']);
    });
  });

  group('el motivo que dejo el servidor en la direccion', () {
    test('suelto', () {
      expect(
        EntradaPorAccesos.motivoEnLaDireccion(
          Uri.parse('https://ejemplo.test/acceso?sso=nodisponible'),
        ),
        'nodisponible',
      );
    });

    test('y metido dentro del `volverA` que guarda el portero', () {
      // El portero mueve la aplicacion a `/arranque?volverA=…` nada mas
      // arrancar. Sin esta mitad, el motivo se pierde y queda la pantalla muda
      // que esto viene a quitar.
      final guardada = Uri.encodeQueryComponent('/acceso?sso=error');
      expect(
        EntradaPorAccesos.motivoEnLaDireccion(
          Uri.parse('https://ejemplo.test/arranque?volverA=$guardada'),
        ),
        'error',
      );
    });

    test('sin motivo, null: entonces se va sola', () {
      expect(
        EntradaPorAccesos.motivoEnLaDireccion(
          Uri.parse('https://ejemplo.test/'),
        ),
        isNull,
      );
    });

    test('cada motivo dice algo distinto y ninguno se queda mudo', () {
      final textos = <String>{};
      for (final motivo in [
        'nodisponible',
        'sincodigo',
        'error',
        EntradaPorAccesos.motivoNoContesta,
      ]) {
        final texto = EntradaPorAccesos.textoDelMotivo(motivo);
        expect(texto.trim(), isNotEmpty, reason: motivo);
        textos.add(texto);
      }
      expect(
        textos,
        hasLength(4),
        reason:
            'un motivo que se cuenta igual que otro manda a arreglar donde no '
            'es: «falta la llave» y «Accesos no contesta» no se parecen en nada',
      );
    });
  });

  group('la sesion que sale de la cookie', () {
    test('lo que dice el servidor manda, y lo que no trae sale del token', () {
      final token = tokenDePrueba(
        sub: 'u-del-token',
        sucursal: 'STG',
        roles: ['GESTOR'],
      );

      final sesion = Sesion.deLaCookie(
        token: token,
        usuario: const <String, Object?>{
          'id': 'u-1',
          'name': 'Claudia',
          'email': 'claudia@procovar.cu',
          'role': 'SUPERVISOR',
          'branchId': 'HAB',
        },
      );

      expect(sesion.sub, 'u-1');
      expect(sesion.sucursalId, 'HAB');
      expect(sesion.rol, 'SUPERVISOR');
      // Los roles no viajan en `/api/me`: salen del token, que viene firmado.
      expect(sesion.roles, ['GESTOR']);
      expect(sesion.token, token);
      expect(sesion.llevaPar, isFalse);
    });

    test('un `branchId` nulo es «ninguna», no una cadena vacia', () {
      // Una cadena vacia acabaria viajando en `x-sucursal-id: ` como si fuera
      // una sucursal elegida.
      final sesion = Sesion.deLaCookie(
        token: tokenDePrueba(sucursal: ''),
        usuario: const <String, Object?>{'id': 'u-1', 'branchId': null},
      );

      expect(sesion.sucursalId, isNull);
    });
  });

  group('el almacen de la web', () {
    test('una sesion de COOKIE no se escribe en el navegador', () async {
      // Escribirla dejaria el token en `localStorage` **despues de cerrar
      // sesion**: el servidor borra su cookie, el almacen sigue devolviendo el
      // token viejo y la persona sigue dentro creyendo que salio.
      final respaldo = AlmacenEnMemoria();
      final almacen = AlmacenPorCookie(respaldo);

      final quedo = await almacen.guardar(
        Sesion.deLaCookie(token: tokenDePrueba(), usuario: const {'id': 'u-1'}),
      );

      expect(
        quedo,
        isTrue,
        reason:
            'guardada SI esta —en la cookie—: decir que no mandaria a la '
            'pantalla de acceso a pintar un fallo que no existe',
      );
      expect(await respaldo.leer(), isNull);
    });

    test('el par de la puerta de respaldo SI se guarda', () async {
      // Si Accesos falla se entra con usuario y contrasena, y sin guardar ese
      // par el interceptor no tendria token que poner: cada recarga devolveria
      // a la puerta con la aplicacion vacia detras.
      final respaldo = AlmacenEnMemoria();
      final almacen = AlmacenPorCookie(respaldo);

      expect(await almacen.guardar(sesionDePrueba()), isTrue);
      expect((await respaldo.leer())?.sub, isNotNull);
      expect(
        (await almacen.leer())?.sub,
        isNotNull,
        reason: 'y se vuelve a leer, que es lo que usa el interceptor',
      );
    });

    test('salir borra lo guardado', () async {
      final respaldo = AlmacenEnMemoria(sesionDePrueba());
      final almacen = AlmacenPorCookie(respaldo);

      await almacen.borrar();

      expect(await almacen.leer(), isNull);
    });
  });
}

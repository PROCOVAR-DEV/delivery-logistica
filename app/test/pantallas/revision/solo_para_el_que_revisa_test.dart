// EL MENU Y LA RUTA DE LA BANDEJA DEL REVISOR.
//
// Jose, 08/10/2026: revisan ADMINISTRADOR de esa sucursal, SUPER ADMIN y
// DESARROLLADOR; nadie revisa lo suyo. La entrada del menu sale solo para esos
// tres (para no estorbar al resto: NO es un permiso, el cerrojo es de `sync`), y
// la pantalla vive en la web igual que en la APK y el escritorio.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/barra_lateral.dart';
import 'package:reparto/navegacion/pantallas.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/pantallas/revision/datos/quien_revisa.dart';
import 'package:reparto/pantallas/revision/registro.dart';
import 'package:reparto/pantallas/revision/vista/pantalla_revision.dart';

import 'apoyo_revision.dart';

void main() {
  test('la ruta NO es del proxy: ni /sync ni /api (CLAUDE.md §3-quater)', () {
    // Traefik se queda con `PathPrefix(/sync)` y `PathPrefix(/api)` ANTES que la
    // aplicacion: recargar la bandeja en `/sync-revision` llegaria al
    // sincronizador con un 401. Es prefijo de CADENA, no de segmento.
    expect(PantallaRevision.ruta, '/revision');
    for (final proxy in ['/sync', '/api']) {
      expect(PantallaRevision.ruta.startsWith(proxy), isFalse);
    }
    expect(registrarRevision().ruta, PantallaRevision.ruta);
  });

  test('esta en el menu y solo para los tres roles que revisan', () {
    final p = registrarRevision();
    expect(p.enElMenu, isTrue);
    expect(p.icono, isNotNull);
    expect(p.soloParaRoles, rolesQueRevisan);
    expect(
      rolesQueRevisan,
      unorderedEquals(['ADMINISTRADOR', 'SUPER ADMIN', 'DESARROLLADOR']),
    );
  });

  test('entradasPara: sale para quien revisa y NO para el resto', () {
    final pantallas = [registrarRevision()];
    bool sale(String? rol) => BarraLateral.entradasPara(
      pantallas,
      rol == null ? null : conRol(rol),
    ).isNotEmpty;

    for (final rol in ['ADMINISTRADOR', 'SUPER ADMIN', 'DESARROLLADOR']) {
      expect(sale(rol), isTrue, reason: rol);
    }
    // EN PAREJA: los demas no la ven. LOGISTICO entra a Reparto pero no revisa
    // el trabajo de otro logistico.
    for (final rol in [
      'LOGISTICO',
      'GERENTE',
      'SUPERVISOR',
      'GESTOR',
      'OPERADOR',
      'ECONOMICA',
      'ANALISTA',
      null,
    ]) {
      expect(sale(rol), isFalse, reason: '$rol');
    }
  });

  test('esta registrada en la aplicacion y vale en las cuatro formas, web '
      'incluida', () async {
    expect(
      pantallasDeLaAplicacion().map((p) => p.ruta),
      contains(PantallaRevision.ruta),
    );
    // Jose, 08/10/2026: la bandeja del revisor TAMBIEN en la web. Se registra
    // igual dentro y fuera de la web (a diferencia de Sincronizacion o del canal
    // con PEDIDO, que dependen del destino).
    final enWeb = await Destino.comoSiFueraWeb(
      () async => pantallasDeLaAplicacion().map((p) => p.ruta).toList(),
    );
    expect(enWeb, contains(PantallaRevision.ruta));
  });
}

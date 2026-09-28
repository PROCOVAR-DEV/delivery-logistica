import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/proveedores.dart';
import '../datos/consultas_panel.dart';

final consultasPanelProvider = Provider<ConsultasPanel>(
  (ref) =>
      ConsultasPanel(ref.watch(baseProvider), reloj: ref.watch(relojProvider)),
);

/// Las cifras, mirando la sucursal elegida arriba.
///
/// `ref.watch(sucursalMiradaProvider)` dentro del provider es lo que hace lo que
/// pide el pliego §0: al cambiar de sucursal **no se recarga la pagina**, se
/// reconstruye este provider y los numeros cambian en el sitio.
final cifrasDelPanelProvider = StreamProvider<CifrasDelPanel>(
  (ref) => ref
      .watch(consultasPanelProvider)
      .cifras(sucursalId: ref.watch(sucursalMiradaProvider)),
);

final pendientePorSucursalProvider = StreamProvider<List<PendienteDeSucursal>>(
  (ref) => ref
      .watch(consultasPanelProvider)
      .porSucursal(sucursalId: ref.watch(sucursalMiradaProvider)),
);

/// EL NOMBRE DE LA SUCURSAL DE LA QUE SON LAS CIFRAS.
///
/// `null` cuando están todas —lo dice la propia línea— y también mientras el
/// nombre no haya bajado. Stream y no Future: en la web `branches` llega un
/// segundo después de que la pantalla se pinte (`CLAUDE.md` §3-ter).
final nombreDeLaSucursalMiradaProvider = StreamProvider<String?>(
  (ref) => ref
      .watch(consultasPanelProvider)
      .nombreDeLaSucursal(ref.watch(sucursalMiradaProvider)),
);

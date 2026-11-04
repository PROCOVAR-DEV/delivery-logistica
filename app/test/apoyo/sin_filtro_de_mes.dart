import 'package:reparto/pantallas/tablero/estado/proveedores.dart';

/// El Tablero arranca en el MES EN CURSO (Jose, 04/11/2026: la bandeja «Sin colocar» no enseña facturas de meses anteriores). Las pruebas
/// de aquí con datos de septiembre u octubre no hablan del mes: parten SIN fecha, como antes. Lo del mes lo ata
/// `sin_colocar_solo_el_mes_test.dart`.
class _SinFiltroDeMes extends FiltrosTablero {
  @override
  FiltrosSinColocar build() => const FiltrosSinColocar();

  @override
  void limpiar() => state = const FiltrosSinColocar();
}

final filtrosSinMes = filtrosTableroProvider.overrideWith(_SinFiltroDeMes.new);

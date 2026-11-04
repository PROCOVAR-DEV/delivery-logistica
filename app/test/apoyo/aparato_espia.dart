import 'package:reparto/pantallas/rutas/datos/abrir_y_compartir.dart';

/// El aparato de mentira: apunta lo que se le pide y contesta lo que le digan.
class AparatoEspia implements AbrirYCompartir {
  AparatoEspia({this.abre = true, this.comparte = true, this.copia = true});

  bool abre;
  bool comparte;
  bool copia;

  final abiertos = <Uri>[];
  final compartidos = <({String texto, String? asunto})>[];
  final copiados = <String>[];

  @override
  Future<bool> abrir(Uri destino) async {
    abiertos.add(destino);
    return abre;
  }

  @override
  Future<bool> compartir({required String texto, String? asunto}) async {
    compartidos.add((texto: texto, asunto: asunto));
    return comparte;
  }

  @override
  Future<bool> copiar(String texto) async {
    copiados.add(texto);
    return copia;
  }
}

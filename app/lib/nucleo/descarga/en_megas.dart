/// «25,8 MB». Con coma, que es como se escriben los numeros aqui.
///
/// Vivia en `mapa/anuncio_de_mapa.dart`, que es donde se escribio. Se movio aqui
/// el 05/10/2026, al bajarse la actualizacion de la APK con el mismo motor que el
/// mapa (`descarga_reanudable.dart`): el motor tiene que escribir «llegaron 12,0
/// MB de los 75,0» y no podia depender del mapa para eso. `anuncio_de_mapa.dart`
/// lo sigue re-exportando, asi que quien lo importaba de alli no se enteró.
library;

String enMegas(int bytes) {
  if (bytes < 1000000) return '${(bytes / 1000).round()} kB';
  final megas = bytes / 1000000;
  return '${megas.toStringAsFixed(1).replaceAll('.', ',')} MB';
}

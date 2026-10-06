#!/bin/sh
# La fuente MaterialIcons se recorta a los símbolos usados en cada build.
# El 06/10 el JS nuevo pedía el libro de Guía, pero Cloudflare entregaba la
# fuente del 01/10: el hueco quedaba vacío. Fuentes, manifiestos y manual deben
# cambiar de dirección junto con el código, sin depender de una purga manual.
set -eu
cd "${1:?Uso: preparar-web.sh directorio-del-build-web}"
test -f index.html
test -f main.dart.js
test -f flutter_bootstrap.js
test -f assets/FontManifest.json
test -f assets/fonts/MaterialIcons-Regular.otf
test -f assets/assets/manual/manual.txt
# No publicar un build si Flutter cambia la forma de inicializar el motor.
test "$(grep -Fo '_flutter.loader.load({' flutter_bootstrap.js | wc -l)" -eq 1
test "$(grep -Fo '"mainJsPath":"main.dart.js"' flutter_bootstrap.js | wc -l)" -eq 1
H=$({ sha256sum main.dart.js; find assets -type f -exec sha256sum {} \; | LC_ALL=C sort; } | sha256sum | cut -c1-12)
sed -i "s#flutter_bootstrap\.js#flutter_bootstrap.js?v=$H#g" index.html
sed -i "s#main\.dart\.js#main.dart.js?v=$H#g" flutter_bootstrap.js
# assetBase precede a `assets/`, tanto para rootBundle como para las fuentes
# del motor. El mismo prefijo sirve con BASE_HREF=/ o con un subdirectorio.
sed -i "s#_flutter.loader.load({#_flutter.loader.load({config: {assetBase: 'recursos/$H/'},#" flutter_bootstrap.js
sed -i "s#href=\"favicon\.png\"#href=\"favicon.png?v=$H\"#g" index.html
sed -i "s#href=\"icons/Icon-192\.png\"#href=\"icons/Icon-192.png?v=$H\"#g" index.html
grep -Fq "flutter_bootstrap.js?v=$H" index.html
grep -Fq "favicon.png?v=$H" index.html
grep -Fq "main.dart.js?v=$H" flutter_bootstrap.js
grep -Fq "assetBase: 'recursos/$H/'" flutter_bootstrap.js
mkdir -p "recursos/$H"
mv assets "recursos/$H/assets"
echo "huella de esta compilacion: $H"

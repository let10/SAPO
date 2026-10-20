/// Corrige los errores sistemáticos de OCR que se repiten en los artículos de
/// las resoluciones. Se aplica al campo extraído; el texto OCR bruto de cada
/// página no se toca.
///
/// Solo corrige patrones que no pueden ser texto legítimo:
///  * el símbolo de número "N°" leído como `N*`, `N%`, `N?`, `Ne`, `N°%`… justo
///    antes de una cifra (`N%402` → `N°402`);
///  * rayas dobles (`—-`) que son una sola raya;
///  * signos sueltos que nunca aparecen en prosa (`>`, `|`, `~`) entre palabras;
///  * puntuación basura al inicio.
class CorrectorArticulo {
  static const String _noLetra = r'(?<![\p{L}])';

  // Uno a tres signos basura tras la N (`N*`, `N*%`, `N°%`); también unifica `Nº` en `N°`.
  static final RegExp _simboloNumeroMalLeido = RegExp('${_noLetra}N(\\.?)[°º*%?¢"“”´`\'’‘¬^~]{1,3}(?=\\s?\\d)', unicode: true);
  static final RegExp _numeroConE = RegExp('${_noLetra}N(\\.?)[eS\$](?=\\s?\\d)', unicode: true);
  static final RegExp _gradoConBasura = RegExp(r'N(\.?)[°º][%*?¢](?=\s?\d)');
  static final RegExp _rayasDobles = RegExp(r'[-—–]{2,}');
  static final RegExp _signoSuelto = RegExp(r'(?<=\s)[>|~«»]+(?=\s)');
  static final RegExp _basuraInicial = RegExp(r'^[\s,;.\-–—_|>]+');

  static String corregir(String texto) {
    var t = texto;
    t = t.replaceAllMapped(_simboloNumeroMalLeido, (m) => 'N${m[1]}°');
    t = t.replaceAllMapped(_numeroConE, (m) => 'N${m[1]}°');
    t = t.replaceAllMapped(_gradoConBasura, (m) => 'N${m[1]}°');
    t = t.replaceAll(_rayasDobles, '-');
    t = t.replaceAll(_signoSuelto, '');
    t = t.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    t = t.replaceFirst(_basuraInicial, '');
    return t;
  }
}

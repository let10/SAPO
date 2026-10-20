import 'dart:math' as math;

const Map<String, String> _equivalencias = {
  'Á': 'A', 'À': 'A', 'Â': 'A', 'Ä': 'A', 'á': 'A', 'à': 'A', 'â': 'A', 'ä': 'A',
  'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E', 'é': 'E', 'è': 'E', 'ê': 'E', 'ë': 'E',
  'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I', 'í': 'I', 'ì': 'I', 'î': 'I', 'ï': 'I',
  'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Ö': 'O', 'ó': 'O', 'ò': 'O', 'ô': 'O', 'ö': 'O',
  'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U', 'ú': 'U', 'ù': 'U', 'û': 'U', 'ü': 'U',
  'Ñ': 'N', 'ñ': 'N',
};

/// Mayúsculas sin tildes, conservando la longitud exacta del texto original
/// (un carácter por carácter) para poder mapear posiciones de vuelta al original.
String normalizarParaBusqueda(String texto) {
  final sb = StringBuffer();
  for (final unidad in texto.codeUnits) {
    final c = String.fromCharCode(unidad);
    final eq = _equivalencias[c];
    if (eq != null) {
      sb.write(eq);
    } else {
      final mayus = c.toUpperCase();
      sb.write(mayus.length == 1 ? mayus : c);
    }
  }
  return sb.toString();
}

/// Distancia de Levenshtein con corte anticipado: devuelve [maximo] + 1 si la
/// distancia real supera [maximo].
int distanciaLevenshtein(String a, String b, {int? maximo}) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  if (maximo != null && (a.length - b.length).abs() > maximo) return maximo + 1;

  var anterior = List<int>.generate(b.length + 1, (i) => i);
  var actual = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    actual[0] = i;
    var minimoFila = actual[0];
    for (var j = 1; j <= b.length; j++) {
      final costo = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      actual[j] = math.min(
        math.min(actual[j - 1] + 1, anterior[j] + 1),
        anterior[j - 1] + costo,
      );
      if (actual[j] < minimoFila) minimoFila = actual[j];
    }
    if (maximo != null && minimoFila > maximo) return maximo + 1;
    final tmp = anterior;
    anterior = actual;
    actual = tmp;
  }
  return anterior[b.length];
}

class CoincidenciaDifusa {
  /// Posiciones sobre el texto ORIGINAL: [inicio, fin).
  final int inicio;
  final int fin;
  final int distancia;

  const CoincidenciaDifusa(this.inicio, this.fin, this.distancia);
}

bool _esAlfanumerico(int codeUnit) =>
    (codeUnit >= 0x30 && codeUnit <= 0x39) || (codeUnit >= 0x41 && codeUnit <= 0x5A);

/// Búsqueda aproximada de [patron] ignorando mayúsculas, tildes y espacios
/// (tolera pequeñas variaciones de OCR). Exige que la coincidencia empiece y
/// termine en límite de palabra del texto original.
List<CoincidenciaDifusa> buscarDifuso(
  String texto,
  String patron, {
  int maxDistancia = 2,
  int desde = 0,
}) {
  final norm = normalizarParaBusqueda(texto);
  final compacto = StringBuffer();
  final mapa = <int>[];
  for (var i = 0; i < norm.length; i++) {
    if (_esAlfanumerico(norm.codeUnitAt(i))) {
      compacto.writeCharCode(norm.codeUnitAt(i));
      mapa.add(i);
    }
  }
  final c = compacto.toString();

  final pat = StringBuffer();
  for (final u in normalizarParaBusqueda(patron).codeUnits) {
    if (_esAlfanumerico(u)) pat.writeCharCode(u);
  }
  final p = pat.toString();
  final m = p.length;
  if (m == 0 || c.length < m - maxDistancia) return const [];

  bool limiteIzquierdo(int idxOrig) =>
      idxOrig == 0 || !_esAlfanumerico(norm.codeUnitAt(idxOrig - 1));
  bool limiteDerecho(int idxOrigFinExcl) =>
      idxOrigFinExcl >= norm.length || !_esAlfanumerico(norm.codeUnitAt(idxOrigFinExcl));

  final resultado = <CoincidenciaDifusa>[];
  for (var i = 0; i < c.length; i++) {
    if (mapa[i] < desde) continue;
    if (!limiteIzquierdo(mapa[i])) continue;

    int? mejorLong;
    var mejorDist = maxDistancia + 1;
    for (var len = math.max(1, m - maxDistancia); len <= m + maxDistancia; len++) {
      if (i + len > c.length) break;
      final finOrig = mapa[i + len - 1] + 1;
      if (!limiteDerecho(finOrig)) continue;
      final d = distanciaLevenshtein(c.substring(i, i + len), p, maximo: maxDistancia);
      if (d < mejorDist || (d == mejorDist && mejorLong != null && (len - m).abs() < (mejorLong - m).abs())) {
        mejorDist = d;
        mejorLong = len;
      }
    }
    if (mejorLong == null || mejorDist > maxDistancia) continue;

    final nueva = CoincidenciaDifusa(mapa[i], mapa[i + mejorLong - 1] + 1, mejorDist);
    if (resultado.isNotEmpty && nueva.inicio < resultado.last.fin) {
      if (nueva.distancia < resultado.last.distancia) {
        resultado[resultado.length - 1] = nueva;
      }
    } else {
      resultado.add(nueva);
    }
  }
  return resultado;
}

/// Colapsa cualquier secuencia de espacios/saltos de línea en un solo espacio.
String colapsarEspacios(String texto) => texto.replaceAll(RegExp(r'\s+'), ' ').trim();

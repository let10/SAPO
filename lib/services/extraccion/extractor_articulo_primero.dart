import '../../utils/texto_utils.dart';
import 'corrector_articulo.dart';

class ResultadoArticulo {
  /// Párrafo resolutivo principal (sin la etiqueta "ARTÍCULO PRIMERO").
  final String principal;

  /// Contenido íntegro del artículo (principal + bloque de detalle).
  final String completo;

  /// Motivos por los que la extracción requiere revisión humana (vacío = sin dudas).
  final List<String> avisos;

  const ResultadoArticulo({
    required this.principal,
    required this.completo,
    this.avisos = const [],
  });

  bool get requiereRevision => avisos.isNotEmpty;
}

class ExtractorArticuloPrimero {
  /// Etiquetas que inician un bloque estructurado de detalle dentro del artículo.
  /// Es una ayuda, no una regla absoluta: además se usan reglas generales
  /// (línea que termina en ":" y filas de tabla numérica).
  static final List<RegExp> _inicioBloqueConDosPuntos = [
    RegExp(r'^SE OTORGA LICENCIA A\s*:?'),
    RegExp(r'^ACTIVIDAD ECONOMICA A DESARROLLAR\s*:?'),
    RegExp(r'^NOMBRE COMERCIAL\s*:?'),
    RegExp(r'^UBICADO EN\s*:?'),
    RegExp(r'^AREA\s*:'),
  ];

  static final List<RegExp> _inicioBloqueLineaCorta = [
    RegExp(r'^INGRESOS?\b'),
    RegExp(r'^EGRESOS?\b'),
    RegExp(r'^PLIEGO\b'),
    RegExp(r'^FUENTE DE FINANCIAMIENTO\b'),
    RegExp(r'^RUBRO\b'),
  ];

  static const int _minimoPrincipal = 40;

  static ResultadoArticulo extraer(String texto, {bool anclaAcuerdo = false}) {
    final avisos = <String>[];
    var desde = 0;

    if (anclaAcuerdo) {
      final marca = _localizarAcuerdoOperativo(texto);
      if (marca == null) {
        avisos.add('No se encontró el bloque "ACUERDO:".');
        return ResultadoArticulo(principal: '', completo: '', avisos: avisos);
      }
      desde = marca.fin;
    } else {
      final sr = _localizarSeResuelve(texto);
      if (sr == null) {
        avisos.add('No se encontró "SE RESUELVE".');
      } else {
        desde = sr.fin;
      }
    }

    // Sin ancla (no hubo "SE RESUELVE") se elige la mención que parece el
    // encabezado real. Con ancla —"SE RESUELVE" o el bloque "ACUERDO:"— solo
    // vale el primer ARTÍCULO PRIMERO que viene después.
    final hayAncla =
        anclaAcuerdo || !avisos.any((a) => a.contains('SE RESUELVE'));
    final primero = hayAncla
        ? _primerArticuloPrimero(texto, desde)
        : _mejorArticuloPrimeroSinAncla(texto);
    if (primero == null) {
      avisos.add('No se encontró "ARTÍCULO PRIMERO".');
      return ResultadoArticulo(principal: '', completo: '', avisos: avisos);
    }

    final inicioContenido = _saltarSeparadores(texto, primero.fin);
    final segundo = _buscarArticulo(texto, 'ARTICULOSEGUNDO', inicioContenido);

    String completo;
    if (segundo != null) {
      completo = texto.substring(inicioContenido, segundo.inicio);
    } else {
      completo = texto.substring(inicioContenido);
      avisos.add(
        'No se encontró "ARTÍCULO SEGUNDO": la extracción puede estar incompleta.',
      );
    }
    completo = CorrectorArticulo.corregir(completo.trim());

    final principal = colapsarEspacios(separarPrincipal(completo));

    if (principal.isEmpty) {
      avisos.add('El contenido del Artículo Primero está vacío.');
    } else {
      if (principal.length < 20) {
        avisos.add(
          'El párrafo principal es muy corto; puede estar incompleto.',
        );
      }
      if (!RegExp(r'[.:;]$').hasMatch(principal)) {
        avisos.add(
          'El párrafo principal no termina en un signo de puntuación; puede estar incompleto.',
        );
      }
    }

    return ResultadoArticulo(
      principal: principal,
      completo: completo,
      avisos: avisos,
    );
  }

  /// Localiza "SE RESUELVE" (con variaciones de OCR) que da paso a la parte
  /// resolutiva. Prefiere la aparición en mayúsculas, al inicio de línea y
  /// seguida de un ARTÍCULO PRIMERO cercano, para no confundirse con menciones
  /// dentro de los considerandos.
  static CoincidenciaDifusa? _localizarSeResuelve(String texto) {
    final candidatos = buscarDifuso(texto, 'SERESUELVE', maxDistancia: 2);
    if (candidatos.isEmpty) return null;

    CoincidenciaDifusa? mejor;
    var mejorPuntaje = -1;
    for (final c in candidatos) {
      final fragmento = texto.substring(c.inicio, c.fin);
      var puntaje = 0;
      if (fragmento == fragmento.toUpperCase()) puntaje += 2;
      final previo = texto.substring(0, c.inicio);
      final ultimoSalto = previo.lastIndexOf('\n');
      if (previo.substring(ultimoSalto + 1).trim().isEmpty) puntaje += 1;
      final seguido = _buscarArticulo(texto, 'ARTICULOPRIMERO', c.fin);
      if (seguido != null && seguido.inicio - c.fin < 400) puntaje += 2;
      puntaje -= c.distancia;
      if (puntaje > mejorPuntaje) {
        mejorPuntaje = puntaje;
        mejor = c;
      }
    }
    return mejor;
  }

  /// Bloque operativo "ACUERDO:" (no el título "ACUERDO DE CONCEJO…" ni una
  /// cita "Acuerdo de Concejo"). Exige dos puntos, o un ARTÍCULO PRIMERO
  /// cercano, para no anclar en una mención suelta.
  static CoincidenciaDifusa? _localizarAcuerdoOperativo(String texto) {
    final candidatos = buscarDifuso(texto, 'ACUERDO', maxDistancia: 1);
    CoincidenciaDifusa? mejor;
    var mejorPuntaje = 2;
    for (final c in candidatos) {
      if (_palabraSiguiente(texto, c.fin) == 'DE') continue;
      var puntaje = 0;
      if (_cierraConPuntuacion(texto, c.fin)) puntaje += 2;
      final previo = texto.substring(0, c.inicio);
      final ultimoSalto = previo.lastIndexOf('\n');
      if (previo.substring(ultimoSalto + 1).trim().isEmpty) puntaje += 1;
      final seguido = _buscarArticulo(texto, 'ARTICULOPRIMERO', c.fin);
      if (seguido != null && seguido.inicio - c.fin < 500) puntaje += 3;
      puntaje -= c.distancia;
      if (puntaje > mejorPuntaje) {
        mejorPuntaje = puntaje;
        mejor = c;
      }
    }
    return mejor;
  }

  static String? _palabraSiguiente(String texto, int fin) {
    final resto = normalizarParaBusqueda(texto.substring(fin));
    return RegExp(r'^[^A-Z]*([A-Z]+)').firstMatch(resto)?.group(1);
  }

  static bool _cierraConPuntuacion(String texto, int fin) {
    final hasta = fin + 6 > texto.length ? texto.length : fin + 6;
    return RegExp(r'^\s*[:;.]').hasMatch(texto.substring(fin, hasta));
  }

  static CoincidenciaDifusa? _primerArticuloPrimero(String texto, int desde) =>
      _buscarArticulo(texto, 'ARTICULOPRIMERO', desde);

  static CoincidenciaDifusa? _buscarArticulo(
    String texto,
    String patron,
    int desde,
  ) {
    final m = buscarDifuso(texto, patron, maxDistancia: 2, desde: desde);
    return m.isEmpty ? null : m.first;
  }

  /// Puntúa cada mención: en mayúsculas (+2), al inicio de línea (+1), seguida
  /// de un ARTÍCULO SEGUNDO (+2) y poco distorsionada (−distancia). A igual
  /// puntaje gana la última (el artículo real va después de los considerandos).
  static CoincidenciaDifusa? _mejorArticuloPrimeroSinAncla(String texto) {
    final todos = buscarDifuso(texto, 'ARTICULOPRIMERO', maxDistancia: 2);
    CoincidenciaDifusa? elegido;
    var mejor = -1000;
    for (final c in todos) {
      var puntaje = 0;
      final fragmento = texto.substring(c.inicio, c.fin);
      if (fragmento == fragmento.toUpperCase()) puntaje += 2;
      final previo = texto.substring(0, c.inicio);
      if (previo.substring(previo.lastIndexOf('\n') + 1).trim().length <= 6) {
        puntaje += 1;
      }
      if (_buscarArticulo(texto, 'ARTICULOSEGUNDO', c.fin) != null) {
        puntaje += 2;
      }
      puntaje -= c.distancia;
      if (puntaje >= mejor) {
        mejor = puntaje;
        elegido = c;
      }
    }
    return elegido;
  }

  static int _saltarSeparadores(String texto, int pos) {
    var i = pos;
    while (i < texto.length && RegExp(r'[\s:.\-–—_]').hasMatch(texto[i])) {
      i++;
    }
    return i;
  }

  /// Líneas del texto con su posición real. Un salto CRLF ocupa dos caracteres;
  /// contarlo como uno desplazaba el corte y recortaba el final del párrafo.
  static List<({String texto, int inicio, int fin})> _lineas(String completo) {
    final lineas = <({String texto, int inicio, int fin})>[];
    var i = 0;
    while (true) {
      var j = i;
      while (j < completo.length &&
          completo[j] != '\n' &&
          completo[j] != '\r') {
        j++;
      }
      lineas.add((texto: completo.substring(i, j), inicio: i, fin: j));
      if (j >= completo.length) break;
      i =
          completo[j] == '\r' &&
              j + 1 < completo.length &&
              completo[j + 1] == '\n'
          ? j + 2
          : j + 1;
    }
    return lineas;
  }

  /// Separa el párrafo resolutivo principal del bloque de detalle posterior
  /// (cuadros de ingresos/egresos, datos de licencia, etc.).
  static String separarPrincipal(String completo) {
    final lineas = _lineas(completo);
    var acumulado = 0; // caracteres de contenido previos a la línea actual
    var ultimoCaracter = '';
    int? corte;

    for (final lineaPos in lineas) {
      final linea = lineaPos.texto;
      final recortada = linea.trim();
      final norm = normalizarParaBusqueda(recortada);
      final inicioLinea = lineaPos.inicio;
      final finLinea = lineaPos.fin;

      if (recortada.isEmpty) continue;

      final enPrincipal = acumulado >= _minimoPrincipal;

      // a) etiquetas de bloque estructurado
      final esEtiqueta =
          _inicioBloqueConDosPuntos.any((r) => r.hasMatch(norm)) ||
          (recortada.length <= 70 &&
              _inicioBloqueLineaCorta.any((r) => r.hasMatch(norm)));
      if (enPrincipal && esEtiqueta) {
        corte = inicioLinea;
        break;
      }

      // c) fila de tabla: varios valores numéricos / importes
      if (enPrincipal && _pareceFilaDeTabla(recortada)) {
        corte = inicioLinea;
        break;
      }

      // Etiqueta corta con ":" después de una oración ya cerrada (p. ej. "REVISION:"):
      // pertenece a lo que sigue, no al párrafo principal.
      if (enPrincipal &&
          recortada.endsWith(':') &&
          recortada.length < 30 &&
          ultimoCaracter == '.') {
        corte = inicioLinea;
        break;
      }

      acumulado += recortada.length;
      ultimoCaracter = recortada[recortada.length - 1];

      // b) la línea termina en ":" → introduce el detalle; el párrafo la incluye
      if (acumulado >= _minimoPrincipal && recortada.endsWith(':')) {
        corte = finLinea;
        break;
      }
    }

    if (corte == null) {
      // Sin indicios de bloque: primer párrafo (hasta línea en blanco). El OCR
      // a veces deja una línea en blanco a mitad de una oración (al saltar de
      // bloque de texto), así que solo cuenta como fin de párrafo si lo
      // anterior termina en un signo de puntuación.
      for (final m in RegExp(r'\n[ \t]*\r?\n').allMatches(completo)) {
        if (m.start < _minimoPrincipal) continue;
        if (RegExp(r'[.:;]$')
            .hasMatch(completo.substring(0, m.start).trimRight())) {
          corte = m.start;
          break;
        }
      }
    }

    return (corte == null ? completo : completo.substring(0, corte)).trim();
  }

  /// Una fila de cuadro está formada casi solo por importes/cifras; la prosa que
  /// menciona años o montos (`del 2026 hasta el 2027`) no cuenta.
  static bool _pareceFilaDeTabla(String linea) {
    final tokens = linea
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.length < 2) return false;
    final numericos = tokens
        .where(
          (t) =>
              RegExp(r'^(?:S/\.?|\$)$').hasMatch(t) ||
              RegExp(r'^(?:S/\.?)?[\d.,]{3,}$').hasMatch(t),
        )
        .length;
    return numericos >= 2 && numericos / tokens.length >= 0.7;
  }
}

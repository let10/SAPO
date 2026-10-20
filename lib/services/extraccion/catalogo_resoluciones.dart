import '../../utils/texto_utils.dart';

class TipoResolucion {
  /// Siglas normalizadas (con guiones), p. ej. `SGDELC-GDESGA-MDP-T`.
  final String siglas;

  /// Nombre oficial normalizado, p. ej. `RESOLUCIÓN DE ALCALDÍA`.
  final String nombre;

  /// Núcleo de la denominación (sin "RESOLUCIÓN DE"), en mayúsculas sin tildes.
  final String nucleoTexto;

  const TipoResolucion(this.siglas, this.nombre, this.nucleoTexto);

  RegExp get _patron {
    final palabras = nucleoTexto.split(' ').map(RegExp.escape).join(r'[\s,]+');
    return RegExp(r'(?<![A-Z])RESOLUCION\s+DE\s+(?:LA\s+)?' + palabras + r'(?![A-Z])');
  }
}

/// Equivalencias de siglas ↔ tipo de resolución. Para soportar un tipo nuevo
/// basta con agregar una entrada a [tipos].
class CatalogoResoluciones {
  static const List<TipoResolucion> tipos = [
    TipoResolucion('A-MDP-T', 'RESOLUCIÓN DE ALCALDÍA', 'ALCALDIA'),
    TipoResolucion('GM-MDP-T', 'RESOLUCIÓN DE GERENCIA MUNICIPAL', 'GERENCIA MUNICIPAL'),
    TipoResolucion('OGA-MDP-T', 'RESOLUCIÓN DE LA OFICINA GENERAL DE ADMINISTRACIÓN',
        'OFICINA GENERAL DE ADMINISTRACION'),
    TipoResolucion('GDTI-MDP-T',
        'RESOLUCIÓN DE GERENCIA DE DESARROLLO TERRITORIAL E INFRAESTRUCTURA',
        'GERENCIA DE DESARROLLO TERRITORIAL E INFRAESTRUCTURA'),
    TipoResolucion('GDESGA-MDP-T',
        'RESOLUCIÓN DE GERENCIA DE DESARROLLO ECONÓMICO, SOCIAL Y GESTIÓN AMBIENTAL',
        'GERENCIA DE DESARROLLO ECONOMICO SOCIAL Y GESTION AMBIENTAL'),
    TipoResolucion('SGDELC-GDESGA-MDP-T',
        'RESOLUCIÓN DE SUBGERENCIA DE DESARROLLO ECONÓMICO, LICENCIAS Y CONTROL',
        'SUBGERENCIA DE DESARROLLO ECONOMICO LICENCIAS Y CONTROL'),
    TipoResolucion('SGDT-GDTI-MDP-T', 'RESOLUCIÓN DE SUBGERENCIA DE DESARROLLO TERRITORIAL',
        'SUBGERENCIA DE DESARROLLO TERRITORIAL'),
  ];

  static TipoResolucion? porSiglas(String siglasNormalizadas) {
    for (final t in tipos) {
      if (t.siglas == siglasNormalizadas) return t;
    }
    return null;
  }

  /// Tipo cuyas siglas distan a lo sumo [maxDistancia] caracteres (típico error
  /// de OCR). Devuelve `null` si hay empate o ninguno está cerca.
  static TipoResolucion? porSiglasAproximadas(String siglasNormalizadas, {int maxDistancia = 1}) {
    TipoResolucion? mejor;
    var mejorDist = maxDistancia + 1;
    var empate = false;
    for (final t in tipos) {
      final d = distanciaLevenshtein(siglasNormalizadas, t.siglas, maximo: maxDistancia);
      if (d < mejorDist) {
        mejorDist = d;
        mejor = t;
        empate = false;
      } else if (d == mejorDist && d <= maxDistancia) {
        empate = true;
      }
    }
    return empate ? null : mejor;
  }

  /// Detecta el tipo a partir del texto del encabezado.
  static TipoResolucion? porTexto(String texto) {
    final norm = normalizarParaBusqueda(texto);

    final ordenados = [...tipos]..sort((a, b) => b.nucleoTexto.length.compareTo(a.nucleoTexto.length));
    for (final t in ordenados) {
      if (t._patron.hasMatch(norm)) return t;
    }

    // Respaldo tolerante a OCR: búsqueda aproximada de la denominación completa.
    TipoResolucion? mejor;
    var mejorDist = 1 << 30;
    var empate = false;
    for (final t in ordenados) {
      final patron = 'RESOLUCION DE ${t.nucleoTexto}';
      final tolerancia = (patron.replaceAll(' ', '').length * 0.12).floor();
      final m = buscarDifuso(texto, patron, maxDistancia: tolerancia);
      if (m.isEmpty) continue;
      final d = m.map((x) => x.distancia).reduce((a, b) => a < b ? a : b);
      if (d < mejorDist) {
        mejorDist = d;
        mejor = t;
        empate = false;
      } else if (d == mejorDist) {
        empate = true;
      }
    }
    return empate ? null : mejor;
  }
}

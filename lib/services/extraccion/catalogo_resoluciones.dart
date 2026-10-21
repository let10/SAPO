import '../../utils/texto_utils.dart';

class TipoResolucion {
  /// Siglas normalizadas (con guiones), p. ej. `SGDELC-GDESGA-MDP-T`.
  final String siglas;

  /// Nombre oficial normalizado, p. ej. `RESOLUCIÓN DE ALCALDÍA`.
  final String nombre;

  /// Núcleo de la denominación (sin el prefijo), en mayúsculas sin tildes.
  final String nucleoTexto;

  /// Lo que antecede al núcleo, en mayúsculas sin tildes. Las resoluciones
  /// usan `RESOLUCION DE` y admiten un "LA" intermedio.
  final String prefijoTitulo;

  const TipoResolucion(
    this.siglas,
    this.nombre,
    this.nucleoTexto, {
    this.prefijoTitulo = 'RESOLUCION DE',
  });

  RegExp get _patron {
    final palabras = nucleoTexto.split(' ').map(RegExp.escape).join(r'[\s,]+');
    final prefijo = prefijoTitulo.split(' ').map(RegExp.escape).join(r'\s+');
    final la = prefijoTitulo == 'RESOLUCION DE' ? r'(?:LA\s+)?' : '';
    return RegExp('(?<![A-Z])$prefijo\\s+$la$palabras(?![A-Z])');
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
    TipoResolucion(
      'CM-MDP-T',
      'ACUERDO DE CONCEJO MUNICIPAL',
      'CONCEJO MUNICIPAL',
      prefijoTitulo: 'ACUERDO DE',
    ),
    // El decreto trae código `NNN-AÑO-MDP-T` (no `A-MDP-T`, que es la resolución).
    TipoResolucion(
      'MDP-T',
      'DECRETO DE ALCALDÍA',
      'ALCALDIA',
      prefijoTitulo: 'DECRETO DE',
    ),
    // La ordenanza trae código `Nro. NNN-AÑO-MDP`, sin la `-T` del decreto.
    TipoResolucion(
      'MDP',
      'ORDENANZA MUNICIPAL',
      'MUNICIPAL',
      prefijoTitulo: 'ORDENANZA',
    ),
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
  ///
  /// Si hay más de un título, gana el que aparece primero: el del documento va
  /// arriba y las citas (una ordenanza citada dentro de un decreto, por ejemplo)
  /// van después. A igual posición gana el núcleo más largo, para no tomar
  /// "gerencia" cuando el título es de una subgerencia.
  static TipoResolucion? porTexto(String texto) => tituloMasTemprano(texto)?.$1;

  /// Título más temprano y su posición en [texto] (misma longitud que el original).
  static (TipoResolucion, int)? tituloMasTemprano(String texto) {
    final norm = normalizarParaBusqueda(texto);

    TipoResolucion? elegido;
    var mejorInicio = 1 << 30;
    var mejorLargo = -1;
    for (final t in tipos) {
      final m = t._patron.firstMatch(norm);
      if (m == null) continue;
      final largo = t.nucleoTexto.length;
      if (m.start < mejorInicio || (m.start == mejorInicio && largo > mejorLargo)) {
        mejorInicio = m.start;
        mejorLargo = largo;
        elegido = t;
      }
    }
    if (elegido != null) return (elegido, mejorInicio);

    final ordenados = [...tipos]..sort((a, b) => b.nucleoTexto.length.compareTo(a.nucleoTexto.length));

    // Respaldo tolerante a OCR: búsqueda aproximada de la denominación completa.
    TipoResolucion? mejor;
    var mejorDist = 1 << 30;
    var mejorPos = 0;
    var empate = false;
    for (final t in ordenados) {
      final patron = '${t.prefijoTitulo} ${t.nucleoTexto}';
      final tolerancia = (patron.replaceAll(' ', '').length * 0.12).floor();
      final m = buscarDifuso(texto, patron, maxDistancia: tolerancia);
      if (m.isEmpty) continue;
      final d = m.map((x) => x.distancia).reduce((a, b) => a < b ? a : b);
      if (d < mejorDist) {
        mejorDist = d;
        mejor = t;
        mejorPos = m.first.inicio;
        empate = false;
      } else if (d == mejorDist) {
        empate = true;
      }
    }
    if (empate || mejor == null) return null;
    return (mejor, mejorPos);
  }

  /// El encabezado es el de un acuerdo de concejo, no el de una resolución que
  /// solo cita un acuerdo más abajo.
  static bool esAcuerdoDeConcejo(String texto) => porTexto(texto)?.siglas == 'CM-MDP-T';
}

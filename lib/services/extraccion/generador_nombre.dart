import 'catalogo_resoluciones.dart';
import 'normalizador_numero.dart';
import 'normalizador_siglas.dart';

class GeneradorNombre {
  /// `NNN-AÑO-SIGLAS` con el número normalizado a tres cifras.
  static String generarCodigo(String numero, String anio, String siglas) {
    final n = NormalizadorNumero.normalizar(numero);
    return '${n.valor}-$anio-${NormalizadorSiglas.normalizar(siglas)}';
  }

  /// `[TIPO DE RESOLUCIÓN] N° [CÓDIGO]`.
  static String generarNombreCompleto(TipoResolucion tipo, String codigo) =>
      '${tipo.nombre} N° $codigo';
}

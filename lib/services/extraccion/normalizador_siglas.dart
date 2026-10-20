import '../../utils/texto_utils.dart';

class NormalizadorSiglas {
  /// `A-MDP/T` → `A-MDP-T`. Solo para metadatos; no altera el OCR bruto.
  static String normalizar(String crudo) {
    var s = normalizarParaBusqueda(crudo).replaceAll(RegExp(r'\s+'), '');
    s = s.replaceAll(RegExp(r'[/\\–—‐‑_]'), '-');
    s = s.replaceAll(RegExp(r'-{2,}'), '-');
    s = s.replaceAll(RegExp(r'^[-.,;:]+|[-.,;:]+$'), '');
    return s;
  }
}

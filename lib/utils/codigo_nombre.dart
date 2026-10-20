import '../services/extraccion/normalizador_numero.dart';

/// El nombre completo (`[TIPO] N° NNN-AÑO-SIGLAS`) y el código (`NNN-AÑO-SIGLAS`)
/// comparten número y siglas: al editar uno se actualiza el otro.
class CodigoNombre {
  static final RegExp _conSimbolo = RegExp(r'^(.*?)\s*N°\s*(.*)$');

  /// Código que sigue a "N°" en el nombre completo, o `null` si no hay "N°".
  static String? codigoDeNombre(String nombre) {
    final m = _conSimbolo.firstMatch(nombre.trim());
    if (m == null) return null;
    return m.group(2)!.trim();
  }

  /// Reemplaza el código dentro del nombre conservando el tipo ("RESOLUCIÓN DE …").
  /// Si el nombre no tiene "N°" (o está vacío) lo devuelve sin cambios.
  static String nombreConCodigo(String nombre, String codigo) {
    final m = _conSimbolo.firstMatch(nombre.trim());
    if (m == null) return nombre;
    final tipo = m.group(1)!.trim();
    return tipo.isEmpty ? nombre : '$tipo N° $codigo';
  }

  /// Número inicial del código (`074` en `074-2026-A-MDP-T`); vacío si falta o es `___`.
  static String numeroDeCodigo(String codigo) {
    final m = RegExp(r'^(\d+)(?:-|$)').firstMatch(codigo.trim());
    return m?.group(1) ?? '';
  }

  /// Número a tres cifras (`87` → `087`); `___` si no hay dígitos.
  static String numeroNormalizado(String digitos) {
    final limpio = digitos.replaceAll(RegExp(r'\D'), '');
    if (limpio.isEmpty) return '___';
    return NormalizadorNumero.normalizar(limpio).valor;
  }

  /// Reemplaza el número del código por [digitos] normalizado a tres cifras.
  static String codigoConNumero(String codigo, String digitos) {
    final nuevo = numeroNormalizado(digitos);
    final partes = codigo.trim().split('-');
    final resto = partes.length > 1 ? partes.sublist(1).join('-') : '';
    return resto.isEmpty ? nuevo : '$nuevo-$resto';
  }
}

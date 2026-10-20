class NumeroNormalizado {
  /// Número con al menos tres cifras (`007`, `050`, `117`). Vacío si no es numérico.
  final String valor;
  final bool requiereRevision;
  final String nota;

  const NumeroNormalizado(this.valor, {this.requiereRevision = false, this.nota = ''});
}

class NormalizadorNumero {
  /// Normaliza el número de resolución a tres cifras. Solo se aplica al campo
  /// estructurado; el OCR bruto nunca se modifica.
  static NumeroNormalizado normalizar(String crudo) {
    final limpio = crudo.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d+$').hasMatch(limpio)) {
      return NumeroNormalizado('',
          requiereRevision: true, nota: 'El número leído ("$crudo") no es numérico.');
    }
    if (RegExp(r'^0+$').hasMatch(limpio)) {
      return NumeroNormalizado(limpio.padLeft(3, '0'),
          requiereRevision: true, nota: 'El número leído es cero.');
    }
    // Los ceros a la izquierda no son significativos: 0121 → 121.
    final significativo = limpio.replaceFirst(RegExp(r'^0+'), '');
    if (significativo.length > 3) {
      return NumeroNormalizado(limpio,
          requiereRevision: true,
          nota: 'El número tiene más de tres cifras ($limpio); no se recortó automáticamente.');
    }
    return NumeroNormalizado(significativo.padLeft(3, '0'));
  }

  static const Map<String, String> _confundibles = {
    'O': '0', 'Q': '0', 'D': '0',
    'I': '1', 'L': '1', '|': '1', '!': '1',
    'Z': '2',
    'S': '5', r'$': '5',
    'G': '6',
    '+': '7', 'Y': '7', 'T': '7',
    'B': '8',
  };

  /// Intenta convertir una lectura OCR con caracteres confundidos (p. ej. `O+4`)
  /// en dígitos. El resultado siempre debe tratarse como lectura NO limpia: solo
  /// sirve como sugerencia o como voto de apoyo, nunca como dato confirmado.
  static String? repararConfundibles(String crudo) {
    final sb = StringBuffer();
    var digitosReales = 0;
    for (final ch in crudo.replaceAll(RegExp(r'\s'), '').toUpperCase().split('')) {
      if (RegExp(r'^\d$').hasMatch(ch)) {
        sb.write(ch);
        digitosReales++;
      } else {
        final equivalente = _confundibles[ch];
        if (equivalente == null) return null;
        sb.write(equivalente);
      }
    }
    final resultado = sb.toString();
    if (digitosReales == 0 || resultado.isEmpty || resultado.length > 5) return null;
    return resultado;
  }
}

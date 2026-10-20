import 'package:flutter/services.dart';

/// Máscara `DD/MM/AAAA`: acepta solo dígitos e inserta las barras al escribir.
class FormatoFechaDDMMAAAA extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue anterior, TextEditingValue nuevo) {
    final digitos = nuevo.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limitado = digitos.length > 8 ? digitos.substring(0, 8) : digitos;
    final sb = StringBuffer();
    for (var i = 0; i < limitado.length; i++) {
      if (i == 2 || i == 4) sb.write('/');
      sb.write(limitado[i]);
    }
    final texto = sb.toString();
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

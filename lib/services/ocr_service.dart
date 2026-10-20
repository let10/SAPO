import 'dart:io';

/// Palabra reconocida por Tesseract con su posición (píxeles de la imagen leída).
class PalabraOcr {
  final int izquierda;
  final int arriba;
  final int ancho;
  final int alto;
  final double confianza;
  final String texto;
  final int bloque;
  final int parrafo;
  final int linea;

  const PalabraOcr({
    required this.izquierda,
    required this.arriba,
    required this.ancho,
    required this.alto,
    required this.confianza,
    required this.texto,
    required this.bloque,
    required this.parrafo,
    required this.linea,
  });
}

class ResultadoOcr {
  final String texto;
  final List<PalabraOcr> palabras;

  const ResultadoOcr(this.texto, this.palabras);
}

/// Envuelve llamadas al ejecutable de Tesseract OCR instalado en el sistema.
class OcrService {
  static const String rutaTesseract = r'C:\Program Files\Tesseract-OCR\tesseract.exe';

  /// OCR general en español (motor LSTM) → solo texto.
  Future<String> reconocerImagen(String rutaImagen) async {
    final r = await reconocer(rutaImagen);
    return r.texto;
  }

  /// OCR en español con motor LSTM (`--oem 1`).
  ///
  /// [psm]: modo de segmentación de página (6 = bloque uniforme, 4 = columna,
  /// 11 = texto disperso, 7 = una sola línea, 8 = una sola palabra).
  /// [dpi]: resolución de la imagen, para que Tesseract no la estime.
  /// [soloDigitos]: restringe los caracteres a 0-9.
  /// [conPalabras]: además del texto, devuelve cada palabra con su caja (TSV).
  Future<ResultadoOcr> reconocer(
    String rutaImagen, {
    int? psm,
    int? dpi,
    bool soloDigitos = false,
    bool conPalabras = false,
  }) async {
    if (!await File(rutaTesseract).exists()) {
      throw Exception('No se encontró Tesseract en $rutaTesseract');
    }

    final salidaBase = rutaImagen.substring(0, rutaImagen.lastIndexOf('.'));
    final args = <String>[
      rutaImagen,
      salidaBase,
      '-l', 'spa',
      '--oem', '1',
      if (psm != null) ...['--psm', '$psm'],
      if (dpi != null) ...['--dpi', '$dpi'],
      if (soloDigitos) ...['-c', 'tessedit_char_whitelist=0123456789'],
      'txt',
      if (conPalabras) 'tsv',
    ];

    final resultado = await Process.run(rutaTesseract, args);
    final archivoTxt = File('$salidaBase.txt');
    final archivoTsv = File('$salidaBase.tsv');

    try {
      if (resultado.exitCode != 0) {
        throw Exception('Tesseract devolvió código ${resultado.exitCode}: ${resultado.stderr}');
      }
      if (!await archivoTxt.exists()) {
        throw Exception('Tesseract no generó archivo de texto de salida');
      }
      final texto = (await archivoTxt.readAsString()).trim();
      final palabras = conPalabras && await archivoTsv.exists()
          ? _parsearTsv(await archivoTsv.readAsString())
          : const <PalabraOcr>[];
      return ResultadoOcr(texto, palabras);
    } finally {
      if (await archivoTxt.exists()) await archivoTxt.delete();
      if (await archivoTsv.exists()) await archivoTsv.delete();
    }
  }

  static List<PalabraOcr> _parsearTsv(String tsv) {
    final palabras = <PalabraOcr>[];
    final lineas = tsv.split(RegExp(r'\r?\n'));
    for (var i = 1; i < lineas.length; i++) {
      final c = lineas[i].split('\t');
      if (c.length < 12) continue;
      if (c[0] != '5') continue; // nivel palabra
      final texto = c.sublist(11).join('\t').trim();
      if (texto.isEmpty) continue;
      palabras.add(PalabraOcr(
        izquierda: int.tryParse(c[6]) ?? 0,
        arriba: int.tryParse(c[7]) ?? 0,
        ancho: int.tryParse(c[8]) ?? 0,
        alto: int.tryParse(c[9]) ?? 0,
        confianza: double.tryParse(c[10]) ?? -1,
        texto: texto,
        bloque: int.tryParse(c[2]) ?? 0,
        parrafo: int.tryParse(c[3]) ?? 0,
        linea: int.tryParse(c[4]) ?? 0,
      ));
    }
    return palabras;
  }
}

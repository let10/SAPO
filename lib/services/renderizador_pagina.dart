import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx_engine/pdfrx_engine.dart';

enum Preproceso {
  /// Sin tratamiento (color original).
  color,

  /// Escala de grises con estiramiento de contraste.
  gris,

  /// Blanco y negro (umbral de Otsu) sobre la imagen en grises.
  binario,
}

/// Zona de la página expresada en fracciones (0..1) del ancho y alto.
class RegionPagina {
  final double izquierda;
  final double arriba;
  final double derecha;
  final double abajo;

  const RegionPagina(this.izquierda, this.arriba, this.derecha, this.abajo);

  static const completa = RegionPagina(0, 0, 1, 1);

  RegionPagina get acotada => RegionPagina(
        izquierda.clamp(0.0, 1.0),
        arriba.clamp(0.0, 1.0),
        derecha.clamp(0.0, 1.0),
        abajo.clamp(0.0, 1.0),
      );

  @override
  String toString() =>
      '[${izquierda.toStringAsFixed(2)},${arriba.toStringAsFixed(2)} → ${derecha.toStringAsFixed(2)},${abajo.toStringAsFixed(2)}]';
}

class ImagenRenderizada {
  final String ruta;
  final int ancho;
  final int alto;

  /// Píxeles blancos agregados alrededor de la imagen (las coordenadas de
  /// Tesseract incluyen este margen).
  final int margen;
  final double escala;
  final RegionPagina region;

  const ImagenRenderizada({
    required this.ruta,
    required this.ancho,
    required this.alto,
    required this.margen,
    required this.escala,
    required this.region,
  });

  int get dpi => (escala * 72).round();

  Future<void> eliminar() async {
    final f = File(ruta);
    if (await f.exists()) await f.delete();
  }
}

class _Entrada {
  final Uint8List bgra;
  final int ancho;
  final int alto;
  final int margen;
  final Preproceso preproceso;

  /// Fila desde la que se borra la tinta azul (null = no se borra).
  final int? quitarAzulDesdeFila;

  _Entrada(this.bgra, this.ancho, this.alto, this.margen, this.preproceso, [this.quitarAzulDesdeFila]);
}

/// Pasa a blanco los píxeles de tinta azul (sellos y firmas con bolígrafo)
/// desde [desdeFila]: sus trazos se cruzan con el texto impreso y el OCR los
/// lee como basura (`> 1 "a` dentro de un nombre). El texto impreso es negro,
/// así que no se pierde.
void _borrarTintaAzul(Uint8List bgra, int ancho, int alto, int desdeFila) {
  for (var y = desdeFila; y < alto; y++) {
    for (var x = 0; x < ancho; x++) {
      final i = (y * ancho + x) * 4;
      final b = bgra[i], g = bgra[i + 1], r = bgra[i + 2];
      final azulidad = b - ((r + g) >> 1);
      // Umbral alto: el texto negro de un escaneo suele tener un tinte azulado
      // leve (azulidad ~30) que no debe borrarse; la tinta de sello o
      // bolígrafo es claramente más azul.
      if (azulidad > 60 && ((r * 299 + g * 587 + b * 114) ~/ 1000) <= 225) {
        bgra[i] = 255;
        bgra[i + 1] = 255;
        bgra[i + 2] = 255;
      }
    }
  }
}

Uint8List _procesarImagen(_Entrada e) {
  final w = e.ancho, h = e.alto, m = e.margen;
  final ancho = w + 2 * m, alto = h + 2 * m;
  final px = e.bgra;
  if (e.quitarAzulDesdeFila != null) _borrarTintaAzul(px, w, h, e.quitarAzulDesdeFila!);

  if (e.preproceso == Preproceso.color) {
    final rgb = Uint8List(ancho * alto * 3)..fillRange(0, ancho * alto * 3, 255);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final o = ((y + m) * ancho + x + m) * 3;
        rgb[o] = px[i + 2];
        rgb[o + 1] = px[i + 1];
        rgb[o + 2] = px[i];
      }
    }
    final imagen = img.Image.fromBytes(width: ancho, height: alto, bytes: rgb.buffer, numChannels: 3);
    return Uint8List.fromList(img.encodePng(imagen, level: 1));
  }

  // Luminancia de la región renderizada
  final lum = Uint8List(w * h);
  final hist = List<int>.filled(256, 0);
  for (var i = 0, j = 0; j < w * h; i += 4, j++) {
    final v = ((px[i + 2] * 299 + px[i + 1] * 587 + px[i] * 114) ~/ 1000);
    lum[j] = v;
    hist[v]++;
  }

  // Estiramiento de contraste entre los percentiles 1 % y 99 %
  final total = w * h;
  var acum = 0, lo = 0, hi = 255;
  for (var v = 0; v < 256; v++) {
    acum += hist[v];
    if (acum >= total * 0.01) {
      lo = v;
      break;
    }
  }
  acum = 0;
  for (var v = 255; v >= 0; v--) {
    acum += hist[v];
    if (acum >= total * 0.01) {
      hi = v;
      break;
    }
  }
  if (hi <= lo) {
    lo = 0;
    hi = 255;
  }
  final rango = hi - lo;
  final estirada = List<int>.filled(256, 0);
  final histEst = List<int>.filled(256, 0);
  for (var v = 0; v < 256; v++) {
    final s = ((v - lo) * 255 ~/ rango).clamp(0, 255);
    estirada[v] = s;
  }
  for (var j = 0; j < total; j++) {
    final s = estirada[lum[j]];
    lum[j] = s;
    histEst[s]++;
  }

  var umbral = -1;
  if (e.preproceso == Preproceso.binario) {
    // Otsu
    var sumaTotal = 0;
    for (var v = 0; v < 256; v++) {
      sumaTotal += v * histEst[v];
    }
    var sumaFondo = 0, pesoFondo = 0;
    double mejor = -1;
    for (var v = 0; v < 256; v++) {
      pesoFondo += histEst[v];
      if (pesoFondo == 0) continue;
      final pesoFrente = total - pesoFondo;
      if (pesoFrente == 0) break;
      sumaFondo += v * histEst[v];
      final mediaFondo = sumaFondo / pesoFondo;
      final mediaFrente = (sumaTotal - sumaFondo) / pesoFrente;
      final varianza = pesoFondo.toDouble() * pesoFrente * (mediaFondo - mediaFrente) * (mediaFondo - mediaFrente);
      if (varianza > mejor) {
        mejor = varianza;
        umbral = v;
      }
    }
  }

  final gris = Uint8List(ancho * alto)..fillRange(0, ancho * alto, 255);
  for (var y = 0; y < h; y++) {
    final base = (y + m) * ancho + m;
    for (var x = 0; x < w; x++) {
      final v = lum[y * w + x];
      gris[base + x] = umbral >= 0 ? (v > umbral ? 255 : 0) : v;
    }
  }
  final imagen = img.Image.fromBytes(width: ancho, height: alto, bytes: gris.buffer, numChannels: 1);
  return Uint8List.fromList(img.encodePng(imagen, level: 1));
}

class RenderizadorPagina {
  static const int margenPx = 24;

  /// Renderiza [region] de [pagina] a [escala] (1.0 = 72 dpi), aplica el
  /// preprocesado y guarda un PNG temporal. Quien lo pida debe llamar a
  /// [ImagenRenderizada.eliminar] al terminar.
  Future<ImagenRenderizada> renderizarAPng(
    PdfPage pagina, {
    RegionPagina region = RegionPagina.completa,
    required double escala,
    Preproceso preproceso = Preproceso.color,
    String etiqueta = 'pg',

    /// Fracción de la altura de la región desde la que se borra la tinta azul
    /// (0 = toda la región, `null` = nunca).
    double? quitarAzulDesde,
  }) async {
    final r = region.acotada;
    final anchoTotal = pagina.width * escala;
    final altoTotal = pagina.height * escala;
    final x = (r.izquierda * anchoTotal).floor();
    final y = (r.arriba * altoTotal).floor();
    final w = ((r.derecha - r.izquierda) * anchoTotal).round().clamp(1, 20000);
    final h = ((r.abajo - r.arriba) * altoTotal).round().clamp(1, 20000);

    final imagenPdf = await pagina.render(
      x: x,
      y: y,
      width: w,
      height: h,
      fullWidth: anchoTotal,
      fullHeight: altoTotal,
      backgroundColor: 0xFFFFFFFF,
    );
    if (imagenPdf == null) {
      throw Exception('No se pudo renderizar la página ${pagina.pageNumber}');
    }

    final Uint8List bgra;
    final int ancho, alto;
    try {
      bgra = Uint8List.fromList(imagenPdf.pixels);
      ancho = imagenPdf.width;
      alto = imagenPdf.height;
    } finally {
      imagenPdf.dispose();
    }

    final entrada = _Entrada(bgra, ancho, alto, margenPx, preproceso,
        quitarAzulDesde == null ? null : (quitarAzulDesde * alto).round().clamp(0, alto));
    final bytesPng = await Isolate.run(() => _procesarImagen(entrada));

    final nombre = 'mdp_${etiqueta}_${DateTime.now().microsecondsSinceEpoch}.png';
    final archivo = File(p.join(Directory.systemTemp.path, nombre));
    await archivo.writeAsBytes(bytesPng);

    return ImagenRenderizada(
      ruta: archivo.path,
      ancho: ancho,
      alto: alto,
      margen: margenPx,
      escala: escala,
      region: r,
    );
  }

  /// Renderiza [region] de [pagina] y devuelve directamente los píxeles en
  /// escala de grises (0-255, con estiramiento de contraste, sin binarizar ni
  /// pasar por disco). Pensado para recortes pequeños, como los dígitos que
  /// lee [RedDigitos].
  Future<ImagenGris> renderizarGrisado(
    PdfPage pagina, {
    required RegionPagina region,
    required double escala,
  }) async {
    final r = region.acotada;
    final anchoTotal = pagina.width * escala;
    final altoTotal = pagina.height * escala;
    final x = (r.izquierda * anchoTotal).floor();
    final y = (r.arriba * altoTotal).floor();
    final w = ((r.derecha - r.izquierda) * anchoTotal).round().clamp(1, 20000);
    final h = ((r.abajo - r.arriba) * altoTotal).round().clamp(1, 20000);

    final imagenPdf = await pagina.render(
      x: x,
      y: y,
      width: w,
      height: h,
      fullWidth: anchoTotal,
      fullHeight: altoTotal,
      backgroundColor: 0xFFFFFFFF,
    );
    if (imagenPdf == null) {
      throw Exception('No se pudo renderizar la página ${pagina.pageNumber}');
    }

    final Uint8List bgra;
    final int ancho, alto;
    try {
      bgra = Uint8List.fromList(imagenPdf.pixels);
      ancho = imagenPdf.width;
      alto = imagenPdf.height;
    } finally {
      imagenPdf.dispose();
    }

    final gris = await Isolate.run(() => _aGrisConContraste(bgra, ancho, alto));
    return ImagenGris(pixeles: gris, ancho: ancho, alto: alto);
  }

  /// Renderiza [region] de [pagina] en color (RGB, sin preprocesar ni pasar por
  /// disco). La separación por color de la tinta (bolígrafo azul frente al
  /// texto impreso en negro) necesita los tres canales.
  Future<ImagenColor> renderizarColor(
    PdfPage pagina, {
    required RegionPagina region,
    required double escala,
  }) async {
    final r = region.acotada;
    final anchoTotal = pagina.width * escala;
    final altoTotal = pagina.height * escala;
    final x = (r.izquierda * anchoTotal).floor();
    final y = (r.arriba * altoTotal).floor();
    final w = ((r.derecha - r.izquierda) * anchoTotal).round().clamp(1, 20000);
    final h = ((r.abajo - r.arriba) * altoTotal).round().clamp(1, 20000);

    final imagenPdf = await pagina.render(
      x: x,
      y: y,
      width: w,
      height: h,
      fullWidth: anchoTotal,
      fullHeight: altoTotal,
      backgroundColor: 0xFFFFFFFF,
    );
    if (imagenPdf == null) {
      throw Exception('No se pudo renderizar la página ${pagina.pageNumber}');
    }

    try {
      final bgra = imagenPdf.pixels;
      final ancho = imagenPdf.width, alto = imagenPdf.height;
      final rgb = Uint8List(ancho * alto * 3);
      for (var i = 0, o = 0; o < rgb.length; i += 4, o += 3) {
        rgb[o] = bgra[i + 2];
        rgb[o + 1] = bgra[i + 1];
        rgb[o + 2] = bgra[i];
      }
      return ImagenColor(rgb: rgb, ancho: ancho, alto: alto);
    } finally {
      imagenPdf.dispose();
    }
  }
}

/// Píxeles en escala de grises (0 = negro, 255 = blanco), fila por fila.
class ImagenGris {
  final Uint8List pixeles;
  final int ancho;
  final int alto;

  const ImagenGris({required this.pixeles, required this.ancho, required this.alto});
}

/// Píxeles RGB (3 bytes por píxel), fila por fila.
class ImagenColor {
  final Uint8List rgb;
  final int ancho;
  final int alto;

  const ImagenColor({required this.rgb, required this.ancho, required this.alto});
}

/// Misma luminancia + estiramiento de contraste que usa [_procesarImagen],
/// pero sin binarizar ni componer el margen: solo los píxeles en gris.
Uint8List _aGrisConContraste(Uint8List bgra, int ancho, int alto) {
  final total = ancho * alto;
  final lum = Uint8List(total);
  final hist = List<int>.filled(256, 0);
  for (var i = 0, j = 0; j < total; i += 4, j++) {
    final v = ((bgra[i + 2] * 299 + bgra[i + 1] * 587 + bgra[i] * 114) ~/ 1000);
    lum[j] = v;
    hist[v]++;
  }

  var acum = 0, lo = 0, hi = 255;
  for (var v = 0; v < 256; v++) {
    acum += hist[v];
    if (acum >= total * 0.01) {
      lo = v;
      break;
    }
  }
  acum = 0;
  for (var v = 255; v >= 0; v--) {
    acum += hist[v];
    if (acum >= total * 0.01) {
      hi = v;
      break;
    }
  }
  if (hi <= lo) {
    lo = 0;
    hi = 255;
  }
  final rango = hi - lo;
  for (var j = 0; j < total; j++) {
    lum[j] = ((lum[j] - lo) * 255 ~/ rango).clamp(0, 255);
  }
  return lum;
}

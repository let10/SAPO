import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../../utils/texto_utils.dart';
import '../ia/red_digitos.dart';
import '../ia/redes_dominio.dart';
import '../ia/segmentador_componentes.dart';
import '../ia/separador_tinta.dart';
import '../ocr_service.dart';
import '../renderizador_pagina.dart';
import 'consolidador_encabezado.dart';
import 'extractor_fecha.dart';

/// Recibe las lecturas obtenidas hasta ahora por el OCR focalizado y decide si
/// ya alcanzan para dar por resueltos el número y la fecha.
typedef EsSuficiente = bool Function(List<LecturaTexto> lecturasFocalizadas);

class _Paso {
  final RegionPagina region;
  final double escala;
  final Preproceso preproceso;
  final int psm;

  const _Paso(this.region, this.escala, this.preproceso, this.psm);

  @override
  String toString() =>
      '$region x${escala.toStringAsFixed(1)} ${preproceso.name} psm$psm';
}

class _LineaOcr {
  final List<PalabraOcr> palabras;
  final String texto;

  /// Caja de la línea en fracciones de la página.
  final RegionPagina caja;

  _LineaOcr(this.palabras, this.texto, this.caja);
}

class _Ancla {
  final _LineaOcr linea;
  final ImagenRenderizada imagen;
  _Ancla(this.linea, this.imagen);
}

/// OCR focalizado sobre el encabezado de la primera página: lo relee a mayor
/// resolución, con distintos preprocesados y modos de segmentación, y vuelve a
/// leer por separado las líneas que contienen el código y la fecha.
class OcrFocalizado {
  final OcrService _ocr;
  final RenderizadorPagina _render;

  /// Redes neuronales propias que leen el número manuscrito y el día del sello
  /// separando la tinta por color. Son opcionales: si no se pudieron cargar,
  /// el OCR focalizado funciona igual, solo que sin esas lecturas.
  final RedesDominio? redes;

  OcrFocalizado({OcrService? ocr, RenderizadorPagina? render, this.redes})
    : _ocr = ocr ?? OcrService(),
      _render = render ?? RenderizadorPagina();

  static const List<_Paso> _barrido = [
    _Paso(RegionPagina(0, 0, 1, 0.40), 3.5, Preproceso.gris, 6),
    _Paso(RegionPagina(0, 0, 1, 0.40), 3.5, Preproceso.binario, 6),
    _Paso(RegionPagina(0, 0, 1, 0.40), 3.5, Preproceso.gris, 11),
    _Paso(RegionPagina(0, 0, 1, 0.55), 4.5, Preproceso.binario, 4),
  ];

  static const List<(double, Preproceso)> _variantesBanda = [
    (6.0, Preproceso.gris),
    (6.0, Preproceso.binario),
    (8.0, Preproceso.gris),
    (8.0, Preproceso.binario),
  ];

  final RegExp _anclaNumeroRe = RegExp(
    r"N(?:O\.?|[°º*%'`´.]{1,2}|\W{0,2})\s*[0-9OIL|]{1,4}\s*[-–—]\s*[2Z][0-9OQ]{3}",
  );
  final RegExp _finEncabezadoRe = RegExp(
    r'(?<![A-Z])(?:VISTOS?|CONSIDERANDO)(?![A-Z])',
  );
  final RegExp _simboloNRe = RegExp(
    r"^(?:N[A-Z°º*%'`´.¡“”"
    '"'
    r"]{0,2}\.?|№)$",
  );
  final RegExp _prefijoNRe = RegExp(r"^(?:NO\.|NO(?=\d)|N[°º*%'`´.]{1,2})");

  Future<ResultadoOcr> _leer(
    PdfPage pagina,
    RegionPagina region,
    double escala,
    Preproceso pre, {
    required int psm,
    bool soloDigitos = false,
    bool conPalabras = false,
    required String etiqueta,
    void Function(ImagenRenderizada)? alTerminar,
  }) async {
    final imagen = await _render.renderizarAPng(
      pagina,
      region: region,
      escala: escala,
      preproceso: pre,
      etiqueta: etiqueta,
    );
    try {
      final r = await _ocr.reconocer(
        imagen.ruta,
        psm: psm,
        dpi: imagen.dpi,
        soloDigitos: soloDigitos,
        conPalabras: conPalabras,
      );
      alTerminar?.call(imagen);
      return r;
    } finally {
      await imagen.eliminar();
    }
  }

  Future<List<LecturaTexto>> leerEncabezado(
    PdfPage pagina, {
    required EsSuficiente esSuficiente,
    void Function(String)? progreso,
  }) async {
    final lecturas = <LecturaTexto>[];
    final anclasNumero = <_Ancla>[];
    final anclasFecha = <_Ancla>[];
    var numeroLeidoPorRed = false, selloLeidoPorRed = false;

    // Etapa 1: barrido del encabezado completo. En cuanto un barrido localiza
    // la zona del número o la del sello, las redes neuronales los leen (es
    // barato y no depende de más pasadas de OCR).
    for (var i = 0; i < _barrido.length; i++) {
      final paso = _barrido[i];
      progreso?.call(
        'OCR focalizado del encabezado (${i + 1}/${_barrido.length})',
      );
      ImagenRenderizada? usada;
      final r = await _leer(
        pagina,
        paso.region,
        paso.escala,
        paso.preproceso,
        psm: paso.psm,
        conPalabras: true,
        etiqueta: 'enc',
        alTerminar: (im) => usada = im,
      );
      lecturas.add(
        LecturaTexto(
          r.texto,
          OrigenLectura.ocrFocalizado,
          config: 'barrido $paso',
        ),
      );
      if (usada != null) {
        _recolectarAnclas(r.palabras, usada!, anclasNumero, anclasFecha);
      }
      if (redes != null) {
        final zonas = _zonasDeAnclas(anclasNumero, anclasFecha);
        if (!numeroLeidoPorRed && zonas.numero != null) {
          numeroLeidoPorRed = true;
          progreso?.call('Red neuronal: número manuscrito');
          lecturas.add(await _leerNumeroConRed(pagina, zonas.numero!));
        }
        if (!selloLeidoPorRed && zonas.sello != null) {
          selloLeidoPorRed = true;
          progreso?.call('Red neuronal: sello de la fecha');
          lecturas.add(await _leerSelloConRed(pagina, zonas.sello!));
        }
      }
      if (esSuficiente(lecturas)) return lecturas;
    }

    // Etapa 2: releer a mayor resolución solo las líneas del código y de la fecha.
    for (final tipo in [('código', anclasNumero), ('fecha', anclasFecha)]) {
      for (final ancla in tipo.$2.take(2)) {
        progreso?.call('OCR focalizado de la línea de ${tipo.$1}');
        for (final (escala, pre) in _variantesBanda) {
          final r = await _leer(
            pagina,
            _banda(ancla.linea.caja),
            escala,
            pre,
            psm: 7,
            etiqueta: 'lin',
          );
          lecturas.add(
            LecturaTexto(
              r.texto,
              OrigenLectura.ocrFocalizado,
              config: 'línea ${tipo.$1} x$escala ${pre.name}',
            ),
          );
          if (esSuficiente(lecturas)) return lecturas;
        }
      }
    }

    // Etapa 3: la zona del número, forzada a dígitos (solo sirve de apoyo).
    for (final ancla in anclasNumero.take(2)) {
      final zona = _zonaDigitos(ancla);
      if (zona == null) continue;
      progreso?.call('OCR focalizado del número');
      for (final (escala, pre) in [
        (8.0, Preproceso.gris),
        (8.0, Preproceso.binario),
      ]) {
        for (final psm in [7, 8]) {
          final r = await _leer(
            pagina,
            zona,
            escala,
            pre,
            psm: psm,
            soloDigitos: true,
            etiqueta: 'num',
          );
          lecturas.add(
            LecturaTexto(
              r.texto,
              OrigenLectura.ocrSoloDigitos,
              config: 'dígitos x$escala ${pre.name} psm$psm',
            ),
          );
          if (esSuficiente(lecturas)) return lecturas;
        }
      }
    }
    return lecturas;
  }

  void _recolectarAnclas(
    List<PalabraOcr> palabras,
    ImagenRenderizada imagen,
    List<_Ancla> anclasNumero,
    List<_Ancla> anclasFecha,
  ) {
    final lineas = _lineas(palabras, imagen);
    // Todo lo que está desde "VISTOS"/"CONSIDERANDO" hacia abajo cita otros
    // documentos (con sus propios códigos y fechas): no puede ser ancla.
    double? limite;
    for (final l in lineas) {
      if (_esFinEncabezado(l)) {
        if (limite == null || l.caja.arriba < limite) limite = l.caja.arriba;
      }
    }
    for (final l in lineas) {
      if (limite != null && l.caja.abajo > limite + 0.002) continue;
      if (_esAnclaNumero(l.texto)) {
        _agregarAncla(anclasNumero, _Ancla(l, imagen));
      }
      if (_esAnclaFecha(l.texto)) {
        _agregarAncla(anclasFecha, _Ancla(l, imagen));
      }
    }
  }

  /// Localiza con un solo barrido de OCR las zonas del encabezado donde van el
  /// número (escrito a mano) y el sello de la fecha. Sirve a las herramientas
  /// de diagnóstico y de armado del conjunto de entrenamiento.
  Future<ZonasEncabezado> localizarZonas(PdfPage pagina) async {
    final paso = _barrido.first;
    ImagenRenderizada? usada;
    final r = await _leer(
      pagina,
      paso.region,
      paso.escala,
      paso.preproceso,
      psm: paso.psm,
      conPalabras: true,
      etiqueta: 'zon',
      alTerminar: (im) => usada = im,
    );
    final anclasNumero = <_Ancla>[];
    final anclasFecha = <_Ancla>[];
    if (usada != null) {
      _recolectarAnclas(r.palabras, usada!, anclasNumero, anclasFecha);
    }
    return _zonasDeAnclas(anclasNumero, anclasFecha);
  }

  ZonasEncabezado _zonasDeAnclas(
    List<_Ancla> anclasNumero,
    List<_Ancla> anclasFecha,
  ) {
    RegionPagina? numero;
    for (final a in anclasNumero) {
      numero = _zonaNumeroTinta(a);
      if (numero != null) break;
    }
    RegionPagina? sello;
    for (final a in anclasFecha) {
      sello = _zonaSello(a);
      if (sello != null) break;
    }
    return ZonasEncabezado(numero: numero, sello: sello);
  }

  /// Lee el número manuscrito: aísla la tinta azul de la zona del número, la
  /// separa en tres dígitos y los clasifica con la red de números. Siempre
  /// devuelve una lectura; si no pudo leer, el texto queda vacío y [config]
  /// dice por qué (se ve con `--diag`).
  Future<LecturaTexto> _leerNumeroConRed(
    PdfPage pagina,
    RegionPagina zona,
  ) async {
    try {
      final color = await _render.renderizarColor(
        pagina,
        region: zona,
        escala: 8.0,
      );
      final tinta = SeparadorTinta.tintaAzul(color);
      final digitos = SegmentadorComponentes.segmentar(
        tinta,
        cantidadEsperada: 3,
      );
      if (digitos.length != 3) {
        return LecturaTexto(
          '',
          OrigenLectura.redNeuronal,
          config:
              'red de números: ${digitos.length} manchas de tinta azul (se esperaban 3: número impreso o ilegible)',
        );
      }
      return _clasificar(
        redes!.numero,
        digitos,
        OrigenLectura.redNeuronal,
        'red de números (3 dígitos)',
      );
    } catch (e) {
      return LecturaTexto(
        '',
        OrigenLectura.redNeuronal,
        config: 'red de números: error: $e',
      );
    }
  }

  /// Lee el día del sello: separa los dígitos de la zona del sello y clasifica
  /// los dos primeros (el día) con la red del sello. El mes y el año los sigue
  /// leyendo el OCR.
  Future<LecturaTexto> _leerSelloConRed(
    PdfPage pagina,
    RegionPagina zona,
  ) async {
    try {
      final color = await _render.renderizarColor(
        pagina,
        region: zona,
        escala: 8.0,
      );
      final tinta = SeparadorTinta.tintaOscura(color);
      final manchas = SegmentadorComponentes.segmentar(tinta);
      // Un sello tiene unas 9-10 manchas (día, mes y año); con muchas más es
      // una fecha mecanografiada, que Tesseract ya lee bien.
      if (manchas.length < 3 || manchas.length > 11) {
        return LecturaTexto(
          '',
          OrigenLectura.redSello,
          config:
              'red del sello: ${manchas.length} manchas (no parece un sello de fecha)',
        );
      }
      return _clasificar(
        redes!.sello,
        manchas.take(2).toList(),
        OrigenLectura.redSello,
        'red del sello (día, ${manchas.length} manchas)',
      );
    } catch (e) {
      return LecturaTexto(
        '',
        OrigenLectura.redSello,
        config: 'red del sello: error: $e',
      );
    }
  }

  LecturaTexto _clasificar(
    RedDigitos red,
    List<DigitoSegmentado> digitos,
    OrigenLectura origen,
    String config,
  ) {
    final sb = StringBuffer();
    final probabilidades = <List<double>>[];
    for (final d in digitos) {
      final p = red.reconocer(d.patch);
      var mejor = 0;
      for (var i = 1; i < p.length; i++) {
        if (p[i] > p[mejor]) mejor = i;
      }
      sb.write(mejor);
      probabilidades.add(p.toList());
    }
    return LecturaTexto(
      sb.toString(),
      origen,
      config: config,
      probabilidades: probabilidades,
    );
  }

  final RegExp _citaRe = RegExp(
    r'INFORME|OFICIO|MEMORANDO|SOLICITUD|DE FECHA|PROVEIDO|EXPEDIENTE|CARTA N',
  );

  /// "VISTOS", "VISTO" o "CONSIDERANDO" (aunque un sello tape alguna letra).
  bool _esFinEncabezado(_LineaOcr linea) {
    final n = normalizarParaBusqueda(linea.texto);
    if (_finEncabezadoRe.hasMatch(n)) return true;
    final primera = normalizarParaBusqueda(linea.palabras.first.texto)
        .replaceAll(RegExp(r'[^A-Z]'), '');
    if (primera.length < 4) return false;
    return distanciaLevenshtein(primera, 'VISTOS', maximo: 1) <= 1 ||
        distanciaLevenshtein(primera, 'VISTO', maximo: 1) <= 1 ||
        distanciaLevenshtein(primera, 'CONSIDERANDO', maximo: 2) <= 2;
  }

  bool _esAnclaNumero(String texto) {
    final n = normalizarParaBusqueda(texto);
    if (_citaRe.hasMatch(n)) return false;
    return n.contains('MDP') || _anclaNumeroRe.hasMatch(n);
  }

  bool _esAnclaFecha(String texto) {
    final n = normalizarParaBusqueda(texto);
    if (_citaRe.hasMatch(n)) return false;
    return ExtractorFecha.contieneMes(texto) || n.contains('POCOLLAY,');
  }

  void _agregarAncla(List<_Ancla> lista, _Ancla nueva) {
    for (final a in lista) {
      if (_solapamientoVertical(a.linea.caja, nueva.linea.caja) > 0.5) return;
    }
    lista.add(nueva);
  }

  double _solapamientoVertical(RegionPagina a, RegionPagina b) {
    final ini = a.arriba > b.arriba ? a.arriba : b.arriba;
    final fin = a.abajo < b.abajo ? a.abajo : b.abajo;
    final inter = fin - ini;
    if (inter <= 0) return 0;
    final menor = (a.abajo - a.arriba) < (b.abajo - b.arriba)
        ? (a.abajo - a.arriba)
        : (b.abajo - b.arriba);
    return menor <= 0 ? 0 : inter / menor;
  }

  RegionPagina _banda(RegionPagina caja) {
    final alto = caja.abajo - caja.arriba;
    return RegionPagina(
      caja.izquierda - 0.03,
      caja.arriba - 0.35 * alto,
      caja.derecha + 0.03,
      caja.abajo + 0.35 * alto,
    );
  }

  double _fx(int px, ImagenRenderizada im) =>
      im.region.izquierda +
      ((px - im.margen) / im.ancho) * (im.region.derecha - im.region.izquierda);

  double _fy(int py, ImagenRenderizada im) =>
      im.region.arriba +
      ((py - im.margen) / im.alto) * (im.region.abajo - im.region.arriba);

  List<_LineaOcr> _lineas(List<PalabraOcr> palabras, ImagenRenderizada im) {
    final grupos = <String, List<PalabraOcr>>{};
    for (final p in palabras) {
      grupos
          .putIfAbsent('${p.bloque}.${p.parrafo}.${p.linea}', () => [])
          .add(p);
    }
    final lineas = <_LineaOcr>[];
    for (final g in grupos.values) {
      g.sort((a, b) => a.izquierda.compareTo(b.izquierda));
      var izq = g.first.izquierda, arr = g.first.arriba;
      var der = 0, aba = 0;
      for (final p in g) {
        if (p.izquierda < izq) izq = p.izquierda;
        if (p.arriba < arr) arr = p.arriba;
        if (p.izquierda + p.ancho > der) der = p.izquierda + p.ancho;
        if (p.arriba + p.alto > aba) aba = p.arriba + p.alto;
      }
      lineas.add(
        _LineaOcr(
          g,
          g.map((p) => p.texto).join(' '),
          RegionPagina(_fx(izq, im), _fy(arr, im), _fx(der, im), _fy(aba, im)),
        ),
      );
    }
    return lineas;
  }

  /// Zona de la línea del código que contiene el número (entre el símbolo N°
  /// y el primer guion), para releerla forzando dígitos.
  RegionPagina? _zonaDigitos(_Ancla ancla) {
    final l = _limitesNumero(ancla);
    if (l == null) return null;
    final margenX = (l.guion.alto * 0.25).round();
    final margenY = (l.guion.alto * 0.5).round();
    return RegionPagina(
      _fx(l.izq - margenX, l.im),
      _fy(l.guion.arriba - margenY, l.im),
      _fx(l.der + margenX, l.im),
      _fy(l.guion.arriba + l.guion.alto + margenY, l.im),
    );
  }

  /// Zona del número escrito a mano, para leerlo por color de tinta. La letra
  /// manuscrita sobresale de la línea impresa (los números son más altos que
  /// el texto de al lado), así que el margen vertical es mayor; el texto
  /// impreso que entre en la zona no importa, porque no es tinta azul.
  RegionPagina? _zonaNumeroTinta(_Ancla ancla) {
    final l = _limitesNumero(ancla);
    if (l == null) return null;
    final alto = l.guion.alto;
    return RegionPagina(
      _fx(l.izq - (alto * 0.3).round(), l.im),
      _fy(l.guion.arriba - (alto * 1.4).round(), l.im),
      _fx(l.der + (alto * 0.6).round(), l.im),
      _fy(l.guion.arriba + alto + (alto * 0.7).round(), l.im),
    );
  }

  /// Zona del sello de la fecha: a la derecha de "Pocollay," en su misma línea.
  RegionPagina? _zonaSello(_Ancla ancla) {
    final palabras = ancla.linea.palabras;
    final k = palabras.indexWhere((p) {
      final t = normalizarParaBusqueda(p.texto)
          .replaceAll(RegExp(r'[^A-Z]'), '');
      return t.length >= 6 &&
          distanciaLevenshtein(t, 'POCOLLAY', maximo: 2) <= 2;
    });
    if (k < 0) return null;
    final im = ancla.imagen;
    final pocollay = palabras[k];
    final alto = pocollay.alto;
    final izq = pocollay.izquierda + pocollay.ancho + (alto * 0.4).round();
    var derLinea = izq;
    for (final p in palabras) {
      if (p.izquierda + p.ancho > derLinea) derLinea = p.izquierda + p.ancho;
    }
    final derMinima = izq + (im.ancho * 0.2).round();
    final der = (derLinea + alto > derMinima ? derLinea + alto : derMinima);
    return RegionPagina(
      _fx(izq, im),
      _fy(pocollay.arriba - (alto * 0.9).round(), im),
      _fx(der, im),
      _fy(pocollay.arriba + alto + (alto * 0.9).round(), im),
    );
  }

  ({int izq, int der, PalabraOcr guion, ImagenRenderizada im})? _limitesNumero(
    _Ancla ancla,
  ) {
    final palabras = ancla.linea.palabras;
    final k = palabras.indexWhere((p) => RegExp(r'[-–—]').hasMatch(p.texto));
    if (k < 0) return null;
    final im = ancla.imagen;
    final palabraGuion = palabras[k];
    final texto = palabraGuion.texto;
    final posGuion = texto.indexOf(RegExp(r'[-–—]'));
    final prefijo = _prefijoNRe.firstMatch(normalizarParaBusqueda(texto));
    final inicioEnPalabra = prefijo?.end ?? 0;

    final porCaracter = palabraGuion.ancho / (texto.isEmpty ? 1 : texto.length);
    var izq = palabraGuion.izquierda + (porCaracter * inicioEnPalabra).round();
    final der = palabraGuion.izquierda + (porCaracter * posGuion).round();

    if (inicioEnPalabra == 0) {
      for (var j = k - 1; j >= 0; j--) {
        final t = normalizarParaBusqueda(palabras[j].texto);
        if (_simboloNRe.hasMatch(t)) {
          // El número ocupa todo el hueco entre el símbolo N° y el guion: la
          // escritura a mano suele ser más ancha que lo que Tesseract delimita.
          izq = palabras[j].izquierda + palabras[j].ancho;
          break;
        }
        if (RegExp(r'^[A-Z]{4,}$').hasMatch(t)) break;
        izq = palabras[j].izquierda;
      }
    } else {
      // El prefijo "N°"/"N*" va pegado al número en el mismo token de OCR
      // (p. ej. "N°146-2026"). Repartir el ancho del token en partes iguales
      // por carácter asume que el símbolo "N°" ocupa lo mismo que un dígito,
      // pero el símbolo es más angosto que un dígito manuscrito: el corte
      // estimado queda desplazado hacia la derecha y puede recortar el primer
      // dígito (caso real observado: solo se segmentó 1 de 3 dígitos). Se
      // retrocede un carácter de margen para compensar ese sesgo.
      izq -= porCaracter.round();
    }
    if (der - izq < 8) return null;
    return (izq: izq, der: der, guion: palabraGuion, im: im);
  }
}

/// Zonas del encabezado de la primera página, en fracciones de la página.
class ZonasEncabezado {
  /// Donde está escrito a mano el número de la resolución.
  final RegionPagina? numero;

  /// Donde está el sello con la fecha (a la derecha de "Pocollay,").
  final RegionPagina? sello;

  const ZonasEncabezado({this.numero, this.sello});
}

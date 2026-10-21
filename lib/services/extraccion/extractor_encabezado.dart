import '../../utils/texto_utils.dart';
import 'catalogo_resoluciones.dart';
import 'normalizador_numero.dart';
import 'normalizador_siglas.dart';

/// Lectura del código `N° NNN-AAAA-SIGLAS` encontrada en un texto.
class CandidatoEncabezado {
  /// Texto leído para el número (antes de normalizar), p. ej. `O+4`.
  final String numeroCrudo;

  /// Dígitos del número tal como se leyeron/repararon, sin rellenar a tres cifras.
  final String? numero;
  final bool numeroReparado;

  /// Si la lectura es ambigua (`N148`: ¿148 o 48?), la otra interpretación.
  final String? numeroAlternativo;

  final String? anio;
  final bool anioReparado;

  /// Siglas normalizadas (`A-MDP-T`).
  final String siglas;
  final bool siglasConocidas;
  final bool siglasAproximadas;

  const CandidatoEncabezado({
    required this.numeroCrudo,
    required this.numero,
    required this.numeroReparado,
    this.numeroAlternativo,
    required this.anio,
    required this.anioReparado,
    required this.siglas,
    required this.siglasConocidas,
    required this.siglasAproximadas,
  });

  TipoResolucion? get tipoPorSiglas => CatalogoResoluciones.porSiglas(siglas);

  bool get limpio =>
      numero != null &&
      anio != null &&
      !numeroReparado &&
      !anioReparado &&
      siglasConocidas &&
      !siglasAproximadas;
}

class ExtractorEncabezado {
  static const String _sep = r'[-–—‐]';

  static final RegExp _anclaRe = RegExp(
    r'(?<![A-Z0-9])(?<pre>[^\n]{0,18}?)\s*' +
        _sep +
        r'\s*(?<anio>[2Z][0OQ][0-9OQIZ|]{2})\s*' +
        _sep +
        r'\s*(?<sig>[A-Z]{1,8}(?:\s?[-–—‐/]\s?[A-Z]{1,8}){0,3}?\s?[-–—‐/]\s?M[DO]P\s?[-–—‐/\\]\s?[TI1L])(?![A-Z])',
  );

  /// Decreto `007-2025-MDP-T` u ordenanza `003-2025-MDP`. Exige que MDP siga
  /// al año: así no toma la cola de `074-2026-A-MDP-T` ni de `019-2025-CM-MDP-T`.
  static final RegExp _anclaMdpRe = RegExp(
    r'(?<![A-Z0-9])(?<pre>[^\n]{0,24}?)\s*' +
        _sep +
        r'\s*(?<anio>[2Z][0OQ][0-9OQIZ|]{2})\s*' +
        _sep +
        r'\s*(?<sig>M[DO]P(?:\s*' +
        _sep +
        r'\s*[TI1L])?)(?![A-Z0-9])',
  );

  /// Símbolo `N°` suelto, con las deformaciones habituales del OCR: `N°`, `N*`,
  /// `N%`, `No.`, `NE`, `NS`, `N“`…
  static final RegExp _simboloN = RegExp(
    r"^(?:N[A-Z°º*%'`´.¡“”"
    '"'
    r"]{0,2}\.?|№)$",
  );

  static final RegExp _prefijoN = RegExp(
    r"^N[°º*%'`´.¡“”"
    '"'
    r"]{1,2}(.+)$",
  );

  /// `N` seguida de una letra ruidosa y los dígitos (`NE48`, `NS48`, `NT48`).
  static final RegExp _prefijoNConLetra = RegExp(r'^N[A-Z](\d{1,5})$');

  /// `No.` o `NO.` pegado al número (`No.117`, `NO.O+4`). El texto ya está en mayúsculas.
  static final RegExp _prefijoNoPunto = RegExp(r'^NO\.(.+)$');

  /// `N148`: el símbolo `°` se leyó como dígito; es ambiguo (¿148 o 48?).
  static final RegExp _prefijoNPegado = RegExp(r'^N(\d{2,5})$');

  /// Parte del texto de la primera página que corresponde al encabezado:
  /// hasta VISTO/CONSIDERANDO (donde se citan otras resoluciones) o, en su
  /// defecto, los primeros caracteres.
  static String seccionEncabezado(String texto, {int maximo = 1500}) {
    final norm = normalizarParaBusqueda(texto);
    final m = RegExp(r'(?<![A-Z])(?:VISTOS?|CONSIDERANDO)(?![A-Z])')
        .firstMatch(norm);
    var fin = m == null ? texto.length : m.start;
    if (fin > maximo) fin = maximo;
    return texto.substring(0, fin);
  }

  /// Parte del encabezado donde puede estar el código de la resolución: hasta la
  /// línea "Pocollay," con la fecha (lo que sigue son considerandos y citas).
  static String seccionCodigo(String texto) {
    final seccion = seccionEncabezado(texto);
    final m = RegExp(r'POCOLLAY\s*[,;:]')
        .firstMatch(normalizarParaBusqueda(seccion));
    return m == null ? seccion : seccion.substring(0, m.start);
  }

  /// Las páginas de continuación repiten el membrete (logo, lema, título y
  /// código). Quita ese bloque inicial para que un artículo que cruza de página
  /// no quede cortado por él. Solo actúa si el primer código del bloque es el
  /// del propio documento y ningún indicio muestra que sea una cita.
  static String quitarMembrete(String textoPagina, {int ventana = 900}) {
    final norm = normalizarParaBusqueda(textoPagina);
    final limite = norm.length < ventana ? norm.length : ventana;
    final zona = norm.substring(0, limite);
    final coincidencias = <RegExpMatch>[
      ..._anclaRe.allMatches(zona),
      ..._anclaMdpRe.allMatches(zona),
    ]..sort((a, b) => a.start.compareTo(b.start));
    if (coincidencias.isEmpty) return textoPagina;
    final m = coincidencias.first;
    final previo = norm.substring(0, m.start);
    if (RegExp(r'INFORME|OFICIO|DE FECHA|MEMORANDO').hasMatch(previo)) {
      return textoPagina;
    }
    final siglas = NormalizadorSiglas.normalizar(m.namedGroup('sig')!);
    final esDecretoUOrdenanza = siglas == 'MDP' || siglas == 'MDP-T';
    final tituloPropio = esDecretoUOrdenanza
        ? previo.contains('ORDENANZA MUNICIPAL') || previo.contains('DECRETO DE ALCALDIA')
        : previo.contains('RESOLUCION') || previo.contains('ACUERDO DE CONCEJO');
    if (!tituloPropio) return textoPagina;
    return textoPagina.substring(m.end).trimLeft();
  }

  static List<CandidatoEncabezado> extraer(String texto, {int? ahora}) {
    final norm = normalizarParaBusqueda(texto);
    final resultado = <CandidatoEncabezado>[];
    final coincidencias = <RegExpMatch>[
      ..._anclaRe.allMatches(norm),
      ..._anclaMdpRe.allMatches(norm),
    ]..sort((a, b) => a.start.compareTo(b.start));
    var ocupadoHasta = -1;
    for (final m in coincidencias) {
      if (m.start < ocupadoHasta) continue;
      ocupadoHasta = m.end;

      final (numeroCrudo, ambiguo) = _extraerNumeroCrudo(m.namedGroup('pre')!);
      String? numero;
      var numeroReparado = ambiguo;
      if (RegExp(r'^\d{1,4}$').hasMatch(numeroCrudo)) {
        numero = numeroCrudo;
      } else {
        final r = NormalizadorNumero.repararConfundibles(numeroCrudo);
        if (r != null && RegExp(r'^\d{1,4}$').hasMatch(r)) {
          numero = r;
          numeroReparado = true;
        }
      }

      final anioCrudo = m.namedGroup('anio')!;
      String? anio;
      var anioReparado = false;
      final anioDigitos = anioCrudo
          .split('')
          .map(
            (c) => RegExp(r'\d').hasMatch(c)
                ? c
                : switch (c) {
                    'O' || 'Q' => '0',
                    'I' || '|' => '1',
                    'Z' => '2',
                    _ => c,
                  },
          )
          .join();
      if (RegExp(r'^20\d{2}$').hasMatch(anioDigitos) &&
          _anioPlausible(anioDigitos, ahora)) {
        anio = anioDigitos;
        anioReparado = anioDigitos != anioCrudo;
      }

      var siglas = NormalizadorSiglas.normalizar(m.namedGroup('sig')!);
      var conocidas = CatalogoResoluciones.porSiglas(siglas) != null;
      var aproximadas = false;
      if (!conocidas) {
        final aprox = CatalogoResoluciones.porSiglasAproximadas(siglas);
        if (aprox != null) {
          siglas = aprox.siglas;
          conocidas = true;
          aproximadas = true;
        }
      }

      resultado.add(
        CandidatoEncabezado(
          numeroCrudo: numeroCrudo,
          numero: numero,
          numeroReparado: numeroReparado,
          numeroAlternativo: ambiguo && numero != null && numero.length >= 3
              ? numero.substring(1)
              : null,
          anio: anio,
          anioReparado: anioReparado,
          siglas: siglas,
          siglasConocidas: conocidas,
          siglasAproximadas: aproximadas,
        ),
      );
    }
    return resultado;
  }

  static bool _anioPlausible(String anio, int? ahora) {
    final a = int.parse(anio);
    final actual = ahora ?? DateTime.now().year;
    return a >= 2000 && a <= actual + 1;
  }

  /// Toma las últimas "piezas" del texto previo al guion (después del símbolo
  /// `N°` si existe) y las une: `N° 074` → `074`, `N° OY 4` → `OY4`.
  /// Devuelve el texto leído y si la lectura es ambigua (`N148`).
  static (String, bool) _extraerNumeroCrudo(String pre) {
    final piezas = pre
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final tomadas = <String>[];
    var ambiguo = false;
    for (var i = piezas.length - 1; i >= 0 && tomadas.length < 4; i--) {
      final p = piezas[i];
      if (_simboloN.hasMatch(p)) break;
      final conPrefijo = _prefijoN.firstMatch(p);
      if (conPrefijo != null) {
        tomadas.insert(0, conPrefijo.group(1)!);
        break;
      }
      final conLetra = _prefijoNConLetra.firstMatch(p);
      if (conLetra != null) {
        tomadas.insert(0, conLetra.group(1)!);
        break;
      }
      final noPunto = _prefijoNoPunto.firstMatch(p);
      if (noPunto != null) {
        tomadas.insert(0, noPunto.group(1)!);
        break;
      }
      final pegado = _prefijoNPegado.firstMatch(p);
      if (pegado != null) {
        tomadas.insert(0, pegado.group(1)!);
        ambiguo = true;
        break;
      }
      if (RegExp(r'^[A-Z]{4,}$').hasMatch(p)) break;
      if (!RegExp(r'^[0-9A-Z|!+$&%*?.,_]{1,6}$').hasMatch(p)) break;
      tomadas.insert(0, p);
    }
    return (tomadas.join().replaceAll(RegExp(r'[.,_]+$'), ''), ambiguo);
  }

  /// Tipo del documento. El título que va con el código del encabezado manda.
  /// Una denominación que aparece después de ese código (después de "Pocollay,")
  /// es una cita: no cambia el tipo aunque el título propio se haya leído mal.
  static TipoResolucion? tipoPorTexto(String texto) {
    final encabezado = seccionEncabezado(texto);
    final hallado = CatalogoResoluciones.tituloMasTemprano(encabezado);
    final zonaCodigo = seccionCodigo(texto);
    final candidatos = extraer(zonaCodigo);
    final tipoCodigo = candidatos.isEmpty ? null : candidatos.first.tipoPorSiglas;
    if (hallado == null) return tipoCodigo;
    final tipoTexto = hallado.$1;
    if (tipoCodigo == null || tipoTexto.siglas == tipoCodigo.siglas) return tipoTexto;
    final tituloDespuesDelCodigo =
        zonaCodigo.length < encabezado.length && hallado.$2 >= zonaCodigo.length;
    return tituloDespuesDelCodigo ? tipoCodigo : tipoTexto;
  }
}

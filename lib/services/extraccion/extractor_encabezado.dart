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
      numero != null && anio != null && !numeroReparado && !anioReparado && siglasConocidas && !siglasAproximadas;
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

  /// Símbolo `N°` suelto, con las deformaciones habituales del OCR: `N°`, `N*`,
  /// `N%`, `No.`, `NE`, `NS`, `N“`…
  static final RegExp _simboloN = RegExp(r"^(?:N[A-Z°º*%'`´.¡“”" '"' r"]{0,2}\.?|№)$");

  static final RegExp _prefijoN = RegExp(r"^N[°º*%'`´.¡“”" '"' r"]{1,2}(.+)$");

  /// `N` seguida de una letra ruidosa y los dígitos (`NE48`, `NS48`, `NT48`).
  static final RegExp _prefijoNConLetra = RegExp(r'^N[A-Z](\d{1,5})$');

  /// `N148`: el símbolo `°` se leyó como dígito; es ambiguo (¿148 o 48?).
  static final RegExp _prefijoNPegado = RegExp(r'^N(\d{2,5})$');

  /// Parte del texto de la primera página que corresponde al encabezado:
  /// hasta VISTO/CONSIDERANDO (donde se citan otras resoluciones) o, en su
  /// defecto, los primeros caracteres.
  static String seccionEncabezado(String texto, {int maximo = 1500}) {
    final norm = normalizarParaBusqueda(texto);
    final m = RegExp(r'(?<![A-Z])(?:VISTOS?|CONSIDERANDO)(?![A-Z])').firstMatch(norm);
    var fin = m == null ? texto.length : m.start;
    if (fin > maximo) fin = maximo;
    return texto.substring(0, fin);
  }

  /// Parte del encabezado donde puede estar el código de la resolución: hasta la
  /// línea "Pocollay," con la fecha (lo que sigue son considerandos y citas).
  static String seccionCodigo(String texto) {
    final seccion = seccionEncabezado(texto);
    final m = RegExp(r'POCOLLAY\s*[,;:]').firstMatch(normalizarParaBusqueda(seccion));
    return m == null ? seccion : seccion.substring(0, m.start);
  }

  /// Las páginas de continuación repiten el membrete (logo, lema, título y
  /// código). Quita ese bloque inicial para que un artículo que cruza de página
  /// no quede cortado por él. Solo actúa si el bloque contiene el título
  /// "RESOLUCIÓN…" y ningún indicio de documento citado.
  static String quitarMembrete(String textoPagina, {int ventana = 900}) {
    final norm = normalizarParaBusqueda(textoPagina);
    final limite = norm.length < ventana ? norm.length : ventana;
    final m = _anclaRe.allMatches(norm.substring(0, limite)).firstOrNull;
    if (m == null) return textoPagina;
    final previo = norm.substring(0, m.start);
    if (!previo.contains('RESOLUCION') || RegExp(r'INFORME|OFICIO|DE FECHA|MEMORANDO').hasMatch(previo)) {
      return textoPagina;
    }
    return textoPagina.substring(m.end).trimLeft();
  }

  static List<CandidatoEncabezado> extraer(String texto, {int? ahora}) {
    final norm = normalizarParaBusqueda(texto);
    final resultado = <CandidatoEncabezado>[];

    var desde = 0;
    while (desde <= norm.length) {
      final m = _anclaRe.allMatches(norm, desde).firstOrNull;
      if (m == null) break;

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
      final anioDigitos = anioCrudo.split('').map((c) => RegExp(r'\d').hasMatch(c)
          ? c
          : switch (c) { 'O' || 'Q' => '0', 'I' || '|' => '1', 'Z' => '2', _ => c }).join();
      if (RegExp(r'^20\d{2}$').hasMatch(anioDigitos) && _anioPlausible(anioDigitos, ahora)) {
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

      resultado.add(CandidatoEncabezado(
        numeroCrudo: numeroCrudo,
        numero: numero,
        numeroReparado: numeroReparado,
        numeroAlternativo:
            ambiguo && numero != null && numero.length >= 3 ? numero.substring(1) : null,
        anio: anio,
        anioReparado: anioReparado,
        siglas: siglas,
        siglasConocidas: conocidas,
        siglasAproximadas: aproximadas,
      ));

      if (m.end <= desde) break;
      desde = m.end;
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
    final piezas = pre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
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

  /// Tipo de resolución según la denominación escrita en el encabezado.
  static TipoResolucion? tipoPorTexto(String textoEncabezado) =>
      CatalogoResoluciones.porTexto(textoEncabezado);
}

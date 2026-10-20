import '../../utils/texto_utils.dart';

class CandidatoFecha {
  /// Fragmento del texto del que salió, tal como se leyó.
  final String crudo;
  final int? dia;
  final int? mes;
  final int? anio;
  final bool valida;
  final String motivo;

  /// `true` si hubo que ignorar espacios dentro del año (p. ej. `2 0 2 6`), es
  /// decir, la lectura no era limpia.
  final bool conEspaciosInternos;

  /// Cuando día y mes son válidos pero el año leído difiere en un solo dígito
  /// del año del código (típico: `2076` en lugar de `2026`), fecha propuesta con
  /// el año del código. Nunca se usa como dato confirmado: solo como sugerencia.
  final String sugerida;

  /// Aparece justo después de `Pocollay,` (lugar y fecha del documento).
  final bool datadoEnLugar;

  /// Va precedida de "de fecha": es la fecha de otro documento citado.
  final bool pareceCitada;

  const CandidatoFecha({
    required this.crudo,
    this.dia,
    this.mes,
    this.anio,
    required this.valida,
    this.motivo = '',
    this.conEspaciosInternos = false,
    this.sugerida = '',
    this.datadoEnLugar = false,
    this.pareceCitada = false,
  });

  /// `DD/MM/AAAA` (solo si [valida]).
  String get normalizada => valida
      ? '${dia!.toString().padLeft(2, '0')}/${mes!.toString().padLeft(2, '0')}/${anio!.toString().padLeft(4, '0')}'
      : '';
}

class ExtractorFecha {
  static const Map<String, int> _meses = {
    'ENE': 1, 'ENERO': 1,
    'FEB': 2, 'FEBRERO': 2,
    'MAR': 3, 'MARZO': 3,
    'ABR': 4, 'ABRIL': 4,
    'MAY': 5, 'MAYO': 5,
    'JUN': 6, 'JUNIO': 6,
    'JUL': 7, 'JULIO': 7,
    'AGO': 8, 'AGOSTO': 8,
    'SET': 9, 'SEP': 9, 'SEPT': 9, 'SETIEMBRE': 9, 'SEPTIEMBRE': 9,
    'OCT': 10, 'OCTUBRE': 10,
    'NOV': 11, 'NOVIEMBRE': 11,
    'DIC': 12, 'DICIEMBRE': 12,
  };

  static const String _alternanciaMeses =
      'SEPTIEMBRE|SETIEMBRE|NOVIEMBRE|DICIEMBRE|FEBRERO|OCTUBRE|AGOSTO|ENERO|MARZO|ABRIL|JUNIO|JULIO|MAYO|SEPT|ENE|FEB|MAR|ABR|MAY|JUN|JUL|AGO|SET|SEP|OCT|NOV|DIC';

  static final RegExp _fechaRe = RegExp(
    r'(?<![0-9])(?<dia>\d(?:\s?\d)?)\s*(?:DE\s+)?(?<mes>' +
        _alternanciaMeses +
        r')(?![A-Z])\s*[.,]?\s*(?:DEL?\s+)?(?<anio>\d(?:\s?\d){3})(?![0-9])',
  );

  static final RegExp _mesSueltoRe = RegExp(r'(?<![A-Z])(' + _alternanciaMeses + r')(?![A-Z])');

  /// Rango de años admitido cuando no hay un año de referencia (el del código).
  static bool anioPlausible(int anio, {int? ahora}) {
    final actual = ahora ?? DateTime.now().year;
    return anio >= 2000 && anio <= actual + 1;
  }

  /// Todas las fechas con forma `DD MES AAAA` (abreviada o completa) del texto,
  /// ya validadas. [anioReferencia] es el año del código de la resolución: si se
  /// conoce, la fecha debe pertenecer a ese año.
  static List<CandidatoFecha> extraer(String texto, {int? anioReferencia, int? ahora}) {
    final norm = normalizarParaBusqueda(texto);
    final candidatos = <CandidatoFecha>[];
    for (final m in _fechaRe.allMatches(norm)) {
      final crudo = texto.substring(m.start, m.end);
      final diaTxt = m.namedGroup('dia')!;
      final anioTxt = m.namedGroup('anio')!;
      // Los sellos de fecha imprimen los dígitos del día separados (`0 8`): es normal.
      final conEspacios = anioTxt.contains(RegExp(r'\s'));
      final previo = norm.substring(m.start >= 24 ? m.start - 24 : 0, m.start);
      final datado = RegExp(r'POCOLLAY\s*[,.:;]?\s*$').hasMatch(previo);
      final citada = RegExp(r'FECHA\s*(?:DE|DEL)?\s*$').hasMatch(previo);
      candidatos.add(validar(
        dia: int.parse(diaTxt.replaceAll(RegExp(r'\s'), '')),
        mes: _meses[m.namedGroup('mes')!]!,
        anio: int.parse(anioTxt.replaceAll(RegExp(r'\s'), '')),
        crudo: crudo,
        anioReferencia: anioReferencia,
        ahora: ahora,
        conEspaciosInternos: conEspacios,
        datadoEnLugar: datado,
        pareceCitada: citada,
      ));
    }
    return candidatos;
  }

  static CandidatoFecha validar({
    required int dia,
    required int mes,
    required int anio,
    String crudo = '',
    int? anioReferencia,
    int? ahora,
    bool conEspaciosInternos = false,
    bool datadoEnLugar = false,
    bool pareceCitada = false,
  }) {
    CandidatoFecha invalida(String motivo, {String sugerida = ''}) => CandidatoFecha(
          crudo: crudo,
          dia: dia,
          mes: mes,
          anio: anio,
          valida: false,
          motivo: motivo,
          conEspaciosInternos: conEspaciosInternos,
          sugerida: sugerida,
          datadoEnLugar: datadoEnLugar,
          pareceCitada: pareceCitada,
        );

    if (mes < 1 || mes > 12) return invalida('mes inválido');
    if (dia < 1 || dia > 31) return invalida('día fuera de rango (01-31)');
    if (anio < 1000 || anio > 9999) return invalida('el año no tiene cuatro dígitos');
    final f = DateTime(anio, mes, dia);
    if (f.day != dia || f.month != mes) return invalida('el día no existe en ese mes');
    if (anioReferencia != null) {
      if (anio != anioReferencia) {
        var sugerida = '';
        final conReferencia = DateTime(anioReferencia, mes, dia);
        if (distanciaLevenshtein('$anio', '$anioReferencia') <= 1 &&
            conReferencia.day == dia &&
            conReferencia.month == mes) {
          sugerida =
              '${dia.toString().padLeft(2, '0')}/${mes.toString().padLeft(2, '0')}/${anioReferencia.toString().padLeft(4, '0')}';
        }
        return invalida('el año ($anio) no coincide con el del código ($anioReferencia)',
            sugerida: sugerida);
      }
    } else if (!anioPlausible(anio, ahora: ahora)) {
      return invalida('año fuera de rango ($anio)');
    }
    return CandidatoFecha(
      crudo: crudo,
      dia: dia,
      mes: mes,
      anio: anio,
      valida: true,
      conEspaciosInternos: conEspaciosInternos,
      datadoEnLugar: datadoEnLugar,
      pareceCitada: pareceCitada,
    );
  }

  /// Valida una fecha escrita a mano en formato `DD/MM/AAAA`.
  static CandidatoFecha validarTextoDDMMAAAA(String texto) {
    final m = RegExp(r'^\s*(\d{1,2})/(\d{1,2})/(\d{4})\s*$').firstMatch(texto);
    if (m == null) {
      return CandidatoFecha(crudo: texto, valida: false, motivo: 'formato esperado DD/MM/AAAA');
    }
    return validar(
      dia: int.parse(m.group(1)!),
      mes: int.parse(m.group(2)!),
      anio: int.parse(m.group(3)!),
      crudo: texto,
    );
  }

  /// ¿El texto menciona algún mes (abreviado o completo)?
  static bool contieneMes(String texto) => _mesSueltoRe.hasMatch(normalizarParaBusqueda(texto));

  /// Fragmento alrededor del primer mes que aparezca (sirve para mostrar al
  /// usuario qué se leyó cuando ninguna fecha pasó la validación).
  static String lecturaDudosa(String texto) {
    final norm = normalizarParaBusqueda(texto);
    final m = _mesSueltoRe.firstMatch(norm);
    if (m == null) return '';
    final ini = (m.start - 7).clamp(0, texto.length);
    final fin = (m.end + 9).clamp(0, texto.length);
    return colapsarEspacios(texto.substring(ini, fin));
  }
}

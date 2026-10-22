import '../../models/campos_resolucion.dart';
import '../../utils/texto_utils.dart';
import 'catalogo_resoluciones.dart';
import 'extractor_encabezado.dart';
import 'extractor_fecha.dart';
import 'normalizador_numero.dart';

enum OrigenLectura {
  /// Texto nativo del PDF (exacto, no pasó por OCR).
  nativo,

  /// OCR de la página completa.
  ocrPagina,

  /// OCR focalizado sobre el encabezado a mayor resolución.
  ocrFocalizado,

  /// OCR de la zona del número forzado a dígitos (siempre lectura no limpia).
  ocrSoloDigitos,

  /// Lectura de la red neuronal propia de los números manuscritos: tres
  /// dígitos leídos de la tinta azul de la zona del número. Es un método
  /// independiente de Tesseract: cuando coincide con él, es una corroboración
  /// más fuerte que otra pasada del mismo motor de OCR.
  redNeuronal,

  /// Lectura de la red neuronal propia del sello de la fecha: los dos dígitos
  /// del día. El mes y el año los sigue leyendo el OCR (letras y año del código).
  redSello,

  /// Encabezado/pie de otras páginas del mismo documento (solo corrobora el número).
  otraPagina,
}

class LecturaTexto {
  final String texto;
  final OrigenLectura origen;

  /// Descripción de cómo se obtuvo (solo diagnóstico).
  final String config;

  /// Solo para lecturas de la red neuronal: probabilidad de cada clase (0-9)
  /// para cada dígito leído, en el mismo orden que [texto].
  final List<List<double>>? probabilidades;

  const LecturaTexto(this.texto, this.origen, {this.config = '', this.probabilidades});

  /// Confianza de una lectura de la red: producto de la probabilidad del
  /// dígito elegido en cada posición. 0 si no hay probabilidades.
  double get confianza {
    final p = probabilidades;
    if (p == null || p.isEmpty || p.length != texto.length) return 0;
    var c = 1.0;
    for (var i = 0; i < p.length; i++) {
      final d = int.tryParse(texto[i]);
      if (d == null) return 0;
      c *= p[i][d];
    }
    return c;
  }

  /// Probabilidad de que la imagen sea exactamente la cifra [valor] según la
  /// red (producto de las probabilidades de cada dígito). 0 si no se puede.
  double verosimilitud(String valor) {
    final p = probabilidades;
    if (p == null || valor.length != p.length) return 0;
    var c = 1.0;
    for (var i = 0; i < p.length; i++) {
      final d = int.tryParse(valor[i]);
      if (d == null) return 0;
      c *= p[i][d];
    }
    return c;
  }
}

class _Votacion {
  final Map<String, double> _totalTexto = {};
  final Map<String, double> _limpioTexto = {};
  final Map<String, double> _totalOtros = {};
  final Map<String, double> _limpioOtros = {};

  /// Tope al peso total que las lecturas de texto (Tesseract) pueden aportar
  /// a una misma cifra. Varias pasadas de Tesseract sobre el mismo trazo
  /// comparten el mismo error, así que sumarlas sin límite deja que una
  /// lectura errónea repetida tape a una fuente independiente. `null` = sin tope.
  final double? topeTexto;

  _Votacion({this.topeTexto});

  /// [texto]: la lectura es un OCR de texto (sujeta a [topeTexto]).
  void agregar(String valor, double peso, {required bool limpio, bool texto = false}) {
    final total = texto ? _totalTexto : _totalOtros;
    final lim = texto ? _limpioTexto : _limpioOtros;
    total[valor] = (total[valor] ?? 0) + peso;
    if (limpio) lim[valor] = (lim[valor] ?? 0) + peso;
  }

  double _conTope(double? v) {
    final x = v ?? 0;
    final t = topeTexto;
    return t != null && x > t ? t : x;
  }

  Set<String> get _claves => {..._totalTexto.keys, ..._totalOtros.keys};

  bool get vacia => _claves.isEmpty;

  List<String> get valores => _claves.toList();

  List<String> get ordenados {
    final claves = _claves.toList();
    claves.sort((a, b) {
      final c = totalDe(b).compareTo(totalDe(a));
      if (c != 0) return c;
      final d = limpioDe(b).compareTo(limpioDe(a));
      return d != 0 ? d : a.compareTo(b);
    });
    return claves;
  }

  String? get ganador => vacia ? null : ordenados.first;
  double totalDe(String v) => _conTope(_totalTexto[v]) + (_totalOtros[v] ?? 0);
  double limpioDe(String v) => _conTope(_limpioTexto[v]) + (_limpioOtros[v] ?? 0);

  bool get hayConflicto {
    final o = ordenados;
    if (o.length < 2) return false;
    return totalDe(o[1]) * 2 >= totalDe(o[0]);
  }

  /// Regla de decisión: sin conflicto, con al menos una lectura limpia y un
  /// respaldo total equivalente a dos lecturas limpias (o una lectura nativa).
  bool get detectado {
    final g = ganador;
    return g != null && !hayConflicto && limpioDe(g) >= 1 && totalDe(g) >= 2;
  }

  String describir() => ordenados.map((v) {
        final t = totalDe(v);
        return '$v (${t.toStringAsFixed(t % 1 == 0 ? 0 : 1)})';
      }).join(', ');
}

class ResultadoEncabezado {
  final String? numero;
  final EstadoCampo estadoNumero;
  final String notaNumero;

  final String? anio;
  final EstadoCampo estadoAnio;
  final String notaAnio;

  final String? siglas;
  final EstadoCampo estadoSiglas;
  final String notaSiglas;

  final TipoResolucion? tipo;
  final EstadoCampo estadoTipo;
  final String notaTipo;

  /// `DD/MM/AAAA`, o `null` si no hubo ninguna fecha válida.
  final String? fecha;
  final EstadoCampo estadoFecha;
  final String notaFecha;

  const ResultadoEncabezado({
    required this.numero,
    required this.estadoNumero,
    required this.notaNumero,
    required this.anio,
    required this.estadoAnio,
    required this.notaAnio,
    required this.siglas,
    required this.estadoSiglas,
    required this.notaSiglas,
    required this.tipo,
    required this.estadoTipo,
    required this.notaTipo,
    required this.fecha,
    required this.estadoFecha,
    required this.notaFecha,
  });

  bool get numeroYFechaDetectados =>
      estadoNumero == EstadoCampo.detectado && estadoFecha == EstadoCampo.detectado;
}

class ConsolidadorEncabezado {
  static double _peso(OrigenLectura o, {required bool limpio}) {
    if (!limpio) return 0.5;
    return o == OrigenLectura.nativo ? 2 : 1;
  }

  /// Parte del texto que corresponde al encabezado (antes de VISTO/CONSIDERANDO,
  /// donde se citan otras resoluciones, informes y fechas).
  static String _seccion(LecturaTexto l) => ExtractorEncabezado.seccionEncabezado(l.texto);

  /// Título escrito en el encabezado, solo si es acuerdo de concejo o gerencia
  /// municipal. No usa las siglas del código: sin eso, una G leída por una C
  /// se tomaría a sí misma como título.
  static String? _tituloEscritoCmGm(List<LecturaTexto> lecturas, Set<String> par) {
    String? hallado;
    for (final l in lecturas) {
      final tipo = CatalogoResoluciones.tituloMasTemprano(
        ExtractorEncabezado.seccionEncabezado(l.texto),
      )?.$1;
      if (tipo == null || !par.contains(tipo.siglas)) continue;
      if (hallado != null && hallado != tipo.siglas) return null;
      hallado = tipo.siglas;
    }
    return hallado;
  }

  /// Bloque operativo en su propia línea: `ACUERDO:` es acuerdo de concejo y
  /// `SE RESUELVE` es gerencia municipal. Una cita a mitad de párrafo no cuenta.
  /// Si aparecen los dos, no hay respaldo.
  static String? _anclaOperativaCmGm(String texto) {
    if (texto.isEmpty) return null;
    final norm = normalizarParaBusqueda(texto);
    final acuerdo = RegExp(r'(?:^|\n)\s*ACUERDO\s*[:;.]').hasMatch(norm);
    final resuelve = RegExp(r'(?:^|\n)\s*SE\s+RESUELVE\b').hasMatch(norm);
    if (acuerdo == resuelve) return null;
    return acuerdo ? 'CM-MDP-T' : 'GM-MDP-T';
  }

  static ResultadoEncabezado consolidar(
    List<LecturaTexto> lecturas, {
    String textoCuerpo = '',
    int? ahora,
  }) {
    final primarias = lecturas
        .where((l) =>
            l.origen != OrigenLectura.otraPagina &&
            l.origen != OrigenLectura.ocrSoloDigitos &&
            l.origen != OrigenLectura.redNeuronal &&
            l.origen != OrigenLectura.redSello)
        .toList();
    final soloDigitos = lecturas.where((l) => l.origen == OrigenLectura.ocrSoloDigitos).toList();
    final redIA = lecturas.where((l) => l.origen == OrigenLectura.redNeuronal).toList();
    final redSello = lecturas.where((l) => l.origen == OrigenLectura.redSello).toList();
    final otrasPaginas = lecturas.where((l) => l.origen == OrigenLectura.otraPagina).toList();

    final candidatosPorLectura = <LecturaTexto, List<CandidatoEncabezado>>{
      for (final l in [...primarias, ...otrasPaginas])
        // En el encabezado propio solo vale el primer código (el de la resolución);
        // los siguientes, si los hubiera, serían documentos citados.
        l: l.origen == OrigenLectura.otraPagina
            ? ExtractorEncabezado.extraer(l.texto, ahora: ahora).take(1).toList()
            : ExtractorEncabezado.extraer(ExtractorEncabezado.seccionCodigo(l.texto), ahora: ahora)
                .take(1)
                .toList(),
    };

    // ── Siglas y año (solo lecturas primarias) ──────────────────────────────
    final votosSiglas = _Votacion();
    final votosAnio = _Votacion();
    final crudosNumero = <String>{};
    // Lecturas del encabezado donde había algo en el lugar del número pero no
    // forma un número (típico de la escritura a mano): si ocurre, el número no
    // puede darse por detectado aunque otras lecturas coincidan.
    var lecturasNumeroIlegibles = 0;
    for (final l in primarias) {
      for (final c in candidatosPorLectura[l]!) {
        if (c.numeroCrudo.isNotEmpty && c.numero == null) lecturasNumeroIlegibles++;
        final limpioSiglas = c.siglasConocidas && !c.siglasAproximadas;
        votosSiglas.agregar(c.siglas, _peso(l.origen, limpio: limpioSiglas), limpio: limpioSiglas);
        if (c.anio != null) {
          votosAnio.agregar(c.anio!, _peso(l.origen, limpio: !c.anioReparado), limpio: !c.anioReparado);
        }
        if (c.numeroCrudo.isNotEmpty) crudosNumero.add(c.numeroCrudo);
      }
    }

    final siglasGanadora = votosSiglas.ganador;
    final anioGanador = votosAnio.ganador;

    // ── Número ──────────────────────────────────────────────────────────────
    // Todo el OCR de texto junto no puede aportar más de 1.5 a una cifra (ver
    // [_Votacion.topeTexto]): lo que la distingue de una lectura aislada tiene
    // que venir de fuentes independientes.
    final votosNumero = _Votacion(topeTexto: 1.5);
    // `ocrPagina`, `ocrFocalizado` y `ocrSoloDigitos` son todas lecturas de
    // Tesseract: si el número está manuscrito (o el recorte incluye el símbolo
    // "N°") y Tesseract lo malinterpreta, lo malinterpreta igual en cada
    // pasada, y esas lecturas "corroborándose" entre sí no son evidencia
    // independiente. Solo cuentan como corroboración real para poder marcar
    // DETECTADO: texto nativo (no es OCR), el encabezado de otra página (es
    // otro recorte de imagen) y la red neuronal propia (otro método por completo).
    const fuentesIndependientes = {
      OrigenLectura.nativo,
      OrigenLectura.otraPagina,
      OrigenLectura.redNeuronal,
    };
    final apoyoTextual = <String>{};
    final fuentesPorNumero = <String, Set<OrigenLectura>>{};
    void marcarFuenteNumero(String valor, OrigenLectura origen) =>
        fuentesPorNumero.putIfAbsent(valor, () => {}).add(origen);
    bool corroboradoIndependiente(String valor) =>
        (fuentesPorNumero[valor] ?? const {}).any(fuentesIndependientes.contains);

    bool coincide(CandidatoEncabezado c) =>
        (siglasGanadora == null || c.siglas == siglasGanadora) && (anioGanador == null || c.anio == anioGanador);

    for (final l in [...primarias, ...otrasPaginas]) {
      for (final c in candidatosPorLectura[l]!) {
        if (c.numero == null || !coincide(c) || RegExp(r'^0+$').hasMatch(c.numero!)) continue;
        final limpio = !c.numeroReparado && !(c.anioReparado);
        final valor = NormalizadorNumero.normalizar(c.numero!).valor;
        // El texto nativo no es OCR (es exacto) y la otra página es otro
        // recorte: ninguno está sujeto al tope del OCR de texto.
        final esOcrDeTexto = l.origen == OrigenLectura.ocrPagina || l.origen == OrigenLectura.ocrFocalizado;
        votosNumero.agregar(valor, _peso(l.origen, limpio: limpio), limpio: limpio, texto: esOcrDeTexto);
        marcarFuenteNumero(valor, l.origen);
        apoyoTextual.add(valor);
      }
    }
    for (final l in soloDigitos) {
      final t = l.texto.replaceAll(RegExp(r'\s'), '');
      if (RegExp(r'^\d{1,4}$').hasMatch(t) && !RegExp(r'^0+$').hasMatch(t)) {
        // Lectura forzada a dígitos: sirve solo como apoyo débil.
        final valor = NormalizadorNumero.normalizar(t).valor;
        // Sigue siendo Tesseract (y el recorte puede incluir el símbolo "N°",
        // que lee como un "9" o un "4"): cuenta dentro del tope del OCR de texto.
        votosNumero.agregar(valor, 0.25, limpio: false, texto: true);
        marcarFuenteNumero(valor, l.origen);
      }
    }
    // Red neuronal de números manuscritos: da, a cada cifra candidata (la que
    // ella eligió y las que leyó Tesseract), un voto proporcional a la
    // probabilidad que la red le asigna a esa cifra. Es un método
    // independiente de Tesseract, así que cuenta como corroboración. Su voto
    // máximo (2) equivale al de un texto nativo, pero sola nunca alcanza para
    // DETECTADO: la medición mostró que su confianza falla en la cima (una
    // lectura con 0.99 de confianza fue incorrecta), por lo que siempre
    // necesita otra fuente que coincida.
    final redAcuerdoFuerte = <String>{};
    for (final l in redIA) {
      final t = l.texto.replaceAll(RegExp(r'\s'), '');
      if (!RegExp(r'^\d{3}$').hasMatch(t) || l.probabilidades == null) continue;
      final propia = NormalizadorNumero.normalizar(t).valor;
      final candidatas = {propia, ...votosNumero.valores.where((v) => RegExp(r'^\d{3}$').hasMatch(v))};
      for (final v in candidatas) {
        final verosimilitud = l.verosimilitud(v);
        if (verosimilitud < 0.05) continue;
        final fuerte = v == propia && l.confianza >= 0.9;
        votosNumero.agregar(v, 2.0 * verosimilitud, limpio: fuerte);
        // Solo corrobora de verdad una cifra a la que la red da una probabilidad apreciable.
        if (verosimilitud >= 0.3) marcarFuenteNumero(v, l.origen);
        if (fuerte) redAcuerdoFuerte.add(v);
      }
    }

    String? numero;
    var estadoNumero = EstadoCampo.requiereRevision;
    var notaNumero = '';
    final candidatoNumero = votosNumero.ganador;
    // Si la red neuronal lee con confianza la misma cifra que alguna lectura de
    // texto, las otras lecturas de Tesseract (que sobre escritura a mano suelen
    // ser basura) ya no invalidan el resultado.
    final acuerdoRedYTexto =
        candidatoNumero != null && redAcuerdoFuerte.contains(candidatoNumero) && apoyoTextual.contains(candidatoNumero);
    if (candidatoNumero != null && !acuerdoRedYTexto) {
      // Lecturas de otra cifra (aunque "reparadas") también delatan un número difícil de leer.
      for (final l in primarias) {
        for (final c in candidatosPorLectura[l]!) {
          if (c.numero == null || !coincide(c)) continue;
          final lectura = NormalizadorNumero.normalizar(c.numero!).valor;
          if (lectura == candidatoNumero) continue;
          if (c.numeroAlternativo != null &&
              NormalizadorNumero.normalizar(c.numeroAlternativo!).valor == candidatoNumero) {
            continue;
          }
          lecturasNumeroIlegibles++;
        }
      }
    }
    // Sin ninguna lectura limpia, una sugerencia necesita el acuerdo de al menos
    // tres lecturas dudosas; con menos respaldo es preferible no proponer nada.
    // Una cifra que la red neuronal lee con probabilidad apreciable sí se
    // propone (como sugerencia), aunque el respaldo sea moderado.
    final leidoPorRed = candidatoNumero != null &&
        (fuentesPorNumero[candidatoNumero] ?? const <OrigenLectura>{}).contains(OrigenLectura.redNeuronal);
    final respaldoDebil = candidatoNumero != null &&
        !leidoPorRed &&
        votosNumero.limpioDe(candidatoNumero) < 1 &&
        votosNumero.totalDe(candidatoNumero) < 1.5;
    if (votosNumero.vacia || respaldoDebil) {
      final vistos = crudosNumero.where((s) => s.isNotEmpty).take(4).map((s) => '"$s"').join(', ');
      notaNumero = 'No se pudo leer el número con seguridad.'
          '${respaldoDebil ? ' Lecturas poco fiables: ${votosNumero.describir()}.' : ''}'
          '${vistos.isEmpty ? '' : ' Lecturas OCR del encabezado: $vistos.'}';
    } else {
      numero = votosNumero.ganador;
      final nn = NormalizadorNumero.normalizar(numero!);
      final independiente = corroboradoIndependiente(numero);
      final sinIlegibles = lecturasNumeroIlegibles == 0 || acuerdoRedYTexto;
      if (votosNumero.detectado && !nn.requiereRevision && sinIlegibles && independiente) {
        estadoNumero = EstadoCampo.detectado;
      } else {
        final partes = <String>[];
        if (nn.requiereRevision) partes.add(nn.nota);
        if (!sinIlegibles && votosNumero.detectado) {
          partes.add('Algunas lecturas del número fueron ilegibles (posible escritura a mano): '
              '${votosNumero.describir()}; verifique contra el documento.');
        } else if (votosNumero.hayConflicto) {
          partes.add('Lecturas distintas: ${votosNumero.describir()}.');
        } else if (!votosNumero.detectado) {
          partes.add('Respaldo insuficiente (${votosNumero.describir()}); verifique contra el documento.');
        } else if (!independiente) {
          partes.add('El número solo se leyó por OCR de texto sobre el mismo recorte de imagen; '
              'falta una lectura independiente (dígitos forzados, red neuronal, texto nativo u otra '
              'página) que lo corrobore; verifique contra el documento.');
        }
        notaNumero = partes.join(' ');
      }
    }

    // ── Año ─────────────────────────────────────────────────────────────────
    String? anio = anioGanador;
    var estadoAnio = EstadoCampo.requiereRevision;
    var notaAnio = '';
    if (anio == null) {
      notaAnio = 'No se pudo leer el año del código.';
    } else if (votosAnio.detectado) {
      estadoAnio = EstadoCampo.detectado;
    } else {
      notaAnio = votosAnio.hayConflicto
          ? 'Lecturas distintas del año: ${votosAnio.describir()}.'
          : 'Respaldo insuficiente para el año ($anio).';
    }

    // ── Tipo y siglas ───────────────────────────────────────────────────────
    final votosTipo = _Votacion();
    for (final l in primarias) {
      final t = ExtractorEncabezado.tipoPorTexto(_seccion(l));
      if (t != null) votosTipo.agregar(t.siglas, _peso(l.origen, limpio: true), limpio: true);
    }
    final tipoTexto = votosTipo.ganador == null ? null : CatalogoResoluciones.porSiglas(votosTipo.ganador!);

    String? siglas = siglasGanadora;
    var estadoSiglas = EstadoCampo.requiereRevision;
    var notaSiglas = '';
    TipoResolucion? tipo;
    var estadoTipo = EstadoCampo.requiereRevision;
    var notaTipo = '';

    final tipoSiglas = siglas == null ? null : CatalogoResoluciones.porSiglas(siglas);
    if (siglas != null && tipoSiglas != null) {
      tipo = tipoSiglas;
      if (votosSiglas.detectado) {
        estadoSiglas = EstadoCampo.detectado;
        estadoTipo = EstadoCampo.detectado;
      } else {
        notaSiglas = votosSiglas.limpioDe(siglas) == 0
            ? 'Las siglas se corrigieron por similitud con un patrón conocido; verifique.'
            : votosSiglas.hayConflicto
                ? 'Lecturas distintas de las siglas: ${votosSiglas.describir()}.'
                : 'Respaldo insuficiente para las siglas ($siglas).';
        notaTipo = 'El tipo se dedujo de siglas dudosas.';
      }
      if (tipoTexto != null && tipoTexto.siglas != tipoSiglas.siglas) {
        estadoTipo = EstadoCampo.requiereRevision;
        notaTipo =
            'El tipo escrito en el encabezado (${tipoTexto.nombre}) no coincide con el de las siglas (${tipoSiglas.nombre}).';
      }
    } else if (siglas != null) {
      notaSiglas = 'Siglas no reconocidas: $siglas.';
      if (tipoTexto != null) {
        tipo = tipoTexto;
        notaTipo = 'El tipo se tomó del texto del encabezado, pero las siglas leídas no son conocidas.';
      } else {
        notaTipo = 'No se pudo determinar el tipo de resolución.';
      }
    } else if (tipoTexto != null) {
      tipo = tipoTexto;
      siglas = tipoTexto.siglas;
      notaSiglas = 'No se leyeron las siglas; se dedujeron del tipo de resolución.';
      notaTipo = 'El tipo se tomó solo del texto del encabezado.';
    } else {
      notaSiglas = 'No se pudieron leer las siglas.';
      notaTipo = 'No se pudo determinar el tipo de resolución.';
    }

    // CM-MDP-T y GM-MDP-T se diferencian solo en C/G. Una lectura exacta de la
    // letra equivocada es un tipo válido, así que no se corrige por similitud.
    // El título y el bloque operativo (ACUERDO: / SE RESUELVE) deshacen esa
    // confusión cuando coinciden. Si no coinciden, no se da por detectado.
    const parCmGm = {'CM-MDP-T', 'GM-MDP-T'};
    final tituloPar = _tituloEscritoCmGm(primarias, parCmGm);
    final siglaPar = siglas != null && parCmGm.contains(siglas) ? siglas : null;
    final lecturasPar = votosSiglas.valores.where(parCmGm.contains).toList();
    if (tituloPar != null || siglaPar != null || lecturasPar.isNotEmpty) {
      final cuerpo = textoCuerpo.isNotEmpty ? textoCuerpo : primarias.map((l) => l.texto).join('\n');
      final anclaPar = _anclaOperativaCmGm(cuerpo);
      final respaldo = tituloPar != null && anclaPar == tituloPar ? tituloPar : null;
      final conflicto = lecturasPar.toSet().length > 1 && votosSiglas.hayConflicto;
      if (respaldo != null && (siglaPar != respaldo || conflicto)) {
        tipo = CatalogoResoluciones.porSiglas(respaldo);
        siglas = respaldo;
        estadoTipo = EstadoCampo.detectado;
        estadoSiglas = EstadoCampo.detectado;
        notaTipo = '';
        notaSiglas = '';
      } else if (siglaPar != null && tituloPar != null && tituloPar != siglaPar) {
        estadoTipo = EstadoCampo.requiereRevision;
        estadoSiglas = EstadoCampo.requiereRevision;
        if (notaTipo.isEmpty) {
          notaTipo =
              'El título y las siglas no coinciden entre acuerdo de concejo (CM-MDP-T) y gerencia municipal (GM-MDP-T).';
        }
        notaSiglas = 'Lectura dudosa entre C y G (CM-MDP-T / GM-MDP-T); verifique las siglas.';
      } else if (siglaPar != null && tituloPar == null && anclaPar != null && anclaPar != siglaPar) {
        estadoTipo = EstadoCampo.requiereRevision;
        estadoSiglas = EstadoCampo.requiereRevision;
        notaTipo =
            'La estructura del documento no coincide con las siglas $siglaPar; puede confundirse el acuerdo de concejo con la gerencia municipal.';
        notaSiglas = 'Lectura dudosa entre C y G (CM-MDP-T / GM-MDP-T); verifique las siglas.';
      } else if (conflicto) {
        estadoTipo = EstadoCampo.requiereRevision;
        estadoSiglas = EstadoCampo.requiereRevision;
        if (notaSiglas.isEmpty) {
          notaSiglas = 'Lecturas distintas de las siglas: ${votosSiglas.describir()}.';
        }
        if (notaTipo.isEmpty) {
          notaTipo =
              'Lecturas distintas entre CM-MDP-T y GM-MDP-T, sin un título y una estructura que las resuelvan.';
        }
      }
    }

    // ── Fecha ───────────────────────────────────────────────────────────────
    final anioRef = anio == null ? null : int.tryParse(anio);
    final votosFecha = _Votacion();
    final votosSugeridas = _Votacion();
    final lecturasSugeridas = <String, String>{};
    final motivos = <String>{};
    String lecturaDudosa = '';
    // La fecha del documento es la que sigue a "Pocollay,". Si en alguna lectura
    // se distingue ese ancla, las demás fechas (citas de otros documentos) se
    // ignoran. Solo si el ancla no se leyó en ninguna, se toma como apoyo débil
    // la primera fecha del encabezado que no parezca citada ("de fecha …"); nunca
    // llega a ser DETECTADO.
    final fechasPorLectura = {
      for (final l in primarias)
        l: ExtractorFecha.extraer(_seccion(l), anioReferencia: anioRef, ahora: ahora),
    };
    var hayAncla = fechasPorLectura.values.any((fs) => fs.any((f) => f.datadoEnLugar));
    // Con ancla, cualquier lectura inválida de la fecha del documento delata un
    // sello difícil de leer: la fecha no puede darse por detectada.
    var lecturasFechaInvalidas = 0;
    // Meses leídos (letras del sello) en las lecturas de la fecha del documento,
    // válidas o no: el mes y el año los lee bien el OCR; los dígitos del día, no.
    final votosMes = <int, int>{};

    void recolectarFechas(bool conAncla) {
      for (final l in primarias) {
        final seccion = _seccion(l);
        final todas = fechasPorLectura[l]!;
        final fechas = conAncla
            ? todas.where((f) => f.datadoEnLugar).toList()
            : todas.where((f) => !f.pareceCitada).take(1).toList();
        for (final f in fechas) {
          if (f.mes != null && f.mes! >= 1 && f.mes! <= 12) votosMes[f.mes!] = (votosMes[f.mes!] ?? 0) + 1;
          if (f.valida) {
            final limpio = conAncla && !f.conEspaciosInternos;
            votosFecha.agregar(f.normalizada, _peso(l.origen, limpio: limpio), limpio: limpio);
          } else {
            if (conAncla) lecturasFechaInvalidas++;
            if (f.sugerida.isNotEmpty) {
              votosSugeridas.agregar(f.sugerida, 0.5, limpio: false);
              lecturasSugeridas.putIfAbsent(f.sugerida, () => colapsarEspacios(f.crudo));
            } else {
              motivos.add('"${colapsarEspacios(f.crudo)}": ${f.motivo}');
            }
          }
        }
        if (lecturaDudosa.isEmpty) lecturaDudosa = ExtractorFecha.lecturaDudosa(seccion);
      }
    }

    recolectarFechas(hayAncla);
    if (hayAncla && votosFecha.vacia && votosSugeridas.vacia) {
      // El ancla "Pocollay," se leyó pero no produjo ninguna fecha utilizable:
      // como último recurso, la primera fecha propia del encabezado (apoyo débil).
      hayAncla = false;
      recolectarFechas(false);
    }

    String? fecha = votosFecha.ganador;
    var estadoFecha = EstadoCampo.requiereRevision;
    var notaFecha = '';
    if (fecha == null && !votosSugeridas.vacia) {
      fecha = votosSugeridas.ganador;
      final leida = lecturasSugeridas[fecha] ?? '';
      notaFecha = 'El año leído por OCR no coincide con el del código ($anio) '
          '(lectura: "$leida"); se propone $fecha usando el año del código. '
          '${votosSugeridas.hayConflicto ? 'Hay lecturas distintas: ${votosSugeridas.describir()}. ' : ''}'
          'Verifique contra el documento.';
    } else if (fecha == null) {
      final partes = <String>['No se pudo obtener una fecha válida del encabezado.'];
      if (motivos.isNotEmpty) partes.add('Lecturas descartadas: ${motivos.take(3).join('; ')}.');
      if (lecturaDudosa.isNotEmpty && motivos.isEmpty) partes.add('Lectura OCR dudosa: "$lecturaDudosa".');
      notaFecha = partes.join(' ');
    } else if (votosFecha.detectado && lecturasFechaInvalidas == 0) {
      estadoFecha = EstadoCampo.detectado;
    } else {
      notaFecha = votosFecha.hayConflicto
          ? 'Lecturas distintas: ${votosFecha.describir()}.'
          : votosFecha.detectado
              ? 'Algunas lecturas de la fecha fueron inválidas ($lecturasFechaInvalidas); las lecturas '
                  'no son consistentes entre sí (${votosFecha.describir()}); verifique contra el documento.'
              : 'Respaldo insuficiente para la fecha (${votosFecha.describir()}); verifique contra el documento.';
      if (!hayAncla) {
        notaFecha = 'No se leyó la línea "Pocollay," que lleva la fecha del documento; '
            'se tomó la primera fecha del encabezado. $notaFecha';
      }
    }
    // Día leído por la red neuronal del sello. El OCR confunde los dígitos del
    // sello (un 2 por un 7, un 0 por un 8); la red, entrenada con esos sellos,
    // los lee mucho mejor, y su confianza resultó fiable en validación cruzada
    // (con ≥ 0.9, ningún error en documentos que no vio al entrenar).
    if (redSello.isNotEmpty && anioRef != null && votosMes.isNotEmpty) {
      final l = redSello.first;
      final dia = int.tryParse(l.texto);
      final c = l.confianza;
      if (dia != null && l.texto.length == 2 && c >= 0.6) {
        final mes = (votosMes.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
        final lecturasConMes = votosMes.values.fold<int>(0, (s, v) => s + v);
        final propuesta = ExtractorFecha.validar(dia: dia, mes: mes, anio: anioRef, anioReferencia: anioRef);
        if (propuesta.valida) {
          final fechaRed = propuesta.normalizada;
          final pct = (c * 100).round();
          if (fecha == fechaRed && hayAncla && c >= 0.8) {
            estadoFecha = EstadoCampo.detectado;
            notaFecha = '';
          } else if (fecha != fechaRed && hayAncla && c >= 0.9 && votosMes.length == 1 && lecturasConMes >= 2) {
            fecha = fechaRed;
            estadoFecha = EstadoCampo.detectado;
            notaFecha = '';
          } else if (fecha != fechaRed) {
            final previa = fecha;
            fecha = fechaRed;
            notaFecha = 'La red neuronal lee el día $dia (confianza $pct %)'
                '${previa == null ? '' : ' y el OCR había leído $previa'}; verifique contra el documento.';
          }
        }
      }
    }
    if (estadoFecha != EstadoCampo.detectado && textoCuerpo.isNotEmpty) {
      final apoyo = ExtractorFecha.extraer(textoCuerpo, anioReferencia: anioRef, ahora: ahora)
          .where((f) => f.valida)
          .map((f) => f.normalizada)
          .toSet()
          .take(3);
      if (apoyo.isNotEmpty) {
        notaFecha += ' Fechas citadas en el texto (solo referencia): ${apoyo.join(', ')}.';
      }
    }

    return ResultadoEncabezado(
      numero: numero,
      estadoNumero: estadoNumero,
      notaNumero: notaNumero.trim(),
      anio: anio,
      estadoAnio: estadoAnio,
      notaAnio: notaAnio,
      siglas: siglas,
      estadoSiglas: estadoSiglas,
      notaSiglas: notaSiglas,
      tipo: tipo,
      estadoTipo: estadoTipo,
      notaTipo: notaTipo,
      fecha: fecha,
      estadoFecha: estadoFecha,
      notaFecha: notaFecha.trim(),
    );
  }
}

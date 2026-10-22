import 'package:flutter_test/flutter_test.dart';
import 'package:procesador_documental_mdp/models/campos_resolucion.dart';
import 'package:procesador_documental_mdp/services/extraccion/catalogo_resoluciones.dart';
import 'package:procesador_documental_mdp/services/extraccion/consolidador_encabezado.dart';
import 'package:procesador_documental_mdp/services/extraccion/extractor_articulo_primero.dart';
import 'package:procesador_documental_mdp/services/extraccion/extractor_encabezado.dart';
import 'package:procesador_documental_mdp/services/extraccion/extractor_fecha.dart';
import 'package:procesador_documental_mdp/services/extraccion/generador_nombre.dart';
import 'package:procesador_documental_mdp/services/extraccion/normalizador_numero.dart';
import 'package:procesador_documental_mdp/services/extraccion/normalizador_siglas.dart';
import 'package:procesador_documental_mdp/services/extraccion/validador_campos.dart';

void main() {
  group('Normalización de número', () {
    test('rellena a tres cifras', () {
      expect(NormalizadorNumero.normalizar('7').valor, '007');
      expect(NormalizadorNumero.normalizar('9').valor, '009');
      expect(NormalizadorNumero.normalizar('50').valor, '050');
      expect(NormalizadorNumero.normalizar('74').valor, '074');
      expect(NormalizadorNumero.normalizar('117').valor, '117');
      expect(NormalizadorNumero.normalizar('416').valor, '416');
      expect(NormalizadorNumero.normalizar('74').requiereRevision, isFalse);
    });

    test('si ya tiene tres cifras se conserva tal cual', () {
      for (final n in ['007', '074', '100', '117', '416']) {
        final r = NormalizadorNumero.normalizar(n);
        expect(r.valor, n);
        expect(r.requiereRevision, isFalse);
      }
    });

    test('los ceros a la izquierda sobrantes se recortan (0121 → 121)', () {
      expect(NormalizadorNumero.normalizar('0121').valor, '121');
      expect(NormalizadorNumero.normalizar('0121').requiereRevision, isFalse);
      expect(NormalizadorNumero.normalizar('0074').valor, '074');
      expect(NormalizadorNumero.normalizar('0007').valor, '007');
    });

    test('cero no es un número de resolución válido', () {
      expect(NormalizadorNumero.normalizar('0').requiereRevision, isTrue);
      expect(NormalizadorNumero.normalizar('000').requiereRevision, isTrue);
    });

    test(
      'más de tres cifras significativas no se recorta y requiere revisión',
      () {
        final n = NormalizadorNumero.normalizar('1234');
        expect(n.valor, '1234');
        expect(n.requiereRevision, isTrue);
      },
    );

    test('no numérico requiere revisión', () {
      expect(NormalizadorNumero.normalizar('O+4').requiereRevision, isTrue);
      expect(NormalizadorNumero.normalizar('O+4').valor, '');
    });

    test('reparación de confundibles solo como sugerencia', () {
      expect(NormalizadorNumero.repararConfundibles('O+4'), '074');
      expect(NormalizadorNumero.repararConfundibles('OY 4'), '074');
      expect(NormalizadorNumero.repararConfundibles('OY'), isNull);
    });
  });

  group('Siglas, código y nombre', () {
    test('normaliza siglas', () {
      expect(NormalizadorSiglas.normalizar('A-MDP/T'), 'A-MDP-T');
      expect(
        NormalizadorSiglas.normalizar('SGDELC-GDESGA-MDP/T'),
        'SGDELC-GDESGA-MDP-T',
      );
      expect(NormalizadorSiglas.normalizar('gm - mdp / t'), 'GM-MDP-T');
    });

    test('genera el código', () {
      expect(
        GeneradorNombre.generarCodigo('50', '2026', 'SGDELC-GDESGA-MDP/T'),
        '050-2026-SGDELC-GDESGA-MDP-T',
      );
      expect(
        GeneradorNombre.generarCodigo('74', '2026', 'A-MDP/T'),
        '074-2026-A-MDP-T',
      );
    });

    test('genera el nombre completo', () {
      final tipo = CatalogoResoluciones.porSiglas('SGDELC-GDESGA-MDP-T')!;
      expect(
        GeneradorNombre.generarNombreCompleto(
          tipo,
          '050-2026-SGDELC-GDESGA-MDP-T',
        ),
        'RESOLUCIÓN DE SUBGERENCIA DE DESARROLLO ECONÓMICO, LICENCIAS Y CONTROL N° 050-2026-SGDELC-GDESGA-MDP-T',
      );
      expect(
        GeneradorNombre.generarNombreCompleto(
          CatalogoResoluciones.porSiglas('A-MDP-T')!,
          '074-2026-A-MDP-T',
        ),
        'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T',
      );
    });

    test('catálogo cubre las resoluciones, el acuerdo, el decreto y la ordenanza', () {
      expect(CatalogoResoluciones.tipos.length, 10);
      expect(
        CatalogoResoluciones.porSiglas('GM-MDP-T')!.nombre,
        'RESOLUCIÓN DE GERENCIA MUNICIPAL',
      );
      expect(
        CatalogoResoluciones.porSiglas('OGA-MDP-T')!.nombre,
        'RESOLUCIÓN DE LA OFICINA GENERAL DE ADMINISTRACIÓN',
      );
      expect(
        CatalogoResoluciones.porSiglas('GDTI-MDP-T')!.nombre,
        'RESOLUCIÓN DE GERENCIA DE DESARROLLO TERRITORIAL E INFRAESTRUCTURA',
      );
      expect(
        CatalogoResoluciones.porSiglas('SGDT-GDTI-MDP-T')!.nombre,
        'RESOLUCIÓN DE SUBGERENCIA DE DESARROLLO TERRITORIAL',
      );
      expect(
        CatalogoResoluciones.porSiglas('CM-MDP-T')!.nombre,
        'ACUERDO DE CONCEJO MUNICIPAL',
      );
      expect(
        CatalogoResoluciones.porTexto('ACUERDO DE CONCEJO MUNICIPAL N° 001')!.siglas,
        'CM-MDP-T',
      );
      expect(
        CatalogoResoluciones.porSiglas('MDP-T')!.nombre,
        'DECRETO DE ALCALDÍA',
      );
      expect(
        CatalogoResoluciones.porSiglas('MDP')!.nombre,
        'ORDENANZA MUNICIPAL',
      );
      expect(
        CatalogoResoluciones.porTexto(
          'DECRETO DE ALCALDÍA\nN° 009-2025-MDP-T\n'
          'La Ordenanza Municipal N° 005-2025-MDP-T, de fecha 13 de mayo de 2025, y;\n'
          'CONSIDERANDO:',
        )!.siglas,
        'MDP-T',
      );
      expect(
        CatalogoResoluciones.porTexto('ORDENANZA MUNICIPAL\nNro. 003-2025-MDP')!.siglas,
        'MDP',
      );
    });

    test('tipo por texto del encabezado (sin confundir subgerencia con gerencia)', () {
      expect(
        CatalogoResoluciones.porTexto('RESOLUCIÓN DE ALCALDÍA N° 074')!.siglas,
        'A-MDP-T',
      );
      expect(
        CatalogoResoluciones.porTexto(
          'RESOLUCIÓN DE SUBGERENCIA DE DESARROLLO TERRITORIAL\nN° 012-2026',
        )!.siglas,
        'SGDT-GDTI-MDP-T',
      );
      expect(
        CatalogoResoluciones.porTexto(
          'RESOLUCIÓN DE SUBGERENCIA DE DESARROLLO ECONÓMICO, LICENCIAS Y CONTROL',
        )!.siglas,
        'SGDELC-GDESGA-MDP-T',
      );
      expect(
        CatalogoResoluciones.porTexto(
          'RESOLUCION DE GERENCIA DE DESARROLLO TERRITORIAL E INFRAESTRUCTURA',
        )!.siglas,
        'GDTI-MDP-T',
      );
      expect(
        CatalogoResoluciones.porTexto('RESOLUCION DE ALCALDIA'),
        isNotNull,
      );
      expect(CatalogoResoluciones.porTexto('INFORME TÉCNICO'), isNull);
    });
  });

  group('Fechas', () {
    String? una(String t, {int? anio}) {
      final v = ExtractorFecha.extraer(
        t,
        anioReferencia: anio,
        ahora: 2026,
      ).where((f) => f.valida);
      return v.isEmpty ? null : v.first.normalizada;
    }

    test('abreviadas y completas', () {
      expect(una('16 JUN. 2026'), '16/06/2026');
      expect(una('08 JUL. 2026'), '08/07/2026');
      expect(una('03 de junio de 2026'), '03/06/2026');
      expect(una('07 de julio del 2026'), '07/07/2026');
      expect(una('5 SET. 2026'), '05/09/2026');
      expect(una('5 SEP 2026'), '05/09/2026');
      expect(una('12 DIC. 2026'), '12/12/2026');
      expect(una('1 de setiembre de 2026'), '01/09/2026');
    });

    test('lecturas OCR dudosas no se convierten silenciosamente', () {
      expect(una('0 g JUL. 2076'), isNull);
      expect(una('4 5 JUN, 2076'), isNull);
      expect(
        ExtractorFecha.lecturaDudosa('Pocollay, 0 g JUL. 2076'),
        contains('JUL'),
      );
    });

    test('valida día, mes calendario y año de referencia', () {
      expect(una('31 JUN. 2026'), isNull);
      expect(una('32 JUN. 2026'), isNull);
      expect(una('08 JUL. 2026', anio: 2026), '08/07/2026');
      expect(una('08 JUL. 2025', anio: 2026), isNull);
    });

    test('valida la edición manual DD/MM/AAAA', () {
      expect(ExtractorFecha.validarTextoDDMMAAAA('08/07/2026').valida, isTrue);
      expect(ExtractorFecha.validarTextoDDMMAAAA('31/02/2026').valida, isFalse);
      expect(ExtractorFecha.validarTextoDDMMAAAA('8-7-2026').valida, isFalse);
    });
  });

  group('Encabezado', () {
    test('lee código limpio y normaliza (caso subgerencia, número 50)', () {
      final c = ExtractorEncabezado.extraer(
        'RESOLUCIÓN DE SUBGERENCIA DE DESARROLLO ECONÓMICO, LICENCIAS Y CONTROL\nN° 50-2026-SGDELC-GDESGA-MDP/T',
        ahora: 2026,
      );
      expect(c, hasLength(1));
      expect(c.first.numero, '50');
      expect(c.first.numeroReparado, isFalse);
      expect(c.first.anio, '2026');
      expect(c.first.siglas, 'SGDELC-GDESGA-MDP-T');
      expect(c.first.limpio, isTrue);
    });

    test('lee código limpio (caso alcaldía 074)', () {
      final c = ExtractorEncabezado.extraer(
        'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP/T',
        ahora: 2026,
      );
      expect(c.first.numero, '074');
      expect(c.first.siglas, 'A-MDP-T');
    });

    test('número mal leído se repara pero queda marcado como no limpio', () {
      final c = ExtractorEncabezado.extraer(
        'RESOLUCIÓN DE ALCALDÍA N° O+4-2026-A-MDP/T',
        ahora: 2026,
      );
      expect(c.first.numeroCrudo, 'O+4');
      expect(c.first.numero, '074');
      expect(c.first.numeroReparado, isTrue);
      expect(c.first.limpio, isFalse);

      final d = ExtractorEncabezado.extraer(
        'N° OY 4-2026-A-MDP/T',
        ahora: 2026,
      );
      expect(d.first.numero, '074');
      expect(d.first.numeroReparado, isTrue);
    });

    test('acepta N*, N%, No. y MDP/T', () {
      for (final n in ['N*', 'N%', 'No.', 'N°']) {
        final c = ExtractorEncabezado.extraer(
          'RESOLUCIÓN DE ALCALDÍA $n 117-2026-A-MDP/T',
          ahora: 2026,
        );
        expect(c.first.numero, '117', reason: n);
      }
    });

    test('acepta Nº, NO. y No, también si No. va pegado al número', () {
      for (final n in ['Nº', 'NO.', 'No']) {
        final c = ExtractorEncabezado.extraer(
          'RESOLUCIÓN DE ALCALDÍA $n 117-2026-A-MDP/T',
          ahora: 2026,
        );
        expect(c.first.numero, '117', reason: n);
        expect(c.first.numeroReparado, isFalse, reason: n);
      }
      for (final n in ['No.117', 'NO.117']) {
        final c = ExtractorEncabezado.extraer(
          'RESOLUCIÓN DE ALCALDÍA $n-2026-A-MDP/T',
          ahora: 2026,
        );
        expect(c.first.numero, '117', reason: n);
        expect(c.first.numeroReparado, isFalse, reason: n);
      }
    });

    test('símbolo N° mal leído pegado al número (N148, NS48, Ne48, N“48)', () {
      final ambiguo = ExtractorEncabezado.extraer(
        'N148-2026-SGDELC-GDESGA-MDP/T',
        ahora: 2026,
      ).first;
      expect(ambiguo.numero, '148');
      expect(ambiguo.numeroReparado, isTrue);
      for (final n in ['NS48', 'Ne48', 'NT48', 'N“48', 'N¡48', 'N°48']) {
        final c = ExtractorEncabezado.extraer(
          '$n-2026-SGDELC-GDESGA-MDP/T',
          ahora: 2026,
        ).first;
        expect(c.numero, '48', reason: n);
        expect(c.numeroReparado, isFalse, reason: n);
      }
    });

    test(
      'número con cero a la izquierda (N° 0121) se lee y normaliza a 121',
      () {
        final c = ExtractorEncabezado.extraer(
          'RESOLUCIÓN DE SUBGERENCIA DE DESARROLLO TERRITORIAL N° 0121-2026-SGDT-GDTI-MDP-T',
          ahora: 2026,
        );
        expect(c.first.numero, '0121');
        expect(NormalizadorNumero.normalizar(c.first.numero!).valor, '121');
      },
    );

    test('símbolo N° leído como letra y separado del número (NE 61)', () {
      final c = ExtractorEncabezado.extraer(
        'RESOLUCIÓN DE GERENCIA MUNICIPAL NE 61 -2026-GM-MDP/T',
        ahora: 2026,
      );
      expect(c.first.numero, '61');
      expect(c.first.numeroReparado, isFalse);
    });

    test('el código solo se busca antes de la línea "Pocollay,"', () {
      const t =
          'RESOLUCIÓN DE ALCALDÍA\nNo. ___ -2026-A-MDP/T\nPocollay, 08 JUL. 2026\n'
          'Que, mediante Resolución N° 113-2026-A-MDP/T se dispuso';
      expect(ExtractorEncabezado.seccionCodigo(t), isNot(contains('113')));
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(t, OrigenLectura.nativo),
      ], ahora: 2026);
      expect(r.numero, isNull);
    });

    test('lee el código de un decreto y de una ordenanza sin tocar el de una resolución', () {
      final decreto = ExtractorEncabezado.extraer(
        'DECRETO DE ALCALDÍA\nN° 007-2025-MDP-T\nPocollay, 22 de agosto de 2025.',
        ahora: 2026,
      );
      expect(decreto.first.numero, '007');
      expect(decreto.first.anio, '2025');
      expect(decreto.first.siglas, 'MDP-T');
      expect(decreto.first.limpio, isTrue);

      final ordenanza = ExtractorEncabezado.extraer(
        'ORDENANZA MUNICIPAL\nNro. 003-2025-MDP\nPocollay, 23 de abril del 2025.',
        ahora: 2026,
      );
      expect(ordenanza.first.numero, '003');
      expect(ordenanza.first.anio, '2025');
      expect(ordenanza.first.siglas, 'MDP');
      expect(ordenanza.first.limpio, isTrue);

      final resolucion = ExtractorEncabezado.extraer(
        'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T',
        ahora: 2026,
      );
      expect(resolucion.single.siglas, 'A-MDP-T');
      final acuerdo = ExtractorEncabezado.extraer(
        'ACUERDO DE CONCEJO MUNICIPAL N° 019-2025-CM-MDP-T',
        ahora: 2026,
      );
      expect(acuerdo.single.siglas, 'CM-MDP-T');
    });

    test('quita el membrete de continuación de una ordenanza', () {
      const pagina =
          'Año de la recuperación\nORDENANZA MUNICIPAL\nNro. 003-2025-MDP\n'
          'Que, el artículo 111 de la Ley continúa el considerando.';
      final r = ExtractorEncabezado.quitarMembrete(pagina);
      expect(r, startsWith('Que, el artículo 111'));
      expect(r, isNot(contains('Nro.')));
    });

    test('quita el membrete repetido de las páginas de continuación', () {
      const pagina2 =
          'Año de la esperanza\nRESOLUCIÓN DE SUB GERENCIA DE DESARROLLO TERRITORIAL\n'
          'N° 0111-2026-SGDT-GDTI-MDP-T GROUP S.A.C, ubicado en la avenida.\nARTÍCULO SEGUNDO: NOTIFICAR.';
      final r = ExtractorEncabezado.quitarMembrete(pagina2);
      expect(r, startsWith('GROUP S.A.C'));
      expect(r, isNot(contains('RESOLUCIÓN')));
    });

    test('no quita texto si el código hallado es de un documento citado', () {
      const pagina =
          'Que, mediante Informe N° 093-2026-A-MDP/T de fecha 08 de junio se dispone lo siguiente.';
      expect(ExtractorEncabezado.quitarMembrete(pagina), pagina);
    });

    test('un artículo que cruza de página no se corta por el membrete', () {
      const p1 =
          'SE RESUELVE:\nARTÍCULO PRIMERO: DECLARAR PROCEDENTE el procedimiento solicitado por la Sra. SONIA, en calidad de representante legal de EDVAL';
      const p2 =
          'RESOLUCIÓN DE ALCALDÍA\nNo. 074-2026-A-MDP/T GROUP S.A.C, en el distrito de Pocollay.\nARTÍCULO SEGUNDO: NOTIFICAR.';
      final cuerpo = [p1, ExtractorEncabezado.quitarMembrete(p2)].join('\n');
      final r = ExtractorArticuloPrimero.extraer(cuerpo);
      expect(r.principal, endsWith('GROUP S.A.C, en el distrito de Pocollay.'));
      expect(r.avisos, isEmpty);
    });

    test('año fuera de rango (OCR 2076) no se acepta', () {
      final c = ExtractorEncabezado.extraer('N° 074-2076-A-MDP/T', ahora: 2026);
      expect(c.first.anio, isNull);
    });

    test('siglas desconocidas o aproximadas', () {
      final a = ExtractorEncabezado.extraer(
        'N° 012-2026-SGDELC-MDP/T',
        ahora: 2026,
      ).first;
      expect(a.siglasConocidas, isFalse);
      final b = ExtractorEncabezado.extraer(
        'N° 012-2026-A-MDP/1',
        ahora: 2026,
      ).first;
      expect(b.siglas, 'A-MDP-T');
      expect(b.siglasAproximadas, isTrue);
    });

    test('el encabezado excluye las resoluciones citadas en los considerandos', () {
      const t =
          'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP/T\nVISTO:\nQue, mediante Resolución de Gerencia Municipal N° 045-2025-GM-MDP/T';
      final c = ExtractorEncabezado.extraer(
        ExtractorEncabezado.seccionEncabezado(t),
        ahora: 2026,
      );
      expect(c, hasLength(1));
      expect(c.first.numero, '074');
    });
  });

  group('Artículo Primero', () {
    const texto = '''
RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP/T
Pocollay, 08 JUL. 2026
VISTO:
El Informe N° 120-2026 y la Resolución de Alcaldía N° 010-2026-A-MDP/T que en su ARTÍCULO PRIMERO: APROBAR
el plan anterior; y,
CONSIDERANDO:
Que, corresponde emitir el acto resolutivo;
SE RESUELVE:
ARTÍCULO PRIMERO: AUTORIZAR, la incorporación de Mayores Ingresos Púbicos mediante Crédito
Suplementario del presupuesto institucional, de acuerdo con el siguiente detalle:
INGRESOS
FUENTE DE FINANCIAMIENTO RUBRO MONTO
S/ 120,000.00 S/ 80,000.00
EGRESOS
ARTÍCULO SEGUNDO: ENCARGAR a la Gerencia Municipal el cumplimiento.
''';

    test('no se confunde con la mención dentro de los considerandos', () {
      final r = ExtractorArticuloPrimero.extraer(texto);
      expect(r.principal, startsWith('AUTORIZAR, la incorporación'));
      expect(r.principal, isNot(contains('APROBAR')));
      expect(r.principal, isNot(contains('ARTÍCULO PRIMERO')));
      expect(r.avisos, isEmpty);
    });

    test('separa el párrafo principal del cuadro y conserva la ortografía original', () {
      final r = ExtractorArticuloPrimero.extraer(texto);
      expect(
        r.principal,
        'AUTORIZAR, la incorporación de Mayores Ingresos Púbicos mediante Crédito Suplementario '
        'del presupuesto institucional, de acuerdo con el siguiente detalle:',
      );
      expect(r.principal, contains('Púbicos'));
      expect(r.completo, contains('INGRESOS'));
      expect(r.completo, isNot(contains('ENCARGAR')));
    });

    test('bloque de licencia de funcionamiento', () {
      const t = '''
SE RESUELVE:
ARTICULO PRIMERO.- APROBAR LICENCIA DE FUNCIONAMIENTO, a favor de Juan Pérez, cuyas especificaciones se detallan a continuación:
Se Otorga Licencia a: JUAN PEREZ
Actividad Económica a Desarrollar: BODEGA
Nombre Comercial: LA ESQUINA
Ubicado en: Calle Los Pinos 123
Área: 20 m2
ARTÍCULO SEGUNDO: NOTIFICAR.
''';
      final r = ExtractorArticuloPrimero.extraer(t);
      expect(
        r.principal,
        'APROBAR LICENCIA DE FUNCIONAMIENTO, a favor de Juan Pérez, cuyas especificaciones se detallan a continuación:',
      );
      expect(r.completo, contains('LA ESQUINA'));
    });

    test(
      'corta antes del bloque aunque el párrafo no termine en dos puntos',
      () {
        const t = '''
SE RESUELVE
ÁRTICULO PRIMERO: APROBAR LICENCIA DE FUNCIONAMIENTO por el plazo indefinido a favor del administrado.
Se Otorga Licencia a: MARIA LOPEZ
Nombre Comercial: TIENDA
ARTICULO SEGUNDO: NOTIFICAR.
''';
        final r = ExtractorArticuloPrimero.extraer(t);
        expect(
          r.principal,
          'APROBAR LICENCIA DE FUNCIONAMIENTO por el plazo indefinido a favor del administrado.',
        );
      },
    );

    test('la prosa con años y montos no se confunde con un cuadro', () {
      const t = '''
SE RESUELVE:
ARTÍCULO PRIMERO: RECONOCER, la Nueva Junta Directiva del Comité "SAN JUAN", cuya vigencia
comprende desde el 01 de febrero del 2026 hasta el 01 de febrero del 2027, a favor del administrado.
ARTÍCULO SEGUNDO: NOTIFICAR.
''';
      final r = ExtractorArticuloPrimero.extraer(t);
      expect(r.principal, endsWith('a favor del administrado.'));
      expect(r.principal, contains('del 2027'));

      const t2 = '''
SE RESUELVE:
ARTÍCULO PRIMERO: RECONOCER el pago a favor del proveedor, correspondiente a las ORDENES DE
SERVICIO N* 6504-2025 del 2025, por el monto de S/ 1,400.00 (MIL CUATROCIENTOS soles).
ARTÍCULO SEGUNDO: NOTIFICAR.
''';
      expect(
        ExtractorArticuloPrimero.extraer(t2).principal,
        endsWith('(MIL CUATROCIENTOS soles).'),
      );
    });

    test('una etiqueta suelta con ":" tras una oración cerrada no pertenece al párrafo', () {
      const t = '''
SE RESUELVE:
ARTÍCULO PRIMERO: APROBAR la Liquidación Técnica y Financiera del PIP con un costo total de S/. 603,187.74 soles (Seiscientos tres mil).
REVISION:
Gerencia de Desarrollo
ARTÍCULO SEGUNDO: NOTIFICAR.
''';
      final r = ExtractorArticuloPrimero.extraer(t);
      expect(r.principal, endsWith('(Seiscientos tres mil).'));
      expect(r.principal, isNot(contains('REVISION')));
    });

    test('una fila de cuadro (solo importes) sí corta el párrafo', () {
      const t = '''
SE RESUELVE:
ARTÍCULO PRIMERO: AUTORIZAR, la transferencia de partidas entre los pliegos que se indican en el cuadro adjunto.
S/ 120,000.00 S/ 80,000.00 S/ 40,000.00
ARTÍCULO SEGUNDO: NOTIFICAR.
''';
      final r = ExtractorArticuloPrimero.extraer(t);
      expect(r.principal, endsWith('en el cuadro adjunto.'));
      expect(r.completo, contains('120,000.00'));
    });

    test('un salto CRLF no recorta el final del párrafo', () {
      const lf = '''
SE RESUELVE:
ARTÍCULO PRIMERO: AUTORIZAR, la incorporación de Mayores Ingresos Públicos
mediante Crédito Suplementario, de acuerdo con el siguiente detalle:
INGRESOS
PLIEGO 120,000.00
ARTÍCULO SEGUNDO: NOTIFICAR.
''';
      final conLf = ExtractorArticuloPrimero.extraer(lf);
      final conCrlf = ExtractorArticuloPrimero.extraer(
        lf.replaceAll('\n', '\r\n'),
      );
      expect(conCrlf.principal, conLf.principal);
      expect(conCrlf.principal, endsWith('detalle:'));
    });

    test('tolera variaciones OCR de SE RESUELVE y ARTÍCULO PRIMERO', () {
      const t =
          'CONSIDERANDO: algo.\nSE RESUELV E:\nARTICUL0 PRIMERO.- DECLARAR procedente la solicitud presentada por el administrado.\nARTICULO SEGUNDO.- NOTIFICAR.';
      final r = ExtractorArticuloPrimero.extraer(t);
      expect(r.principal, startsWith('DECLARAR procedente'));
    });

    test('marca revisión si falta SE RESUELVE o ARTÍCULO PRIMERO', () {
      expect(
        ExtractorArticuloPrimero.extraer('texto sin nada relevante')
            .requiereRevision,
        isTrue,
      );
      final r = ExtractorArticuloPrimero.extraer(
        'SE RESUELVE:\nartículo único: algo',
      );
      expect(r.requiereRevision, isTrue);
    });

    test('marca revisión si no hay ARTÍCULO SEGUNDO', () {
      final r = ExtractorArticuloPrimero.extraer(
        'SE RESUELVE:\nARTÍCULO PRIMERO: AUTORIZAR el gasto indicado en el expediente administrativo.',
      );
      expect(r.principal, startsWith('AUTORIZAR'));
      expect(r.requiereRevision, isTrue);
    });
  });

  group('Consolidación y validación', () {
    const encabezadoLimpio =
        'RESOLUCIÓN DE SUBGERENCIA DE DESARROLLO ECONÓMICO, LICENCIAS Y CONTROL\n'
        'N° 50-2026-SGDELC-GDESGA-MDP/T\nPocollay, 16 JUN. 2026\nVISTO: ...';

    test('texto nativo limpio → todo DETECTADO', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(encabezadoLimpio, OrigenLectura.nativo),
      ], ahora: 2026);
      expect(r.numero, '050');
      expect(r.estadoNumero, EstadoCampo.detectado);
      expect(r.fecha, '16/06/2026');
      expect(r.estadoFecha, EstadoCampo.detectado);
      expect(r.tipo!.siglas, 'SGDELC-GDESGA-MDP-T');

      final datos = ValidadorCampos.construir(
        r,
        const ResultadoArticulo(
          principal: 'AUTORIZAR, algo.',
          completo: 'AUTORIZAR, algo.',
        ),
      );
      expect(datos.codigo.valor, '050-2026-SGDELC-GDESGA-MDP-T');
      expect(
        datos.nombreCompleto.valor,
        'RESOLUCIÓN DE SUBGERENCIA DE DESARROLLO ECONÓMICO, LICENCIAS Y CONTROL N° 050-2026-SGDELC-GDESGA-MDP-T',
      );
      expect(datos.fecha.valor, '16/06/2026');
      expect(datos.camposPorRevisar, 0);
    });

    test('una sola lectura OCR no basta: requiere revisión', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(encabezadoLimpio, OrigenLectura.ocrPagina),
      ], ahora: 2026);
      expect(r.numero, '050');
      expect(r.estadoNumero, EstadoCampo.requiereRevision);
      expect(r.estadoFecha, EstadoCampo.requiereRevision);
    });

    test('dos lecturas OCR coincidentes: fecha y siglas DETECTADO; número REQUIERE REVISIÓN '
        '(ambas lecturas son Tesseract sobre el mismo recorte, no corroboración independiente)', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(encabezadoLimpio, OrigenLectura.ocrPagina),
        const LecturaTexto(encabezadoLimpio, OrigenLectura.ocrFocalizado),
      ], ahora: 2026);
      expect(r.estadoNumero, EstadoCampo.requiereRevision);
      expect(r.estadoFecha, EstadoCampo.detectado);
      expect(r.estadoSiglas, EstadoCampo.detectado);
    });

    test(
      'dos lecturas OCR coincidentes + otra página: número también DETECTADO',
      () {
        final r = ConsolidadorEncabezado.consolidar([
          const LecturaTexto(encabezadoLimpio, OrigenLectura.ocrPagina),
          const LecturaTexto(encabezadoLimpio, OrigenLectura.ocrFocalizado),
          const LecturaTexto(
            'N° 50-2026-SGDELC-GDESGA-MDP/T',
            OrigenLectura.otraPagina,
          ),
        ], ahora: 2026);
        expect(r.estadoNumero, EstadoCampo.detectado);
      },
    );

    test('número mal leído por solo dos lecturas: no se propone y REQUIERE REVISIÓN', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(
          'RESOLUCIÓN DE ALCALDÍA N° O+4-2026-A-MDP/T',
          OrigenLectura.ocrFocalizado,
        ),
        const LecturaTexto(
          'RESOLUCIÓN DE ALCALDÍA N° OY 4-2026-A-MDP/T',
          OrigenLectura.ocrFocalizado,
        ),
      ], ahora: 2026);
      expect(r.numero, isNull);
      expect(r.estadoNumero, EstadoCampo.requiereRevision);
      expect(r.notaNumero, contains('O+4'));
    });

    test('una lectura limpia corroborada por reparadas, todas de OCR de texto: '
        'propone el número pero REQUIERE REVISIÓN (falta corroboración independiente)', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(
          'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP/T',
          OrigenLectura.ocrFocalizado,
        ),
        const LecturaTexto(
          'RESOLUCIÓN DE ALCALDÍA N° O+4-2026-A-MDP/T',
          OrigenLectura.ocrFocalizado,
        ),
        const LecturaTexto(
          'RESOLUCIÓN DE ALCALDÍA N° OY 4-2026-A-MDP/T',
          OrigenLectura.ocrPagina,
        ),
      ], ahora: 2026);
      expect(r.numero, '074');
      expect(r.estadoNumero, EstadoCampo.requiereRevision);
    });

    test(
      'una lectura limpia corroborada por reparadas + otra página → DETECTADO',
      () {
        final r = ConsolidadorEncabezado.consolidar([
          const LecturaTexto(
            'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP/T',
            OrigenLectura.ocrFocalizado,
          ),
          const LecturaTexto(
            'RESOLUCIÓN DE ALCALDÍA N° O+4-2026-A-MDP/T',
            OrigenLectura.ocrFocalizado,
          ),
          const LecturaTexto(
            'RESOLUCIÓN DE ALCALDÍA N° OY 4-2026-A-MDP/T',
            OrigenLectura.ocrPagina,
          ),
          const LecturaTexto(
            'Resolución N° 074-2026-A-MDP/T',
            OrigenLectura.otraPagina,
          ),
        ], ahora: 2026);
        expect(r.numero, '074');
        expect(r.estadoNumero, EstadoCampo.detectado);
      },
    );

    test('lecturas distintas del número → conflicto, REQUIERE REVISIÓN', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto('N° 074-2026-A-MDP/T', OrigenLectura.ocrFocalizado),
        const LecturaTexto('N° 071-2026-A-MDP/T', OrigenLectura.ocrFocalizado),
      ], ahora: 2026);
      expect(r.estadoNumero, EstadoCampo.requiereRevision);
      expect(r.notaNumero, contains('distintas'));
    });

    test('el encabezado de otras páginas corrobora el número', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(
          'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP/T',
          OrigenLectura.ocrFocalizado,
        ),
        const LecturaTexto(
          'Resolución N° 074-2026-A-MDP/T',
          OrigenLectura.otraPagina,
        ),
      ], ahora: 2026);
      expect(r.estadoNumero, EstadoCampo.detectado);
    });

    test('un código citado en otra página con otras siglas/año no cuenta', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto('N° 074-2026-A-MDP/T', OrigenLectura.ocrFocalizado),
        const LecturaTexto(
          'Resolución N° 045-2025-GM-MDP/T',
          OrigenLectura.otraPagina,
        ),
      ], ahora: 2026);
      expect(r.numero, '074');
    });

    test('año del sello leído mal (2076): se propone con el año del código pero REQUIERE REVISIÓN', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(
          'N° 074-2026-A-MDP/T\nPocollay, 0 8 JUL. 2076',
          OrigenLectura.ocrFocalizado,
        ),
        const LecturaTexto(
          'N° 074-2026-A-MDP/T\nPocollay, 0 8 JUL. 7076',
          OrigenLectura.ocrFocalizado,
        ),
      ], ahora: 2026);
      expect(r.fecha, '08/07/2026');
      expect(r.estadoFecha, EstadoCampo.requiereRevision);
      expect(r.notaFecha, contains('2076'));
    });

    test('la fecha que sigue a "Pocollay," prevalece sobre fechas citadas', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(
          'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP/T\nPocollay, 30 de junio del 2026\nSolicitud s/n de fecha 03 de junio del 2026',
          OrigenLectura.nativo,
        ),
      ], ahora: 2026);
      expect(r.fecha, '30/06/2026');
      expect(r.estadoFecha, EstadoCampo.detectado);
    });

    test('sin "Pocollay," se usa la primera fecha no citada, pero solo como sugerencia', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(
          'N° 074-2026-A-MDP/T\n08 JUL. 2026\nde fecha 03 de junio del 2026',
          OrigenLectura.nativo,
        ),
      ], ahora: 2026);
      expect(r.fecha, '08/07/2026');
      expect(r.estadoFecha, EstadoCampo.requiereRevision);
      expect(r.notaFecha, contains('Pocollay'));
    });

    test(
      'solo fechas citadas ("de fecha …") y ninguna fecha propia → sin fecha',
      () {
        final r = ConsolidadorEncabezado.consolidar([
          const LecturaTexto(
            'N° 074-2026-A-MDP/T\nSolicitud s/n de fecha 03 de junio del 2026, informe de fecha 24 de junio de 2026',
            OrigenLectura.nativo,
          ),
        ], ahora: 2026);
        expect(r.fecha, isNull);
        expect(r.estadoFecha, EstadoCampo.requiereRevision);
      },
    );

    test('caso real: sello "30 JUN 2076" frente a fechas citadas en los VISTOS (sin cortar)', () {
      const lectura =
          'RESOLUCIÓN DE GERENCIA DE DESARROLLO ECONÓMICO, SOCIAL Y GESTIÓN AMBIENTAL\nN° 63 -2026-GDESGA-MDP/T\n'
          'Pocollay, 30 JUN 2076\nISTOS: Solicitud s/n de fecha 03 de junio del 2026; Informe N° 093-2026-PVL-GDESGA/MDP-T '
          'de fecha 08 de junio del 2026; Informe de fecha 24 de junio de 2026, y;';
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(lectura, OrigenLectura.ocrFocalizado),
        const LecturaTexto(lectura, OrigenLectura.ocrFocalizado),
      ], ahora: 2026);
      expect(r.fecha, '30/06/2026');
      expect(r.estadoFecha, EstadoCampo.requiereRevision);
      expect(r.fecha, isNot('24/06/2026'));
    });

    test(
      'el encabezado se corta en VISTOS (plural) y no toma códigos citados',
      () {
        final r = ConsolidadorEncabezado.consolidar([
          const LecturaTexto(
            'RESOLUCIÓN DE ALCALDÍA\nNo. 074-2026-A-MDP/T\nPocollay, 08 JUL. 2026\nVISTOS:\nEl Informe N° 0576-2026-OGPPMPI/MDP-T de fecha 06 de julio del 2026',
            OrigenLectura.nativo,
          ),
        ], ahora: 2026);
        expect(r.numero, '074');
        expect(r.fecha, '08/07/2026');
        expect(r.siglas, 'A-MDP-T');
      },
    );

    test(
      'lecturas débiles del número no se proponen (manuscrito ilegible)',
      () {
        final r = ConsolidadorEncabezado.consolidar([
          const LecturaTexto(
            'N° O+4-2026-A-MDP/T',
            OrigenLectura.ocrFocalizado,
          ),
          const LecturaTexto('N° OT-2026-A-MDP/T', OrigenLectura.ocrFocalizado),
          const LecturaTexto('5', OrigenLectura.ocrSoloDigitos),
        ], ahora: 2026);
        expect(r.estadoNumero, EstadoCampo.requiereRevision);
        expect(r.numero, isNull);
      },
    );

    test('tres lecturas dudosas coincidentes sí se proponen, pero REQUIEREN REVISIÓN', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto('No. O+4-2026-A-MDP/T', OrigenLectura.ocrFocalizado),
        const LecturaTexto(
          'No. OY 4-2026-A-MDP/T',
          OrigenLectura.ocrFocalizado,
        ),
        const LecturaTexto('No. O+4-2026-A-MDP/T', OrigenLectura.ocrPagina),
      ], ahora: 2026);
      expect(r.numero, '074');
      expect(r.estadoNumero, EstadoCampo.requiereRevision);
    });

    test('número manuscrito: una lectura ilegible impide darlo por detectado aunque otras coincidan', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(
          'No. 074 -2026-A-MDP/T',
          OrigenLectura.ocrFocalizado,
        ),
        const LecturaTexto(
          'No. 074 -2026-A-MDP/T',
          OrigenLectura.ocrFocalizado,
        ),
        const LecturaTexto(
          'Resolución N° 074-2026-A-MDP/T',
          OrigenLectura.otraPagina,
        ),
        const LecturaTexto(
          'No. O3 Y-2026-A-MDP/T',
          OrigenLectura.ocrFocalizado,
        ),
      ], ahora: 2026);
      expect(r.numero, '074');
      expect(r.estadoNumero, EstadoCampo.requiereRevision);
      expect(r.notaNumero, contains('ilegibles'));
    });

    test(
      'fecha: una lectura inválida del sello impide darla por detectada',
      () {
        const ok = 'N° 074-2026-A-MDP/T\nPocollay, 08 JUL. 2026';
        final r = ConsolidadorEncabezado.consolidar([
          const LecturaTexto(ok, OrigenLectura.ocrFocalizado),
          const LecturaTexto(ok, OrigenLectura.ocrFocalizado),
          const LecturaTexto(
            'N° 074-2026-A-MDP/T\nPocollay, 41 JUL. 2026',
            OrigenLectura.ocrFocalizado,
          ),
        ], ahora: 2026);
        expect(r.fecha, '08/07/2026');
        expect(r.estadoFecha, EstadoCampo.requiereRevision);
      },
    );

    test('fecha: si el ancla "Pocollay," no da nada utilizable, se usa la primera fecha propia (débil)', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(
          'N° 097-2026-A-MDP/T\nPocollay, ###\n31 de agosto del 2026',
          OrigenLectura.ocrFocalizado,
        ),
      ], ahora: 2026);
      expect(r.fecha, isNotNull);
      expect(r.estadoFecha, EstadoCampo.requiereRevision);
    });

    test(
      'siglas con una lectura limpia y otra aproximada → DETECTADO '
      '(el número, sin corroboración independiente, queda REQUIERE REVISIÓN)',
      () {
        final r = ConsolidadorEncabezado.consolidar([
          const LecturaTexto(
            'N° 0121-2026-SGDT-GDTI-MDP-T',
            OrigenLectura.ocrFocalizado,
          ),
          const LecturaTexto(
            'N° 0121-2026-SGDI-GDTI-MDP-T',
            OrigenLectura.ocrFocalizado,
          ),
          const LecturaTexto(
            'N° 0121-2026-SGDT-GDTI-MDP-T',
            OrigenLectura.ocrPagina,
          ),
        ], ahora: 2026);
        expect(r.estadoSiglas, EstadoCampo.detectado);
        expect(r.numero, '121');
        expect(r.estadoNumero, EstadoCampo.requiereRevision);
      },
    );

    test('fecha con lectura OCR inválida no se inventa', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(
          'N° 074-2026-A-MDP/T\nPocollay, 0 g JUL. 2076',
          OrigenLectura.ocrFocalizado,
        ),
      ], ahora: 2026);
      expect(r.fecha, isNull);
      expect(r.estadoFecha, EstadoCampo.requiereRevision);
      expect(r.notaFecha, contains('JUL'));
    });

    test('sin número: código con marcador visible y REQUIERE REVISIÓN', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(
          'RESOLUCIÓN DE ALCALDÍA N° ___-2026-A-MDP/T',
          OrigenLectura.nativo,
        ),
      ], ahora: 2026);
      expect(r.numero, isNull);
      final d = ValidadorCampos.construir(
        r,
        const ResultadoArticulo(principal: 'AUTORIZAR, algo.', completo: 'x'),
      );
      expect(d.codigo.valor, '___-2026-A-MDP-T');
      expect(d.codigo.estado, EstadoCampo.requiereRevision);
      expect(d.nombreCompleto.estado, EstadoCampo.requiereRevision);
    });

    test('siglas desconocidas marcan revisión y no inventan tipo', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto('N° 012-2026-SGDELC-MDP/T', OrigenLectura.nativo),
      ], ahora: 2026);
      expect(r.estadoSiglas, EstadoCampo.requiereRevision);
      expect(r.tipo, isNull);
    });

    test('tipo del texto distinto del de las siglas → REQUIERE REVISIÓN', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(
          'RESOLUCIÓN DE GERENCIA MUNICIPAL N° 074-2026-A-MDP/T',
          OrigenLectura.nativo,
        ),
      ], ahora: 2026);
      expect(r.estadoTipo, EstadoCampo.requiereRevision);
    });
  });

  group('Redes neuronales en la votación', () {
    List<double> p(int d, double c) => [
      for (var i = 0; i < 10; i++) i == d ? c : (1 - c) / 9,
    ];
    LecturaTexto red(
      String t,
      double porDigito, [
      OrigenLectura o = OrigenLectura.redNeuronal,
    ]) => LecturaTexto(
      t,
      o,
      probabilidades: [for (final c in t.split('')) p(int.parse(c), porDigito)],
    );

    const limpia =
        'RESOLUCIÓN DE GERENCIA MUNICIPAL\nNo. 146 -2026-GM-MDP/T\nPocollay, 02 OCT. 2026';

    test('la red y una lectura de texto coinciden → DETECTADO aunque otra lectura sea basura', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(limpia, OrigenLectura.ocrFocalizado),
        const LecturaTexto(
          'RESOLUCIÓN DE GERENCIA MUNICIPAL\nNo. O3 Y-2026-GM-MDP/T',
          OrigenLectura.ocrFocalizado,
        ),
        red('146', 0.98),
      ], ahora: 2026);
      expect(r.numero, '146');
      expect(r.estadoNumero, EstadoCampo.detectado);
    });

    test('la red sola propone el número pero REQUIERE REVISIÓN', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(
          'RESOLUCIÓN DE GERENCIA MUNICIPAL\nNo. -2026-GM-MDP/T',
          OrigenLectura.ocrFocalizado,
        ),
        red('146', 0.98),
      ], ahora: 2026);
      expect(r.numero, '146');
      expect(r.estadoNumero, EstadoCampo.requiereRevision);
    });

    test(
      'una lectura errónea repetida de Tesseract no tapa a la red neuronal',
      () {
        final r = ConsolidadorEncabezado.consolidar([
          for (var i = 0; i < 4; i++)
            const LecturaTexto(
              'RESOLUCIÓN DE GERENCIA MUNICIPAL\nNo. 046 -2026-GM-MDP/T',
              OrigenLectura.ocrFocalizado,
            ),
          red('146', 0.98),
        ], ahora: 2026);
        expect(r.numero, '146');
        expect(r.estadoNumero, EstadoCampo.requiereRevision);
      },
    );

    test('la red que ve otra cosa que Tesseract impide el DETECTADO', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(limpia, OrigenLectura.ocrFocalizado),
        const LecturaTexto(limpia, OrigenLectura.ocrPagina),
        red('177', 0.98),
      ], ahora: 2026);
      expect(r.estadoNumero, EstadoCampo.requiereRevision);
    });

    const sello =
        'RESOLUCIÓN DE GERENCIA MUNICIPAL\nNo. 146 -2026-GM-MDP/T\nPocollay, 07 OCT. 2076';

    test(
      'día del sello: la red corrige al OCR con confianza alta → DETECTADO',
      () {
        final r = ConsolidadorEncabezado.consolidar([
          const LecturaTexto(sello, OrigenLectura.ocrFocalizado),
          const LecturaTexto(sello, OrigenLectura.ocrFocalizado),
          red('02', 0.97, OrigenLectura.redSello),
        ], ahora: 2026);
        expect(r.fecha, '02/10/2026');
        expect(r.estadoFecha, EstadoCampo.detectado);
      },
    );

    test('día del sello: la red coincide con el OCR → DETECTADO', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(sello, OrigenLectura.ocrFocalizado),
        red('07', 0.97, OrigenLectura.redSello),
      ], ahora: 2026);
      expect(r.fecha, '07/10/2026');
      expect(r.estadoFecha, EstadoCampo.detectado);
    });

    test(
      'día del sello: confianza media → se propone pero REQUIERE REVISIÓN',
      () {
        final r = ConsolidadorEncabezado.consolidar([
          const LecturaTexto(sello, OrigenLectura.ocrFocalizado),
          const LecturaTexto(sello, OrigenLectura.ocrFocalizado),
          red('02', 0.8, OrigenLectura.redSello),
        ], ahora: 2026);
        expect(r.fecha, '02/10/2026');
        expect(r.estadoFecha, EstadoCampo.requiereRevision);
        expect(r.notaFecha, contains('red neuronal'));
      },
    );

    test('día del sello: confianza baja → se ignora', () {
      final r = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(sello, OrigenLectura.ocrFocalizado),
        const LecturaTexto(sello, OrigenLectura.ocrFocalizado),
        red('02', 0.5, OrigenLectura.redSello),
      ], ahora: 2026);
      expect(r.fecha, '07/10/2026');
      expect(r.estadoFecha, EstadoCampo.requiereRevision);
    });
  });

  group('Acuerdo de Concejo Municipal', () {
    const acuerdo = '''
ACUERDO DE CONCEJO MUNICIPAL
N* 8-2026-CM-MDP/T
Pocollay, 07 de enero de 2026.
EL ALCALDE DE LA MUNICIPALIDAD DISTRITAL DE POCOLLAY;
VISTO:
Que, la Resolución de Alcaldía N° 010-2025-A-MDP-T, en su ARTÍCULO PRIMERO: DISPONER una medida citada que no es este acuerdo.
Que, el artículo 41 de la Ley N° 27972 señala que los acuerdos son decisiones del concejo.
ACUERDO:
ARTÍCULO PRIMERO.- APROBAR la priorización del plan de trabajo del distrito, con cargo al presupuesto institucional.
ARTÍCULO SEGUNDO.- ENCARGAR a la Gerencia Municipal el cumplimiento del presente acuerdo.
''';

    test('extrae los cuatro campos y normaliza el número a tres cifras', () {
      expect(
        CatalogoResoluciones.esAcuerdoDeConcejo(ExtractorEncabezado.seccionEncabezado(acuerdo)),
        isTrue,
      );
      final enc = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(acuerdo, OrigenLectura.nativo),
      ], ahora: 2026);
      final art = ExtractorArticuloPrimero.extraer(acuerdo, anclaAcuerdo: true);
      final datos = ValidadorCampos.construir(enc, art);

      expect(datos.nombreCompleto.valor, 'ACUERDO DE CONCEJO MUNICIPAL N° 008-2026-CM-MDP-T');
      expect(datos.nombreCompleto.estado, EstadoCampo.detectado);
      expect(datos.codigo.valor, '008-2026-CM-MDP-T');
      expect(datos.codigo.estado, EstadoCampo.detectado);
      expect(datos.fecha.valor, '07/01/2026');
      expect(datos.fecha.estado, EstadoCampo.detectado);
      expect(datos.articuloPrimeroPrincipal.valor, startsWith('APROBAR la priorización'));
      expect(datos.articuloPrimeroPrincipal.valor, isNot(contains('DISPONER')));
      expect(datos.articuloPrimeroPrincipal.estado, EstadoCampo.detectado);
    });

    test('no usa un ARTÍCULO PRIMERO citado antes del bloque ACUERDO:', () {
      final r = ExtractorArticuloPrimero.extraer(acuerdo, anclaAcuerdo: true);
      expect(r.principal, startsWith('APROBAR la priorización'));
      expect(r.principal, isNot(contains('DISPONER')));
    });

    test('sin el bloque ACUERDO: queda en revisión y no toma la cita anterior', () {
      const sinBloque = '''
ACUERDO DE CONCEJO MUNICIPAL
N° 002-2026-CM-MDP-T
Pocollay, 02 de febrero de 2026.
VISTO:
Que, la Resolución N° 010-2025-A-MDP-T en su ARTÍCULO PRIMERO: APROBAR una cita previa que no es el acuerdo.
''';
      final r = ExtractorArticuloPrimero.extraer(sinBloque, anclaAcuerdo: true);
      expect(r.principal, isEmpty);
      expect(r.requiereRevision, isTrue);
      expect(r.avisos.join(' '), contains('ACUERDO:'));
    });

    test('quita el membrete de un acuerdo en la página de continuación', () {
      const pagina =
          'ACUERDO DE CONCEJO MUNICIPAL\nN° 001-2026-CM-MDP-T del distrito.\nARTÍCULO SEGUNDO: NOTIFICAR.';
      final r = ExtractorEncabezado.quitarMembrete(pagina);
      expect(r, startsWith('del distrito'));
      expect(r, isNot(contains('ACUERDO DE CONCEJO')));
    });
  });

  group('Regresión de resoluciones frente a un acuerdo citado', () {
    const resolucion = '''
RESOLUCIÓN DE ALCALDÍA
N° 074-2026-A-MDP/T
Pocollay, 08 de julio de 2026
VISTO:
Que, mediante Acuerdo de Concejo Municipal N° 010-2026-CM-MDP-T, en su ARTÍCULO PRIMERO: APROBAR un plan citado que no es el de esta resolución.
CONSIDERANDO:
SE RESUELVE:
ARTÍCULO PRIMERO: AUTORIZAR el gasto indicado en el expediente administrativo de la municipalidad.
ARTÍCULO SEGUNDO: NOTIFICAR a los interesados conforme a ley.
''';

    test('sigue extrayendo la resolución y no el acuerdo citado', () {
      expect(
        CatalogoResoluciones.esAcuerdoDeConcejo(ExtractorEncabezado.seccionEncabezado(resolucion)),
        isFalse,
      );
      final enc = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(resolucion, OrigenLectura.nativo),
      ], ahora: 2026);
      final art = ExtractorArticuloPrimero.extraer(resolucion);
      final datos = ValidadorCampos.construir(enc, art);

      expect(datos.nombreCompleto.valor, 'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T');
      expect(datos.codigo.valor, '074-2026-A-MDP-T');
      expect(datos.codigo.estado, EstadoCampo.detectado);
      expect(datos.fecha.valor, '08/07/2026');
      expect(datos.articuloPrimeroPrincipal.valor, startsWith('AUTORIZAR el gasto'));
      expect(datos.articuloPrimeroPrincipal.valor, isNot(contains('plan citado')));
      expect(enc.siglas, 'A-MDP-T');
    });
  });

  group('Decreto de alcaldía y ordenanza municipal', () {
    const decreto = '''
DECRETO DE ALCALDÍA
N° 008-2025-MDP-T
Pocollay, 27 de agosto de 2025.
EL ALCALDE DE LA MUNICIPALIDAD DISTRITAL DE POCOLLAY:
VISTOS:
La Ordenanza Regional N° 012-2025-CR/GOB.REG.TACNA, de fecha 05 de junio de 2025.
CONSIDERANDO:
Que, la Ley Orgánica de Municipalidades señala que el alcalde ejerce las funciones mediante decretos de alcaldía.
Que, mediante Ordenanza Regional se ordenó: "ARTÍCULO PRIMERO: DECLARAR día cívico no laborable el día 1 de setiembre."
En uso de sus facultades conferidas.
DECRETA:
ARTÍCULO PRIMERO.- DECLARAR, EL DÍA 01 DE SETIEMBRE DEL 2025, FERIADO NO LABORABLE, COMPENSABLE, para los trabajadores de la Municipalidad Distrital de Pocollay.
ARTÍCULO SEGUNDO.- DISPONER que las horas dejadas de laborar se compensen.
''';

    const ordenanza = '''
ORDENANZA MUNICIPAL
Nro. 003-2025-MDP
Pocollay, 23 de abril del 2025.
EL ALCALDE DE LA MUNICIPALIDAD DISTRITAL DE POCOLLAY;
VISTO:
El Acuerdo de Concejo Municipal N° 019-2025-CM-MDP-T de fecha 23 de abril de 2025.
CONSIDERANDO:
Que, el artículo 9 de la Ley N° 27972 señala aprobar, modificar o derogar las ordenanzas.
Estando a lo actuado, el Concejo Distrital de Pocollay, por UNANIMIDAD, aprobó la siguiente:
ORDENANZA MUNICIPAL
QUE APRUEBA EL REGLAMENTO DE ORGANIZACIÓN Y FUNCIONES DE JUNTAS VECINALES
ARTÍCULO PRIMERO.- APROBAR, el REGLAMENTO DE ORGANIZACIÓN Y FUNCIONES de las JUNTAS VECINALES COMUNALES DEL DISTRITO DE POCOLLAY, el cual forma parte integrante de la presente Ordenanza Municipal.
ARTÍCULO SEGUNDO.- FACULTAR, al Titular de la Entidad, a dictar mediante Decreto de Alcaldía las disposiciones complementarias.
''';

    test('decreto: título, código, fecha y el artículo que sigue a DECRETA', () {
      final enc = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(decreto, OrigenLectura.nativo),
      ], ahora: 2026);
      final art = ExtractorArticuloPrimero.extraer(decreto, ancla: AnclaDispositiva.decreta);
      final datos = ValidadorCampos.construir(enc, art);

      expect(datos.nombreCompleto.valor, 'DECRETO DE ALCALDÍA N° 008-2025-MDP-T');
      expect(datos.nombreCompleto.estado, EstadoCampo.detectado);
      expect(datos.codigo.valor, '008-2025-MDP-T');
      expect(datos.codigo.estado, EstadoCampo.detectado);
      expect(datos.fecha.valor, '27/08/2025');
      expect(datos.fecha.estado, EstadoCampo.detectado);
      expect(art.principal, startsWith('DECLARAR, EL DÍA 01 DE SETIEMBRE'));
      expect(art.principal, isNot(contains('día cívico')));
      expect(art.principal, isNot(contains('DISPONER')));
      expect(art.avisos, isEmpty);
    });

    test('ordenanza: título, código Nro. sin T, fecha y el artículo tras "aprobó la siguiente"', () {
      final enc = ConsolidadorEncabezado.consolidar([
        const LecturaTexto(ordenanza, OrigenLectura.nativo),
      ], ahora: 2026);
      final art = ExtractorArticuloPrimero.extraer(ordenanza, ancla: AnclaDispositiva.ordenanza);
      final datos = ValidadorCampos.construir(enc, art);

      expect(datos.nombreCompleto.valor, 'ORDENANZA MUNICIPAL N° 003-2025-MDP');
      expect(datos.nombreCompleto.estado, EstadoCampo.detectado);
      expect(datos.codigo.valor, '003-2025-MDP');
      expect(datos.codigo.estado, EstadoCampo.detectado);
      expect(datos.fecha.valor, '23/04/2025');
      expect(datos.fecha.estado, EstadoCampo.detectado);
      expect(art.principal, startsWith('APROBAR, el REGLAMENTO'));
      expect(art.principal, isNot(contains('FACULTAR')));
      expect(art.avisos, isEmpty);
    });

    test('también reconoce "aprobó lo siguiente"', () {
      const texto = '''
ORDENANZA MUNICIPAL
Nro. 005-2025-MDP
Pocollay, 01 de agosto del 2025.
CONSIDERANDO:
Que, se evaluó el reglamento.
El Concejo Distrital, por UNANIMIDAD, aprobó lo siguiente:
ORDENANZA MUNICIPAL
QUE APRUEBA EL REGLAMENTO DE AUDIENCIAS PÚBLICAS
ARTÍCULO PRIMERO.- APROBAR, el REGLAMENTO QUE REGULA LA REALIZACIÓN DE LAS AUDIENCIAS PÚBLICAS DE RENDICIÓN DE CUENTAS.
ARTÍCULO SEGUNDO.- FACULTAR al titular.
''';
      final art = ExtractorArticuloPrimero.extraer(texto, ancla: AnclaDispositiva.ordenanza);
      expect(art.principal, startsWith('APROBAR, el REGLAMENTO QUE REGULA'));
      expect(art.avisos, isEmpty);
    });

    test('ordenanza 004: el título roto no cede el tipo a la cita de acuerdo', () {
      const pagina1 = '''
NANZA MUNICIPAL
. 004-2025-MDP
Pocollay, 30 de junio del 2025.
Ed Sesión Ordinaria de Concejo de fecha 23 de junio de 2025, el Acuerdo de Concejo Municipal N* 027-2025-CM-MDP-T de fecha 23 de junio de 2025, que aprueba la Ordenanza Municipal.
CONSIDERANDO:
''';
      const cuerpo = '''
$pagina1
de conformidad con las atribuciones, por UNANIMIDAD, aprobó lo siguiente:
ORDENANZA MUNICIPAL
ARTÍCULO PRIMERO.- APROBAR, la CREACIÓN y CONFORMACIÓN del COMITÉ DISTRITAL DE LUCHA CONTRA LA TRATA DE PERSONAS.
ARTÍCULO SEGUNDO.- DESIGNAR, a los INTEGRANTES del COMITÉ.
''';

      final tipo = ExtractorEncabezado.tipoPorTexto(pagina1);
      expect(tipo!.siglas, 'MDP');
      expect(tipo.nombre, 'ORDENANZA MUNICIPAL');

      final art = ExtractorArticuloPrimero.extraer(cuerpo, ancla: AnclaDispositiva.ordenanza);
      expect(art.principal, startsWith('APROBAR, la CREACIÓN y CONFORMACIÓN'));
      expect(art.avisos, isEmpty);

      final comoAcuerdo = ExtractorArticuloPrimero.extraer(cuerpo, ancla: AnclaDispositiva.acuerdo);
      expect(comoAcuerdo.principal, isEmpty);
    });

    test('decreto 006: sin DECRETA, el artículo pegado tras Documentaria', () {
      const texto = '''
DECRETO DE ALCALDÍA
N° 006-2025-MDP-T
Pocollay, 10 de julio de 2025.
CONSIDERANDO:
Que, el alcalde ejerce las funciones mediante decretos de alcaldía.
Que, el artículo 42 de la Ley N° 27972.
Que, se dispuso: "ARTÍCULO PRIMERO: DECLARAR día cívico."
Gestión Documentaria;

¡JARTÍCULO PRIMERO, - DISPONER el EMBANDERAMIENTO GENERAL DE TODOS LOS INMUEBLES PÚBLICOS Y PRIVADOS UBICADOS EN EL DISTRITO DE POCOLLAY.
ARTÍCULO SEGUNDO. - ESTABLECER que todas las banderas sean izadas.
''';

      expect(ExtractorEncabezado.tipoPorTexto(texto)!.siglas, 'MDP-T');
      final art = ExtractorArticuloPrimero.extraer(texto, ancla: AnclaDispositiva.decreta);
      expect(art.principal, startsWith('DISPONER el EMBANDERAMIENTO'));
      expect(art.principal, isNot(contains('día cívico')));
      expect(art.principal, isNot(contains('ESTABLECER')));
      expect(art.avisos, isEmpty);
    });

    test('decreto sin DECRETA no toma un artículo citado en los considerandos', () {
      const texto = '''
DECRETO DE ALCALDÍA
N° 010-2025-MDP-T
Pocollay, 01 de octubre de 2025.
CONSIDERANDO:
Que, se dispuso: "ARTÍCULO PRIMERO: DECLARAR día cívico."
La oficina de Gestión Documentaria emitió un informe extenso que no contiene el articulado y sigue por varios renglones hasta perderse del todo.
''';
      final art = ExtractorArticuloPrimero.extraer(texto, ancla: AnclaDispositiva.decreta);
      expect(art.principal, isEmpty);
      expect(art.avisos, isNotEmpty);
    });
  });

  group('Confusión OCR entre CM-MDP-T y GM-MDP-T', () {
    ResultadoEncabezado consolidar(String texto, {String otro = ''}) {
      return ConsolidadorEncabezado.consolidar([
        LecturaTexto(texto, OrigenLectura.nativo),
        LecturaTexto(otro.isEmpty ? texto : otro, OrigenLectura.ocrFocalizado),
      ], textoCuerpo: otro.isEmpty ? texto : '$texto\n$otro', ahora: 2026);
    }

    test('título y bloque ACUERDO corrigen una G leída en lugar de la C', () {
      const acuerdo = '''
ACUERDO DE CONCEJO MUNICIPAL
N° 019-2026-GM-MDP-T
Pocollay, 07 de enero de 2026.
VISTO:
Que, el concejo vio el expediente de priorización.
ACUERDO:
ARTÍCULO PRIMERO.- APROBAR la priorización del plan de trabajo del distrito para el presente año.
ARTÍCULO SEGUNDO.- ENCARGAR el cumplimiento del presente acuerdo.
''';
      final r = consolidar(acuerdo);
      final datos = ValidadorCampos.construir(
        r,
        ExtractorArticuloPrimero.extraer(acuerdo, ancla: AnclaDispositiva.acuerdo),
      );

      expect(r.tipo!.siglas, 'CM-MDP-T');
      expect(r.estadoTipo, EstadoCampo.detectado);
      expect(r.estadoSiglas, EstadoCampo.detectado);
      expect(datos.nombreCompleto.valor, 'ACUERDO DE CONCEJO MUNICIPAL N° 019-2026-CM-MDP-T');
      expect(datos.nombreCompleto.estado, EstadoCampo.detectado);
      expect(datos.codigo.valor, '019-2026-CM-MDP-T');
      expect(datos.codigo.estado, EstadoCampo.detectado);
    });

    test('título y SE RESUELVE corrigen una C leída en lugar de la G', () {
      const gerencia = '''
RESOLUCIÓN DE GERENCIA MUNICIPAL
N° 146-2026-CM-MDP-T
Pocollay, 02 de octubre de 2026.
VISTO:
Que, la gerencia revisó el expediente.
SE RESUELVE:
ARTÍCULO PRIMERO.- APROBAR el informe de la oficina de administración del distrito.
ARTÍCULO SEGUNDO.- NOTIFICAR la presente resolución.
''';
      final r = consolidar(gerencia);
      final datos = ValidadorCampos.construir(
        r,
        ExtractorArticuloPrimero.extraer(gerencia, ancla: AnclaDispositiva.seResuelve),
      );

      expect(r.tipo!.siglas, 'GM-MDP-T');
      expect(r.estadoTipo, EstadoCampo.detectado);
      expect(datos.nombreCompleto.valor, 'RESOLUCIÓN DE GERENCIA MUNICIPAL N° 146-2026-GM-MDP-T');
      expect(datos.nombreCompleto.estado, EstadoCampo.detectado);
      expect(datos.codigo.valor, '146-2026-GM-MDP-T');
      expect(datos.codigo.estado, EstadoCampo.detectado);
    });

    test('título y estructura en desacuerdo: no se clasifica y queda REQUIERE REVISIÓN', () {
      const ambiguo = '''
ACUERDO DE CONCEJO MUNICIPAL
N° 019-2026-GM-MDP-T
Pocollay, 07 de enero de 2026.
VISTO:
Que, el expediente trae antecedentes.
SE RESUELVE:
ARTÍCULO PRIMERO.- APROBAR el informe de la oficina de administración del distrito.
ARTÍCULO SEGUNDO.- NOTIFICAR la presente resolución.
''';
      final r = consolidar(ambiguo);
      final datos = ValidadorCampos.construir(
        r,
        const ResultadoArticulo(principal: 'APROBAR el informe.', completo: 'x'),
      );

      expect(r.estadoTipo, EstadoCampo.requiereRevision);
      expect(r.estadoSiglas, EstadoCampo.requiereRevision);
      expect(datos.nombreCompleto.estado, EstadoCampo.requiereRevision);
      expect(datos.codigo.estado, EstadoCampo.requiereRevision);
    });

    test('sin título, la estructura sola no confirma unas siglas GM y queda REQUIERE REVISIÓN', () {
      const sinTitulo = '''
N° 019-2026-GM-MDP-T
Pocollay, 07 de enero de 2026.
VISTO:
Que, el expediente figura en mesa de partes.
ACUERDO:
ARTÍCULO PRIMERO.- APROBAR la priorización del plan de trabajo del distrito para el presente año.
ARTÍCULO SEGUNDO.- ENCARGAR el cumplimiento del presente acuerdo.
''';
      final r = consolidar(sinTitulo);

      expect(r.estadoTipo, EstadoCampo.requiereRevision);
      expect(r.estadoSiglas, EstadoCampo.requiereRevision);
      expect(
        r.estadoTipo == EstadoCampo.detectado && r.tipo?.siglas == 'GM-MDP-T',
        isFalse,
      );
    });

    test('lecturas C y G sin título ni estructura quedan REQUIERE REVISIÓN', () {
      final r = consolidar(
        'N° 019-2026-CM-MDP-T\nPocollay, 07 de enero de 2026.',
        otro: 'N° 019-2026-GM-MDP-T\nPocollay, 07 de enero de 2026.',
      );

      expect(r.estadoTipo, EstadoCampo.requiereRevision);
      expect(r.estadoSiglas, EstadoCampo.requiereRevision);
    });

    test('un acuerdo y una gerencia coherentes siguen DETECTADO', () {
      const acuerdo = '''
ACUERDO DE CONCEJO MUNICIPAL
N° 019-2026-CM-MDP-T
Pocollay, 07 de enero de 2026.
ACUERDO:
ARTÍCULO PRIMERO.- APROBAR la priorización del plan de trabajo del distrito para el presente año.
ARTÍCULO SEGUNDO.- ENCARGAR el cumplimiento.
''';
      const gerencia = '''
RESOLUCIÓN DE GERENCIA MUNICIPAL
N° 146-2026-GM-MDP-T
Pocollay, 02 de octubre de 2026.
SE RESUELVE:
ARTÍCULO PRIMERO.- APROBAR el informe de la oficina de administración del distrito.
ARTÍCULO SEGUNDO.- NOTIFICAR la presente resolución.
''';

      final a = consolidar(acuerdo);
      final g = consolidar(gerencia);
      expect(a.tipo!.siglas, 'CM-MDP-T');
      expect(a.estadoTipo, EstadoCampo.detectado);
      expect(a.estadoSiglas, EstadoCampo.detectado);
      expect(g.tipo!.siglas, 'GM-MDP-T');
      expect(g.estadoTipo, EstadoCampo.detectado);
      expect(g.estadoSiglas, EstadoCampo.detectado);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:procesador_documental_mdp/services/extraccion/corrector_articulo.dart';
import 'package:procesador_documental_mdp/services/extraccion/extractor_articulo_primero.dart';

void main() {
  group('CorrectorArticulo', () {
    test('corrige el símbolo de número mal leído antes de una cifra', () {
      expect(CorrectorArticulo.corregir('Decreto Legislativo N* 1057'), 'Decreto Legislativo N° 1057');
      expect(CorrectorArticulo.corregir('Gerencia Municipal N%402-2011'), 'Gerencia Municipal N°402-2011');
      expect(CorrectorArticulo.corregir('Alcaldía Ne025-2010'), 'Alcaldía N°025-2010');
      expect(CorrectorArticulo.corregir('Temporal NS 111-2026 y DNI Nº%00674010'), 'Temporal N° 111-2026 y DNI N°00674010');
      expect(CorrectorArticulo.corregir('DNI N°% 48702434'), 'DNI N° 48702434');
      expect(CorrectorArticulo.corregir('Trabajo N.* 111-2026'), 'Trabajo N.° 111-2026');
    });

    test('no toca texto legítimo', () {
      expect(CorrectorArticulo.corregir('Resolución No. 120-2026'), 'Resolución No. 120-2026');
      expect(CorrectorArticulo.corregir('Informe N° 063-2026 y NUEVE'), 'Informe N° 063-2026 y NUEVE');
      expect(CorrectorArticulo.corregir('Neto 5 y Nueva 2026'), 'Neto 5 y Nueva 2026');
      expect(CorrectorArticulo.corregir('NOMBRE: algo * otra cosa'), 'NOMBRE: algo * otra cosa');
    });

    test('limpia rayas dobles, signos sueltos y puntuación inicial', () {
      expect(CorrectorArticulo.corregir('EVITAMIENTO —- PAGO'), 'EVITAMIENTO - PAGO');
      expect(CorrectorArticulo.corregir('REYNALDO > BELARMINO'), 'REYNALDO BELARMINO');
      expect(CorrectorArticulo.corregir(', - RECONOCER oficialmente'), 'RECONOCER oficialmente');
    });
  });

  group('Artículo Primero: línea en blanco a mitad de oración', () {
    test('no corta el párrafo si lo anterior no termina en puntuación', () {
      const texto = 'SE RESUELVE:\nARTÍCULO PRIMERO: DESIGNAR, con eficacia anticipada al 05 de octubre, '
          'al ING. PEDRO PEREZ en la Municipalidad\n\nDistrital de Pocollay, bajo los alcances del Decreto N* 276.\n'
          'ARTÍCULO SEGUNDO: NOTIFICAR.';
      final r = ExtractorArticuloPrimero.extraer(texto);
      expect(r.principal, endsWith('Decreto N° 276.'));
      expect(r.principal, contains('Distrital de Pocollay'));
    });

    test('sí corta en la línea en blanco si lo anterior termina en punto', () {
      const texto = 'SE RESUELVE:\nARTÍCULO PRIMERO: AUTORIZAR el gasto indicado en el expediente administrativo.\n\n'
          'Detalle adicional que no es del párrafo principal.\nARTÍCULO SEGUNDO: NOTIFICAR.';
      final r = ExtractorArticuloPrimero.extraer(texto);
      expect(r.principal, 'AUTORIZAR el gasto indicado en el expediente administrativo.');
    });
  });

  group('Artículo Primero sin "SE RESUELVE"', () {
    test('elige el artículo real y no una cita en los considerandos', () {
      const texto = 'Que, mediante el artículo primero de la Resolución de Gerencia Municipal No. 064-2025 se desconcentró '
          'facultades del despacho.\n\n. EA ARTICULO PRIMERO.- DAR POR CONCLUIDA, al 04 de octubre del 2026, la designación '
          'del C.P.C. JHIMMY CARLSEN MAMANI TURPO como Jefe de la Oficina de Contabilidad.\n'
          'ARTICULO SEGUNDO.- DISPONER que se proceda a la notificación.';
      final r = ExtractorArticuloPrimero.extraer(texto);
      expect(r.principal, startsWith('DAR POR CONCLUIDA'));
    });
  });
}

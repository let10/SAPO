import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:procesador_documental_mdp/app/app.dart';
import 'package:procesador_documental_mdp/models/documento_almacenado.dart';
import 'package:procesador_documental_mdp/screens/pantalla_control.dart';
import 'package:procesador_documental_mdp/services/base_datos/base_datos_local.dart';
import 'package:procesador_documental_mdp/services/base_datos/repositorio_documentos.dart';

void main() {
  late Directory carpeta;
  late RepositorioDocumentos repo;
  late BaseDatosLocal bd;
  final abiertos = <String>[];

  setUp(() {
    carpeta = Directory.systemTemp.createTempSync('mdp_control_');
    bd = BaseDatosLocal.abrir(ruta: p.join(carpeta.path, 'control.db'));
    repo = RepositorioDocumentos(bd);
    abiertos.clear();
  });

  tearDown(() {
    bd.cerrar();
    try {
      carpeta.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> mostrar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: PantallaControl(
          repositorio: repo,
          abrirPdf: (ruta) async => abiertos.add(ruta),
        ),
      ),
    );
    await tester.pump();
  }

  DocumentoAlmacenado alta({
    required String tipo,
    required String nombre,
    required String codigo,
    required String fecha,
    required String articulo,
    required String ruta,
    bool publicado = false,
  }) {
    final resultado = repo.registrar(
      DocumentoAlmacenado(
        tipoDocumento: tipo,
        nombreCompleto: nombre,
        codigo: codigo,
        fechaDocumento: fecha,
        articuloPrimero: articulo,
        rutaPdf: ruta,
      ),
    );
    final id = resultado.documento.id!;
    if (resultado.documento.publicado != publicado) {
      repo.marcarPublicado(id, publicado);
    }
    return repo.porId(id)!;
  }

  void cargarEjemplos() {
    alta(
      tipo: 'RESOLUCIÓN DE ALCALDÍA',
      nombre: 'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T',
      codigo: '074-2026-A-MDP-T',
      fecha: '2026-07-08',
      articulo: 'AUTORIZAR el gasto de control.',
      ruta: r'C:\pdf\074.pdf',
    );
    alta(
      tipo: 'ACUERDO DE CONCEJO MUNICIPAL',
      nombre: 'ACUERDO DE CONCEJO MUNICIPAL N° 001-2026-CM-MDP-T',
      codigo: '001-2026-CM-MDP-T',
      fecha: '2026-01-07',
      articulo: 'APROBAR el plan de trabajo.',
      ruta: r'C:\pdf\001.pdf',
      publicado: true,
    );
    alta(
      tipo: 'RESOLUCIÓN DE ALCALDÍA',
      nombre: 'RESOLUCIÓN DE ALCALDÍA N° 075-2026-A-MDP-T',
      codigo: '075-2026-A-MDP-T',
      fecha: '2026-08-15',
      articulo: 'MODIFICAR el plazo del contrato.',
      ruta: r'C:\pdf\075.pdf',
    );
  }

  Future<void> elegirTipo(WidgetTester tester, String tipo) async {
    await tester.tap(find.byKey(const Key('filtro-tipo')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DropdownMenuItem<String>, tipo).last);
    await tester.pumpAndSettle();
  }

  Future<void> elegirEstado(WidgetTester tester, String texto) async {
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('filtro-publicado')),
        matching: find.text(texto),
      ),
    );
    await tester.pump();
  }

  testWidgets('un documento recién registrado aparece como publicado', (tester) async {
    repo.registrar(
      const DocumentoAlmacenado(
        tipoDocumento: 'RESOLUCIÓN DE ALCALDÍA',
        nombreCompleto: 'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T',
        codigo: '074-2026-A-MDP-T',
        fechaDocumento: '2026-07-08',
        articuloPrimero: 'AUTORIZAR el gasto de control.',
        rutaPdf: r'C:\pdf\074.pdf',
      ),
    );
    await mostrar(tester);

    final interruptor = tester.widget<Switch>(find.byKey(const ValueKey('publicado-1')));
    expect(interruptor.value, isTrue);

    await tester.tap(find.byKey(const ValueKey('fila-1')));
    await tester.pump();
    expect(find.text('Marcar no publicado'), findsOneWidget);
    expect(find.text('Marcar publicado'), findsNothing);
  });

  testWidgets('lista las columnas de control y reserva el Artículo Primero para el detalle', (
    tester,
  ) async {
    cargarEjemplos();
    await mostrar(tester);

    expect(find.text('Tipo'), findsOneWidget);
    expect(find.text('Código'), findsOneWidget);
    expect(find.text('Fecha del documento'), findsWidgets);
    expect(find.text('Fecha de recepción'), findsWidgets);
    expect(find.text('074-2026-A-MDP-T'), findsOneWidget);
    expect(find.text('08/07/2026'), findsOneWidget);
    expect(find.text('AUTORIZAR el gasto de control.'), findsNothing);
    expect(find.text('Artículo Primero'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('fila-1')));
    await tester.pump();

    expect(find.text('Artículo Primero'), findsOneWidget);
    expect(find.text('AUTORIZAR el gasto de control.'), findsOneWidget);
    expect(find.text('RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T'), findsOneWidget);
    expect(find.text(r'C:\pdf\074.pdf'), findsOneWidget);
    expect(find.text('No publicado'), findsWidgets);
  });

  testWidgets('busca por código o por nombre y combina con el tipo', (tester) async {
    cargarEjemplos();
    await mostrar(tester);

    await tester.enterText(find.byKey(const Key('busqueda-documentos')), '074');
    await tester.pump();
    expect(find.text('074-2026-A-MDP-T'), findsOneWidget);
    expect(find.text('075-2026-A-MDP-T'), findsNothing);
    expect(find.text('001-2026-CM-MDP-T'), findsNothing);

    await tester.enterText(find.byKey(const Key('busqueda-documentos')), 'resolucion de alcaldia');
    await tester.pump();
    expect(find.text('074-2026-A-MDP-T'), findsOneWidget);
    expect(find.text('075-2026-A-MDP-T'), findsOneWidget);
    expect(find.text('001-2026-CM-MDP-T'), findsNothing);

    await tester.enterText(find.byKey(const Key('busqueda-documentos')), '074');
    await elegirTipo(tester, 'ACUERDO DE CONCEJO MUNICIPAL');
    expect(find.text('Ningún documento coincide con la búsqueda o los filtros.'), findsOneWidget);
  });

  testWidgets('filtra por tipo y por publicado o no publicado', (tester) async {
    cargarEjemplos();
    await mostrar(tester);

    await elegirTipo(tester, 'ACUERDO DE CONCEJO MUNICIPAL');
    expect(find.text('001-2026-CM-MDP-T'), findsOneWidget);
    expect(find.text('074-2026-A-MDP-T'), findsNothing);

    await elegirTipo(tester, 'Todos los tipos');
    await elegirEstado(tester, 'Publicado');
    expect(find.text('001-2026-CM-MDP-T'), findsOneWidget);
    expect(find.text('075-2026-A-MDP-T'), findsNothing);

    await elegirEstado(tester, 'No publicado');
    expect(find.text('074-2026-A-MDP-T'), findsOneWidget);
    expect(find.text('075-2026-A-MDP-T'), findsOneWidget);
    expect(find.text('001-2026-CM-MDP-T'), findsNothing);
  });

  testWidgets('marca y desmarca publicado sin cambiar la fecha de recepción', (tester) async {
    cargarEjemplos();
    final antes = repo.porId(1)!.fechaRecepcion;
    await mostrar(tester);

    await tester.tap(find.byKey(const ValueKey('publicado-1')));
    await tester.pump();
    expect(repo.porId(1)!.publicado, isTrue);
    expect(repo.porId(1)!.fechaRecepcion, antes);
    expect(find.text('Marcado como publicado.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fila-1')));
    await tester.pump();
    await tester.tap(find.text('Marcar no publicado'));
    await tester.pump();
    expect(repo.porId(1)!.publicado, isFalse);
    expect(repo.porId(1)!.fechaRecepcion, antes);
    expect(find.text('Marcado como no publicado.'), findsOneWidget);
  });

  testWidgets('abre el PDF del detalle y avisa si el archivo no existe', (tester) async {
    cargarEjemplos();
    await mostrar(tester);

    await tester.tap(find.byKey(const ValueKey('abrir-2')));
    await tester.pump();
    expect(abiertos, [r'C:\pdf\001.pdf']);

    await tester.tap(find.byKey(const ValueKey('fila-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('abrir-pdf-detalle')));
    await tester.pump();
    expect(abiertos, [r'C:\pdf\001.pdf', r'C:\pdf\074.pdf']);

    await tester.pumpWidget(
      MaterialApp(home: PantallaControl(repositorio: repo)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('abrir-1')));
    await tester.pump();
    expect(find.text('No se encontró el archivo PDF.'), findsOneWidget);
  });

  testWidgets('la pantalla principal abre el control', (tester) async {
    await tester.pumpWidget(const App());
    await tester.tap(find.text('Control de documentos'));
    await tester.pumpAndSettle();

    expect(find.byType(PantallaControl), findsOneWidget);
    expect(find.textContaining('No se pudo abrir la base de datos'), findsOneWidget);
  });

  testWidgets('sin registros muestra el estado vacío', (tester) async {
    await mostrar(tester);
    expect(find.text('Ningún documento registrado.'), findsOneWidget);
    expect(find.text('0 documentos'), findsOneWidget);
  });
}

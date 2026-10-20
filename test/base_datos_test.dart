import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:procesador_documental_mdp/models/campos_resolucion.dart';
import 'package:procesador_documental_mdp/models/documento.dart';
import 'package:procesador_documental_mdp/models/documento_almacenado.dart';
import 'package:procesador_documental_mdp/services/base_datos/base_datos_local.dart';
import 'package:procesador_documental_mdp/services/base_datos/repositorio_documentos.dart';
import 'package:sqlite3/sqlite3.dart';

String _hoyIso() {
  final n = DateTime.now();
  String dos(int v) => v.toString().padLeft(2, '0');
  return '${n.year}-${dos(n.month)}-${dos(n.day)}';
}

String _hoyMostrar() {
  final p = _hoyIso().split('-');
  return '${p[2]}/${p[1]}/${p[0]}';
}

void main() {
  late Directory carpeta;
  late String rutaBd;

  setUp(() {
    carpeta = Directory.systemTemp.createTempSync('mdp_bd_');
    rutaBd = p.join(carpeta.path, 'sub', BaseDatosLocal.nombreArchivo);
  });

  tearDown(() {
    try {
      carpeta.deleteSync(recursive: true);
    } catch (_) {}
  });

  Documento confirmado({
    String codigo = '074-2026-A-MDP-T',
    String ruta = r'C:\pdf\074.pdf',
    String articulo = 'AUTORIZAR el gasto.',
    String fecha = '08/07/2026',
  }) {
    final d = Documento(nombre: '074.pdf', ruta: ruta);
    d.datos = DatosResolucion(
      nombreCompleto: CampoExtraido(valor: 'RESOLUCIÓN DE ALCALDÍA N° $codigo'),
      codigo: CampoExtraido(valor: codigo),
      fecha: CampoExtraido(valor: fecha),
      articuloPrimeroPrincipal: CampoExtraido(valor: articulo),
    );
    d.datosConfirmados = true;
    return d;
  }

  test('crea la base y la tabla documentos automáticamente', () {
    expect(File(rutaBd).existsSync(), isFalse);
    final bd = BaseDatosLocal.abrir(ruta: rutaBd);
    expect(File(rutaBd).existsSync(), isTrue);
    final tablas = bd.conexion.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'documentos'",
    );
    expect(tablas, hasLength(1));
    bd.cerrar();
  });

  test('inserta un documento confirmado como publicado y con la fecha de recepción de hoy', () {
    final bd = BaseDatosLocal.abrir(ruta: rutaBd);
    final repo = RepositorioDocumentos(bd);

    final r = repo.registrar(
      DocumentoAlmacenado.desdeDocumentoConfirmado(confirmado()),
    );
    expect(r.registrado, isTrue);

    final leido = repo.porId(r.documento.id!)!;
    expect(leido.tipoDocumento, 'RESOLUCIÓN DE ALCALDÍA');
    expect(leido.nombreCompleto, 'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T');
    expect(leido.codigo, '074-2026-A-MDP-T');
    expect(leido.fechaDocumento, '2026-07-08');
    expect(leido.fechaDocumentoParaMostrar, '08/07/2026');
    expect(leido.articuloPrimero, 'AUTORIZAR el gasto.');
    expect(leido.rutaPdf, r'C:\pdf\074.pdf');
    expect(leido.publicado, isTrue);
    expect(leido.fechaRecepcion, _hoyIso());
    expect(leido.fechaRecepcionParaMostrar, _hoyMostrar());
    expect(repo.porCodigo('074-2026-A-MDP-T')!.id, leido.id);
    bd.cerrar();
  });

  test(
    'impide el duplicado tipo_documento + codigo sin tocar el existente',
    () {
      final bd = BaseDatosLocal.abrir(ruta: rutaBd);
      final repo = RepositorioDocumentos(bd);

      final primero = repo.registrar(
        DocumentoAlmacenado.desdeDocumentoConfirmado(confirmado()),
      );
      final segundo = repo.registrar(
        DocumentoAlmacenado.desdeDocumentoConfirmado(
          confirmado(ruta: r'C:\otra\copia.pdf'),
        ),
      );

      expect(segundo.registrado, isFalse);
      expect(segundo.duplicado, isTrue);
      expect(segundo.documento.id, primero.documento.id);
      expect(
        bd.conexion.select('SELECT COUNT(*) AS n FROM documentos').first['n'],
        1,
      );
      expect(repo.porId(primero.documento.id!)!.rutaPdf, r'C:\pdf\074.pdf');
      bd.cerrar();
    },
  );

  test('al corregir un documento registrado actualiza todos los datos confirmados', () {
    final bd = BaseDatosLocal.abrir(ruta: rutaBd);
    final repo = RepositorioDocumentos(bd);

    final primero = repo.registrar(
      DocumentoAlmacenado.desdeDocumentoConfirmado(confirmado()),
    );
    final id = primero.documento.id!;
    final recepcion = primero.documento.fechaRecepcion;

    repo.actualizarDatosConfirmados(
      id,
      DocumentoAlmacenado.desdeDocumentoConfirmado(
        confirmado(
          codigo: '075-2026-A-MDP-T',
          ruta: r'C:\pdf\renombrado.pdf',
          articulo: 'MODIFICAR el plazo del contrato.',
          fecha: '15/08/2026',
        ),
      ),
    );

    final leido = repo.porId(id)!;
    expect(leido.codigo, '075-2026-A-MDP-T');
    expect(leido.nombreCompleto, 'RESOLUCIÓN DE ALCALDÍA N° 075-2026-A-MDP-T');
    expect(leido.tipoDocumento, 'RESOLUCIÓN DE ALCALDÍA');
    expect(leido.fechaDocumento, '2026-08-15');
    expect(leido.articuloPrimero, 'MODIFICAR el plazo del contrato.');
    expect(leido.rutaPdf, r'C:\pdf\renombrado.pdf');
    expect(leido.publicado, isTrue);
    expect(leido.fechaRecepcion, recepcion);
    expect(leido.articuloPrimero, isNotEmpty);
    bd.cerrar();
  });

  test('no pisa otro registro al cambiar el código a uno que ya existe', () {
    final bd = BaseDatosLocal.abrir(ruta: rutaBd);
    final repo = RepositorioDocumentos(bd);
    final primero = repo.registrar(
      DocumentoAlmacenado.desdeDocumentoConfirmado(confirmado()),
    );
    repo.registrar(
      DocumentoAlmacenado.desdeDocumentoConfirmado(
        confirmado(codigo: '075-2026-A-MDP-T'),
      ),
    );

    expect(
      () => repo.actualizarDatosConfirmados(
        primero.documento.id!,
        DocumentoAlmacenado.desdeDocumentoConfirmado(
          confirmado(codigo: '075-2026-A-MDP-T'),
        ),
      ),
      throwsStateError,
    );
    expect(repo.porId(primero.documento.id!)!.codigo, '074-2026-A-MDP-T');
    bd.cerrar();
  });

  test('no registra datos sin confirmar', () {
    final d = confirmado()..datosConfirmados = false;
    expect(
      () => DocumentoAlmacenado.desdeDocumentoConfirmado(d),
      throwsStateError,
    );
  });

  test('lista, busca y filtra por tipo y por publicado', () {
    final bd = BaseDatosLocal.abrir(ruta: rutaBd);
    final repo = RepositorioDocumentos(bd);
    final resolucion = repo.registrar(
      DocumentoAlmacenado.desdeDocumentoConfirmado(confirmado()),
    );
    final acuerdo = repo.registrar(
      const DocumentoAlmacenado(
        tipoDocumento: 'acuerdo de concejo municipal',
        nombreCompleto: 'ACUERDO DE CONCEJO MUNICIPAL N° 001-2026-CM-MDP-T',
        codigo: '001-2026-CM-MDP-T',
        fechaDocumento: '2026-01-07',
        articuloPrimero: 'APROBAR el plan de trabajo.',
        rutaPdf: r'C:\pdf\001.pdf',
      ),
    );
    expect(resolucion.documento.publicado, isTrue);
    expect(acuerdo.documento.publicado, isTrue);
    repo.marcarPublicado(acuerdo.documento.id!, false);

    expect(repo.listar(), hasLength(2));
    expect(repo.listar().first.id, acuerdo.documento.id);
    expect(
      repo.listar(tipoDocumento: 'Acuerdo de Concejo Municipal').single.codigo,
      '001-2026-CM-MDP-T',
    );
    expect(repo.listar(publicado: true).single.codigo, '074-2026-A-MDP-T');
    expect(repo.listar(publicado: false).single.codigo, '001-2026-CM-MDP-T');
    expect(repo.buscar('074').single.id, resolucion.documento.id);
    expect(repo.buscar('resolución de alcaldía').single.id, resolucion.documento.id);
    expect(repo.buscar('concejo').single.id, acuerdo.documento.id);
    expect(repo.buscar('no-existe'), isEmpty);
    expect(
      repo.buscar('001', tipoDocumento: 'RESOLUCIÓN DE ALCALDÍA'),
      isEmpty,
    );

    final recepcion = repo.porId(resolucion.documento.id!)!.fechaRecepcion;
    repo.marcarPublicado(resolucion.documento.id!, false);
    final otraVez = repo.porId(resolucion.documento.id!)!;
    expect(otraVez.publicado, isFalse);
    expect(otraVez.fechaRecepcion, recepcion);
    expect(() => repo.marcarPublicado(9999, true), throwsStateError);
    bd.cerrar();
  });

  test('una base antigua convierte fecha_registro en fecha_recepcion de un solo día', () {
    final rutaAntigua = p.join(carpeta.path, 'antigua.db');
    final cruda = sqlite3.open(rutaAntigua);
    cruda.execute('''
      CREATE TABLE documentos (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo_documento    TEXT NOT NULL,
        nombre_completo   TEXT NOT NULL,
        codigo            TEXT NOT NULL,
        fecha_documento   TEXT NOT NULL,
        articulo_primero  TEXT NOT NULL,
        ruta_pdf          TEXT NOT NULL,
        publicado         INTEGER NOT NULL DEFAULT 0,
        fecha_publicacion TEXT,
        fecha_registro    TEXT NOT NULL
      )
    ''');
    cruda.execute(
      'INSERT INTO documentos '
      '(tipo_documento, nombre_completo, codigo, fecha_documento, articulo_primero, ruta_pdf, publicado, fecha_publicacion, fecha_registro) '
      'VALUES (?, ?, ?, ?, ?, ?, 0, NULL, ?)',
      [
        'RESOLUCIÓN DE ALCALDÍA',
        'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T',
        '074-2026-A-MDP-T',
        '2026-07-08',
        'AUTORIZAR el gasto.',
        r'C:\pdf\074.pdf',
        '2026-03-01T14:30:00',
      ],
    );
    cruda.close();

    final bd = BaseDatosLocal.abrir(ruta: rutaAntigua);
    final columnas = bd.conexion
        .select('PRAGMA table_info(documentos)')
        .map((f) => f['name'] as String)
        .toList();
    expect(columnas, contains('fecha_recepcion'));
    expect(columnas, contains('fecha_publicacion'));
    expect(columnas, isNot(contains('fecha_registro')));

    final leido = RepositorioDocumentos(bd).listar().single;
    expect(leido.fechaRecepcion, '2026-03-01');
    expect(leido.fechaRecepcionParaMostrar, '01/03/2026');
    expect(leido.articuloPrimero, 'AUTORIZAR el gasto.');
    bd.cerrar();
  });
}

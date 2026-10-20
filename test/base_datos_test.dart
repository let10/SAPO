import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:procesador_documental_mdp/models/campos_resolucion.dart';
import 'package:procesador_documental_mdp/models/documento.dart';
import 'package:procesador_documental_mdp/models/documento_almacenado.dart';
import 'package:procesador_documental_mdp/services/base_datos/base_datos_local.dart';
import 'package:procesador_documental_mdp/services/base_datos/repositorio_documentos.dart';

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

  test('inserta un documento confirmado, lo lee de nuevo y empieza como no publicado', () {
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
    expect(leido.publicado, isFalse);
    expect(leido.fechaPublicacion, isNull);
    expect(leido.fechaRegistro, isNotNull);
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
    bd.conexion.execute(
      'UPDATE documentos SET publicado = 1, fecha_publicacion = ? WHERE id = ?',
      ['2026-10-01', id],
    );

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
    expect(leido.fechaPublicacion, DateTime.parse('2026-10-01'));
    expect(leido.fechaRegistro, primero.documento.fechaRegistro);
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
}

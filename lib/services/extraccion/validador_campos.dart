import '../../models/campos_resolucion.dart';
import 'consolidador_encabezado.dart';
import 'extractor_articulo_primero.dart';
import 'normalizador_numero.dart';

/// Arma los cuatro campos finales y decide su estado (DETECTADO / REQUIERE
/// REVISIÓN) a partir de lo realmente leído; no se inventan porcentajes.
class ValidadorCampos {
  static DatosResolucion construir(ResultadoEncabezado enc, ResultadoArticulo art) {
    // Código NNN-AÑO-SIGLAS (con marcadores visibles si falta alguna parte).
    final numero = enc.numero == null ? '___' : NormalizadorNumero.normalizar(enc.numero!).valor;
    final anio = enc.anio ?? '____';
    final siglas = enc.siglas ?? '___';
    final codigoCompleto = enc.numero != null && enc.anio != null && enc.siglas != null;
    final codigoValor = '$numero-$anio-$siglas';

    final codigoDetectado = codigoCompleto &&
        enc.estadoNumero == EstadoCampo.detectado &&
        enc.estadoAnio == EstadoCampo.detectado &&
        enc.estadoSiglas == EstadoCampo.detectado;

    final notasCodigo = [
      if (enc.estadoNumero != EstadoCampo.detectado) enc.notaNumero,
      if (enc.estadoAnio != EstadoCampo.detectado) enc.notaAnio,
      if (enc.estadoSiglas != EstadoCampo.detectado) enc.notaSiglas,
    ].where((n) => n.isNotEmpty).join(' ');

    final codigo = CampoExtraido(
      valor: codigoValor,
      estado: codigoDetectado ? EstadoCampo.detectado : EstadoCampo.requiereRevision,
      nota: codigoDetectado ? '' : notasCodigo,
    );

    // Nombre completo [TIPO] N° [CÓDIGO]
    final tipo = enc.tipo;
    final nombreDetectado = codigoDetectado && tipo != null && enc.estadoTipo == EstadoCampo.detectado;
    final nombre = CampoExtraido(
      valor: tipo == null ? '' : '${tipo.nombre} N° $codigoValor',
      estado: nombreDetectado ? EstadoCampo.detectado : EstadoCampo.requiereRevision,
      nota: nombreDetectado
          ? ''
          : [
              if (enc.estadoTipo != EstadoCampo.detectado) enc.notaTipo,
              if (!codigoDetectado) notasCodigo,
            ].where((n) => n.isNotEmpty).join(' '),
    );

    final fecha = CampoExtraido(
      valor: enc.fecha ?? '',
      estado: enc.estadoFecha,
      nota: enc.estadoFecha == EstadoCampo.detectado ? '' : enc.notaFecha,
    );

    final articulo = CampoExtraido(
      valor: art.principal,
      estado: art.requiereRevision || art.principal.isEmpty
          ? EstadoCampo.requiereRevision
          : EstadoCampo.detectado,
      nota: art.avisos.join(' '),
    );

    return DatosResolucion(
      nombreCompleto: nombre,
      codigo: codigo,
      fecha: fecha,
      articuloPrimeroPrincipal: articulo,
      articuloPrimeroCompleto: art.completo,
    );
  }
}

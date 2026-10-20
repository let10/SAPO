import '../models/documento.dart';
import 'texto_utils.dart';

/// Orden de la lista principal: primero los documentos con datos confirmados (ya
/// renombrados), luego los procesados por confirmar y al final los pendientes.
/// Dentro de cada grupo, alfabético (sin distinguir mayúsculas ni tildes).
List<Documento> ordenarDocumentos(Iterable<Documento> documentos) {
  int grupo(Documento d) {
    if (d.datosConfirmados) return 0;
    if (d.estado == EstadoDocumento.completado || d.estado == EstadoDocumento.error) return 1;
    return 2;
  }

  final lista = documentos.toList();
  final posicion = {for (var i = 0; i < lista.length; i++) lista[i]: i};
  lista.sort((a, b) {
    final porGrupo = grupo(a).compareTo(grupo(b));
    if (porGrupo != 0) return porGrupo;
    final porNombre = normalizarParaBusqueda(a.nombre).compareTo(normalizarParaBusqueda(b.nombre));
    if (porNombre != 0) return porNombre;
    return posicion[a]!.compareTo(posicion[b]!);
  });
  return lista;
}

import 'package:flutter/material.dart';

import '../models/documento_almacenado.dart';
import '../services/abrir_pdf.dart';
import '../services/base_datos/repositorio_documentos.dart';

enum _FiltroPublicado { todos, publicado, noPublicado }

/// Listado de los documentos ya registrados: búsqueda, filtros, publicación,
/// detalle y apertura del PDF. No procesa documentos nuevos.
class PantallaControl extends StatefulWidget {
  final RepositorioDocumentos? repositorio;
  final String? errorBaseDatos;

  /// Si se indica, sustituye la apertura con el programa del sistema.
  /// Las pruebas lo usan para no lanzar un visor real.
  final Future<void> Function(String ruta)? abrirPdf;

  const PantallaControl({
    super.key,
    this.repositorio,
    this.errorBaseDatos,
    this.abrirPdf,
  });

  @override
  State<PantallaControl> createState() => _PantallaControlState();
}

class _PantallaControlState extends State<PantallaControl> {
  final TextEditingController _busqueda = TextEditingController();
  _FiltroPublicado _filtro = _FiltroPublicado.todos;
  String? _tipo;
  List<String> _tipos = const [];
  List<DocumentoAlmacenado> _documentos = const [];
  DocumentoAlmacenado? _detalle;

  @override
  void initState() {
    super.initState();
    _busqueda.addListener(_recargar);
    final inicial = _consultar();
    _documentos = inicial.documentos;
    _tipos = inicial.tipos;
  }

  @override
  void dispose() {
    _busqueda.removeListener(_recargar);
    _busqueda.dispose();
    super.dispose();
  }

  bool? get _publicado {
    switch (_filtro) {
      case _FiltroPublicado.todos:
        return null;
      case _FiltroPublicado.publicado:
        return true;
      case _FiltroPublicado.noPublicado:
        return false;
    }
  }

  ({List<DocumentoAlmacenado> documentos, List<String> tipos}) _consultar() {
    final repo = widget.repositorio;
    if (repo == null) return (documentos: const [], tipos: const []);
    final texto = _busqueda.text.trim();
    final tipo = _tipo;
    final publicado = _publicado;
    final documentos = texto.isEmpty
        ? repo.listar(tipoDocumento: tipo, publicado: publicado)
        : repo.buscar(texto, tipoDocumento: tipo, publicado: publicado);
    final tipos = repo.listar().map((d) => d.tipoDocumento).toSet().toList()
      ..sort();
    return (documentos: documentos, tipos: tipos);
  }

  void _recargar() {
    if (!mounted) return;
    final consulta = _consultar();
    DocumentoAlmacenado? detalle;
    final id = _detalle?.id;
    final repo = widget.repositorio;
    if (id != null && repo != null) detalle = repo.porId(id);
    setState(() {
      _documentos = consulta.documentos;
      _tipos = consulta.tipos;
      _detalle = detalle;
    });
  }

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _marcar(DocumentoAlmacenado doc, bool publicado) async {
    final repo = widget.repositorio;
    final id = doc.id;
    if (repo == null || id == null) return;
    try {
      repo.marcarPublicado(id, publicado);
      _recargar();
      _avisar(publicado ? 'Marcado como publicado.' : 'Marcado como no publicado.');
    } catch (e) {
      _avisar(e is StateError ? e.message : 'No se pudo cambiar la publicación: $e');
    }
  }

  Future<void> _abrir(DocumentoAlmacenado doc) async {
    try {
      await (widget.abrirPdf ?? abrirPdfDelSistema)(doc.rutaPdf);
    } catch (e) {
      _avisar(e is StateError ? e.message : 'No se pudo abrir el PDF: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sinBase = widget.repositorio == null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Control de documentos'),
            Text(
              'Municipalidad Distrital de Pocollay',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        toolbarHeight: 68,
      ),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: sinBase
            ? Center(
                child: Text(
                  'No se pudo abrir la base de datos: ${widget.errorBaseDatos ?? 'error desconocido'}',
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _barraFiltros(theme),
                  const SizedBox(height: 18),
                  Text(
                    '${_documentos.length} documento${_documentos.length == 1 ? '' : 's'}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(child: _cuerpo(theme)),
                ],
              ),
      ),
    );
  }

  Widget _barraFiltros(ThemeData theme) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 320,
          child: TextField(
            key: const Key('busqueda-documentos'),
            controller: _busqueda,
            decoration: const InputDecoration(
              labelText: 'Buscar por código o nombre',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 300,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Tipo de documento',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('filtro-tipo'),
                value: _tipo ?? '',
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: '', child: Text('Todos los tipos')),
                  for (final tipo in _tipos)
                    DropdownMenuItem(value: tipo, child: Text(tipo)),
                ],
                onChanged: (valor) {
                  _tipo = (valor == null || valor.isEmpty) ? null : valor;
                  _recargar();
                },
              ),
            ),
          ),
        ),
        SegmentedButton<_FiltroPublicado>(
          key: const Key('filtro-publicado'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _FiltroPublicado.todos, label: Text('Todos')),
            ButtonSegment(value: _FiltroPublicado.publicado, label: Text('Publicado')),
            ButtonSegment(
              value: _FiltroPublicado.noPublicado,
              label: Text('No publicado'),
            ),
          ],
          selected: {_filtro},
          onSelectionChanged: (seleccion) {
            _filtro = seleccion.first;
            _recargar();
          },
        ),
      ],
    );
  }

  Widget _cuerpo(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final lateral = constraints.maxWidth >= 980;
        final tabla = _tabla(theme);
        final detalle = _detalle;
        if (detalle == null) return tabla;
        final panel = _panelDetalle(theme, detalle);
        if (!lateral) {
          return Column(
            children: [
              Expanded(child: tabla),
              const SizedBox(height: 12),
              SizedBox(height: 280, child: panel),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: tabla),
            const SizedBox(width: 16),
            SizedBox(width: 360, child: panel),
          ],
        );
      },
    );
  }

  Widget _tabla(ThemeData theme) {
    if (_documentos.isEmpty) {
      final hayCriterios =
          _busqueda.text.trim().isNotEmpty || _tipo != null || _filtro != _FiltroPublicado.todos;
      return Center(
        child: Text(
          hayCriterios
              ? 'Ningún documento coincide con la búsqueda o los filtros.'
              : 'Ningún documento registrado.',
          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            ColoredBox(
              color: theme.colorScheme.surfaceContainerHigh,
              child: _lineaTabla(
                [
                  Text(
                    'Tipo',
                    style: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    'Código',
                    style: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    'Fecha del documento',
                    style: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    'Fecha de recepción',
                    style: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    'Publicado',
                    style: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
                acciones: const SizedBox(width: 88),
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: _documentos.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
                itemBuilder: (context, index) {
                  final doc = _documentos[index];
                  final seleccionado = doc.id != null && doc.id == _detalle?.id;
                  return Material(
                    color: seleccionado
                        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
                        : theme.colorScheme.surface,
                    child: InkWell(
                      key: ValueKey('fila-${doc.id}'),
                      onTap: () => setState(() => _detalle = doc),
                      child: _lineaTabla(
                        [
                          Text(doc.tipoDocumento, maxLines: 2, overflow: TextOverflow.ellipsis),
                          Text(doc.codigo, maxLines: 2, overflow: TextOverflow.ellipsis),
                          Text(doc.fechaDocumentoParaMostrar),
                          Text(doc.fechaRecepcionParaMostrar),
                          Switch(
                            key: ValueKey('publicado-${doc.id}'),
                            value: doc.publicado,
                            onChanged: (valor) => _marcar(doc, valor),
                          ),
                        ],
                        acciones: IconButton(
                          key: ValueKey('abrir-${doc.id}'),
                          tooltip: 'Abrir PDF',
                          onPressed: () => _abrir(doc),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineaTabla(List<Widget> celdas, {required Widget acciones}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          for (var i = 0; i < celdas.length; i++)
            Expanded(
              flex: i < 2 ? 3 : 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: celdas[i],
              ),
            ),
          acciones,
        ],
      ),
    );
  }

  Widget _panelDetalle(ThemeData theme, DocumentoAlmacenado doc) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Detalle del documento', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Cerrar detalle',
                  onPressed: () => setState(() => _detalle = null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _campo(theme, 'Nombre completo', doc.nombreCompleto),
                    _campo(theme, 'Código', doc.codigo),
                    _campo(theme, 'Fecha del documento', doc.fechaDocumentoParaMostrar),
                    _campo(theme, 'Fecha de recepción', doc.fechaRecepcionParaMostrar),
                    _campo(theme, 'Artículo Primero', doc.articuloPrimero),
                    _campo(
                      theme,
                      'Publicado',
                      doc.publicado ? 'Publicado' : 'No publicado',
                    ),
                    _campo(theme, 'Ruta del PDF', doc.rutaPdf),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _marcar(doc, !doc.publicado),
                  icon: Icon(doc.publicado ? Icons.unpublished_outlined : Icons.check_circle_outline),
                  label: Text(doc.publicado ? 'Marcar no publicado' : 'Marcar publicado'),
                ),
                FilledButton.icon(
                  key: const Key('abrir-pdf-detalle'),
                  onPressed: () => _abrir(doc),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Abrir PDF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(ThemeData theme, String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            etiqueta,
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          SelectableText(valor.isEmpty ? '—' : valor),
        ],
      ),
    );
  }
}

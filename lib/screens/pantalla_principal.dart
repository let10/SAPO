import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../models/documento.dart';
import '../models/documento_almacenado.dart';
import '../services/base_datos/repositorio_documentos.dart';
import '../services/ia/cargador_redes.dart';
import '../services/ia/redes_dominio.dart';
import '../services/procesador_pdf.dart';
import '../services/selector_documentos.dart';
import '../utils/orden_documentos.dart';
import '../widgets/documento_tile.dart';

class PantallaPrincipal extends StatefulWidget {
  /// Base de datos local donde se registran los documentos confirmados.
  final RepositorioDocumentos? repositorio;

  /// Motivo por el que no se pudo abrir la base de datos, si es el caso.
  final String? errorBaseDatos;

  const PantallaPrincipal({super.key, this.repositorio, this.errorBaseDatos});

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  final _selector = SelectorDocumentos();
  final List<Documento> _documentos = [];
  bool _cargando = false;
  bool _arrastrandoEncima = false;
  bool _procesandoTodos = false;

  /// Red neuronal propia de reconocimiento de dígitos. `null` hasta que
  /// termine de cargarse (o si no hay un modelo entrenado disponible).
  RedesDominio? _redes;

  @override
  void initState() {
    super.initState();
    CargadorRedes.cargar().then((redes) {
      if (mounted) setState(() => _redes = redes);
    });
  }

  Future<void> _seleccionarDocumentos() async {
    setState(() => _cargando = true);
    try {
      final nuevos = await _selector.seleccionar();
      if (nuevos.isNotEmpty) _agregarDocumentos(nuevos);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _agregarDocumentos(List<Documento> nuevos) {
    final rutasExistentes = _documentos.map((d) => d.ruta).toSet();
    final sinDuplicados =
        nuevos.where((d) => !rutasExistentes.contains(d.ruta)).toList();

    setState(() => _documentos.addAll(sinDuplicados));

    final omitidos = nuevos.length - sinDuplicados.length;
    if (omitidos > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '$omitidos archivo${omitidos != 1 ? 's' : ''} ya estaba${omitidos != 1 ? 'n' : ''} en la lista.'),
      ));
    }
  }

  void _onDrop(DropDoneDetails details) {
    final pdfs = details.files
        .where((f) => f.path.toLowerCase().endsWith('.pdf'))
        .map((f) => Documento(
              nombre: File(f.path).uri.pathSegments.last,
              ruta: f.path,
            ))
        .toList();

    final ignorados = details.files.length - pdfs.length;

    if (pdfs.isNotEmpty) _agregarDocumentos(pdfs);

    if (ignorados > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '$ignorados archivo${ignorados != 1 ? 's' : ''} ignorado${ignorados != 1 ? 's' : ''}: solo se aceptan PDF.'),
      ));
    }
  }

  void _quitarDocumento(Documento documento) {
    if (documento.estado == EstadoDocumento.procesando) return;
    setState(() => _documentos.remove(documento));
  }

  void _limpiarSeleccion() {
    if (_procesandoTodos) return;
    setState(() => _documentos.clear());
  }

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  /// Registra en la base de datos el documento con sus datos ya confirmados y
  /// la ruta actual del PDF (ya renombrado).
  void _registrarDocumento(Documento documento) {
    final repositorio = widget.repositorio;
    if (repositorio == null) {
      _avisar('No se pudo abrir la base de datos: ${widget.errorBaseDatos ?? 'error desconocido'}');
      return;
    }
    try {
      final resultado = repositorio.registrar(DocumentoAlmacenado.desdeDocumentoConfirmado(documento));
      if (resultado.registrado) {
        setState(() => documento.idRegistro = resultado.documento.id);
        _avisar('Documento registrado correctamente.');
      } else {
        // Ya existía: no se crea otro ni se toca el existente (y este PDF no
        // se enlaza con él, para no sobrescribirle la ruta más adelante).
        _avisar('Este documento ya se encuentra registrado.');
      }
    } catch (e) {
      _avisar('No se pudo registrar el documento: ${e is StateError ? e.message : e}');
    }
  }

  /// Si un documento ya registrado se vuelve a confirmar (y por tanto se puede
  /// renombrar), la base debe seguir apuntando a su ruta actual.
  void _documentoCambio(Documento documento) {
    final id = documento.idRegistro;
    if (id != null && documento.datosConfirmados) {
      try {
        widget.repositorio?.actualizarRutaPdf(id, documento.ruta);
      } catch (_) {
        // La ruta guardada quedaría desactualizada; no debe interrumpir la edición.
      }
    }
    setState(() {});
  }

  Future<void> _procesarDocumento(Documento documento) async {
    final procesador = ProcesadorPdf(redes: _redes);
    await procesador.procesarDocumento(documento, () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _procesarTodos() async {
    setState(() => _procesandoTodos = true);
    try {
      for (final documento in _documentos) {
        if (documento.sePuedeProcesar) {
          await _procesarDocumento(documento);
        }
      }
    } finally {
      if (mounted) setState(() => _procesandoTodos = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hayDocumentos = _documentos.isNotEmpty;
    final haySinProcesar = _documentos.any((d) => d.sePuedeProcesar);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Procesamiento de Documentos Administrativos'),
            Text(
              'Municipalidad Distrital de Pocollay',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        toolbarHeight: 64,
        actions: hayDocumentos
            ? [
                if (haySinProcesar)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton.icon(
                      onPressed: _procesandoTodos ? null : _procesarTodos,
                      icon: _procesandoTodos
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.play_circle_outline),
                      label: const Text('Procesar todos'),
                    ),
                  ),
                TextButton.icon(
                  onPressed: _procesandoTodos ? null : _limpiarSeleccion,
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Limpiar selección'),
                ),
                const SizedBox(width: 8),
              ]
            : null,
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _arrastrandoEncima = true),
        onDragExited: (_) => setState(() => _arrastrandoEncima = false),
        onDragDone: (details) {
          setState(() => _arrastrandoEncima = false);
          _onDrop(details);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _arrastrandoEncima
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
                : null,
            border: _arrastrandoEncima
                ? Border.all(
                    color: theme.colorScheme.primary,
                    width: 2,
                  )
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fila superior: botón + indicador de arrastre
                Row(
                  children: [
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _cargando ? null : _seleccionarDocumentos,
                        icon: _cargando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.folder_open),
                        label: const Text('Seleccionar documentos PDF'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'o arrastra archivos PDF aquí',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Contador
                if (hayDocumentos) ...[
                  Text(
                    '${_documentos.length} documento${_documentos.length != 1 ? 's' : ''} seleccionado${_documentos.length != 1 ? 's' : ''}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Lista o estado vacío
                Expanded(
                  child: hayDocumentos
                      ? Builder(builder: (context) {
                          final ordenados = ordenarDocumentos(_documentos);
                          return ListView.builder(
                            itemCount: ordenados.length,
                            itemBuilder: (context, index) {
                              final documento = ordenados[index];
                              return DocumentoTile(
                                key: ObjectKey(documento),
                                documento: documento,
                                onQuitar: () => _quitarDocumento(documento),
                                onProcesar: () => _procesarDocumento(documento),
                                onCambio: () => _documentoCambio(documento),
                                onRegistrar: () => _registrarDocumento(documento),
                              );
                            },
                          );
                        })
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _arrastrandoEncima
                                    ? Icons.file_download
                                    : Icons.inbox_outlined,
                                size: 72,
                                color: _arrastrandoEncima
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _arrastrandoEncima
                                    ? 'Suelta para agregar los PDFs'
                                    : 'Ningún documento seleccionado',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: _arrastrandoEncima
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.outlineVariant,
                                ),
                              ),
                              if (!_arrastrandoEncima) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Usa el botón o arrastra archivos PDF directamente a esta ventana.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

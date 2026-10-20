import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../models/documento.dart';
import '../services/editor_pdf.dart';

/// Visor básico del PDF del documento (estilo lector de PDF): miniaturas,
/// página actual, navegación, rotación y eliminación de la página mostrada.
/// El PDF se lee en memoria (no se bloquea el archivo) y las ediciones se aplican
/// directamente sobre el archivo.
class VistaPreviaPdf extends StatefulWidget {
  final Documento documento;

  /// Se invoca cuando el documento cambió (se editó el PDF y se descartó el
  /// resultado OCR), para que la pantalla que lo contiene se actualice.
  final VoidCallback alModificarDocumento;

  const VistaPreviaPdf({
    super.key,
    required this.documento,
    required this.alModificarDocumento,
  });

  @override
  State<VistaPreviaPdf> createState() => _VistaPreviaPdfState();
}

class _VistaPreviaPdfState extends State<VistaPreviaPdf> {
  static const double _escalaPagina = 2.4;
  static const double _escalaMiniatura = 0.22;
  static const double _altoItemMiniatura = 138;

  final EditorPdf _editor = EditorPdf();
  final ScrollController _scrollMiniaturas = ScrollController();
  final FocusNode _foco = FocusNode();

  PdfDocument? _pdf;
  ui.Image? _imagen;
  List<ui.Image?> _miniaturas = [];
  int _pagina = 1;
  int _total = 0;
  bool _cargando = true;
  bool _ocupado = false;
  String? _error;
  String? _aviso;
  int _generacion = 0;
  int _pedido = 0;
  DateTime _ultimaRueda = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    // setState no puede llamarse de forma síncrona dentro de initState.
    scheduleMicrotask(() => _abrir(1));
  }

  @override
  void dispose() {
    _generacion++;
    _pdf?.dispose();
    _imagen?.dispose();
    for (final m in _miniaturas) {
      m?.dispose();
    }
    _scrollMiniaturas.dispose();
    _foco.dispose();
    super.dispose();
  }

  Future<ui.Image> _dibujarPagina(PdfPage pagina, double escala) async {
    final render = await pagina.render(
      fullWidth: pagina.width * escala,
      fullHeight: pagina.height * escala,
      backgroundColor: 0xFFFFFFFF,
    );
    if (render == null) throw Exception('no se pudo dibujar la página');
    final ancho = render.width;
    final alto = render.height;
    final pixeles = Uint8List.fromList(render.pixels);
    render.dispose();
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixeles, ancho, alto, ui.PixelFormat.bgra8888, completer.complete);
    return completer.future;
  }

  Future<void> _abrir(int pagina) async {
    if (!mounted) return;
    final gen = ++_generacion;
    final pedido = ++_pedido;
    setState(() {
      _cargando = true;
      _error = null;
    });
    PdfDocument? nuevo;
    try {
      final bytes = await File(widget.documento.ruta).readAsBytes();
      nuevo = await PdfDocument.openData(bytes, sourceName: 'vista:${widget.documento.ruta}:$gen');
      if (!mounted || gen != _generacion) {
        await nuevo.dispose();
        return;
      }
      if (nuevo.pages.isEmpty) {
        await nuevo.dispose();
        throw Exception('el PDF no tiene páginas');
      }
      final anterior = _pdf;
      _pdf = nuevo;
      nuevo = null;
      await anterior?.dispose();
      _total = _pdf!.pages.length;
      _pagina = pagina.clamp(1, _total);
      await _dibujar(gen, pedido);
      unawaited(_cargarMiniaturas(gen));
    } catch (e) {
      await nuevo?.dispose();
      if (!mounted || gen != _generacion) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo abrir el PDF: $e';
      });
    }
  }

  Future<void> _dibujar(int gen, int pedido) async {
    final pdf = _pdf;
    if (pdf == null) return;
    setState(() => _cargando = true);
    try {
      final imagen = await _dibujarPagina(pdf.pages[_pagina - 1], _escalaPagina);
      if (!mounted || gen != _generacion || pedido != _pedido) {
        imagen.dispose();
        return;
      }
      final anterior = _imagen;
      setState(() {
        _imagen = imagen;
        _cargando = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => anterior?.dispose());
    } catch (e) {
      if (!mounted || gen != _generacion || pedido != _pedido) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo mostrar la página: $e';
      });
    }
  }

  Future<void> _cargarMiniaturas(int gen) async {
    final pdf = _pdf;
    if (pdf == null || !mounted) return;
    final anteriores = _miniaturas;
    setState(() => _miniaturas = List<ui.Image?>.filled(pdf.pages.length, null));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final m in anteriores) {
        m?.dispose();
      }
    });
    _centrarMiniatura();
    for (var i = 0; i < pdf.pages.length; i++) {
      if (!mounted || gen != _generacion) return;
      try {
        final mini = await _dibujarPagina(pdf.pages[i], _escalaMiniatura);
        if (!mounted || gen != _generacion) {
          mini.dispose();
          return;
        }
        setState(() => _miniaturas[i] = mini);
      } catch (_) {
        return;
      }
    }
  }

  void _centrarMiniatura() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollMiniaturas.hasClients) return;
      final pos = _scrollMiniaturas.position;
      final destino = ((_pagina - 1) * _altoItemMiniatura - pos.viewportDimension / 2 + _altoItemMiniatura / 2)
          .clamp(0.0, pos.maxScrollExtent);
      _scrollMiniaturas.animateTo(destino, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
    });
  }

  void _irA(int nueva) {
    if (_pdf == null || _ocupado || nueva < 1 || nueva > _total || nueva == _pagina) return;
    final pedido = ++_pedido;
    setState(() {
      _pagina = nueva;
      _aviso = null;
    });
    _centrarMiniatura();
    _dibujar(_generacion, pedido);
  }

  KeyEventResult _alTeclear(FocusNode nodo, KeyEvent evento) {
    if (evento is! KeyDownEvent) return KeyEventResult.ignored;
    final tecla = evento.logicalKey;
    if (tecla == LogicalKeyboardKey.arrowRight ||
        tecla == LogicalKeyboardKey.arrowDown ||
        tecla == LogicalKeyboardKey.pageDown) {
      _irA(_pagina + 1);
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.arrowLeft ||
        tecla == LogicalKeyboardKey.arrowUp ||
        tecla == LogicalKeyboardKey.pageUp) {
      _irA(_pagina - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _alRueda(PointerSignalEvent senal) {
    if (senal is! PointerScrollEvent) return;
    final ahora = DateTime.now();
    if (ahora.difference(_ultimaRueda).inMilliseconds < 200) return;
    _ultimaRueda = ahora;
    _irA(senal.scrollDelta.dy > 0 ? _pagina + 1 : _pagina - 1);
  }

  Future<bool> _confirmar(String titulo, String detalle, {required String etiqueta, bool peligro = false}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(detalle),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: peligro ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(etiqueta),
          ),
        ],
      ),
    );
    return r == true && mounted;
  }

  /// Aplica una edición directamente sobre el archivo y recarga el visor al
  /// instante. El texto OCR y los campos extraídos no se modifican.
  Future<void> _aplicarEdicion(
    Future<void> Function(String ruta) operacion,
    void Function() contar,
    String aviso,
  ) async {
    final numero = _pagina;
    setState(() {
      _ocupado = true;
      _aviso = null;
    });
    try {
      await operacion(widget.documento.ruta);
      contar();
      widget.alModificarDocumento();
      await _abrir(numero);
      if (mounted) setState(() => _aviso = aviso);
    } catch (e) {
      if (mounted) setState(() => _aviso = 'No se pudo completar la acción: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _eliminarPaginaActual() async {
    if (_total <= 1 || _ocupado) return;
    final numero = _pagina;
    final ok = await _confirmar(
      '¿Eliminar la página $numero de $_total?',
      'La página se eliminará del archivo PDF de forma definitiva (se modifica el archivo original). '
      'El texto OCR y los campos ya extraídos no se modifican.',
      etiqueta: 'Eliminar página',
      peligro: true,
    );
    if (!ok) return;
    await _aplicarEdicion(
      (ruta) => _editor.eliminarPagina(ruta, numero),
      () => widget.documento.paginasEliminadas++,
      'Se eliminó la página $numero del PDF.',
    );
  }

  Future<void> _rotar({required bool horario}) async {
    if (_pdf == null || _ocupado) return;
    final numero = _pagina;
    await _aplicarEdicion(
      (ruta) => _editor.rotarPagina(ruta, numero, horario: horario),
      () => widget.documento.paginasRotadas++,
      'Se giró la página $numero 90° ${horario ? 'a la derecha' : 'a la izquierda'} en el PDF.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listo = _pdf != null && _error == null && !_ocupado;
    final puedeEliminar = listo && _total > 1 && !_cargando;

    return Focus(
      focusNode: _foco,
      onKeyEvent: _alTeclear,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(_total == 0 ? 'Página –' : 'Página $_pagina de $_total', style: theme.textTheme.titleSmall),
              Tooltip(
                message: _total == 1 ? 'No se puede eliminar la única página del documento' : '',
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: puedeEliminar ? theme.colorScheme.error : theme.colorScheme.outlineVariant),
                  ),
                  onPressed: puedeEliminar ? _eliminarPaginaActual : null,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Eliminar esta página'),
                ),
              ),
              Tooltip(
                message: 'Girar la página 90° a la izquierda',
                child: OutlinedButton.icon(
                  onPressed: listo && !_cargando ? () => _rotar(horario: false) : null,
                  icon: const Icon(Icons.rotate_left, size: 18),
                  label: const Text('Girar izq.'),
                ),
              ),
              Tooltip(
                message: 'Girar la página 90° a la derecha',
                child: OutlinedButton.icon(
                  onPressed: listo && !_cargando ? () => _rotar(horario: true) : null,
                  icon: const Icon(Icons.rotate_right, size: 18),
                  label: const Text('Girar der.'),
                ),
              ),
            ],
          ),          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 104, child: _listaMiniaturas(theme)),
                const SizedBox(width: 8),
                Expanded(child: _areaPagina(theme)),
              ],
            ),
          ),
          if (_aviso != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_aviso!, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }

  Widget _marco(ThemeData theme, Widget hijo) => DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(4),
        ),
        child: hijo,
      );

  Widget _listaMiniaturas(ThemeData theme) {
    return _marco(
      theme,
      ListView.builder(
        controller: _scrollMiniaturas,
        itemCount: _total,
        itemExtent: _altoItemMiniatura,
        itemBuilder: (context, i) {
          final seleccionada = i + 1 == _pagina;
          final mini = i < _miniaturas.length ? _miniaturas[i] : null;
          return Padding(
            padding: const EdgeInsets.all(5),
            child: InkWell(
              onTap: () {
                _foco.requestFocus();
                _irA(i + 1);
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                    color: seleccionada ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                    width: seleccionada ? 3 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: mini == null
                            ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                            : RawImage(image: mini, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                      ),
                    ),
                    Text('${i + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: seleccionada ? FontWeight.bold : FontWeight.normal,
                          color: Colors.black87,
                        )),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _areaPagina(ThemeData theme) {
    Widget contenido;
    if (_error != null) {
      contenido = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ),
      );
    } else if (_imagen == null) {
      contenido = const Center(child: CircularProgressIndicator());
    } else {
      contenido = Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: RawImage(image: _imagen, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
          ),
          if (_cargando || _ocupado)
            const Positioned.fill(
              child: ColoredBox(color: Colors.white54, child: Center(child: CircularProgressIndicator())),
            ),
        ],
      );
    }
    return Listener(
      onPointerSignal: _alRueda,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _foco.requestFocus,
        child: _marco(theme, contenido),
      ),
    );
  }
}
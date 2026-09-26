import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Native Flutter adaptation of the supplied Originkit Ribbon Glow effect.
class RibbonGlow extends StatefulWidget {
  const RibbonGlow({super.key});
  @override
  State<RibbonGlow> createState() => _RibbonGlowState();
}

class _RibbonGlowState extends State<RibbonGlow> with WidgetsBindingObserver {
  static final _program =
      ui.FragmentProgram.fromAsset('shaders/ribbon_glow.frag');
  ui.FragmentShader? _shader;
  Timer? _timer;
  double _time = 0;
  Offset? _pointer;
  bool _reduceMotion = true, _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      final program = await _program;
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
      _animate();
    } catch (_) {
      // Keep the blue gradient when a renderer cannot load runtime shaders.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _animate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    _animate();
  }

  void _animate() {
    _timer?.cancel();
    if (_shader == null || _reduceMotion || !_visible) return;
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (mounted) setState(() => _time = (_time + .0165) % 3600);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shader?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
      child: MouseRegion(
          onHover: _reduceMotion
              ? null
              : (event) => setState(() => _pointer = event.localPosition),
          onExit: (_) => setState(() => _pointer = null),
          child: DecoratedBox(
              decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF07142D), Color(0xFF2455C9)])),
              child: _shader == null
                  ? const SizedBox.expand()
                  : CustomPaint(
                      painter: _RibbonPainter(_shader!, _time, _pointer),
                      child: const SizedBox.expand()))));
}

class _RibbonPainter extends CustomPainter {
  const _RibbonPainter(this.shader, this.time, this.pointer);
  final ui.FragmentShader shader;
  final double time;
  final Offset? pointer;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(
          3, pointer == null ? 0 : (pointer!.dx - size.width / 2) / size.height)
      ..setFloat(4,
          pointer == null ? 0 : (size.height / 2 - pointer!.dy) / size.height)
      ..setFloat(5, pointer == null ? 0 : 1);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_RibbonPainter old) =>
      old.time != time || old.pointer != pointer;
}

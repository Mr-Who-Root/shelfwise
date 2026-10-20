import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/fx.dart';

const _paper = Color(0xFFFFFDF7);
const _wood = Color(0xFF2B1D10);

/// Opens the attached PDF of [b] at the page it was left on.
Future<void> openReader(Item b) async {
  if (!store.copyExists(b)) {
    toast('This book’s PDF isn’t on this phone. Attach it again.');
    return;
  }
  Sfx.play('page');
  dropFocus();
  await navKey.currentState!.push(PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => ReaderScreen(book: b),
    transitionsBuilder: (_, a, _, c) {
      final t = CurvedAnimation(parent: a, curve: ease);
      return FadeTransition(opacity: t, child: ScaleTransition(scale: Tween(begin: .94, end: 1.0).animate(t), child: c));
    },
  ));
}

/// A paper-like PDF reader.
///
/// At normal size, drag a corner (or tap the sides) to curl the page over.
/// Pinch or double-tap to zoom in place; while zoomed, one finger pans and
/// swiping past the page edge (or tapping the sides) slides to the next page.
class ReaderScreen extends StatefulWidget {
  final Item book;
  const ReaderScreen({super.key, required this.book});
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> with TickerProviderStateMixin {
  Item get b => widget.book;
  PdfDocument? _doc;
  int _count = 0;
  late int _page = b.page;
  double _aspect = 1 / 1.414;
  String? _err;

  final _cache = <int, ui.Image>{};
  final _loading = <int>{};
  final _hi = <int, ui.Image>{};
  final _hiLoading = <int>{};
  Future<void> _queue = Future.value();
  double _renderW = 0;
  Rect _rect = Rect.zero;
  Size _view = Size.zero;

  // curl (normal size)
  Offset? _t;
  bool _forward = true, _top = false;
  Offset _start = Offset.zero;
  late final AnimationController _anim = AnimationController(vsync: this);
  Offset Function(double)? _path;

  // zoom: screen = _zo + _zs * layout
  double _zs = 1;
  Offset _zo = Offset.zero;
  late final AnimationController _zAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  (double, Offset) _za = (1, Offset.zero), _zb = (1, Offset.zero);

  // sliding between pages while zoomed
  late final AnimationController _slide = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
  int _slideDir = 0;
  Offset _nextZo = Offset.zero;

  // gesture bookkeeping
  String _mode = '';
  double _s0 = 1;
  Offset _o0 = Offset.zero, _f0 = Offset.zero;
  double _over = 0;
  Timer? _tapTimer;
  DateTime? _lastTap;
  Offset _lastTapPos = Offset.zero;

  bool _chrome = true, _hint = false;
  double? _slideValue;

  bool get _zoomed => _zs > 1.01;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _anim.addListener(() {
      if (_path != null) setState(() => _t = _path!(_anim.value));
    });
    _zAnim.addListener(() {
      final v = Curves.easeOutCubic.transform(_zAnim.value);
      setState(() {
        _zs = _za.$1 + (_zb.$1 - _za.$1) * v;
        _zo = Offset.lerp(_za.$2, _zb.$2, v)!;
      });
    });
    _slide.addListener(() => setState(() {}));
    _hint = b.readAt == null;
    _open();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _tapTimer?.cancel();
    _anim.dispose();
    _zAnim.dispose();
    _slide.dispose();
    for (final i in [..._cache.values, ..._hi.values]) {
      i.dispose();
    }
    _queue.whenComplete(() => _doc?.close());
    _save();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final d = await PdfDocument.openFile(store.bookFile(b.file!).path);
      final p = await d.getPage(min(d.pagesCount, max(1, b.page + 1)));
      final aspect = p.width / p.height;
      await p.close();
      if (!mounted) {
        await d.close();
        return;
      }
      setState(() {
        _doc = d;
        _count = d.pagesCount;
        _aspect = aspect.isFinite && aspect > 0 ? aspect : _aspect;
        _page = _page.clamp(0, max(0, _count - 1));
      });
      if (b.pages != _count) b.pages = _count;
      _save();
      if (_hint) Future.delayed(const Duration(milliseconds: 4200), () => mounted ? setState(() => _hint = false) : null);
    } catch (e) {
      setState(() => _err = 'This PDF couldn’t be opened.');
    }
  }

  void _save() {
    b
      ..page = _page
      ..readAt = DateTime.now().millisecondsSinceEpoch;
    store.changed();
  }

  // ---------------- rendering ----------------

  Future<ui.Image?> _render(int i, double w) async {
    final d = _doc;
    if (d == null) return null;
    final p = await d.getPage(i + 1);
    final img = await p.render(width: w, height: w * p.height / p.width, format: PdfPageImageFormat.jpeg, backgroundColor: '#FFFFFF', quality: 92);
    await p.close();
    if (img == null) return null;
    return (await (await ui.instantiateImageCodec(img.bytes)).getNextFrame()).image;
  }

  void _want(int i) {
    if (_doc == null || i < 0 || i >= _count || _cache.containsKey(i) || _loading.contains(i) || _renderW <= 0) return;
    _loading.add(i);
    final w = _renderW;
    _queue = _queue.then((_) async {
      if (!mounted) return;
      try {
        final img = await _render(i, w);
        if (img == null) return;
        if (!mounted) return img.dispose();
        setState(() => _cache[i] = img);
        _evict();
      } catch (_) {
      } finally {
        _loading.remove(i);
      }
    });
  }

  /// A sharper copy of a page for reading zoomed in.
  void _wantHi(int i) {
    if (_doc == null || i < 0 || i >= _count || _hi.containsKey(i) || _hiLoading.contains(i) || _renderW <= 0) return;
    _hiLoading.add(i);
    final w = min(_renderW * 2.2, 2000.0);
    _queue = _queue.then((_) async {
      if (!mounted) return;
      try {
        final img = await _render(i, w);
        if (img == null) return;
        if (!mounted) return img.dispose();
        setState(() => _hi[i] = img);
        for (final k in _hi.keys.where((k) => (k - _page).abs() > 1).toList()) {
          _hi.remove(k)?.dispose();
        }
      } catch (_) {
      } finally {
        _hiLoading.remove(i);
      }
    });
  }

  void _evict() {
    final keep = {for (var k = _page - 2; k <= _page + 3; k++) k};
    for (final k in _cache.keys.where((k) => !keep.contains(k)).toList()) {
      _cache.remove(k)?.dispose();
    }
  }

  void _prefetch() {
    for (final i in [_page, _page + 1, _page - 1, _page + 2]) {
      _want(i);
    }
    if (_zs > 1.25) {
      _wantHi(_page);
      _wantHi(_page + 1);
    }
  }

  // ---------------- zoom ----------------

  /// Keeps the zoomed page covering the screen (or centred when it's smaller).
  Offset _clampZo(double s, Offset o, {double slack = 0}) {
    double axis(double v, double lo, double size, double view, double centre) {
      final len = size * s;
      if (len <= view) return centre * (1 - s);
      final minV = view - s * (lo + size); // right/bottom edge reaches the screen edge
      final maxV = -s * lo; // left/top edge reaches the screen edge
      return v.clamp(minV - slack, maxV + slack);
    }

    return Offset(
      axis(o.dx, _rect.left, _rect.width, _view.width, _rect.center.dx),
      axis(o.dy, _rect.top, _rect.height, _view.height, _rect.center.dy),
    );
  }

  void _zoomTo(double s, Offset o, {int ms = 280}) {
    _za = (_zs, _zo);
    _zb = (s, s <= 1.01 ? Offset.zero : _clampZo(s, o));
    _zAnim
      ..duration = Duration(milliseconds: ms)
      ..forward(from: 0);
    if (s > 1.25) _wantHi(_page);
  }

  void _toggleZoom(Offset focal) {
    Buzz.tick();
    if (_zoomed) {
      _zoomTo(1, Offset.zero);
    } else {
      const s = 2.2;
      final p = (focal - _zo) / _zs;
      setState(() => _chrome = false);
      _zoomTo(s, focal - p * s);
    }
  }

  /// Where the zoomed view should sit on a freshly turned page: same zoom and column, top of the page.
  Offset _topOf(double s, Offset o) => _clampZo(s, Offset(o.dx, -s * _rect.top));

  // ---------------- turning ----------------

  Offset get _corner => Offset(_rect.right, _top ? _rect.top : _rect.bottom);
  Offset get _flat => Offset(_rect.left - _rect.width, _corner.dy);

  Offset _constrain(Offset t) {
    final s = Offset(_rect.left, _corner.dy);
    var v = t - s;
    if (v.distance > _rect.width) v = v / v.distance * _rect.width;
    t = s + v;
    final s2 = Offset(_rect.left, _top ? _rect.bottom : _rect.top);
    final diag = sqrt(_rect.width * _rect.width + _rect.height * _rect.height);
    var v2 = t - s2;
    if (v2.distance > diag) v2 = v2 / v2.distance * diag;
    t = s2 + v2;
    return Offset(min(t.dx, _corner.dx - .5), t.dy);
  }

  bool get _busy => _anim.isAnimating || _slide.isAnimating;

  void _run(Offset Function(double) path, int ms, Curve curve, VoidCallback done) {
    _path = (v) => path(curve.transform(v));
    _anim
      ..duration = Duration(milliseconds: ms)
      ..forward(from: 0).whenComplete(() {
        _path = null;
        if (mounted) done();
      });
  }

  void _turned(int delta) {
    setState(() {
      _page += delta;
      _t = null;
    });
    _evict();
    _prefetch();
    _save();
  }

  bool _canGo(int dir) {
    if (dir > 0 && _page >= _count - 1) {
      _end();
      return false;
    }
    if (dir < 0 && _page <= 0) {
      toast('This is the first page');
      return false;
    }
    return true;
  }

  void _go(int dir) {
    if (_busy || _doc == null || !_canGo(dir)) return;
    if (_zoomed) return _slideTo(dir);
    _want(_page + dir);
    _forward = dir > 0;
    _top = false;
    Sfx.play('page');
    Buzz.tick();
    final c = _corner, f = _flat, h = _rect.height;
    if (dir > 0) {
      _run((p) => Offset(c.dx + (f.dx - c.dx) * p, c.dy - sin(p * pi) * h * .12), 560, Curves.easeInOut, () => _turned(1));
    } else {
      _run((p) => Offset(f.dx + (c.dx - f.dx) * p, c.dy - sin(p * pi) * h * .12), 560, Curves.easeInOut, () => _turned(-1));
    }
  }

  /// Zoomed in: slide the next page across, keeping the zoom.
  void _slideTo(int dir) {
    _want(_page + dir);
    _wantHi(_page + dir);
    _nextZo = _topOf(_zs, _zo);
    _slideDir = dir;
    Sfx.play('page');
    Buzz.tick();
    _slide.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      _zo = _nextZo;
      _slideDir = 0;
      _slide.value = 0;
      _turned(dir);
    });
  }

  void _end() {
    if (b.finished) {
      toast('That’s the last page');
      return;
    }
    openDialog((ctx) => AppDialog(title: 'You reached the end 🎉', children: [
          Sub('That’s the last page of ${b.title}. Mark it as finished?'),
        ], actions: [
          const Btn('Not yet'),
          Btn('Mark as finished', kind: Kind.pri, onTap: () {
            store.setStatus(b, 'f');
            Sfx.play('trophy');
            final s = MediaQuery.sizeOf(ctx);
            confetti(Offset(s.width / 2, s.height * .4));
            toast('Marked as Finished');
            return true;
          }),
        ]));
  }

  // ---------------- gestures ----------------

  void _onTapUp(Offset p) {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < const Duration(milliseconds: 280) && (p - _lastTapPos).distance < 60) {
      _tapTimer?.cancel();
      _lastTap = null;
      _toggleZoom(p);
      return;
    }
    _lastTap = now;
    _lastTapPos = p;
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      final w = _view.width;
      if (p.dx > w * .66) {
        _go(1);
      } else if (p.dx < w * .3) {
        _go(-1);
      } else {
        setState(() => _chrome = !_chrome);
      }
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    if (_doc == null || _busy) {
      _mode = '';
      return;
    }
    _zAnim.stop();
    _s0 = _zs;
    _o0 = _zo;
    _f0 = d.localFocalPoint;
    _over = 0;
    if (d.pointerCount >= 2) {
      _mode = 'pinch';
    } else if (_zoomed) {
      _mode = 'pan';
    } else {
      _mode = 'curl';
      _curlStart(d.localFocalPoint);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2 && _mode != 'pinch') {
      // a second finger landed: switch to zooming
      if (_mode == 'curl') setState(() => _t = null);
      if (_chrome) setState(() => _chrome = false);
      _mode = 'pinch';
      _s0 = _zs;
      _o0 = _zo;
      _f0 = d.localFocalPoint;
      return;
    }
    switch (_mode) {
      case 'pinch':
        final s = (_s0 * d.scale).clamp(1.0, 5.0);
        final p = (_f0 - _o0) / _s0;
        setState(() {
          _zs = s;
          _zo = s <= 1.01 ? Offset.zero : _clampZo(s, d.localFocalPoint - p * s);
        });
      case 'pan':
        final raw = _o0 + (d.localFocalPoint - _f0);
        final cl = _clampZo(_zs, raw);
        _over = raw.dx - cl.dx;
        setState(() => _zo = Offset(cl.dx + _over * .35, cl.dy));
      case 'curl':
        _curlMove(d.localFocalPoint);
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final vx = d.velocity.pixelsPerSecond.dx;
    switch (_mode) {
      case 'pinch':
        if (_zs < 1.08) {
          _zoomTo(1, Offset.zero, ms: 200);
        } else {
          _wantHi(_page);
        }
      case 'pan':
        final cl = _clampZo(_zs, _zo);
        final atRight = (_zo.dx - cl.dx) <= 1 && (cl.dx - _clampZo(_zs, Offset(-1e9, cl.dy)).dx).abs() < 1;
        final atLeft = (cl.dx - _clampZo(_zs, Offset(1e9, cl.dy)).dx).abs() < 1;
        if (_over < -70 || (atRight && vx < -900)) {
          _zo = cl;
          if (_canGo(1)) _slideTo(1);
        } else if (_over > 70 || (atLeft && vx > 900)) {
          _zo = cl;
          if (_canGo(-1)) _slideTo(-1);
        } else if (_over.abs() > .5) {
          _zoomTo(_zs, cl, ms: 220);
        }
      case 'curl':
        _curlEnd(vx);
    }
    _mode = '';
  }

  void _curlStart(Offset p) {
    _forward = p.dx >= _rect.center.dx;
    if (_forward && _page >= _count - 1) return;
    if (!_forward && _page <= 0) return;
    _top = p.dy < _rect.center.dy - _rect.height * .15;
    _start = p;
    _want(_page + (_forward ? 1 : -1));
    _t = null;
  }

  void _curlMove(Offset p) {
    final d = p - _start;
    if (_t == null) {
      if (d.distance < 8) return; // a tap, not a turn
      if (_forward ? _page >= _count - 1 : _page <= 0) return;
      Buzz.tick();
    }
    if (_forward) {
      setState(() => _t = _constrain(_corner + Offset(d.dx * 1.5, d.dy * 1.2)));
    } else {
      final prog = (d.dx / max(1, _rect.right - _start.dx)).clamp(0.0, 1.0);
      final x = _flat.dx + (_corner.dx - _flat.dx) * prog;
      setState(() => _t = _constrain(Offset(x, _corner.dy + d.dy * 1.2)));
    }
  }

  void _curlEnd(double vx) {
    final t = _t;
    if (t == null) return;
    final c = _corner, f = _flat;
    final prog = ((c.dx - t.dx) / (c.dx - f.dx)).clamp(0.0, 1.0);
    if (_forward) {
      if (vx < -350 || (vx < 350 && prog > .4)) {
        Sfx.play('page');
        _run((p) => Offset.lerp(t, f, p)!, (380 * (1 - prog) + 120).round(), Curves.easeOut, () => _turned(1));
      } else {
        _run((p) => Offset.lerp(t, c - const Offset(.6, 0), p)!, (300 * prog + 120).round(), Curves.easeOut, () => setState(() => _t = null));
      }
    } else {
      if (vx > 350 || (vx > -350 && prog < .6)) {
        Sfx.play('page');
        _run((p) => Offset.lerp(t, c - const Offset(.6, 0), p)!, (380 * prog + 120).round(), Curves.easeOut, () => _turned(-1));
      } else {
        _run((p) => Offset.lerp(t, f, p)!, (300 * (1 - prog) + 120).round(), Curves.easeOut, () => setState(() => _t = null));
      }
    }
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return PopScope(
      canPop: !_zoomed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _zoomed) _zoomTo(1, Offset.zero);
      },
      child: Scaffold(
        backgroundColor: _wood,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A2816), _wood, Color(0xFF1E140A)]),
          ),
          child: LayoutBuilder(builder: (context, cons) {
            _view = cons.biggest;
            final pad = EdgeInsets.fromLTRB(14, mq.padding.top + 58, 14, mq.padding.bottom + 84);
            final availW = cons.maxWidth - pad.horizontal, availH = cons.maxHeight - pad.vertical;
            final cur = _cache[_page];
            if (cur != null && _t == null && _slideDir == 0) _aspect = cur.width / cur.height;
            var w = availW, h = w / _aspect;
            if (h > availH) {
              h = availH;
              w = h * _aspect;
            }
            _rect = Rect.fromLTWH(pad.left + (availW - w) / 2, pad.top + (availH - h) / 2, w, h);
            final rw = min(availW * mq.devicePixelRatio, 1500.0);
            if (_doc != null && (rw - _renderW).abs() > 40) {
              _renderW = rw;
              for (final i in _cache.values) {
                i.dispose();
              }
              _cache.clear();
            }
            if (_doc != null) WidgetsBinding.instance.addPostFrameCallback((_) => _prefetch());
            final next = _slideDir == 0 ? null : _page + _slideDir;
            return Stack(children: [
              if (_err != null)
                Center(child: Text(_err!, style: nu(16, FontWeight.w700, const Color(0xFFF3EEE6))))
              else if (_doc == null)
                Center(child: CircularProgressIndicator(color: C.brown))
              else
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _onTapUp(d.localPosition),
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: _onScaleEnd,
                    child: CustomPaint(
                      painter: _PagePainter(
                        rect: _rect,
                        front: _zoomed ? (_hi[_page] ?? _cache[_page]) : _cache[_forward || _t == null ? _page : _page - 1],
                        under: _t == null ? null : _cache[_forward ? _page + 1 : _page],
                        t: _zoomed ? null : _t,
                        corner: _t == null ? null : _corner,
                        zs: _zs,
                        zo: _zo,
                        slide: _slide.value,
                        slideDir: _slideDir,
                        next: next == null ? null : (_hi[next] ?? _cache[next]),
                        nextZo: _nextZo,
                        view: _view,
                      ),
                    ),
                  ),
                ),
              _topBar(mq),
              _bottomBar(mq),
              if (_hint && _doc != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: _rect.center.dy - 30,
                  child: IgnorePointer(
                    child: Center(
                      child: FadeIn(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(color: const Color(0xE62B1D10), borderRadius: BorderRadius.circular(18)),
                          child: Text('Drag a corner or tap the edges to turn\nPinch or double-tap to zoom · tap the middle for controls',
                              textAlign: TextAlign.center, style: nu(13, FontWeight.w700, Colors.white, 1.4)),
                        ),
                      ),
                    ),
                  ),
                ),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _circle(Widget child, VoidCallback onTap, String label) => Semantics(
        button: true,
        label: label,
        child: Pressable(
          onTap: onTap,
          scale: .88,
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: Color.fromRGBO(255, 255, 255, .14), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      );

  Widget _topBar(MediaQueryData mq) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: IgnorePointer(
        ignoring: !_chrome,
        child: AnimatedOpacity(
          opacity: _chrome ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: AnimatedSlide(
            offset: _chrome ? Offset.zero : const Offset(0, -.4),
            duration: const Duration(milliseconds: 260),
            curve: ease,
            child: Container(
              padding: EdgeInsets.fromLTRB(12, mq.padding.top + 8, 12, 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xE61E140A), Color(0x002B1D10)]),
              ),
              child: Row(children: [
                _circle(const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20), () => Navigator.of(context).pop(), 'Close reader'),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(16, FontWeight.w800, const Color(0xFFF3EEE6))),
                    Text(b.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(12, FontWeight.w700, const Color(0xFFCDBFAE))),
                  ]),
                ),
                const SizedBox(width: 8),
                _circle(
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(_zoomed ? Icons.zoom_out_map_rounded : Icons.zoom_in_rounded,
                        key: ValueKey(_zoomed), color: Colors.white, size: 22),
                  ),
                  () => _toggleZoom(_view.center(Offset.zero)),
                  _zoomed ? 'Fit page' : 'Zoom in',
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(MediaQueryData mq) {
    final show = _chrome && _count > 0;
    final shown = (_slideValue ?? _page.toDouble()).round();
    final pct = _count <= 1 ? 100 : (shown / (_count - 1) * 100).round();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !show,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: AnimatedSlide(
            offset: show ? Offset.zero : const Offset(0, .4),
            duration: const Duration(milliseconds: 260),
            curve: ease,
            child: Container(
              padding: EdgeInsets.fromLTRB(18, 10, 18, mq.padding.bottom + 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x002B1D10), Color(0xCC1E140A)]),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Text('Page ${shown + 1} of $_count', style: nu(13, FontWeight.w800, const Color(0xFFF3EEE6))),
                  if (_zoomed) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(10)),
                      child: Text('${_zs.toStringAsFixed(1)}×', style: nu(11, FontWeight.w800, const Color(0xFFF3EEE6))),
                    ),
                  ],
                  const Spacer(),
                  Text('$pct%', style: nu(13, FontWeight.w800, const Color(0xFFF2B84B))),
                ]),
                SliderTheme(
                  data: const SliderThemeData(
                    trackHeight: 4,
                    activeTrackColor: Color(0xFFF2B84B),
                    inactiveTrackColor: Color.fromRGBO(255, 255, 255, .2),
                    thumbColor: Color(0xFFF2B84B),
                    overlayColor: Color(0x33F2B84B),
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
                  ),
                  child: Slider(
                    value: (_slideValue ?? _page.toDouble()).clamp(0, max(0, _count - 1).toDouble()),
                    min: 0,
                    max: max(1, _count - 1).toDouble(),
                    onChanged: (v) => setState(() => _slideValue = v),
                    onChangeEnd: (v) {
                      final target = v.round();
                      setState(() => _slideValue = null);
                      if (target == _page) return;
                      Sfx.play('page');
                      if (_zoomed) _zo = _topOf(_zs, _zo);
                      _turned(target - _page);
                    },
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the page: zoomed and sliding, or flat and curling over like paper.
class _PagePainter extends CustomPainter {
  final Rect rect;
  final ui.Image? front, under, next;
  final Offset? t, corner;
  final double zs, slide;
  final Offset zo, nextZo;
  final int slideDir;
  final Size view;
  _PagePainter({
    required this.rect,
    this.front,
    this.under,
    this.t,
    this.corner,
    required this.zs,
    required this.zo,
    required this.slide,
    required this.slideDir,
    this.next,
    required this.nextZo,
    required this.view,
  });

  void _page(Canvas c, ui.Image? img) {
    c.drawRect(rect, Paint()..color = _paper);
    if (img == null) {
      final p = Paint()..color = const Color(0xFFEDE6DA);
      for (var i = 0; i < 14; i++) {
        final y = rect.top + rect.height * (.1 + i * .058);
        c.drawRRect(RRect.fromLTRBR(rect.left + rect.width * .1, y, rect.right - rect.width * (i % 4 == 3 ? .35 : .1), y + 6, const Radius.circular(3)), p);
      }
      return;
    }
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final fit = applyBoxFit(BoxFit.contain, src.size, rect.size);
    final dst = Alignment.center.inscribe(fit.destination, rect);
    c.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.medium);
  }

  void _spine(Canvas c) {
    c.drawRect(
      Rect.fromLTWH(rect.left, rect.top, 22, rect.height),
      Paint()..shader = ui.Gradient.linear(rect.topLeft, rect.topLeft + const Offset(22, 0), [const Color(0x24000000), const Color(0x00000000)]),
    );
  }

  void _shadow(Canvas c) => c.drawRRect(
        RRect.fromRectAndRadius(rect.shift(const Offset(0, 6)), const Radius.circular(4)),
        Paint()
          ..color = const Color(0x8C000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );

  static List<Offset> _clip(List<Offset> poly, double Function(Offset) f) {
    final out = <Offset>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      final fa = f(a), fb = f(b);
      if (fa >= 0) out.add(a);
      if ((fa >= 0) != (fb >= 0)) out.add(a + (b - a) * (fa / (fa - fb)));
    }
    return out;
  }

  void _zoomedPage(Canvas c, ui.Image? img, Offset o, double dx) {
    c.save();
    c.translate(dx, 0);
    c.translate(o.dx, o.dy);
    c.scale(zs);
    _shadow(c);
    _page(c, img);
    c.restore();
  }

  @override
  void paint(Canvas c, Size size) {
    if (zs > 1.01 || slideDir != 0) {
      final w = view.width;
      final e = Curves.easeInOutCubic.transform(slide);
      _zoomedPage(c, front, zo, -slideDir * w * e);
      if (slideDir != 0) _zoomedPage(c, next, nextZo, slideDir * w * (1 - e));
      return;
    }
    _shadow(c);
    c.save();
    c.clipRect(rect);
    final tt = t, cc = corner;
    if (tt == null || cc == null || (cc - tt).distance < .5) {
      _page(c, front);
      _spine(c);
      c.restore();
      return;
    }
    final d = cc - tt;
    final n = d / d.distance;
    final m = (cc + tt) / 2;
    double side(Offset p) => (p - m).dx * n.dx + (p - m).dy * n.dy;
    Offset reflect(Offset p) => p - n * (2 * side(p));
    final quad = [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft];
    final kept = _clip(quad, (p) => -side(p));
    final removed = _clip(quad, side);
    final keptPath = Path()..addPolygon(kept, true);
    final removedPath = Path()..addPolygon(removed, true);
    final flap = removed.map(reflect).toList();
    final flapPath = Path()..addPolygon(flap, true);
    final depth = min(70.0, d.distance / 2 + 8);

    // 1. the page underneath, darkened next to the fold
    _page(c, under);
    _spine(c);
    c.save();
    c.clipPath(removedPath);
    c.drawRect(rect, Paint()..shader = ui.Gradient.linear(m, m + n * depth, [const Color(0x59000000), const Color(0x00000000)]));
    c.restore();

    // 2. what's left of the current page, with the flap's soft shadow on it
    c.save();
    c.clipPath(keptPath);
    _page(c, front);
    _spine(c);
    c.drawPath(
      flapPath.shift(-n * 4),
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    c.restore();

    // 3. the curled-over flap: the back of the paper, ink faintly showing through
    if (flap.length >= 3) {
      c.save();
      c.clipPath(flapPath);
      final a = 1 - 2 * n.dx * n.dx, bb = -2 * n.dx * n.dy, dd = 1 - 2 * n.dy * n.dy;
      final k = 2 * (m.dx * n.dx + m.dy * n.dy);
      c.save();
      c.transform(Float64List.fromList([a, bb, 0, 0, bb, dd, 0, 0, 0, 0, 1, 0, k * n.dx, k * n.dy, 0, 1]));
      _page(c, front);
      c.drawRect(rect, Paint()..color = const Color(0xDBFBF7EE));
      c.restore();
      c.drawRect(
        Rect.largest,
        Paint()..shader = ui.Gradient.linear(m, m - n * depth * 1.6, [const Color(0x2E000000), const Color(0x00FFFFFF), const Color(0x14000000)], [0, .55, 1]),
      );
      c.restore();
      c.drawPath(flapPath, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = const Color(0x22000000));
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_PagePainter o) => true;
}

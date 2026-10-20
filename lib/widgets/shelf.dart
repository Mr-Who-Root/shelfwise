import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../services/sfx.dart';
import '../theme.dart';
import 'book_cover.dart';
import 'common.dart';

class _Slot {
  final Item it;
  final double x, w, h;
  _Slot(this.it, this.x, this.w, this.h);
  double get mid => x + w / 2;
}

/// One shelf: overlapping books on a pastel glass band, with label, actions and slider.
class ShelfRow extends StatefulWidget {
  final Collection col;
  final int palette;
  final List<Item> items;
  final bool sub, home, exp, filtered;
  final int count;
  final void Function(Item it) onOpen;
  final VoidCallback? onMore, onAdd, onDecor;
  const ShelfRow({
    super.key,
    required this.col,
    required this.palette,
    required this.items,
    required this.count,
    required this.onOpen,
    this.sub = false,
    this.home = false,
    this.exp = false,
    this.filtered = false,
    this.onMore,
    this.onAdd,
    this.onDecor,
  });

  @override
  State<ShelfRow> createState() => _ShelfRowState();
}

class _ShelfRowState extends State<ShelfRow> with TickerProviderStateMixin {
  final _sc = ScrollController();
  final _stackKey = GlobalKey();
  final _viewKey = GlobalKey();
  late final AnimationController _shine =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final Ticker _auto = createTicker(_autoScroll);

  String? _pressed;
  Item? _drag;
  double _dragX = 0, _grab = 0, _finger = 0, _vx = 0;
  int? _insertAt; // where the dragged item would land; the others slide apart to make room
  bool _overflow = false;
  final Set<String> _fresh = {};

  double get _w => (MediaQuery.sizeOf(context).width * .21).clamp(70.0, 88.0);
  double get _h => _w * 1.42;
  bool get _canDrag => !widget.home && !widget.exp;

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  @override
  void didUpdateWidget(ShelfRow old) {
    super.didUpdateWidget(old);
    final before = old.items.map((e) => e.id).toSet();
    for (final it in widget.items) {
      if (!before.contains(it.id)) _fresh.add(it.id);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  @override
  void dispose() {
    _auto.dispose();
    _shine.dispose();
    _sc.dispose();
    super.dispose();
  }

  void _checkOverflow() {
    if (!mounted || !_sc.hasClients) return;
    final o = _sc.position.maxScrollExtent > 4;
    if (o != _overflow) setState(() => _overflow = o);
  }

  /// The items in display order: while dragging, the dragged one sits at [_insertAt].
  List<Item> get _ordered {
    final d = _drag, at = _insertAt;
    if (d == null || at == null) return widget.items;
    final others = widget.items.where((x) => x.id != d.id).toList();
    return others..insert(at.clamp(0, others.length), d);
  }

  (List<_Slot>, double) _layout([List<Item>? items]) {
    final w = _w, h = _h;
    final out = <_Slot>[];
    var x = 22.0, prevMr = 0.0;
    for (final (i, it) in (items ?? _ordered).indexed) {
      final g = it.isDecor;
      // decorations stand behind the glass like the books, drawn tall enough to peek over it
      final iw = g ? w * .95 : w;
      final ih = g ? h * shelfGadgetFactor(it.gadget!) : h;
      final ml = i == 0 ? 0.0 : (g ? -w * .05 : -w * .32);
      x += prevMr + ml;
      out.add(_Slot(it, x, iw, ih));
      x += iw;
      prevMr = g ? w * .28 : 0;
    }
    return (out, x + prevMr + 30);
  }

  // ---------------- press & drag ----------------

  void _tapDown(Item it) {
    if (_drag != null) return;
    setState(() => _pressed = it.id);
    if (!it.isDecor) _shine.forward(from: 0);
  }

  void _tapUp(Item it) {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _pressed = null);
      widget.onOpen(it);
    });
  }

  void _dragStart(Item it, _Slot s, LongPressStartDetails d) {
    Buzz.medium();
    Sfx.play('lift');
    setState(() {
      _pressed = null;
      _drag = it;
      _grab = d.localPosition.dx;
      _dragX = s.x;
      _finger = s.x + _grab;
      _insertAt = widget.items.indexOf(it);
    });
    _auto.start();
  }

  void _dragMove(LongPressMoveUpdateDetails d) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final view = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || view == null) return;
    _finger = box.globalToLocal(d.globalPosition).dx;
    final vx = view.globalToLocal(d.globalPosition).dx;
    _vx = vx < 36 ? -9 : (vx > view.size.width - 36 ? 9 : 0);
    _place();
  }

  /// Picks the gap from the other items' resting positions (not the animated ones), so it never jitters.
  void _place() {
    final d = _drag;
    if (d == null) return;
    _dragX = _finger - _grab;
    final others = widget.items.where((x) => x.id != d.id).toList();
    final (slots, _) = _layout(others);
    final centre = _dragX + (d.isDecor ? _w * .95 : _w) / 2;
    final at = slots.where((s) => s.mid < centre).length;
    if (at != _insertAt) Buzz.tick();
    setState(() => _insertAt = at);
  }

  void _autoScroll(Duration _) {
    if (_drag == null || _vx == 0 || !_sc.hasClients) return;
    final p = _sc.position;
    final next = (p.pixels + _vx).clamp(0.0, p.maxScrollExtent);
    final delta = next - p.pixels;
    if (delta == 0) return;
    _sc.jumpTo(next);
    _finger += delta;
    _place();
  }

  void _dragEnd() {
    _auto.stop();
    final d = _drag, at = _insertAt;
    Item? anchor;
    var before = true;
    if (d != null && at != null && at != widget.items.indexOf(d)) {
      final others = widget.items.where((x) => x.id != d.id).toList();
      if (at < others.length) {
        anchor = others[at];
      } else if (others.isNotEmpty) {
        anchor = others.last;
        before = false;
      }
    }
    setState(() {
      _drag = null;
      _insertAt = null;
      _vx = 0;
    });
    if (d == null) return;
    Sfx.play('drop');
    Buzz.light();
    if (anchor != null) {
      store.reorder(widget.col, d, anchor, before: before);
      toast(d.isDecor ? 'Decoration moved' : 'Book moved');
    }
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    final p = shelfPalettes[widget.palette % shelfPalettes.length];
    final exp = widget.exp;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        child: exp ? _expanded(p) : _row(p),
      ),
      if (!exp)
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _overflow ? _slider() : const SizedBox(width: double.infinity),
        ),
    ]);
  }

  Widget _row(List<Color> p) {
    final (slots, total) = _layout();
    final glassH = max(64.0, _h * .45);
    final raised = _drag?.id ?? _pressed;
    return LayoutBuilder(builder: (context, cons) {
      final vw = cons.maxWidth;
      final rowH = _h + 34;
      final normal = <Widget>[], top = <Widget>[];
      for (final (i, s) in slots.indexed) {
        (s.it.id == raised ? top : normal).add(_item(s, i, slots));
      }
      return Stack(clipBehavior: Clip.none, children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
            return false;
          },
          child: SingleChildScrollView(
            key: _viewKey,
            controller: _sc,
            scrollDirection: Axis.horizontal,
            physics: _drag != null ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
            child: SizedBox(
              key: _stackKey,
              width: max(total, vw),
              height: rowH,
              child: Stack(clipBehavior: Clip.none, children: [
                ...normal,
                // the glass band sits over the books' lower half but stays put while scrolling
                Positioned(
                  left: _sc.hasClients ? _sc.offset : 0,
                  width: vw,
                  bottom: 0,
                  height: glassH,
                  child: IgnorePointer(child: _Glass(p)),
                ),
                ...top,
              ]),
            ),
          ),
        ),
        if (widget.items.isEmpty)
          Positioned(
            left: 0,
            right: 0,
            top: 18,
            child: IgnorePointer(
              child: Text(
                widget.home ? 'Nothing here yet' : 'Empty shelf · tap ＋ to add a book',
                textAlign: TextAlign.center,
                style: nu(13, FontWeight.w700, C.muted),
              ),
            ),
          ),
        Positioned(left: 12, bottom: 13, right: widget.home ? 12 : 140, child: Align(alignment: Alignment.centerLeft, child: _slab(p))),
        if (!widget.home) Positioned(right: 12, bottom: 10, child: _acts()),
      ]);
    });
  }

  Widget _expanded(List<Color> p) {
    final w = _w, h = _h;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 8, 14),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final it in widget.items)
              _tappable(
                it,
                null,
                const [],
                it.isDecor
                    ? GadgetView(it.gadget!, w: w * .95, h: h * shelfGadgetFactor(it.gadget!), lit: it.lit)
                    : _Shadowed(child: BookCover(it, w: w, h: h)),
              ),
          ],
        ),
      ),
      Row(children: [
        Flexible(child: Padding(padding: const EdgeInsets.only(left: 8), child: _slab(p))),
        const SizedBox(width: 8),
        if (!widget.home) _acts(),
        const SizedBox(width: 8),
      ]),
    ]);
  }

  Widget _item(_Slot s, int i, List<_Slot> slots) {
    final it = s.it;
    final dragging = _drag?.id == it.id;
    final lifted = _pressed == it.id;
    var dx = 0.0;
    if (_pressed != null && !lifted) {
      if (i > 0 && slots[i - 1].it.id == _pressed) dx = 12;
      if (i < slots.length - 1 && slots[i + 1].it.id == _pressed) dx = -8;
    }
    final Matrix4 m;
    if (dragging) {
      m = Matrix4.identity()
        ..translateByDouble(0, -14, 0, 1)
        ..rotateZ(-3 * pi / 180)
        ..scaleByDouble(1.12, 1.12, 1, 1);
    } else if (lifted) {
      m = Matrix4.identity()
        ..translateByDouble(0, -16, 0, 1)
        ..rotateZ(-4 * pi / 180)
        ..scaleByDouble(1.1, 1.1, 1, 1);
    } else {
      m = Matrix4.identity()..translateByDouble(dx, 0, 0, 1);
    }
    final shadows = <BoxShadow>[
      if (!it.isDecor && dragging) const BoxShadow(color: Color.fromRGBO(0, 0, 0, .4), offset: Offset(0, 16), blurRadius: 26),
      if (!it.isDecor && lifted && !dragging) ...const [
        BoxShadow(color: Color.fromRGBO(40, 20, 5, .45), offset: Offset(0, 18), blurRadius: 22, spreadRadius: -6),
        BoxShadow(color: Color.fromRGBO(0, 0, 0, .2), offset: Offset(0, 4), blurRadius: 8),
      ],
      if (!it.isDecor && !lifted && !dragging) const BoxShadow(color: Color.fromRGBO(0, 0, 0, .28), offset: Offset(0, 2), blurRadius: 6),
    ];
    final dur = dragging ? Duration.zero : const Duration(milliseconds: 380);
    Widget face = it.isDecor
        ? GadgetView(it.gadget!, w: s.w, h: s.h, lit: it.lit)
        : AnimatedBuilder(
            animation: _shine,
            builder: (_, _) => BookCover(it, w: s.w, h: s.h, shine: lifted ? _shine.value : 0),
          );
    if (_fresh.contains(it.id)) {
      face = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 550),
        curve: springCurve,
        onEnd: () => _fresh.remove(it.id),
        builder: (_, t, c) => Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, -16 * (1 - t)),
            child: Transform.scale(scale: .75 + .25 * t, child: c),
          ),
        ),
        child: face,
      );
    }
    return AnimatedPositioned(
      key: ValueKey(it.id),
      duration: dur,
      curve: ease,
      left: dragging ? _dragX : s.x,
      bottom: 14,
      width: s.w,
      height: s.h,
      child: _tappable(
        it,
        s,
        slots,
        AnimatedContainer(
          duration: dur,
          curve: ease,
          transform: m,
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), boxShadow: shadows),
          child: face,
        ),
      ),
    );
  }

  Widget _tappable(Item it, _Slot? s, List<_Slot> slots, Widget child) {
    final label = it.isDecor ? '${gadgetName(it.gadget!)} decoration' : '${it.title} by ${it.author}';
    return Semantics(
      button: true,
      label: label,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            TapGestureRecognizer.new,
            (t) => t
              ..onTapDown = ((_) => _tapDown(it))
              ..onTapUp = ((_) => _tapUp(it))
              ..onTapCancel = (() {
                if (_pressed == it.id) setState(() => _pressed = null);
              }),
          ),
          if (_canDrag && s != null)
            LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 320)),
              (l) => l
                ..onLongPressStart = ((d) => _dragStart(it, s, d))
                ..onLongPressMoveUpdate = _dragMove
                ..onLongPressEnd = ((_) => _dragEnd())
                ..onLongPressCancel = (() {
                  if (_drag != null) _dragEnd();
                }),
            ),
        },
        child: child,
      ),
    );
  }

  Widget _slab(List<Color> p) {
    final c = widget.col;
    final n = widget.count;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 248, 236, .85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromRGBO(184, 105, 42, .25)),
        boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, .2), offset: Offset(0, 1), blurRadius: 3)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text('${c.emoji} ${c.name}${widget.sub ? ' · sub shelf' : ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(14, FontWeight.w800, lightPal.ink)),
        ),
        const SizedBox(width: 8),
        Container(width: 6, height: 6, decoration: BoxDecoration(color: p[3], shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('$n${widget.filtered ? '' : '/$shelfMax'} ${n == 1 ? 'book' : 'books'}', style: nu(12, FontWeight.w700, lightPal.muted)),
      ]),
    );
  }

  Widget _acts() {
    Widget b(String t, String label, VoidCallback? f, {double size = 20}) => Semantics(
          button: true,
          label: label,
          child: Pressable(
            onTap: f,
            scale: .88,
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(left: 6),
              decoration: const BoxDecoration(color: Color.fromRGBO(255, 255, 255, .8), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(t, style: nu(size, FontWeight.w700, lightPal.ink, 1)),
            ),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (!widget.sub && widget.onMore != null) b('⋯', 'Shelf options for ${widget.col.name}', widget.onMore, size: 22),
      b('+', 'Add a book to ${widget.col.name}', widget.onAdd),
      b('🪴', 'Add a decoration', widget.onDecor, size: 17),
    ]);
  }

  Widget _slider() {
    final max = _sc.hasClients ? _sc.position.maxScrollExtent : 1.0;
    final v = _sc.hasClients && max > 0 ? (_sc.offset / max).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 2, 30, 0),
      child: SizedBox(
        height: 28,
        child: SliderTheme(
          data: SliderThemeData(
            trackHeight: 6,
            activeTrackColor: C.track,
            inactiveTrackColor: C.track,
            thumbShape: const _PillThumb(),
            overlayShape: SliderComponentShape.noOverlay,
            trackShape: const RoundedRectSliderTrackShape(),
            padding: EdgeInsets.zero,
          ),
          child: Slider(
            value: v,
            onChanged: (x) => _sc.jumpTo(x * max),
            semanticFormatterCallback: (_) => 'Slide shelf left and right',
          ),
        ),
      ),
    );
  }
}

class _Glass extends StatelessWidget {
  final List<Color> p;
  const _Glass(this.p);
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(colors: [p[0], p[1], p[2]], stops: const [0, .55, 1]),
        ),
      );
}

class _Shadowed extends StatelessWidget {
  final Widget child;
  const _Shadowed({required this.child});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, .28), offset: Offset(0, 2), blurRadius: 6)],
        ),
        child: child,
      );
}

/// The 44x18 brown pill thumb from the mockup's range input.
class _PillThumb extends SliderComponentShape {
  const _PillThumb();
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(44, 18);

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: 44, height: 18), const Radius.circular(9));
    final c = context.canvas;
    c.drawRRect(r.shift(const Offset(0, 1)), Paint()..color = const Color.fromRGBO(0, 0, 0, .3)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    c.drawRRect(r, Paint()..color = C.brown);
  }
}

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../art.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/book_cover.dart';
import '../widgets/common.dart';

Route<void> tourRoute() => PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (_, _, _) => const Tour(replay: true),
      transitionsBuilder: (_, a, _, c) => FadeTransition(opacity: a, child: c),
    );

class _Step {
  final String title, body;
  final List<String> tips;
  final Color panel;
  final Widget Function() art;
  const _Step(this.title, this.body, this.tips, this.panel, this.art);
}

/// A swipeable tour of everything Shelfwise can do, shown once after the intro.
class Tour extends StatefulWidget {
  final bool replay;
  const Tour({super.key, this.replay = false});
  @override
  State<Tour> createState() => _TourState();
}

class _TourState extends State<Tour> {
  final _pc = PageController();
  int _i = 0;

  late final List<_Step> _steps = [
    _Step('Cozy shelves', 'Your books stand on shelves just like at home. Tap one to open it, or press and hold to drag it to a new spot. A full shelf grows a sub shelf.',
        ['Long-press to reorder', '🪴 Decorations you can play with', 'Slide across to tear out'], const Color(0xFFF5ECDF), () => const _ShelfArt()),
    _Step('Read your own copy', 'Attach a PDF when you add a book. Drag a corner and the page curls over like paper. Pinch or double-tap to zoom, and Shelfwise remembers your page.',
        ['📎 Attach a PDF', '📖 Continue where you stopped', '🔍 Swipe pages while zoomed'], const Color(0xFF1D4A37), () => const _ReadArt()),
    _Step('Reading to-dos', 'Plan the reading life: “finish chapter 12 tonight”, “return Rebecca”. Add due times, stars, hashtags and a linked book. Ticking them off unlocks rewards.',
        ['⏰ Reminders', '⭐ Star the important ones', '🎁 Rewards for milestones'], const Color(0xFFF6B300), () => const _TodoArt()),
    _Step('Stats & Rewind', 'Watch your month, year or all-time reading fill up. Play your Rewind, a story-style recap, then share it or save it as an image.',
        ['📊 Books by month', '🎞️ Rewind story', '📤 Share your stats'], const Color(0xFF1C1C1C), () => const _StatsArt()),
    _Step('Make it yours', 'Light, dark or follow your phone. Pick an accent colour, a font you love and a comfortable text size in Settings.',
        ['🌙 Dark mode', '🎨 Five accents', 'Aa Three fonts'], const Color(0xFFB6D8D5), () => const _ThemeArt()),
    _Step('Private by design', 'No account, no ads, everything stays on this phone. Use Settings → Share backup to keep a copy safe, and Import backup on a new phone.',
        ['🔒 Stays on your phone', '📤 Share backup', '📥 Import backup'], const Color(0xFFFF4F0F), () => const _BackupArt()),
  ];

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _finish() {
    Sfx.play('reset');
    if (widget.replay) {
      Navigator.of(context).pop();
      return;
    }
    store.toured = true;
    store.changed();
  }

  void _next() {
    Buzz.tick();
    if (_i == _steps.length - 1) return _finish();
    _pc.nextPage(duration: const Duration(milliseconds: 420), curve: ease);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final last = _i == _steps.length - 1;
    return Scaffold(
      backgroundColor: C.bg,
      body: Padding(
        padding: EdgeInsets.only(top: mq.padding.top, bottom: mq.padding.bottom),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 10, 0),
            child: Row(children: [
              const SizedBox(width: 2),
              SvgPicture.string(owlSvg, width: 34, height: 31),
              const SizedBox(width: 8),
              Text('What you can do', style: nu(14, FontWeight.w800, C.muted)),
              const Spacer(),
              AnimatedOpacity(
                opacity: last ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: TextButton(
                  onPressed: last ? null : _finish,
                  style: TextButton.styleFrom(foregroundColor: C.brown),
                  child: Text('Skip', style: nu(15, FontWeight.w800, C.brown)),
                ),
              ),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: _steps.length,
              onPageChanged: (i) {
                setState(() => _i = i);
                Sfx.play('swoosh');
              },
              itemBuilder: (_, i) => AnimatedBuilder(
                animation: _pc,
                builder: (_, _) {
                  final page = _pc.hasClients && _pc.position.haveDimensions ? _pc.page ?? 0 : 0.0;
                  return _page(_steps[i], (i - page).toDouble());
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 6, 26, 18),
            child: Row(children: [
              for (var k = 0; k < _steps.length; k++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: ease,
                  width: k == _i ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(color: k == _i ? C.brown : C.track, borderRadius: BorderRadius.circular(4)),
                ),
              const Spacer(),
              Pressable(
                onTap: _next,
                scale: .95,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: ease,
                  height: 54,
                  padding: EdgeInsets.symmetric(horizontal: last ? 26 : 22),
                  decoration: BoxDecoration(color: C.black, borderRadius: BorderRadius.circular(6)),
                  alignment: Alignment.center,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(last ? (widget.replay ? 'Done' : 'Start reading') : 'Next',
                          key: ValueKey(last),
                          style: const TextStyle(fontFamily: F.hand, fontWeight: FontWeight.w500, fontSize: 25, color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    const Text('⟶', style: TextStyle(fontSize: 20, color: C.orange)),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _page(_Step s, double off) {
    final fade = (1 - off.abs()).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, c) {
      final artH = min(c.maxHeight * .56, 380.0);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Transform.translate(
            offset: Offset(off * -60, 0),
            child: Transform.scale(
              scale: .92 + .08 * fade,
              child: Container(
                height: artH,
                width: double.infinity,
                decoration: BoxDecoration(color: s.panel, borderRadius: BorderRadius.circular(28)),
                clipBehavior: Clip.antiAlias,
                child: s.art(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Opacity(
            opacity: fade,
            child: Transform.translate(
              offset: Offset(off * 40, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.title, style: TextStyle(fontFamily: F.serif, fontWeight: FontWeight.w800, fontSize: 30, color: C.ink, height: 1.1)),
                const SizedBox(height: 10),
                Text(s.body, style: nu(15.5, FontWeight.w600, C.body, 1.45)),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final t in s.tips)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(16)),
                      child: Text(t, style: nu(13, FontWeight.w800, C.chipText)),
                    ),
                ]),
              ]),
            ),
          ),
        ]),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Looping illustrations
// ---------------------------------------------------------------------------

/// Gives an illustration a repeating 0..1 clock.
abstract class _Loop extends StatefulWidget {
  final int ms;
  const _Loop(this.ms);
  Widget draw(BuildContext context, double t);
  @override
  State<_Loop> createState() => _LoopState();
}

class _LoopState extends State<_Loop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.ms))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (context, _) => widget.draw(context, _c.value));
}

double _seg(double t, double a, double b, [Curve c = Curves.easeInOut]) => c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

class _ShelfArt extends _Loop {
  const _ShelfArt() : super(3200);
  static final _books = [
    Item(title: 'Pride and Prejudice', author: 'Jane Austen'),
    Item(title: 'The Hobbit', author: 'Tolkien'),
    Item(title: 'Circe', author: 'Madeline Miller'),
    Item(title: 'Dune', author: 'Frank Herbert'),
    Item(title: 'Rebecca', author: 'du Maurier'),
  ];
  @override
  Widget draw(BuildContext context, double t) {
    final lift = _seg(t, .1, .3) - _seg(t, .45, .65);
    final lit = t > .55 && t < .95;
    return LayoutBuilder(builder: (_, c) {
      const w = 64.0, h = 92.0;
      final left = (c.maxWidth - (w * 5 * .72 + w * .28 + 70)) / 2;
      final base = c.maxHeight * .72;
      return Stack(clipBehavior: Clip.none, children: [
        for (final (i, b) in _books.indexed)
          if (i != 2) _book(b, left + i * w * .72, base - h, w, h, 0),
        Positioned(
          left: left + 5 * w * .72 + 6,
          top: base - h * .85,
          child: GadgetView('lamp', w: 60, h: h * .85, lit: lit),
        ),
        Positioned(
          left: 18,
          right: 18,
          top: base - 46,
          height: 58,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(colors: [shelfPalettes[0][0], shelfPalettes[0][1], shelfPalettes[0][2]], stops: const [0, .55, 1]),
            ),
          ),
        ),
        _book(_books[2], left + 2 * w * .72, base - h, w, h, lift),
        Positioned(
          left: 30,
          top: base - 32,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: const Color(0xD9FFF8EC), borderRadius: BorderRadius.circular(10)),
            child: Text('📖 Reading now · 5/10', style: nu(11, FontWeight.w800, lightPal.ink)),
          ),
        ),
        Positioned(
          left: left + 2 * w * .72 + w * .5 - 14,
          top: base + 22,
          child: Opacity(opacity: lift, child: const Text('👆', style: TextStyle(fontSize: 26))),
        ),
      ]);
    });
  }

  Widget _book(Item b, double x, double y, double w, double h, double lift) => Positioned(
        left: x,
        top: y,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(0, -16 * lift, 0, 1)
            ..rotateZ(-4 * pi / 180 * lift)
            ..scaleByDouble(1 + .1 * lift, 1 + .1 * lift, 1, 1),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              boxShadow: [BoxShadow(color: Color.fromRGBO(0, 0, 0, .25 + .2 * lift), offset: Offset(0, 2 + 12 * lift), blurRadius: 6 + 14 * lift)],
            ),
            child: BookCover(b, w: w, h: h, titleSize: 9, authorSize: 6.5, shine: lift > 0 && lift < 1 ? lift : 0),
          ),
        ),
      );
}

class _ReadArt extends _Loop {
  const _ReadArt() : super(2600);
  @override
  Widget draw(BuildContext context, double t) {
    final a = _seg(t, .15, .55) * (1 - _seg(t, .7, .95));
    return Center(
      child: SizedBox(width: 170, height: 220, child: CustomPaint(painter: _CurlPainter(a))),
    );
  }
}

class _CurlPainter extends CustomPainter {
  final double a;
  _CurlPainter(this.a);
  @override
  void paint(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRRect(RRect.fromRectAndRadius(r.shift(const Offset(0, 6)), const Radius.circular(4)),
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    // page underneath peeks out where the corner lifts
    c.drawRect(r, Paint()..color = const Color(0xFFF7F1E6));
    final f = 18 + a * 110; // fold size
    final page = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width, s.height - f)
      ..lineTo(s.width - f, s.height)
      ..lineTo(0, s.height)
      ..close();
    c.drawPath(page, Paint()..color = const Color(0xFFFFFDF7));
    final line = Paint()..color = const Color(0xFFD9CDBB);
    c.drawRRect(RRect.fromLTRBR(20, 24, s.width * .62, 34, const Radius.circular(3)), Paint()..color = const Color(0xFF3A2A1C));
    for (var i = 0; i < 11; i++) {
      final y = 50.0 + i * 14;
      final right = min(s.width - 20, s.width - 20 - max(0, y - (s.height - f - 30)));
      if (right > 30) c.drawRRect(RRect.fromLTRBR(20, y, i % 4 == 3 ? right * .6 : right, y + 5, const Radius.circular(2)), line);
    }
    // the curled-back flap
    final flap = Path()
      ..moveTo(s.width, s.height - f)
      ..lineTo(s.width - f, s.height)
      ..lineTo(s.width - f * 1.05, s.height - f * 1.05)
      ..close();
    c.drawShadow(flap, Colors.black, 4, false);
    c.drawPath(
      flap,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomRight,
          end: Alignment.topLeft,
          colors: const [Color(0xFFD8D0C2), Color(0xFFFBF7EE)],
        ).createShader(Rect.fromLTWH(s.width - f * 1.05, s.height - f * 1.05, f * 1.05, f * 1.05)),
    );
    // bookmark ribbon
    c.drawPath(
      Path()
        ..moveTo(s.width - 34, 0)
        ..lineTo(s.width - 22, 0)
        ..lineTo(s.width - 22, 30)
        ..lineTo(s.width - 28, 25)
        ..lineTo(s.width - 34, 30)
        ..close(),
      Paint()..color = C.orange,
    );
  }

  @override
  bool shouldRepaint(_CurlPainter o) => o.a != a;
}

class _TodoArt extends _Loop {
  const _TodoArt() : super(2800);
  @override
  Widget draw(BuildContext context, double t) {
    final check = _seg(t, .2, .35, popCurve);
    final star = _seg(t, .5, .62, popCurve);
    Widget tile(Color bg, Color fg, double w, double h, {bool big = false, double done = 0, double starred = 0}) => Container(
          width: w,
          height: h,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: w * .5, height: big ? 10 : 7, decoration: BoxDecoration(color: fg.withValues(alpha: .85), borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 6),
            Container(width: w * .7, height: big ? 10 : 7, decoration: BoxDecoration(color: fg.withValues(alpha: .85), borderRadius: BorderRadius.circular(4))),
            const Spacer(),
            Row(children: [
              Transform.scale(
                scale: 1 + .3 * sin(done * pi),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done > .5 ? const Color(0xFF5FBF9A) : Colors.transparent,
                    border: Border.all(color: done > .5 ? const Color(0xFF5FBF9A) : fg, width: 2),
                  ),
                  child: done > .5 ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
                ),
              ),
              const SizedBox(width: 8),
              Transform.scale(
                scale: 1 + .3 * sin(starred * pi),
                child: Icon(starred > .5 ? Icons.star_rounded : Icons.star_border_rounded, size: 22, color: fg),
              ),
            ]),
          ]),
        );
    return LayoutBuilder(builder: (_, c) {
      final w = c.maxWidth - 40;
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Stack(clipBehavior: Clip.none, children: [
          Column(children: [
            tile(const Color(0xFFFF4F0F), const Color(0xFF111111), w, c.maxHeight * .44, big: true, done: check),
            const SizedBox(height: 10),
            Row(children: [
              tile(const Color(0xFFF5ECDF), const Color(0xFF111111), (w - 10) / 2, c.maxHeight * .34, starred: star),
              const SizedBox(width: 10),
              tile(const Color(0xFF1D4A37), Colors.white, (w - 10) / 2, c.maxHeight * .34),
            ]),
          ]),
          for (var i = 0; i < 10; i++)
            Positioned(
              left: 18 + cos(i * .63) * 70 * check + 4,
              top: c.maxHeight * .44 - 50 - sin(i * .63).abs() * 60 * check + 40 * check * check,
              child: Opacity(
                opacity: (check * (1 - _seg(t, .45, .6))).clamp(0, 1),
                child: Container(width: 6, height: 8, color: const [Color(0xFFB8692A), Color(0xFF5FBF9A), Color(0xFFB58BE0), Color(0xFFF6B300)][i % 4]),
              ),
            ),
        ]),
      );
    });
  }
}

class _StatsArt extends _Loop {
  const _StatsArt() : super(3400);
  @override
  Widget draw(BuildContext context, double t) {
    const vals = [.45, .6, .52, .85, .75, 1.0];
    final card = _seg(t, .5, .68, Curves.easeOutBack) * (1 - _seg(t, .92, 1));
    return LayoutBuilder(builder: (_, c) {
      final h = c.maxHeight * .5;
      return Stack(children: [
        Positioned(
          left: 24,
          bottom: 30,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final (i, v) in vals.indexed)
              Container(
                width: 22,
                height: max(4, h * v * _seg(t, i * .05, .3 + i * .05, Curves.easeOutBack)),
                margin: const EdgeInsets.only(right: 9),
                decoration: BoxDecoration(color: i == 3 ? C.orange : const Color(0xFFB8692A), borderRadius: BorderRadius.circular(6)),
              ),
          ]),
        ),
        Positioned(
          right: 22 - (1 - card) * 200,
          top: 26,
          bottom: 26,
          child: Transform.rotate(
            angle: .06 * (1 - card),
            child: Container(
              width: 120,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF4F0F),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Color(0x66000000), offset: Offset(0, 8), blurRadius: 16)],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  for (var k = 0; k < 4; k++)
                    Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.only(right: 3),
                        color: k <= (t * 8).floor() % 4 ? const Color(0xFF111111) : const Color(0x55111111),
                      ),
                    ),
                ]),
                const Spacer(),
                Text('You finished', style: nu(11, FontWeight.w800, const Color(0xFF111111))),
                const Text('49', style: TextStyle(fontFamily: F.serif, fontWeight: FontWeight.w800, fontSize: 46, color: Color(0xFF111111), height: 1.05, fontFeatures: [FontFeature.liningFigures()])),
                Text('books', style: nu(12, FontWeight.w800, const Color(0xFF111111))),
                const Spacer(),
              ]),
            ),
          ),
        ),
      ]);
    });
  }
}

class _ThemeArt extends _Loop {
  const _ThemeArt() : super(4800);
  @override
  Widget draw(BuildContext context, double t) {
    final dark = t > .5;
    final accent = accents[(t * 10).floor() % accents.length].color;
    final fonts = [F.nunito, F.sans, F.lora];
    final font = fonts[(t * 6).floor() % 3];
    final p = dark ? darkPal : lightPal;
    Widget phone() => AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          width: 130,
          height: 210,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.bg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF111111), width: 4),
            boxShadow: const [BoxShadow(color: Color(0x55000000), offset: Offset(0, 10), blurRadius: 18)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Aa', style: TextStyle(fontFamily: font, fontWeight: FontWeight.w800, fontSize: 30, color: p.ink)),
            const SizedBox(height: 6),
            for (final w in [.9, .7, .8])
              Container(
                height: 7,
                width: 100 * w,
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(4)),
              ),
            const Spacer(),
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              height: 26,
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(13)),
            ),
          ]),
        );
    return Center(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        phone(),
        const SizedBox(width: 18),
        Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 56,
            height: 30,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: dark ? const Color(0xFF3A2D20) : Colors.white, borderRadius: BorderRadius.circular(15)),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 400),
              curve: ease,
              alignment: dark ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(color: dark ? const Color(0xFFF2B84B) : C.orange, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(dark ? '🌙' : '☀️', style: const TextStyle(fontSize: 12)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final a in accents)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: a.color == accent ? 26 : 18,
              height: a.color == accent ? 26 : 18,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: a.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: a.color == accent ? 3 : 0),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _BackupArt extends _Loop {
  const _BackupArt() : super(2400);
  @override
  Widget draw(BuildContext context, double t) {
    Widget node(IconData i, String l) => Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(18)),
            alignment: Alignment.center,
            child: Icon(i, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 6),
          Text(l, style: nu(11.5, FontWeight.w800, const Color(0xFF111111))),
        ]);
    return LayoutBuilder(builder: (_, c) {
      final w = c.maxWidth;
      final x = 40 + (w - 80) * Curves.easeInOut.transform(t);
      final lineY = c.maxHeight * .42 - 41; // through the middle of the icons
      return Stack(children: [
        Positioned(
          left: 34,
          right: 34,
          top: lineY,
          child: CustomPaint(size: Size(w - 68, 2), painter: _Dash()),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: c.maxHeight * .42 - 70,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            node(Icons.smartphone_rounded, 'This phone'),
            node(Icons.cloud_upload_rounded, 'Drive / chat'),
            node(Icons.phone_android_rounded, 'New phone'),
          ]),
        ),
        Positioned(
          left: x - 13,
          top: lineY - 16,
          child: Transform.rotate(angle: sin(t * pi * 4) * .1, child: const Text('📄', style: TextStyle(fontSize: 26))),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 26,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(20)),
              child: Text('🔒 No account · no ads · offline', style: nu(13, FontWeight.w800, Colors.white)),
            ),
          ),
        ),
      ]);
    });
  }
}

class _Dash extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (double x = 0; x < s.width; x += 12) {
      c.drawLine(Offset(x, 0), Offset(x + 5, 0), p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

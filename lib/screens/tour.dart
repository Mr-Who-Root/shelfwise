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
  final String pointerLabel;
  final bool pointsUp;
  const _Step(
    this.title,
    this.body,
    this.tips,
    this.panel,
    this.art, {
    required this.pointerLabel,
    this.pointsUp = false,
  });
}

class _AnimatedArrowPointer extends StatefulWidget {
  final String label;
  final bool pointsUp;
  const _AnimatedArrowPointer({required this.label, this.pointsUp = false});
  @override
  State<_AnimatedArrowPointer> createState() => _AnimatedArrowPointerState();
}

class _AnimatedArrowPointerState extends State<_AnimatedArrowPointer> with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, child) {
        final dy = (widget.pointsUp ? -1.0 : 1.0) * (_ac.value * 7);
        return Transform.translate(
          offset: Offset(0, dy),
          child: child,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: C.orange,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: C.orange.withValues(alpha: .38),
              blurRadius: 10,
              offset: Offset(0, widget.pointsUp ? -2 : 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.pointsUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: const TextStyle(
                fontFamily: F.sans,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: .2,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
    _Step(
      'Share & Notifications',
      'At the top right of your sanctuary, tap the Share icon near the notification bell to share your cozy bookshelves with friends. Tap the bell to see due to-dos, alerts, and reading rewards.',
      ['📤 Share icon near bell', '🔔 Due notifications', '🎁 Reading rewards'],
      const Color(0xFF1D4A37),
      () => const _ShareHeaderArt(),
      pointerLabel: 'Section 1: Top Bar & Share',
      pointsUp: true,
    ),
    _Step(
      'Cozy Shelves & One Bookmark',
      'Your books sit on wooden shelves just like at home. Open any book to read with page-curl animations. Each book keeps exactly one bookmark so you never lose your place. Once a book is finished, it clears from "Continue Reading" automatically.',
      ['🔖 1 bookmark per book', '✅ Finished clears continue reading', '📖 PDF & EPUB reader'],
      const Color(0xFFF5ECDF),
      () => const _ShelfArt(),
      pointerLabel: 'Section 2: Bookshelves & Bookmarks',
      pointsUp: false,
    ),
    _Step(
      'Shelf Styles, Stickers & Pets',
      'Personalize your sanctuary! Choose from 4 rich wood styles (Oak, Walnut, Pine, Rosewood), place movable stickers anywhere across your shelves, and play with cute pets that jump across platforms with sound effects.',
      ['🪵 4 wood finishes', '🪴 Movable stickers', '🐾 Playful pets with sounds'],
      const Color(0xFFB6D8D5),
      () => const _ShelvesAndPetsArt(),
      pointerLabel: 'Section 3: Styles, Stickers & Pets',
      pointsUp: false,
    ),
    _Step(
      'Double-Tap Navigation',
      'The bottom navigation features a single, sleek button. On the first page only the Home button is shown. Double-tap the "Home" button to switch directly to your full "Library". Double-tap "Library" to return Home.',
      ['✨ Single sleek button', '👆👆 Double-tap to toggle', '📚 Home ⇄ Library'],
      const Color(0xFF1C1C1C),
      () => const _DoubleTapNavArt(),
      pointerLabel: 'Section 4: Navigation Toggle',
      pointsUp: false,
    ),
    _Step(
      'Reading To-Dos & Smart Alerts',
      'Plan your reading schedule with to-dos. If a to-do is due today or starting soon, you get mobile notifications and a 1-hour start popup with OK and Skip buttons. Completing tasks unlocks milestone badges.',
      ['⏰ 1-hour start popups', '⭐ Star & prioritize', '🏆 Milestone badges'],
      const Color(0xFFF6B300),
      () => const _TodoArt(),
      pointerLabel: 'Section 5: Reading To-Dos & Alerts',
      pointsUp: false,
    ),
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
            padding: const EdgeInsets.fromLTRB(22, 10, 16, 4),
            child: Row(children: [
              const SizedBox(width: 2),
              SvgPicture.string(owlSvg, width: 34, height: 31),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Shelfwise Walkthrough', style: nu(15, FontWeight.w800, C.ink)),
                  Text('Section ${_i + 1} of ${_steps.length}', style: nu(12, FontWeight.w600, C.muted)),
                ],
              ),
              const Spacer(),
              Pressable(
                onTap: _finish,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: C.brown.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: C.brown.withValues(alpha: .28), width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Skip', style: nu(14, FontWeight.w800, C.brown)),
                      const SizedBox(width: 4),
                      const Icon(Icons.fast_forward_rounded, size: 16, color: C.brown),
                    ],
                  ),
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
                  decoration: BoxDecoration(color: C.dark ? C.brown : C.black, borderRadius: BorderRadius.circular(6)),
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
      final artH = min(c.maxHeight * .52, 360.0);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: _AnimatedArrowPointer(
              label: s.pointerLabel,
              pointsUp: s.pointsUp,
            ),
          ),
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
          const SizedBox(height: 20),
          Opacity(
            opacity: fade,
            child: Transform.translate(
              offset: Offset(off * 40, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.title, style: TextStyle(fontFamily: F.serif, fontWeight: FontWeight.w800, fontSize: 28, color: C.ink, height: 1.1)),
                const SizedBox(height: 8),
                Text(s.body, style: nu(15, FontWeight.w600, C.body, 1.45)),
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

class _ShareHeaderArt extends _Loop {
  const _ShareHeaderArt() : super(3000);
  @override
  Widget draw(BuildContext context, double t) {
    final pop = _seg(t, .2, .45, Curves.easeOutBack);
    final flash = (sin(t * pi * 4) * .5 + .5);
    return LayoutBuilder(builder: (_, c) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF235540),
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Rajkumar’s Sanctuary', style: nu(15, FontWeight.w800, Colors.white)),
                        Text('12 books on cozy shelves', style: nu(12, FontWeight.w600, const Color(0xFFB0D5C5))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: C.orange,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(color: C.orange.withValues(alpha: .4 * flash), blurRadius: 8, spreadRadius: 2),
                      ],
                    ),
                    child: SvgPicture.string(Ic.share, width: 17, height: 17, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E6B52),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SvgPicture.string(Ic.bell, width: 17, height: 17, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Transform.scale(
              scale: pop,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 6))],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.share_rounded, size: 20, color: C.orange),
                        const SizedBox(width: 8),
                        Text('Share your bookshelf!', style: nu(14, FontWeight.w800, C.ink)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap the Share icon near the bell to invite friends to see your reading sanctuary & books.',
                      textAlign: TextAlign.center,
                      style: nu(12.5, FontWeight.w600, C.muted, 1.3),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      );
    });
  }
}

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
          left: left + 2 * w * .72 + w * .5 - 8,
          top: base - h - 16 * lift - 12,
          child: Opacity(opacity: lift, child: const Text('🔖', style: TextStyle(fontSize: 18))),
        ),
        Positioned(
          left: 20,
          right: 20,
          top: base - 34,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: const Color(0xD9FFF8EC), borderRadius: BorderRadius.circular(10)),
            child: Text('🔖 1 Bookmark per book · Finished clears continue reading', textAlign: TextAlign.center, style: nu(10.5, FontWeight.w800, lightPal.ink)),
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

class _ShelvesAndPetsArt extends _Loop {
  const _ShelvesAndPetsArt() : super(2800);
  @override
  Widget draw(BuildContext context, double t) {
    final petX = (sin(t * pi * 2) * .5 + .5);
    final petJump = (sin(t * pi * 4).abs() * 20);
    return LayoutBuilder(builder: (_, c) {
      final base = c.maxHeight * .68;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 20,
            right: 20,
            top: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final (i, name) in ['Oak', 'Walnut', 'Pine', 'Rosewood'].indexed)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 24,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: LinearGradient(
                            colors: [shelfPalettes[i % shelfPalettes.length][0], shelfPalettes[i % shelfPalettes.length][1]],
                          ),
                          border: Border.all(color: Colors.white.withValues(alpha: .6), width: 1.5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(name, style: nu(10.5, FontWeight.w800, const Color(0xFF1E3A36))),
                    ],
                  ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            top: base,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(colors: [shelfPalettes[1][0], shelfPalettes[1][1], shelfPalettes[1][2]]),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 6))],
              ),
            ),
          ),
          Positioned(
            left: 36,
            top: base - 44,
            child: const Text('🪴', style: TextStyle(fontSize: 34)),
          ),
          Positioned(
            right: 40,
            top: base - 56,
            child: Row(
              children: [
                Container(width: 14, height: 56, decoration: BoxDecoration(color: const Color(0xFF9E472A), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 4),
                Container(width: 16, height: 62, decoration: BoxDecoration(color: const Color(0xFF2F5233), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 4),
                Container(width: 13, height: 50, decoration: BoxDecoration(color: const Color(0xFFD4A373), borderRadius: BorderRadius.circular(3))),
              ],
            ),
          ),
          Positioned(
            left: 90 + petX * 70,
            top: base - 38 - petJump,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🎵', style: TextStyle(fontSize: 12 + petJump * .2)),
                    const SizedBox(width: 4),
                    const Text('🐾', style: TextStyle(fontSize: 10)),
                  ],
                ),
                Text(petX > .5 ? '🐱' : '🐶', style: const TextStyle(fontSize: 34)),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('🐾 Adopt pets · Move stickers · Pick shelf woods', style: nu(11.5, FontWeight.w800, const Color(0xFF1E3A36))),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _DoubleTapNavArt extends _Loop {
  const _DoubleTapNavArt() : super(3200);
  @override
  Widget draw(BuildContext context, double t) {
    final isLibrary = t > .5;
    final tapPop = (sin(t * pi * 4).abs() * .2);
    return LayoutBuilder(builder: (_, c) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '👆👆 Double-tap to toggle',
                style: nu(14, FontWeight.w800, Colors.white),
              ),
            ),
            const SizedBox(height: 24),
            Transform.scale(
              scale: 1.0 + tapPop,
              child: Container(
                width: 170,
                height: 56,
                decoration: BoxDecoration(
                  color: isLibrary ? const Color(0xFF1D4A37) : const Color(0xFFFF5200),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: (isLibrary ? const Color(0xFF1D4A37) : const Color(0xFFFF5200)).withValues(alpha: .5),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(isLibrary ? '📚' : '🏠', style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 8),
                    Text(
                      isLibrary ? 'Library' : 'Home',
                      style: const TextStyle(fontFamily: F.hand, fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x22FFFFFF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                isLibrary ? 'Showing: Full Library Shelves' : 'Showing: Cozy Home Sanctuary',
                style: nu(12.5, FontWeight.w600, const Color(0xFFDDD0BA)),
              ),
            ),
          ],
        ),
      );
    });
  }
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
          Positioned(
            left: 0,
            right: 0,
            bottom: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
              ),
              child: Row(
                children: [
                  const Text('⏰', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Rebecca starts in 1 hr', style: nu(11, FontWeight.w800, C.ink)),
                        Text('Pop-up alert reminder', style: nu(9.5, FontWeight.w600, C.muted)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFEFE8DD), borderRadius: BorderRadius.circular(6)),
                    child: Text('OK', style: nu(10, FontWeight.w800, C.ink)),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFEFE8DD), borderRadius: BorderRadius.circular(6)),
                    child: Text('Skip', style: nu(10, FontWeight.w800, C.muted)),
                  ),
                ],
              ),
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

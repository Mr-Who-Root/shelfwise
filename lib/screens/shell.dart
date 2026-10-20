import 'package:flutter/material.dart';

import '../data/store.dart';
import '../icons.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pet_overlay.dart';
import 'library_screen.dart';
import 'onboarding.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'todo_screen.dart';

/// Main app frame: one page at a time plus the frosted bottom nav.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0; // 0 home, 1 library, 2 to-do, 3 stats, 4 settings, 5 profile

  void go(int t) {
    dropFocus();
    if (t == 0) {
      LibUi.f = 'all';
      LibUi.q = '';
      LibUi.exp = false;
    }
    setState(() => _tab = t);
  }


  Widget _page() => switch (_tab) {
        0 => LibraryScreen(key: const ValueKey('home'), home: true, onProfile: () => go(5), onTodo: () => go(2), onStats: () => go(3)),
        1 => LibraryScreen(key: const ValueKey('lib'), home: false, onProfile: () => go(5), onTodo: () => go(2), onStats: () => go(3)),
        2 => const TodoScreen(key: ValueKey('todo')),
        3 => const StatsScreen(key: ValueKey('stats')),
        4 => SettingsScreen(key: const ValueKey('settings'), onProfile: () => go(5), onReplay: () => Navigator.of(context).push(introRoute())),
        _ => ProfileScreen(key: const ValueKey('profile'), go: go),
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) go(0);
      },
      child: Scaffold(
        backgroundColor: C.bg,
        resizeToAvoidBottomInset: false,
        body: Stack(children: [
          if (store.settings.pattern != 'none')
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(painter: PatternPainter(store.settings.pattern, C.ink.withValues(alpha: C.dark ? .07 : .06))),
                ),
              ),
            ),
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: ease,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, .018), end: Offset.zero).animate(a),
                  child: child,
                ),
              ),
              child: _page(),
            ),
          ),
          Positioned.fill(
            child: PetOverlay(tab: _tab),
          ),
          Positioned(left: 0, right: 0, top: 0, height: MediaQuery.paddingOf(context).top, child: ColoredBox(color: C.bg.withValues(alpha: .95))),
          Positioned(left: 0, right: 0, bottom: 0, child: _NavBar(tab: _tab, onTab: go)),
        ]),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onTab;
  const _NavBar({required this.tab, required this.onTab});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: blur(10),
        child: Container(
          padding: EdgeInsets.fromLTRB(8, 8, 8, 12 + bottom),
          decoration: BoxDecoration(
            color: C.nav,
            border: Border(top: BorderSide(color: Color(0x0D000000))),
          ),
          child: ListenableBuilder(
            listenable: store,
            builder: (_, _) => Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _HomeLibSlider(tab: tab, onTab: onTab),
              _NavBtn(Ic.todo, 'To-do', tab == 2, () => onTab(2), dot: store.dueTodos.isNotEmpty),
              _NavBtn(Ic.stats, 'Stats', tab == 3, () => onTab(3)),
              _NavBtn(Ic.settings, 'Settings', tab >= 4, () => onTab(4)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _HomeLibSlider extends StatefulWidget {
  final int tab;
  final ValueChanged<int> onTab;
  const _HomeLibSlider({required this.tab, required this.onTab});

  @override
  State<_HomeLibSlider> createState() => _HomeLibSliderState();
}

class _HomeLibSliderState extends State<_HomeLibSlider> {
  double _dragOffset = 0;

  void _switchTo(int t) {
    if (widget.tab != t) {
      Buzz.tick();
      Sfx.play('tap');
      widget.onTab(t);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHome = widget.tab == 0;
    final isLib = widget.tab == 1;
    final isSelected = isHome || isLib;

    return Semantics(
      button: true,
      label: isLib ? 'Library (Slide right for Home)' : 'Home (Slide left for Library)',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _dragOffset = 0,
        onHorizontalDragUpdate: (details) {
          _dragOffset += details.primaryDelta ?? 0;
          if (_dragOffset < -24) {
            _switchTo(1);
            _dragOffset = 0;
          } else if (_dragOffset > 24) {
            _switchTo(0);
            _dragOffset = 0;
          }
        },
        onHorizontalDragEnd: (details) {
          final vx = details.primaryVelocity ?? 0;
          if (vx < -150) {
            _switchTo(1);
          } else if (vx > 150) {
            _switchTo(0);
          }
          _dragOffset = 0;
        },
        onTap: () {
          _switchTo(isHome ? 1 : 0);
        },
        child: Container(
          width: 122,
          height: 52,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isSelected ? C.card : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: isSelected ? C.brown.withValues(alpha: .28) : C.line.withValues(alpha: .5),
              width: 1.2,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color.fromRGBO(0, 0, 0, .05),
                      offset: const Offset(0, 2),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 240),
                curve: ease,
                alignment: isLib ? Alignment.centerRight : Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.52,
                  heightFactor: 1.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? C.brown : const Color.fromRGBO(184, 105, 42, .14),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: C.brown.withValues(alpha: .3),
                                offset: const Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _switchTo(0),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SvgIcon(
                              Ic.home,
                              color: isHome
                                  ? Colors.white
                                  : (isSelected ? C.ink.withValues(alpha: .7) : C.ink),
                              size: 19,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'Home',
                              style: nu(
                                10,
                                FontWeight.w700,
                                isHome
                                    ? Colors.white
                                    : (isSelected ? C.ink.withValues(alpha: .7) : C.ink),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _switchTo(1),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SvgIcon(
                              Ic.library,
                              color: isLib
                                  ? Colors.white
                                  : (isSelected ? C.ink.withValues(alpha: .7) : C.ink),
                              size: 19,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'Library',
                              style: nu(
                                10,
                                FontWeight.w700,
                                isLib
                                    ? Colors.white
                                    : (isSelected ? C.ink.withValues(alpha: .7) : C.ink),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBtn extends StatefulWidget {
  final String icon, label;
  final bool on, dot;
  final VoidCallback onTap;
  const _NavBtn(this.icon, this.label, this.on, this.onTap, {this.dot = false});
  @override
  State<_NavBtn> createState() => _NavBtnState();
}

class _NavBtnState extends State<_NavBtn> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final color = widget.on ? C.brown : C.ink;
    return Semantics(
      button: true,
      selected: widget.on,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          Buzz.tick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? .92 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: ease,
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: widget.on ? const Color.fromRGBO(184, 105, 42, .14) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Stack(clipBehavior: Clip.none, children: [
                TweenAnimationBuilder<double>(
                  key: ValueKey(widget.on),
                  tween: Tween(begin: widget.on ? .8 : 1, end: 1),
                  duration: const Duration(milliseconds: 380),
                  curve: popCurve,
                  builder: (_, s, c) => Transform.scale(scale: s, child: c),
                  child: SvgIcon(widget.icon, color: color, size: 26),
                ),
                if (widget.dot)
                  Positioned(
                    top: -3,
                    right: -5,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4F0F),
                        shape: BoxShape.circle,
                        border: Border.all(color: C.bg, width: 2),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 2),
              Text(widget.label, style: nu(11, FontWeight.w700, color)),
            ]),
          ),
        ),
      ),
    );
  }
}

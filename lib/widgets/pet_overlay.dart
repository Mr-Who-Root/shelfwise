import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../services/sfx.dart';

/// Global registries for screen targets so the pet can jump accurately onto
/// shelves (on Home page) and to-do cards (on To-do page).
class ShelfBoundsRegistry {
  static final Map<String, Rect> homeShelves = {};
}

class TodoBoundsRegistry {
  static final Map<String, Rect> items = {};
}

/// Overlay that renders the chosen companion pet across all screens.
/// Features:
/// - Roams floor across all tabs.
/// - On Home page (tab == 0): Jumps up onto shelves, perches, naps, hops between shelves.
/// - On Library page (tab == 1): Does NOT jump onto shelves (per user instruction).
/// - On To-do page (tab == 2): Jumps onto to-do list items, performs naughty antics, jumps between them.
/// - Double-tap: Pet gets scared, plays panic sound, runs rapidly off-screen.
/// - Single-tap: Greets with species sound and happy hop.
class PetOverlay extends StatefulWidget {
  final int tab;
  const PetOverlay({super.key, required this.tab});

  @override
  State<PetOverlay> createState() => _PetOverlayState();
}

class _PetOverlayState extends State<PetOverlay> with TickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat();

  double _x = 100;
  double _y = 500;
  double _facing = 1; // 1 facing right, -1 facing left
  String _state = 'walk'; // walk, run, sit, lick, sleep, jump, naughty
  bool _fleeing = false;
  bool _offScreen = false;
  String? _naughtyEmoji;
  int _loopId = 0;
  Timer? _fleeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPosition();
      _startLifeLoop();
    });
  }

  @override
  void didUpdateWidget(PetOverlay old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab) {
      if (_fleeing) {
        _fleeing = false;
        _offScreen = false;
      }
      _loopId++;
      _startLifeLoop();
    }
  }

  @override
  void dispose() {
    _fleeTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  double _floorY(Size size, EdgeInsets padding) {
    // Floor is just above the bottom frosted navigation bar (~72px + bottom inset)
    return size.height - padding.bottom - 78;
  }

  void _initPosition() {
    if (!mounted) return;
    final mq = MediaQuery.of(context);
    final floor = _floorY(mq.size, mq.padding);
    setState(() {
      _x = (mq.size.width * .3).clamp(40.0, mq.size.width - 80.0);
      _y = floor;
      _facing = 1;
      _state = 'sit';
    });
  }

  Future<void> _flee() async {
    if (_fleeing || store.settings.pet == 'none') return;
    final kind = store.settings.pet;
    _fleeing = true;
    _loopId++;
    final curLoop = _loopId;

    Sfx.pet(kind, 'scare');

    final size = MediaQuery.sizeOf(context);
    final targetX = _x < size.width / 2 ? -90.0 : size.width + 90.0;
    final dir = targetX > _x ? 1.0 : -1.0;

    setState(() {
      _facing = dir;
      _state = 'run';
      _naughtyEmoji = '💨';
    });

    // Run off-screen rapidly
    final startX = _x;
    final dist = (targetX - startX).abs();
    final durationMs = (dist * 2.8).clamp(400.0, 950.0).toInt();
    final t0 = DateTime.now();

    while (mounted && curLoop == _loopId) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      final t = (elapsed / durationMs).clamp(0.0, 1.0);
      setState(() {
        _x = startX + (targetX - startX) * t;
      });
      if (t >= 1.0) break;
      await Future.delayed(const Duration(milliseconds: 16));
    }

    if (!mounted || curLoop != _loopId) return;
    setState(() {
      _offScreen = true;
      _naughtyEmoji = null;
    });

    // Return after ~12 seconds
    _fleeTimer?.cancel();
    _fleeTimer = Timer(const Duration(seconds: 12), () {
      if (!mounted) return;
      setState(() {
        _fleeing = false;
        _offScreen = false;
        _initPosition();
        _startLifeLoop();
      });
    });
  }

  void _tapPet() {
    if (_fleeing || store.settings.pet == 'none') return;
    final kind = store.settings.pet;
    Sfx.pet(kind, 'call');
    setState(() {
      _state = 'jump';
      _naughtyEmoji = '❤️';
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && !_fleeing) {
        setState(() {
          _state = 'sit';
          _naughtyEmoji = null;
        });
      }
    });
  }

  Future<void> _walkTo(double targetX, {double speed = 65, required int loop}) async {
    final startX = _x;
    final dist = targetX - startX;
    if (dist.abs() < 4) return;
    setState(() {
      _facing = dist > 0 ? 1 : -1;
      _state = 'walk';
    });
    final durationMs = (dist.abs() / speed * 1000).clamp(300.0, 4000.0).toInt();
    final t0 = DateTime.now();
    while (mounted && loop == _loopId && !_fleeing) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      final t = (elapsed / durationMs).clamp(0.0, 1.0);
      setState(() {
        _x = startX + dist * t;
      });
      if (t >= 1.0) break;
      await Future.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _jumpTo(double tx, double ty, {required int loop, double rise = 38}) async {
    final startX = _x;
    final startY = _y;
    final dx = tx - startX;
    final dy = ty - startY;
    setState(() {
      _facing = dx >= 0 ? 1 : -1;
      _state = 'jump';
    });
    final durationMs = (max(dx.abs(), dy.abs()) * 1.8).clamp(420.0, 850.0).toInt();
    final t0 = DateTime.now();
    while (mounted && loop == _loopId && !_fleeing) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      final t = (elapsed / durationMs).clamp(0.0, 1.0);
      final parabolic = 4 * rise * t * (1 - t);
      setState(() {
        _x = startX + dx * t;
        _y = startY + dy * t - parabolic;
      });
      if (t >= 1.0) break;
      await Future.delayed(const Duration(milliseconds: 16));
    }
    if (mounted && loop == _loopId && !_fleeing) {
      setState(() {
        _x = tx;
        _y = ty;
        _state = 'sit';
      });
      Sfx.pet(store.settings.pet, 'land');
    }
  }

  Future<void> _startLifeLoop() async {
    final curLoop = ++_loopId;
    final rnd = Random();

    while (mounted && curLoop == _loopId && !_fleeing && !_offScreen) {
      if (store.settings.pet == 'none') {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }
      if (!mounted) return;
      final size = MediaQuery.sizeOf(context);
      final padding = MediaQuery.paddingOf(context);
      final floor = _floorY(size, padding);

      // --- Tab 0: Home page behavior ---
      if (widget.tab == 0) {
        final shelves = ShelfBoundsRegistry.homeShelves.values
            .where((r) => r.top > padding.top + 60 && r.bottom < floor - 10)
            .toList();

        final onFloor = (_y - floor).abs() < 12;

        if (onFloor && shelves.isNotEmpty && rnd.nextDouble() < 0.65) {
          // Walk near target shelf X first
          final s = shelves[rnd.nextInt(shelves.length)];
          final targetX = (s.left + s.width * (.3 + rnd.nextDouble() * .4)).clamp(40.0, size.width - 60.0);
          await _walkTo(targetX, loop: curLoop);
          if (curLoop != _loopId || _fleeing) return;

          // Jump onto shelf!
          final targetY = s.bottom - 8;
          await _jumpTo(targetX, targetY, loop: curLoop, rise: 46);
          if (curLoop != _loopId || _fleeing) return;

          // Sit, groom, sleep on shelf
          setState(() => _state = 'sit');
          await Future.delayed(Duration(milliseconds: 1000 + rnd.nextInt(1200)));
          if (curLoop != _loopId || _fleeing) return;

          setState(() => _state = 'lick');
          await Future.delayed(Duration(milliseconds: 1800 + rnd.nextInt(1500)));
          if (curLoop != _loopId || _fleeing) return;

          // Sometimes take a nap on the shelf
          if (rnd.nextDouble() < 0.5) {
            setState(() {
              _state = 'sleep';
              _naughtyEmoji = '💤';
            });
            Sfx.pet(store.settings.pet, 'sleep');
            await Future.delayed(Duration(milliseconds: 3500 + rnd.nextInt(3000)));
            if (curLoop != _loopId || _fleeing) return;
            setState(() {
              _state = 'sit';
              _naughtyEmoji = null;
            });
          }

          // Jump down to floor or to another shelf
          final nextY = floor;
          final nextX = (_x + (rnd.nextBool() ? 40 : -40)).clamp(40.0, size.width - 60.0);
          await _jumpTo(nextX, nextY, loop: curLoop, rise: 30);
          continue;
        }
      }

      // --- Tab 2: To-do page behavior (jump into to-do lists & naughty antics) ---
      if (widget.tab == 2) {
        final todos = TodoBoundsRegistry.items.values
            .where((r) => r.top > padding.top + 80 && r.bottom < floor - 20)
            .toList();

        final onFloor = (_y - floor).abs() < 12;

        if (onFloor && todos.isNotEmpty && rnd.nextDouble() < 0.75) {
          // Pick a to-do item to jump onto
          final t = todos[rnd.nextInt(todos.length)];
          final tx = (t.left + t.width * .5).clamp(40.0, size.width - 60.0);
          await _walkTo(tx, loop: curLoop);
          if (curLoop != _loopId || _fleeing) return;

          // Jump onto the to-do item!
          final ty = t.top + 6;
          await _jumpTo(tx, ty, loop: curLoop, rise: 52);
          if (curLoop != _loopId || _fleeing) return;

          // Naughty things!
          final naughtyEmojis = switch (store.settings.pet) {
            'cat' => ['🐾', '🧶', '✨', '🐾'],
            'dog' => ['🦴', '🐾', '🎾', '🐾'],
            'rabbit' => ['🥕', '🌾', '🐾'],
            'bird' => ['🪶', '🎵', '✨'],
            _ => ['🐾', '✨'],
          };
          final emoji = naughtyEmojis[rnd.nextInt(naughtyEmojis.length)];

          setState(() {
            _state = 'naughty';
            _naughtyEmoji = emoji;
          });
          Sfx.pet(store.settings.pet, 'call');

          await Future.delayed(Duration(milliseconds: 2000 + rnd.nextInt(1800)));
          if (curLoop != _loopId || _fleeing) return;

          // Maybe hop to another to-do item if one is nearby
          if (todos.length > 1 && rnd.nextBool()) {
            final other = todos.firstWhere((item) => item != t, orElse: () => t);
            if (other != t) {
              final oX = (other.left + other.width * .5).clamp(40.0, size.width - 60.0);
              final oY = other.top + 6;
              await _jumpTo(oX, oY, loop: curLoop, rise: 36);
              if (curLoop != _loopId || _fleeing) return;

              setState(() {
                _state = 'naughty';
                _naughtyEmoji = '🐾';
              });
              await Future.delayed(Duration(milliseconds: 1600 + rnd.nextInt(1400)));
              if (curLoop != _loopId || _fleeing) return;
            }
          }

          // Jump down back to the floor
          setState(() => _naughtyEmoji = null);
          final downX = (_x + (rnd.nextBool() ? 50 : -50)).clamp(40.0, size.width - 60.0);
          await _jumpTo(downX, floor, loop: curLoop, rise: 24);
          continue;
        }
      }

      // --- Default Floor roaming (applies to all tabs, including Tab 1 Library) ---
      // Walk to random spot on floor
      final targetFloorX = 40.0 + rnd.nextDouble() * (size.width - 90.0);
      await _walkTo(targetFloorX, loop: curLoop);
      if (curLoop != _loopId || _fleeing) return;

      // Sit quietly
      setState(() => _state = 'sit');
      if (rnd.nextDouble() < 0.35) {
        Sfx.pet(store.settings.pet, 'call');
      }
      await Future.delayed(Duration(milliseconds: 1200 + rnd.nextInt(1600)));
      if (curLoop != _loopId || _fleeing) return;

      // Groom / Lick
      setState(() => _state = 'lick');
      await Future.delayed(Duration(milliseconds: 2000 + rnd.nextInt(1600)));
      if (curLoop != _loopId || _fleeing) return;

      // Sleep occasionally
      if (rnd.nextDouble() < 0.4) {
        setState(() {
          _state = 'sleep';
          _naughtyEmoji = '💤';
        });
        Sfx.pet(store.settings.pet, 'sleep');
        await Future.delayed(Duration(milliseconds: 4000 + rnd.nextInt(3500)));
        if (curLoop != _loopId || _fleeing) return;
        setState(() {
          _state = 'sit';
          _naughtyEmoji = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final kind = store.settings.pet;
        if (kind == 'none' || _offScreen) return const SizedBox.shrink();

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: _x - 35,
              top: _y - 56,
              width: 70,
              height: 64,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: _flee,
                onTap: _tapPet,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (_naughtyEmoji != null)
                      Positioned(
                        top: -16,
                        left: 24,
                        child: AnimatedBuilder(
                          animation: _anim,
                          builder: (_, _) => Transform.translate(
                            offset: Offset(0, sin(_anim.value * 2 * pi) * 3),
                            child: Text(_naughtyEmoji!, style: const TextStyle(fontSize: 16)),
                          ),
                        ),
                      ),
                    AnimatedBuilder(
                      animation: _anim,
                      builder: (_, _) => Transform.scale(
                        scaleX: _facing,
                        alignment: Alignment.bottomCenter,
                        child: CustomPaint(
                          size: const Size(70, 56),
                          painter: _PetPainter(
                            kind: kind,
                            state: _state,
                            animValue: _anim.value,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Custom painter rendering Cat, Dog, Rabbit, and Bird matching the SVG artwork.
class _PetPainter extends CustomPainter {
  final String kind;
  final String state;
  final double animValue;

  _PetPainter({required this.kind, required this.state, required this.animValue});

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case 'cat':
        _paintCat(canvas, size);
        break;
      case 'dog':
        _paintDog(canvas, size);
        break;
      case 'rabbit':
        _paintRabbit(canvas, size);
        break;
      case 'bird':
        _paintBird(canvas, size);
        break;
    }
  }

  void _paintCat(Canvas canvas, Size size) {
    const bodyCol = Color(0xFFE9A45E);
    const bellyCol = Color(0xFFF6D9B0);
    const darkCol = Color(0xFFC47F3C);
    const earCol = Color(0xFFF4A6A6);

    final legSwing = (state == 'walk' || state == 'run')
        ? sin(animValue * 2 * pi) * (state == 'run' ? 24.0 : 14.0)
        : 0.0;
    final bob = (state == 'walk' || state == 'run')
        ? (sin(animValue * 4 * pi) * 2.0).abs()
        : 0.0;

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(36, 54), width: 44, height: 6),
      Paint()..color = const Color(0x28000000),
    );

    // Tail
    final tailPaint = Paint()
      ..color = bodyCol
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    final tailWag = sin(animValue * 2 * pi) * 8.0;
    final path = Path()
      ..moveTo(16, 42 - bob)
      ..cubicTo(8, 38 - bob, 4 + tailWag, 22 - bob, 12 + tailWag, 18 - bob);
    canvas.drawPath(path, tailPaint);

    // Back legs
    final legPaintDark = Paint()..color = darkCol;
    final legPaintLight = Paint()..color = bodyCol;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(20 + legSwing, 40 - bob, 6, 15), const Radius.circular(3)),
      legPaintDark,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(44 - legSwing, 40 - bob, 6, 15), const Radius.circular(3)),
      legPaintDark,
    );

    // Body
    canvas.drawOval(
      Rect.fromCenter(center: Offset(35, 40 - bob), width: 38, height: 22),
      Paint()..color = bodyCol,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(37, 45 - bob), width: 26, height: 10),
      Paint()..color = bellyCol,
    );

    // Front legs
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(26 - legSwing, 41 - bob, 6, 15), const Radius.circular(3)),
      legPaintLight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(49 + legSwing, 41 - bob, 6, 15), const Radius.circular(3)),
      legPaintLight,
    );

    // Head
    final headCenter = Offset(52, 28 - bob);
    canvas.drawCircle(headCenter, 11, Paint()..color = bodyCol);

    // Ears
    final leftEar = Path()
      ..moveTo(headCenter.dx - 9, headCenter.dy - 6)
      ..lineTo(headCenter.dx - 8, headCenter.dy - 19)
      ..lineTo(headCenter.dx - 1, headCenter.dy - 9)
      ..close();
    canvas.drawPath(leftEar, Paint()..color = bodyCol);
    canvas.drawPath(leftEar, Paint()..color = earCol..style = PaintingStyle.stroke..strokeWidth = 2);

    final rightEar = Path()
      ..moveTo(headCenter.dx + 1, headCenter.dy - 9)
      ..lineTo(headCenter.dx + 8, headCenter.dy - 19)
      ..lineTo(headCenter.dx + 10, headCenter.dy - 5)
      ..close();
    canvas.drawPath(rightEar, Paint()..color = bodyCol);
    canvas.drawPath(rightEar, Paint()..color = earCol..style = PaintingStyle.stroke..strokeWidth = 2);

    // Snout
    canvas.drawOval(
      Rect.fromCenter(center: Offset(headCenter.dx + 7, headCenter.dy + 4), width: 10, height: 8),
      Paint()..color = bellyCol,
    );
    canvas.drawCircle(Offset(headCenter.dx + 10, headCenter.dy + 2.5), 1.8, Paint()..color = const Color(0xFFE8788A));

    // Whiskers
    final whiskerPaint = Paint()
      ..color = const Color(0xFF8A6A4A)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(headCenter.dx + 9, headCenter.dy + 4), Offset(headCenter.dx + 18, headCenter.dy + 2), whiskerPaint);
    canvas.drawLine(Offset(headCenter.dx + 9, headCenter.dy + 5.5), Offset(headCenter.dx + 18, headCenter.dy + 7.5), whiskerPaint);

    // Eye
    if (state == 'sleep') {
      final sleepEye = Path()
        ..moveTo(headCenter.dx + 2, headCenter.dy - 2)
        ..quadraticBezierTo(headCenter.dx + 5, headCenter.dy + 1, headCenter.dx + 8, headCenter.dy - 2);
      canvas.drawPath(sleepEye, Paint()..color = const Color(0xFF2B2B2B)..style = PaintingStyle.stroke..strokeWidth = 1.4);
    } else {
      canvas.drawCircle(Offset(headCenter.dx + 5, headCenter.dy - 2), 2.2, Paint()..color = const Color(0xFF2B2B2B));
      canvas.drawCircle(Offset(headCenter.dx + 5.8, headCenter.dy - 2.8), 0.8, Paint()..color = Colors.white);
    }
  }

  void _paintDog(Canvas canvas, Size size) {
    const bodyCol = Color(0xFFC99560);
    const bellyCol = Color(0xFFF1DFC2);
    const darkCol = Color(0xFF9C6A3A);
    const earCol = Color(0xFF8E5F33);

    final legSwing = (state == 'walk' || state == 'run')
        ? sin(animValue * 2 * pi) * (state == 'run' ? 24.0 : 14.0)
        : 0.0;
    final bob = (state == 'walk' || state == 'run')
        ? (sin(animValue * 4 * pi) * 2.0).abs()
        : 0.0;

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(36, 54), width: 44, height: 6),
      Paint()..color = const Color(0x28000000),
    );

    // Tail (happy wagging)
    final tailPaint = Paint()
      ..color = bodyCol
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    final wag = sin(animValue * 4 * pi) * 12.0;
    final path = Path()
      ..moveTo(17, 38 - bob)
      ..cubicTo(12, 34 - bob, 10 + wag, 24 - bob, 14 + wag, 20 - bob);
    canvas.drawPath(path, tailPaint);

    // Back legs
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(20 + legSwing, 40 - bob, 6, 15), const Radius.circular(3)),
      Paint()..color = darkCol,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(44 - legSwing, 40 - bob, 6, 15), const Radius.circular(3)),
      Paint()..color = darkCol,
    );

    // Body
    canvas.drawOval(
      Rect.fromCenter(center: Offset(35, 40 - bob), width: 38, height: 22),
      Paint()..color = bodyCol,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(37, 45 - bob), width: 24, height: 10),
      Paint()..color = bellyCol,
    );

    // Front legs
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(26 - legSwing, 41 - bob, 6, 15), const Radius.circular(3)),
      Paint()..color = bodyCol,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(49 + legSwing, 41 - bob, 6, 15), const Radius.circular(3)),
      Paint()..color = bodyCol,
    );

    // Head
    final headCenter = Offset(52, 28 - bob);
    canvas.drawCircle(headCenter, 11, Paint()..color = bodyCol);

    // Floppy Ear
    canvas.save();
    canvas.translate(headCenter.dx - 6, headCenter.dy + 1);
    canvas.rotate(18 * pi / 180);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 9, height: 18), Paint()..color = earCol);
    canvas.restore();

    // Snout
    canvas.drawOval(
      Rect.fromCenter(center: Offset(headCenter.dx + 8, headCenter.dy + 4), width: 14, height: 10),
      Paint()..color = bellyCol,
    );
    canvas.drawCircle(Offset(headCenter.dx + 13, headCenter.dy + 2), 2.4, Paint()..color = const Color(0xFF2B2B2B));

    // Eye
    if (state == 'sleep') {
      final sleepEye = Path()
        ..moveTo(headCenter.dx + 2, headCenter.dy - 2)
        ..quadraticBezierTo(headCenter.dx + 5, headCenter.dy + 1, headCenter.dx + 8, headCenter.dy - 2);
      canvas.drawPath(sleepEye, Paint()..color = const Color(0xFF2B2B2B)..style = PaintingStyle.stroke..strokeWidth = 1.4);
    } else {
      canvas.drawCircle(Offset(headCenter.dx + 4.5, headCenter.dy - 2), 2.2, Paint()..color = const Color(0xFF2B2B2B));
      canvas.drawCircle(Offset(headCenter.dx + 5.2, headCenter.dy - 2.8), 0.8, Paint()..color = Colors.white);
    }
  }

  void _paintRabbit(Canvas canvas, Size size) {
    const bodyCol = Color(0xFFEFE9E1);
    const bellyCol = Colors.white;
    const darkCol = Color(0xFFD6CDC2);
    const earCol = Color(0xFFF4B6C0);

    final legSwing = (state == 'walk' || state == 'run')
        ? sin(animValue * 2 * pi) * (state == 'run' ? 20.0 : 12.0)
        : 0.0;
    final bob = (state == 'walk' || state == 'run')
        ? (sin(animValue * 4 * pi) * 3.0).abs()
        : 0.0;

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(36, 54), width: 40, height: 6),
      Paint()..color = const Color(0x28000000),
    );

    // Fluffy cotton tail
    canvas.drawCircle(Offset(14, 38 - bob), 6, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(14, 38 - bob), 6, Paint()..color = darkCol..style = PaintingStyle.stroke..strokeWidth = 1);

    // Back legs
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(21 + legSwing, 41 - bob, 6, 14), const Radius.circular(3)),
      Paint()..color = darkCol,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(42 - legSwing, 41 - bob, 6, 14), const Radius.circular(3)),
      Paint()..color = darkCol,
    );

    // Body
    canvas.drawOval(
      Rect.fromCenter(center: Offset(34, 40 - bob), width: 34, height: 20),
      Paint()..color = bodyCol,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(36, 44 - bob), width: 22, height: 10),
      Paint()..color = bellyCol,
    );

    // Front legs
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(27 - legSwing, 42 - bob, 6, 14), const Radius.circular(3)),
      Paint()..color = bodyCol,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(46 + legSwing, 42 - bob, 6, 14), const Radius.circular(3)),
      Paint()..color = bodyCol,
    );

    // Head
    final headCenter = Offset(50, 28 - bob);
    canvas.drawCircle(headCenter, 10, Paint()..color = bodyCol);

    // Tall Ears
    canvas.save();
    canvas.translate(headCenter.dx - 3, headCenter.dy - 12);
    canvas.rotate(-8 * pi / 180);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 7, height: 18), Paint()..color = bodyCol);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 4, height: 14), Paint()..color = earCol);
    canvas.restore();

    canvas.save();
    canvas.translate(headCenter.dx + 4, headCenter.dy - 12);
    canvas.rotate(8 * pi / 180);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 7, height: 18), Paint()..color = bodyCol);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 4, height: 14), Paint()..color = earCol);
    canvas.restore();

    // Nose
    canvas.drawCircle(Offset(headCenter.dx + 8, headCenter.dy + 3), 1.8, Paint()..color = const Color(0xFFE8788A));

    // Eye
    if (state == 'sleep') {
      final sleepEye = Path()
        ..moveTo(headCenter.dx + 1, headCenter.dy - 2)
        ..quadraticBezierTo(headCenter.dx + 4, headCenter.dy + 1, headCenter.dx + 7, headCenter.dy - 2);
      canvas.drawPath(sleepEye, Paint()..color = const Color(0xFF2B2B2B)..style = PaintingStyle.stroke..strokeWidth = 1.4);
    } else {
      canvas.drawCircle(Offset(headCenter.dx + 3.5, headCenter.dy - 2), 2.0, Paint()..color = const Color(0xFF2B2B2B));
      canvas.drawCircle(Offset(headCenter.dx + 4.1, headCenter.dy - 2.6), 0.7, Paint()..color = Colors.white);
    }
  }

  void _paintBird(Canvas canvas, Size size) {
    const bodyCol = Color(0xFF5AA7E0);
    const bellyCol = Color(0xFFF3E3B8);
    const wingCol = Color(0xFF3F84C0);
    const beakCol = Color(0xFFF2A03D);
    const legCol = Color(0xFFC98A3D);

    final flap = (state == 'jump' || state == 'run' || state == 'naughty')
        ? sin(animValue * 6 * pi) * 22.0
        : 0.0;
    final hop = (state == 'walk') ? (sin(animValue * 4 * pi) * 3.5).abs() : 0.0;

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(36, 54), width: 32, height: 5),
      Paint()..color = const Color(0x28000000),
    );

    // Legs
    final legPaint = Paint()
      ..color = legCol
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(32, 48 - hop), Offset(32, 53), legPaint);
    canvas.drawLine(Offset(39, 48 - hop), Offset(39, 53), legPaint);
    canvas.drawLine(Offset(29, 53), Offset(34, 53), legPaint);
    canvas.drawLine(Offset(36, 53), Offset(41, 53), legPaint);

    // Tail feathers
    final tail = Path()
      ..moveTo(22, 40 - hop)
      ..lineTo(4, 48 - hop)
      ..lineTo(10, 38 - hop)
      ..lineTo(2, 36 - hop)
      ..lineTo(22, 33 - hop)
      ..close();
    canvas.drawPath(tail, Paint()..color = wingCol);

    // Body
    canvas.drawOval(
      Rect.fromCenter(center: Offset(36, 38 - hop), width: 30, height: 24),
      Paint()..color = bodyCol,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(42, 42 - hop), width: 18, height: 16),
      Paint()..color = bellyCol,
    );

    // Wing
    canvas.save();
    canvas.translate(30, 38 - hop);
    canvas.rotate((-18 + flap) * pi / 180);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 22, height: 14), Paint()..color = wingCol);
    canvas.restore();

    // Head
    final headCenter = Offset(48, 28 - hop);
    canvas.drawCircle(headCenter, 9, Paint()..color = bodyCol);

    // Beak
    final beak = Path()
      ..moveTo(headCenter.dx + 6, headCenter.dy - 3)
      ..lineTo(headCenter.dx + 16, headCenter.dy)
      ..lineTo(headCenter.dx + 6, headCenter.dy + 3)
      ..close();
    canvas.drawPath(beak, Paint()..color = beakCol);

    // Eye
    if (state == 'sleep') {
      final sleepEye = Path()
        ..moveTo(headCenter.dx + 2, headCenter.dy - 2)
        ..quadraticBezierTo(headCenter.dx + 4.5, headCenter.dy + 1, headCenter.dx + 7, headCenter.dy - 2);
      canvas.drawPath(sleepEye, Paint()..color = const Color(0xFF2B2B2B)..style = PaintingStyle.stroke..strokeWidth = 1.4);
    } else {
      canvas.drawCircle(Offset(headCenter.dx + 4, headCenter.dy - 2), 2.0, Paint()..color = const Color(0xFF2B2B2B));
      canvas.drawCircle(Offset(headCenter.dx + 4.6, headCenter.dy - 2.6), 0.7, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _PetPainter old) =>
      old.kind != kind || old.state != state || old.animValue != animValue;
}

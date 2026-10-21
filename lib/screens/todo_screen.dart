import 'dart:math';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../icons.dart';
import '../services/notify.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/fx.dart';
import '../widgets/pet_overlay.dart';
import '../widgets/sticky_note.dart';
import 'bell.dart';

class TodoUi {
  static String f = 'all';
  static final seen = <String>{};
}

const _sizes = ['big', 'small', 'small', 'wide', 'small', 'small'];

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});
  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  final _scroll = ScrollController();
  bool _fabDown = false;

  void _addStickyNoteDialog() {
    Buzz.tick();
    String selectedColor = '#ffe27a';
    String selectedSize = 'm';
    final textCtrl = TextEditingController(text: '');
    openDialog((ctx) => StatefulBuilder(
          builder: (ctx, set) {
            return AppDialog(
              title: 'New sticky note',
              maxWidth: 360,
              actions: [
                const Btn('Cancel'),
                Btn('Stick Note 📌', kind: Kind.pri, onTap: () {
                  final text = textCtrl.text.trim();
                  store.addTodoStickyNote(
                    text: text.isEmpty ? 'Reading to-do note…' : text,
                    color: selectedColor,
                    ink: '#1c2f6b',
                    size: selectedSize,
                  );
                  Sfx.play('pop');
                  toast('Sticky note added to To-do!');
                  return true;
                }),
              ],
              children: [
                Text('Add a cozy reminder, thought, or quote to your to-do page',
                    style: nu(13, FontWeight.w600, C.muted)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: parseStickyColor(selectedColor),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Color(0x22000000), offset: Offset(0, 3), blurRadius: 8)],
                  ),
                  child: TextField(
                    controller: textCtrl,
                    maxLines: 3,
                    autofocus: true,
                    style: TextStyle(
                      fontFamily: 'Caveat',
                      fontSize: selectedSize == 'l' ? 20 : (selectedSize == 's' ? 16 : 18),
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1C2F6B),
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Write a thought, note, or reminder…',
                      hintStyle: TextStyle(
                        fontFamily: 'Caveat',
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Color(0x661C2F6B),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Note size', style: nu(13, FontWeight.w800, C.chipText)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final (sz, label) in const [
                      ('s', 'S Small'),
                      ('m', 'M Medium'),
                      ('l', 'L Large'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => set(() => selectedSize = sz),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: selectedSize == sz ? C.brown : C.chip,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selectedSize == sz ? C.brown : const Color(0x33000000),
                                width: selectedSize == sz ? 2 : 1,
                              ),
                            ),
                            child: Text(
                              label,
                              style: nu(12.5, FontWeight.w800, selectedSize == sz ? Colors.white : C.chipText),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('Paper color', style: nu(13, FontWeight.w800, C.chipText)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final entry in stickyColorDefs.entries)
                      GestureDetector(
                        onTap: () => set(() => selectedColor = entry.key),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: entry.value,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selectedColor == entry.key ? C.brown : const Color(0x33000000),
                              width: selectedColor == entry.key ? 2.5 : 1,
                            ),
                          ),
                          child: selectedColor == entry.key
                              ? const Center(child: Icon(Icons.check, size: 16, color: Color(0xFF2B2B2B)))
                              : null,
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<Todo> _list() {
    final f = TodoUi.f;
    final end = AppStore.endOfToday().millisecondsSinceEpoch;
    final l = store.todos.where((t) {
      return switch (f) {
        'active' => !t.done,
        'done' => t.done,
        'today' => !t.done && t.due != null && t.due! <= end,
        _ when f.startsWith('t:') => t.tags.contains(f.substring(2)),
        _ => true,
      };
    }).toList();
    int key(Todo t) => t.due ?? (1 << 52);
    l.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      if (a.done) return (b.doneAt ?? 0).compareTo(a.doneAt ?? 0);
      if (a.starred != b.starred) return a.starred ? -1 : 1;
      final d = key(a).compareTo(key(b));
      return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
    });
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final list = _list();
        final open = store.todos.where((t) => !t.done).length;
        final f = TodoUi.f;
        final chips = [
          ('all', 'All'),
          ('active', 'Active'),
          ('today', 'Today'),
          ('done', 'Done'),
          if (f.startsWith('t:')) (f, '#${f.substring(2)} ✕'),
        ];
        return Stack(children: [
          ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(14, mq.padding.top + 26, 14, 170),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(child: Text('To-do', style: nu((mq.size.width * .08).clamp(26.0, 32.0), FontWeight.w800).copyWith(letterSpacing: -.4))),
                  Pressable(
                    onTap: _addStickyNoteDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE27A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x33000000)),
                        boxShadow: const [BoxShadow(color: Color(0x18000000), offset: Offset(0, 2), blurRadius: 4)],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text('📌', style: TextStyle(fontSize: 13)),
                        const SizedBox(width: 4),
                        Text('Note', style: nu(12, FontWeight.w800, const Color(0xFF1C2F6B))),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const BellButton(),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 14),
                child: Text(
                  store.todos.isEmpty ? 'Little tasks for your reading life' : '$open open · ${store.todos.length - open} done',
                  style: nu(14, FontWeight.w600, C.muted),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 14),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (k, l) in chips)
                    PopChip(l,
                        on: f == k,
                        fontSize: 14,
                        pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        onTap: () => setState(() => TodoUi.f = (k == f && k.startsWith('t:')) ? 'all' : k)),
                ]),
              ),
              if (store.todoNotes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final note in store.todoNotes)
                          Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: StickyNoteWidget(
                              key: ValueKey(note.id),
                              note: note,
                              width: 144,
                              minHeight: 114,
                              onEdited: () => store.changed(),
                              onTear: () => store.removeTodoStickyNote(note.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (list.isEmpty) _empty() else _bento(list),
            ],
          ),
          Positioned(
            right: 18,
            bottom: 96 + mq.padding.bottom,
            child: Semantics(
              button: true,
              label: 'Add a to-do',
              child: GestureDetector(
                onTapDown: (_) => setState(() => _fabDown = true),
                onTapCancel: () => setState(() => _fabDown = false),
                onTapUp: (_) => setState(() => _fabDown = false),
                onTap: () {
                  Buzz.tick();
                  editTodo(null);
                },
                child: AnimatedRotation(
                  turns: _fabDown ? .25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: AnimatedScale(
                    scale: _fabDown ? 1.06 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: C.brown,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Color.fromRGBO(184, 105, 42, .4), offset: Offset(0, 6), blurRadius: 18)],
                      ),
                      alignment: Alignment.center,
                      child: const SvgIcon(Ic.pencil, color: Colors.white, size: 26, stroke: 2.4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }

  Widget _empty() {
    final f = TodoUi.f;
    final msg = switch (f) {
      'done' => 'Nothing ticked off yet. You’ve got this.',
      'today' => 'Nothing due today. Enjoy your book!',
      'active' => 'All done! Add something new with ✎.',
      _ => 'No to-dos yet. Tap ✎ to add your first one, like “Finish chapter 12 tonight”.',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 30),
      child: Column(children: [
        SizedBox(
          width: 160,
          height: 60,
          child: CustomPaint(painter: _EmptyShelf()),
        ),
        const SizedBox(height: 8),
        Text(store.todos.isEmpty ? 'A fresh page' : 'Nothing here', style: nu(18, FontWeight.w800)),
        const SizedBox(height: 4),
        Text(msg, textAlign: TextAlign.center, style: nu(14, FontWeight.w600, C.muted, 1.4)),
      ]),
    );
  }

  Widget _bento(List<Todo> list) {
    final rows = <Widget>[];
    var i = 0;
    while (i < list.length) {
      final size = _sizes[i % 6];
      if (size != 'small') {
        rows.add(IntrinsicHeight(child: TodoTile(list[i], key: ValueKey(list[i].id), k: i % 6, size: size)));
        i++;
        continue;
      }
      final a = list[i];
      final hasPair = i + 1 < list.length && _sizes[(i + 1) % 6] == 'small';
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: TodoTile(a, key: ValueKey(a.id), k: i % 6, size: 'small')),
          const SizedBox(width: 10),
          Expanded(child: hasPair ? TodoTile(list[i + 1], key: ValueKey(list[i + 1].id), k: (i + 1) % 6, size: 'small') : const SizedBox()),
        ]),
      ));
      i += hasPair ? 2 : 1;
    }
    return Column(children: [
      for (final r in rows) Padding(padding: const EdgeInsets.only(bottom: 10), child: r),
    ]);
  }
}

class _EmptyShelf extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final k = s.width / 160;
    c.scale(k);
    c.drawRRect(RRect.fromLTRBR(8, 46, 152, 54, const Radius.circular(3)), Paint()..color = const Color(0xFF5A4630));
    c.drawRRect(RRect.fromLTRBR(8, 54, 152, 57, const Radius.circular(1)), Paint()..color = const Color(0xFF3A2C1D));
    c.drawRRect(RRect.fromLTRBR(14, 26, 22, 46, const Radius.circular(2)), Paint()..color = const Color(0xFF3A3A3A));
    c.drawRRect(RRect.fromLTRBR(138, 26, 146, 46, const Radius.circular(2)), Paint()..color = const Color(0xFF3A3A3A));
  }

  @override
  bool shouldRepaint(_) => false;
}

/// A bento tile for one to-do.
class TodoTile extends StatefulWidget {
  final Todo t;
  final int k;
  final String size;
  const TodoTile(this.t, {super.key, required this.k, required this.size});

  @override
  State<TodoTile> createState() => _TodoTileState();
}

class _TodoTileState extends State<TodoTile> {
  late final bool _fresh = TodoUi.seen.add(widget.t.id);
  final _checkKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportBounds());
  }

  @override
  void didUpdateWidget(TodoTile old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportBounds());
  }

  @override
  void dispose() {
    TodoBoundsRegistry.items.remove(widget.t.id);
    super.dispose();
  }

  void _reportBounds() {
    if (!mounted) return;
    final ro = context.findRenderObject() as RenderBox?;
    if (ro != null && ro.hasSize) {
      final pos = ro.localToGlobal(Offset.zero);
      TodoBoundsRegistry.items[widget.t.id] = Rect.fromLTWH(pos.dx, pos.dy, ro.size.width, ro.size.height);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t, size = widget.size;
    final col = tileColors[widget.k];
    final n = t.text.length;
    final fs = size == 'big'
        ? (n < 70 ? 34.0 : n < 120 ? 26.0 : 20.0)
        : size == 'wide'
            ? (n < 100 ? 22.0 : 18.0)
            : (n < 60 ? 20.0 : n < 110 ? 17.0 : 15.0);
    final lines = size == 'wide' ? 4 : 6;
    final minH = size == 'big' ? 232.0 : size == 'wide' ? 150.0 : 176.0;
    final chipBg = col.dark ? const Color.fromRGBO(255, 255, 255, .16) : const Color.fromRGBO(0, 0, 0, .13);
    final showN = size != 'small';
    final late = store.isOverdue(t);

    Widget tile = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      constraints: BoxConstraints(minHeight: minH),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: col.bg,
        borderRadius: BorderRadius.circular(22),
        border: col.border == null ? null : Border.all(color: col.border!),
      ),
      child: DefaultTextStyle(
        style: nu(13, FontWeight.w800, col.fg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.done ? const Color(0xFF5FBF9A) : (late ? const Color(0xFFC9372C) : C.brown),
                border: Border.all(color: const Color.fromRGBO(255, 255, 255, .6), width: 2),
              ),
              alignment: Alignment.center,
              child: Text(t.done ? '✓' : (t.due != null ? '⏰' : '📌'), style: nu(t.done ? 13 : 11, FontWeight.w800, Colors.white, 1)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  t.done ? 'Done' : (t.dueAt != null ? fmtDue(t.dueAt!) : 'Someday'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: nu(13, FontWeight.w800, col.fg, 1.15),
                ),
                Opacity(
                  opacity: .65,
                  child: Text(
                    late ? 'Overdue' : (t.done && t.doneAt != null ? fmtDate(t.doneAt!) : 'Added ${fmtDate(t.createdAt)}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: nu(11, FontWeight.w700, col.fg),
                  ),
                ),
              ]),
            ),
            Semantics(
              button: true,
              label: 'Edit or delete this to-do',
              child: Pressable(
                onTap: () => editTodo(t),
                scale: .85,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: col.dark ? const Color.fromRGBO(255, 255, 255, .18) : const Color.fromRGBO(0, 0, 0, .14), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text('⋯', style: nu(20, FontWeight.w800, col.fg, 1)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => openTodo(t),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: t.done ? .55 : 1,
              child: Text(
                t.text,
                maxLines: lines,
                overflow: TextOverflow.ellipsis,
                style: nu(fs, FontWeight.w800, col.fg, 1.16).copyWith(
                  letterSpacing: -.01 * fs,
                  decoration: t.done ? TextDecoration.lineThrough : null,
                  decorationThickness: 2.5,
                  decorationColor: col.fg,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (t.book.isNotEmpty || t.edited)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (t.book.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(10)),
                    child: Text('📖 ${t.book}', maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(11, FontWeight.w800, col.fg)),
                  ),
                if (t.edited) Opacity(opacity: .7, child: Text('Edited', style: nu(11, FontWeight.w800, col.fg).copyWith(fontStyle: FontStyle.italic))),
              ]),
            ),
          if (t.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(spacing: 4, runSpacing: 4, children: [
                for (final tag in t.tags)
                  Pressable(
                    onTap: () {
                      TodoUi.f = 't:$tag';
                      store.changed();
                    },
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 28),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: col.dark ? const Color.fromRGBO(255, 255, 255, .16) : const Color.fromRGBO(0, 0, 0, .1),
                          borderRadius: BorderRadius.circular(10)),
                      child: Text('#$tag', style: nu(11, FontWeight.w800, col.fg)),
                    ),
                  ),
              ]),
            ),
          const Spacer(),
          Transform.translate(
            offset: const Offset(-8, 8),
            child: Row(children: [
              _Act(
                key: _checkKey,
                icon: Ic.check,
                on: t.done,
                label: showN ? (t.done ? 'Done' : 'Mark done') : null,
                fg: col.fg,
                dark: col.dark,
                onTap: () => _toggle(t),
                tip: t.done ? 'Mark not done' : 'Mark done',
              ),
              _Act(
                icon: Ic.star,
                on: t.starred,
                label: showN ? (t.starred ? 'Starred' : 'Star') : null,
                fg: col.fg,
                dark: col.dark,
                tip: t.starred ? 'Unstar' : 'Star',
                onTap: () {
                  t.starred = !t.starred;
                  store.changed();
                  Sfx.play(t.starred ? 'pop' : 'tap');
                  toast(t.starred ? 'Starred · stays on top' : 'Unstarred');
                },
              ),
              const Spacer(),
              _Act(
                icon: Ic.clock,
                on: t.due != null,
                label: showN ? 'Due' : null,
                fg: col.fg,
                dark: col.dark,
                tip: 'Set a due time',
                onTap: () async {
                  final d = await pickDue(t.dueAt);
                  if (d == null) return;
                  t.due = d.millisecondsSinceEpoch == 0 ? null : d.millisecondsSinceEpoch;
                  store.changed();
                  toast(t.due == null ? 'Due time cleared' : 'Due ${fmtDue(t.dueAt!)}');
                  remindTip(t);
                },
              ),
            ]),
          ),
        ]),
      ),
    );
    if (_fresh) {
      tile = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 450),
        curve: ease,
        builder: (_, v, c) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: Transform.scale(scale: .97 + .03 * v, child: c)),
        ),
        child: tile,
      );
    }
    return tile;
  }

  void _toggle(Todo t) {
    store.toggleTodo(t);
    if (t.done) {
      Sfx.play('check');
      Buzz.light();
      final box = _checkKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) confetti(box.localToGlobal(box.size.center(Offset.zero)), count: 22);
      toast('Nice! Task done ✓');
    } else {
      Sfx.play('tap');
      toast('Back on your list');
    }
  }
}

class _Act extends StatelessWidget {
  final String icon;
  final bool on;
  final String? label;
  final Color fg;
  final bool dark;
  final VoidCallback onTap;
  final String tip;
  const _Act({super.key, required this.icon, required this.on, this.label, required this.fg, required this.dark, required this.onTap, required this.tip});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: on,
      label: tip,
      child: Pressable(
        onTap: onTap,
        scale: .9,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minHeight: 38),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: on ? (dark ? const Color.fromRGBO(255, 255, 255, .2) : const Color.fromRGBO(0, 0, 0, .17)) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            TweenAnimationBuilder<double>(
              key: ValueKey(on),
              tween: Tween(begin: on ? 1.3 : 1, end: 1),
              duration: const Duration(milliseconds: 300),
              curve: popCurve,
              builder: (_, s, c) => Transform.scale(scale: s, child: c),
              child: SvgIcon(icon, color: fg, size: 19, fill: on && icon == Ic.star ? fg : null),
            ),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(label!, style: nu(12, FontWeight.w800, fg)),
            ],
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------

void openTodo(Todo t) {
  Sfx.play('tap');
  openDialog((ctx) => ListenableBuilder(
        listenable: store,
        builder: (ctx, _) => AppDialog(
          maxWidth: 380,
          children: [
            Text(t.done ? '✅ Done${t.doneAt != null ? ' · ${fmtDate(t.doneAt!)}' : ''}' : (t.dueAt != null ? '⏰ ${fmtDue(t.dueAt!)}' : '📌 Someday'),
                style: nu(13, FontWeight.w800, store.isOverdue(t) ? C.error : C.muted)),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
              child: Text(t.text,
                  style: nu(20, FontWeight.w800, C.ink, 1.3).copyWith(decoration: t.done ? TextDecoration.lineThrough : null)),
            ),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (t.book.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .08), borderRadius: BorderRadius.circular(10)),
                  child: Text('📖 ${t.book}', style: nu(11, FontWeight.w800)),
                ),
              for (final tag in t.tags)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color.fromRGBO(0, 0, 0, .08), borderRadius: BorderRadius.circular(10)),
                  child: Text('#$tag', style: nu(11, FontWeight.w800)),
                ),
              if (t.edited) Text('Edited', style: nu(11, FontWeight.w800, C.muted).copyWith(fontStyle: FontStyle.italic)),
            ]),
          ],
          actions: [
            Btn('Edit / Delete', then: () => editTodo(t)),
            Btn(t.done ? 'Not done' : 'Mark done', kind: Kind.pri, onTap: () {
              store.toggleTodo(t);
              Sfx.play(t.done ? 'check' : 'tap');
              toast(t.done ? 'Nice! Task done ✓' : 'Back on your list');
              return true;
            }),
            const Btn('Close'),
          ],
        ),
      ));
}

List<String> parseTags(String v) {
  final out = <String>[];
  for (final raw in v.split(RegExp(r'[\s,]+'))) {
    final t = raw.replaceAll(RegExp(r'^#+'), '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (t.isNotEmpty && !out.contains(t)) out.add(t);
  }
  return out;
}

/// When reminders are off, nudge people toward turning them on.
void remindTip(Todo t) {
  if (t.due != null && !store.settings.reminders) {
    Future.delayed(const Duration(milliseconds: 2000), () => toast('Tip: turn on To-do reminders in Settings to get a nudge'));
  }
}

/// Create (null) or edit a to-do.
void editTodo(Todo? t) {
  final text = TextEditingController(text: t?.text ?? '');
  final book = TextEditingController(text: t?.book ?? '');
  final tags = TextEditingController(text: (t?.tags ?? const []).map((e) => '#$e').join(' '));
  DateTime? due = t?.dueAt;
  var err = '', tagErr = '';
  final reading = store.allBooks.where((b) => !b.finished).map((b) => b.title).toSet().take(6).toList();
  openDialog((ctx) => StatefulBuilder(builder: (ctx, set) {
        final nTags = parseTags(tags.text).length;
        return AppDialog(
          title: t == null ? 'New to-do' : 'Edit your to-do',
          maxWidth: 380,
          children: [
            if (t == null) const Sub('A little task for your reading life.'),
            AppInput(text, 'What do you want to do?', maxLength: 220, lines: 3, autofocus: t == null, onChanged: (_) => set(() => err = '')),
            Align(
              alignment: Alignment.centerRight,
              child: Text('${text.text.length}/220', style: nu(12, FontWeight.w700, C.muted)),
            ),
            ErrText(err),
            AppInput(book, 'Book (optional)', maxLength: 60, caps: TextCapitalization.words, onChanged: (_) => set(() {})),
            if (reading.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final r in reading)
                    PopChip(r.length > 22 ? '${r.substring(0, 21)}…' : r,
                        on: book.text == r,
                        fontSize: 12,
                        pad: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        onTap: () => set(() => book.text = book.text == r ? '' : r)),
                ]),
              ),
            const SizedBox(height: 8),
            Text('When?', style: nu(13, FontWeight.w800, C.chipText)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              PopChip('No date', on: due == null, fontSize: 13, pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), onTap: () => set(() => due = null)),
              PopChip('Today', on: due != null && _sameDay(due!, DateTime.now()), fontSize: 13,
                  pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), onTap: () => set(() => due = _todayAt())),
              PopChip('Tomorrow', on: due != null && _sameDay(due!, DateTime.now().add(const Duration(days: 1))), fontSize: 13,
                  pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), onTap: () {
                final n = DateTime.now().add(const Duration(days: 1));
                set(() => due = DateTime(n.year, n.month, n.day, 9));
              }),
              PopChip('Pick…', on: false, dashed: true, fontSize: 13, pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), onTap: () async {
                final d = await _pickDateTime(ctx, due);
                if (d != null) set(() => due = d);
              }),
            ]),
            if (due != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Due ${fmtDue(due!)}${store.settings.reminders ? ' · you’ll get a reminder' : ''}',
                    style: nu(12, FontWeight.w700, C.brown)),
              ),
            const SizedBox(height: 8),
            AppInput(tags, 'Hashtags, up to 3 (e.g. #weekend #fantasy)', maxLength: 60, caps: TextCapitalization.none,
                onChanged: (_) => set(() => tagErr = '')),
            Align(
              alignment: Alignment.centerRight,
              child: Text('$nTags/3 hashtags', style: nu(12, FontWeight.w700, nTags > 3 ? C.error : C.muted)),
            ),
            ErrText(tagErr),
          ],
          actions: [
            if (t != null)
              Btn('Delete', kind: Kind.dng, then: () async {
                if (await confirm('Delete this to-do?', 'It will be removed from your list. This can’t be undone.', yes: 'Delete')) {
                  store.todos.remove(t);
                  store.changed();
                  Sfx.play('swoosh');
                  toast('To-do deleted');
                }
              }),
            const Btn('Cancel'),
            Btn(t == null ? 'Add' : 'Save', kind: Kind.pri, onTap: () {
              final v = text.text.trim();
              if (v.length < 3) {
                set(() => err = 'Write at least a few letters.');
                return false;
              }
              final tg = parseTags(tags.text);
              if (tg.length > 3) {
                set(() => tagErr = 'You can add up to 3 hashtags. Remove ${tg.length - 3}.');
                return false;
              }
              final ms = due?.millisecondsSinceEpoch;
              if (t == null) {
                final nt = Todo(text: v, book: book.text.trim(), tags: tg, due: ms);
                store.todos.add(nt);
                TodoUi.f = TodoUi.f == 'done' ? 'all' : TodoUi.f;
                Sfx.play('pop');
                toast('Added to your to-do list');
                remindTip(nt);
              } else {
                if (v != t.text || book.text.trim() != t.book || tg.join() != t.tags.join()) t.edited = true;
                t
                  ..text = v
                  ..book = book.text.trim()
                  ..tags = tg
                  ..due = ms;
                toast('To-do updated');
                remindTip(t);
              }
              store.changed();
              if (ms != null && store.settings.reminders) Notifier.sync();
              return true;
            }),
          ],
        );
      }));
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _todayAt() {
  final n = DateTime.now();
  final eight = DateTime(n.year, n.month, n.day, 20);
  if (eight.isAfter(n.add(const Duration(minutes: 30)))) return eight;
  final h = n.add(const Duration(hours: 1));
  return DateTime(h.year, h.month, h.day, h.hour, (h.minute ~/ 15) * 15);
}

Future<DateTime?> _pickDateTime(BuildContext ctx, DateTime? cur) async {
  final now = DateTime.now();
  final d = await showDatePicker(
    context: ctx,
    initialDate: cur ?? now,
    firstDate: DateTime(now.year - 1),
    lastDate: DateTime(now.year + 5),
  );
  if (d == null || !ctx.mounted) return null;
  final tm = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(cur ?? DateTime(now.year, now.month, now.day, 20)));
  final t = tm ?? const TimeOfDay(hour: 20, minute: 0);
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}

/// Quick due-time picker. Returns epoch 0 to clear, null when cancelled.
Future<DateTime?> pickDue(DateTime? cur) async {
  DateTime? out;
  await openDialog((ctx) => AppDialog(title: 'When is it due?', children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          Pill('Today', onTap: () {
            out = _todayAt();
            Navigator.pop(ctx);
          }),
          Pill('Tomorrow', onTap: () {
            final n = DateTime.now().add(const Duration(days: 1));
            out = DateTime(n.year, n.month, n.day, 9);
            Navigator.pop(ctx);
          }),
          Pill('This weekend', onTap: () {
            final n = DateTime.now();
            final add = max(1, (DateTime.saturday - n.weekday) % 7);
            final s = n.add(Duration(days: add));
            out = DateTime(s.year, s.month, s.day, 10);
            Navigator.pop(ctx);
          }),
          Pill('Pick a date…', kind: Kind.outline, onTap: () async {
            final d = await _pickDateTime(ctx, cur);
            if (d == null || !ctx.mounted) return;
            out = d;
            Navigator.pop(ctx);
          }),
          if (cur != null)
            Pill('Clear', kind: Kind.dng, onTap: () {
              out = DateTime.fromMillisecondsSinceEpoch(0);
              Navigator.pop(ctx);
            }),
        ]),
      ], actions: const [
        Btn('Cancel'),
      ]));
  return out;
}

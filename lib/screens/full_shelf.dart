import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../widgets/book_cover.dart';
import '../widgets/common.dart';
import 'library_screen.dart';

/// Every shelf at once on a dark wooden wall (the mockup's full-screen shelf).
void openFullShelf() {
  Sfx.play('swoosh');
  dropFocus();
  navKey.currentState!.push(PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => const _FullShelf(),
    transitionsBuilder: (_, a, _, child) {
      final t = CurvedAnimation(parent: a, curve: ease);
      return FadeTransition(
        opacity: t,
        child: SlideTransition(position: Tween(begin: const Offset(0, .06), end: Offset.zero).animate(t), child: child),
      );
    },
  ));
}

class _FullShelf extends StatelessWidget {
  const _FullShelf();

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
      backgroundColor: const Color(0xFF2B1D10),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final total = store.totalBooks;
          return Column(children: [
            Container(
              padding: EdgeInsets.fromLTRB(16, mq.padding.top + 14, 16, 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color.fromRGBO(255, 255, 255, .12)))),
              child: Row(children: [
                Expanded(
                  child: Text('📚 ${store.profile.first}’s shelf',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(18, FontWeight.w800, const Color(0xFFF3EEE6))),
                ),
                Text(plural(total, 'book'), style: nu(12, FontWeight.w700, const Color(0xFFCDBFAE))),
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  label: 'Close full screen',
                  child: Pressable(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(color: Color.fromRGBO(255, 255, 255, .14), shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: store.cols.isEmpty
                  ? Center(child: Text('No books on this shelf yet.', style: nu(15, FontWeight.w600, const Color(0xFFCDBFAE))))
                  : ListView(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + mq.padding.bottom),
                      children: [
                        for (final (i, c) in store.cols.indexed)
                          FadeIn(
                            delay: i * 70,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
                                child: Row(children: [
                                  Expanded(child: Text('${c.emoji} ${c.name}', style: nu(16, FontWeight.w800, const Color(0xFFF3EEE6)))),
                                  Text(plural(c.books.length, 'book'), style: nu(12, FontWeight.w700, const Color(0xFFCDBFAE))),
                                ]),
                              ),
                              Container(
                                padding: const EdgeInsets.fromLTRB(10, 22, 10, 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
                                  border: Border(bottom: BorderSide(color: C.plank, width: 8)),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Color.fromRGBO(255, 255, 255, .03), Color.fromRGBO(255, 255, 255, .09)],
                                  ),
                                ),
                                child: c.items.isEmpty
                                    ? Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: Text('Empty shelf', textAlign: TextAlign.center, style: nu(13, FontWeight.w700, const Color(0xFFCDBFAE))),
                                      )
                                    : Wrap(
                                        spacing: 10,
                                        runSpacing: 12,
                                        crossAxisAlignment: WrapCrossAlignment.end,
                                        children: [
                                          for (final it in c.items)
                                            Pressable(
                                              onTap: () => it.isDecor ? openDecor(c, it, home: true) : openBookView(c, it),
                                              child: it.isDecor
                                                  ? GadgetView(it.gadget!, w: 78 * .85, h: 112 * gadgetHeightFactor(it.gadget!), lit: it.lit)
                                                  : DecoratedBox(
                                                      decoration: BoxDecoration(
                                                        borderRadius: BorderRadius.circular(5),
                                                        boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, .4), offset: Offset(0, 2), blurRadius: 6)],
                                                      ),
                                                      child: BookCover(it, w: 78, h: 112),
                                                    ),
                                            ),
                                        ],
                                      ),
                              ),
                            ]),
                          ),
                      ],
                    ),
            ),
          ]);
        },
      ),
    ),
    );
  }
}

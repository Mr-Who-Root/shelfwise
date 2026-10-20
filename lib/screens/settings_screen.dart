import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../art.dart';
import '../data/store.dart';
import '../look.dart';
import '../services/notify.dart';
import '../services/sfx.dart';
import '../theme.dart';
import '../version.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import 'library_screen.dart';

/// Settings, as a full page: appearance, backup, alerts and the rest.
class SettingsScreen extends StatefulWidget {
  final VoidCallback onProfile, onReplay;
  const SettingsScreen({super.key, required this.onProfile, required this.onReplay});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false, _about = false;

  void _set(void Function() f, {bool look = false}) {
    f();
    store.changed();
    if (look) Look.apply(animate: true);
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    final box = context.findRenderObject() as RenderBox?;
    try {
      final f = await store.exportBackup();
      Sfx.play('swoosh');
      await SharePlus.instance.share(ShareParams(
        files: [XFile(f.path, mimeType: 'application/json')],
        subject: 'Shelfwise backup',
        text: 'My Shelfwise backup: ${plural(store.totalBooks, 'book')}, ${plural(store.todos.length, 'to-do')}. '
            'Open Shelfwise → Settings → Import backup to restore it.',
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
    } catch (_) {
      toast('Couldn’t create the backup');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    final PlatformFile? f;
    try {
      f = await FilePicker.pickFile(type: FileType.any, dialogTitle: 'Choose a Shelfwise backup');
    } catch (_) {
      toast('Couldn’t open the file picker');
      return;
    }
    if (f == null) return;
    final BackupFile b;
    try {
      b = store.parseBackup(await f.readAsBytes());
    } on FormatException catch (e) {
      Sfx.play('knock');
      toast(e.message);
      return;
    } catch (_) {
      toast('Couldn’t read that file');
      return;
    }
    final when = b.exportedAt == null ? '' : ', saved ${fmtDate(b.exportedAt!.millisecondsSinceEpoch)}';
    final ok = await confirm(
      'Restore this backup?',
      'It has ${plural(b.books, 'book')} on ${plural(b.shelves, 'shelf', 'shelves')} and ${plural(b.todos, 'to-do')}$when. '
          'It replaces everything on this phone right now. PDF copies aren’t inside backups, so re-attach them if needed.',
      yes: 'Restore',
      no: 'Cancel',
      kind: Kind.pri,
    );
    if (!ok) return;
    await store.restore(b);
    await Notifier.sync();
    Sfx.play('reset');
    toast('Backup restored · welcome back, ${store.profile.first}!');
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final s = store.settings;
        var i = 0;
        Widget sec(Widget w) => FadeIn(delay: 60 * i++, dy: 12, child: w);
        return ListView(
          padding: EdgeInsets.fromLTRB(22, mq.padding.top + 26, 22, 120),
          children: [
            sec(const H1('Settings')),
            sec(Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Make Shelfwise feel like yours', style: nu(14, FontWeight.w600, C.muted)),
            )),
            const SizedBox(height: 18),
            sec(_profileCard()),
            sec(const H2('Appearance')),
            sec(CardBox(
              pad: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('Theme'),
                Row(children: [
                  for (final (k, l) in const [('light', 'Light'), ('dark', 'Dark'), ('system', 'System')]) ...[
                    Expanded(child: _ThemeTile(kind: k, label: l, on: s.theme == k, onTap: () => _set(() => s.theme = k, look: true))),
                    if (k != 'system') const SizedBox(width: 10),
                  ],
                ]),
                const SizedBox(height: 18),
                _label('Accent colour'),
                Wrap(spacing: 12, runSpacing: 10, children: [
                  for (final (ix, a) in accents.indexed)
                    _Swatch(accent: a, on: s.accent == ix, onTap: () => _set(() => s.accent = ix, look: true)),
                ]),
                const SizedBox(height: 18),
                _label('Font'),
                Row(children: [
                  for (final (f, d) in fontChoices) ...[
                    Expanded(child: _FontTile(font: f, desc: d, on: s.font == f, onTap: () => _set(() => s.font = f, look: true))),
                    if (f != fontChoices.last.$1) const SizedBox(width: 10),
                  ],
                ]),
                const SizedBox(height: 18),
                _label('Text size'),
                Row(children: [
                  for (final (v, l) in const [(.9, 'Small'), (1.0, 'Default'), (1.12, 'Large')]) ...[
                    PopChip(l,
                        on: s.textScale == v,
                        fontSize: 13,
                        pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        onTap: () => _set(() => s.textScale = v, look: true)),
                    const SizedBox(width: 8),
                  ],
                ]),
                const SizedBox(height: 12),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
                    child: Text('The owl read one more chapter before bed, as owls do.',
                        style: nu(15, FontWeight.w600, C.body, 1.4)),
                  ),
                ),
              ]),
            )),
            sec(const H2('Backup & restore')),
            sec(_card([
              _item('📤', 'Share backup',
                  sub: _busy ? 'Saving…' : (store.lastBackup == null ? 'Send a backup file to Drive, email or chat' : 'Last saved ${fmtDate(store.lastBackup!)}'),
                  onTap: _share),
              _item('📥', 'Import backup', sub: 'Restore from a Shelfwise backup file', onTap: _import),
            ])),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
              child: Text('Everything stays on this phone. Backups hold your shelves, to-dos, covers and progress. PDF copies aren’t included.',
                  style: nu(12, FontWeight.w600, C.muted, 1.4)),
            ),
            sec(const H2('Alerts')),
            sec(_card([
              _item('🔔', 'To-do reminders', sub: 'A nudge when a to-do is due', trailing: AppSwitch(value: s.reminders, onChanged: (v) async {
                if (v && !await Notifier.requestPermission()) toast('Allow notifications for Shelfwise in Android settings');
                _set(() => s.reminders = v);
                toast(v ? 'To-do reminders on' : 'To-do reminders off');
              })),
              _item('🌙', 'Evening reading nudge', sub: 'Every day at 8 PM', trailing: AppSwitch(value: s.dailyNudge, onChanged: (v) async {
                if (v && !await Notifier.requestPermission()) toast('Allow notifications for Shelfwise in Android settings');
                _set(() => s.dailyNudge = v);
                toast(v ? 'We’ll nudge you at 8 PM' : 'Evening nudge off');
              })),
            ])),
            sec(const H2('Feel')),
            sec(_card([
              _item('🔊', 'Sound effects', sub: 'Page turns, lamps, owls and tears', trailing: AppSwitch(value: s.sounds, onChanged: (v) {
                _set(() => s.sounds = v);
                if (v) Sfx.play('pop');
              })),
              _item('📳', 'Haptics', sub: 'Little taps under your finger', trailing: AppSwitch(value: s.haptics, onChanged: (v) {
                _set(() => s.haptics = v);
                Buzz.light();
              })),
            ])),
            sec(const H2('More')),
            sec(_card([
              _item('🎁', 'Rewards', sub: store.unclaimed.isEmpty ? 'See what’s next' : '${store.unclaimed.length} waiting for you', onTap: openRewards),
              _item('🔁', 'Replay intro', sub: 'See the welcome screens again', onTap: widget.onReplay),
              _item('ℹ️', 'About Shelfwise', sub: 'Version $appVersion', onTap: () => setState(() => _about = !_about), open: _about),
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: ease,
                child: _about ? _aboutBody() : const SizedBox(width: double.infinity),
              ),
            ])),
            const SizedBox(height: 26),
            Center(child: Opacity(opacity: .8, child: SvgPicture.string(owlSvg, width: 56, height: 51))),
            const SizedBox(height: 6),
            Text('Shelfwise $appVersion · made for readers', textAlign: TextAlign.center, style: nu(12, FontWeight.w700, C.muted)),
          ],
        );
      },
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t, style: nu(13, FontWeight.w800, C.chipText)),
      );

  Widget _profileCard() {
    final p = store.profile;
    return Pressable(
      onTap: widget.onProfile,
      scale: .98,
      child: CardBox(
        pad: const EdgeInsets.all(14),
        child: Row(children: [
          const MeAvatar(size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name.isEmpty ? 'Reader' : p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(18, FontWeight.w800)),
              Text('@${p.handle} · ${plural(store.totalBooks, 'book')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(13, FontWeight.w600, C.muted)),
            ]),
          ),
          Pill('Profile', kind: Kind.pri, size: 13, pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), onTap: widget.onProfile),
        ]),
      ),
    );
  }

  Widget _card(List<Widget> rows) => CardBox(
        pad: EdgeInsets.zero,
        child: Column(children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0 && r is! AnimatedSize) Divider(height: 1, color: C.line),
            r,
          ],
        ]),
      );

  Widget _item(String emoji, String title, {String? sub, VoidCallback? onTap, Widget? trailing, bool open = false}) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: nu(15, FontWeight.w800)),
            if (sub != null) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: nu(13, FontWeight.w600, C.muted)),
          ]),
        ),
        const SizedBox(width: 8),
        trailing ??
            AnimatedRotation(
              turns: open ? .25 : 0,
              duration: const Duration(milliseconds: 220),
              child: Text('›', style: nu(22, FontWeight.w700, C.muted)),
            ),
      ]),
    );
    return onTap == null ? row : Pressable(onTap: onTap, scale: .98, child: row);
  }

  Widget _aboutBody() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(children: [
          Text(
            'A cozy home for the books you love and the reading plans you make. No account, no ads. '
            'Use Share backup to keep a copy safe or to move to a new phone.',
            textAlign: TextAlign.center,
            style: nu(13, FontWeight.w600, C.body, 1.45),
          ),
          const SizedBox(height: 12),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            Pill('🌐 Website', size: 13, onTap: () => launchUrl(Uri.parse(siteUrl), mode: LaunchMode.externalApplication)),
            Pill('⬇️ Latest version', size: 13, onTap: () => launchUrl(Uri.parse('$repoUrl/releases/latest'), mode: LaunchMode.externalApplication)),
          ]),
        ]),
      );
}

/// A mini app preview for the theme picker.
class _ThemeTile extends StatelessWidget {
  final String kind, label;
  final bool on;
  final VoidCallback onTap;
  const _ThemeTile({required this.kind, required this.label, required this.on, required this.onTap});

  Widget _mini(Pal p) => Container(
        color: p.bg,
        padding: const EdgeInsets.all(6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 26, height: 5, decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(3))),
          const SizedBox(height: 5),
          Row(children: [
            for (final c in const [Color(0xFF1E1A14), Color(0xFFD9C493), Color(0xFFF26B2A)])
              Container(width: 9, height: 16, margin: const EdgeInsets.only(right: 2), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          ]),
          const SizedBox(height: 4),
          Container(height: 6, decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(3))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      label: '$label theme',
      child: Pressable(
        onTap: onTap,
        scale: .95,
        child: Column(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? C.brown : C.line, width: on ? 2.5 : 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: kind == 'system'
                  ? Row(children: [Expanded(child: _mini(lightPal)), Expanded(child: _mini(darkPal))])
                  : SizedBox(width: double.infinity, child: _mini(kind == 'dark' ? darkPal : lightPal)),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: nu(13, on ? FontWeight.w800 : FontWeight.w700, on ? C.brown : C.ink)),
        ]),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Accent accent;
  final bool on;
  final VoidCallback onTap;
  const _Swatch({required this.accent, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        label: '${accent.name} accent',
        child: Tooltip(
          message: accent.name,
          child: Pressable(
            onTap: onTap,
            scale: .85,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 42,
              height: 42,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? accent.color : Colors.transparent, width: 2.5)),
              child: Container(
                decoration: BoxDecoration(color: accent.color, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: AnimatedScale(
                  scale: on ? 1 : 0,
                  duration: const Duration(milliseconds: 260),
                  curve: popCurve,
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
          ),
        ),
      );
}

class _FontTile extends StatelessWidget {
  final String font, desc;
  final bool on;
  final VoidCallback onTap;
  const _FontTile({required this.font, required this.desc, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        label: '$font font',
        child: Pressable(
          onTap: onTap,
          scale: .95,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: on ? C.brown.withValues(alpha: .12) : C.bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? C.brown : C.line, width: on ? 2 : 1),
            ),
            child: Column(children: [
              Text('Aa', style: TextStyle(fontFamily: font, fontSize: 24, fontWeight: FontWeight.w700, color: on ? C.brown : C.ink)),
              Text(font, style: TextStyle(fontFamily: font, fontSize: 12, fontWeight: FontWeight.w700, color: C.ink)),
              Text(desc, style: nu(11, FontWeight.w600, C.muted)),
            ]),
          ),
        ),
      );
}

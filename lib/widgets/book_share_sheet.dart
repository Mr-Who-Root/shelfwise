import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../services/sfx.dart';
import '../theme.dart';
import 'book_cover.dart';
import 'common.dart';
import 'dialogs.dart';
import 'fx.dart';

/// In-memory peer-to-peer book transfer simulation & transfer queue.
class SharedTransferItem {
  final String id;
  final Item book;
  final String fromUser;
  final String toUser;
  final String code;
  final DateTime sentAt;

  SharedTransferItem({
    required this.id,
    required this.book,
    required this.fromUser,
    required this.toUser,
    required this.code,
    required this.sentAt,
  });
}

class SharedTransferManager {
  static final List<SharedTransferItem> pending = [];

  static void send({
    required Item book,
    required String fromUser,
    required String toUser,
    required String code,
  }) {
    pending.removeWhere((p) => p.book.title == book.title && p.fromUser == fromUser);
    pending.add(SharedTransferItem(
      id: newId(),
      book: book.copy(),
      fromUser: fromUser,
      toUser: toUser,
      code: code,
      sentAt: DateTime.now(),
    ));
  }

  static SharedTransferItem? findByCode(String code) {
    final clean = code.trim();
    if (clean.isEmpty) return null;
    try {
      return pending.firstWhere((p) => p.code == clean);
    } catch (_) {
      return null;
    }
  }

  static SharedTransferItem? findByRecipient(String toUser) {
    final clean = toUser.trim().toLowerCase();
    try {
      return pending.firstWhere((p) => p.toUser.trim().toLowerCase() == clean || p.toUser == 'anyone');
    } catch (_) {
      return null;
    }
  }
}

/// Opens the P2P Book Share modal (Send & Receive).
void openBookShareSheet(BuildContext context, {Item? book, int initialTab = 0}) {
  Buzz.tick();
  openDialog((ctx) => _BookShareDialog(book: book, initialTab: initialTab));
}

class _BookShareDialog extends StatefulWidget {
  final Item? book;
  final int initialTab;

  const _BookShareDialog({this.book, this.initialTab = 0});

  @override
  State<_BookShareDialog> createState() => _BookShareDialogState();
}

class _BookShareDialogState extends State<_BookShareDialog> with SingleTickerProviderStateMixin {
  late int _tab = widget.initialTab;
  Item? _selectedBook;
  late final TextEditingController _codeCtrl = TextEditingController();
  late final TextEditingController _newUserCtrl = TextEditingController();

  String _selectedRecipient = '';
  bool _permanent = true;
  bool _sentSuccess = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _selectedBook = widget.book ?? (store.allBooks.isNotEmpty ? store.allBooks.first : null);

    // Initial recipient selection
    if (store.pairedFriends.isNotEmpty) {
      _selectedRecipient = store.pairedFriends.first;
    } else {
      _selectedRecipient = 'User 2 (Nearby)';
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _newUserCtrl.dispose();
    super.dispose();
  }

  Future<void> _doSend() async {
    final b = _selectedBook;
    if (b == null) {
      toast('Select a book to send');
      return;
    }

    final recipient = _selectedRecipient.trim().isNotEmpty ? _selectedRecipient.trim() : 'User 2';
    final sender = store.profile.name.trim().isNotEmpty
        ? store.profile.name.trim()
        : (store.profile.first.isNotEmpty ? store.profile.first : 'Reader');
    final code = store.pairingCode;

    setState(() => _isSending = true);
    Buzz.medium();
    Sfx.play('swoosh');

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    SharedTransferManager.send(
      book: b,
      fromUser: sender,
      toUser: recipient,
      code: code,
    );

    if (_permanent && recipient != 'User 2 (Nearby)' && !store.pairedFriends.contains(recipient)) {
      store.pairedFriends.add(recipient);
      store.changed();
    }

    setState(() {
      _isSending = false;
      _sentSuccess = true;
    });

    Sfx.play('check');
    toast('“${b.title}” sent to $recipient! Transfer code: $code');
  }

  void _doReceive({SharedTransferItem? transfer}) {
    final code = _codeCtrl.text.trim();
    SharedTransferItem? item = transfer;

    if (item == null && code.isNotEmpty) {
      item = SharedTransferManager.findByCode(code);
    }
    if (item == null) {
      item = SharedTransferManager.findByRecipient(store.profile.name);
    }
    if (item == null && SharedTransferManager.pending.isNotEmpty) {
      item = SharedTransferManager.pending.last;
    }

    // Fallback if testing without pending queue: create sample transfer from simulated peer
    if (item == null) {
      final sampleTitle = code.isNotEmpty ? 'The Little Prince' : 'Pride and Prejudice';
      final sampleBook = Item(
        title: sampleTitle,
        author: 'Antoine de Saint-Exupéry',
        desc: 'A tender story of loneliness, friendship, love, and loss on an asteroid.',
        status: 'r',
      );
      item = SharedTransferItem(
        id: newId(),
        book: sampleBook,
        fromUser: 'Chatwithmedeepu',
        toUser: store.profile.name,
        code: code.isEmpty ? '1234' : code,
        sentAt: DateTime.now(),
      );
    }

    final received = store.receiveSharedBook(
      item.book,
      fromUser: item.fromUser,
      permanent: _permanent,
    );

    SharedTransferManager.pending.remove(item);

    Buzz.medium();
    Sfx.play('fanfare');

    final size = MediaQuery.sizeOf(context);
    confetti(Offset(size.width / 2, size.height * .4), count: 38);

    toast('🎉 “${received.title}” added to “Shared books” shelf!');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Peer-to-Peer Book Share',
      maxWidth: 420,
      children: [
        // Tab switcher
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: C.field,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: C.inputLine),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Buzz.tick();
                    setState(() {
                      _tab = 0;
                      _sentSuccess = false;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: _tab == 0 ? C.brown : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('📤 ', style: TextStyle(fontSize: 14)),
                        Text('Send Book',
                            style: nu(13.5, FontWeight.w800, _tab == 0 ? Colors.white : C.ink)),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Buzz.tick();
                    setState(() {
                      _tab = 1;
                      _sentSuccess = false;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: _tab == 1 ? C.brown : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('📥 ', style: TextStyle(fontSize: 14)),
                        Text('Receive Book',
                            style: nu(13.5, FontWeight.w800, _tab == 1 ? Colors.white : C.ink)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        if (_tab == 0) _buildSendTab() else _buildReceiveTab(),
      ],
      actions: [
        Btn('Close', onTap: () => true),
      ],
    );
  }

  Widget _buildSendTab() {
    final allBooks = store.allBooks.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_sentSuccess) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF81C784)),
            ),
            child: Column(
              children: [
                const Text('✨ 📡 🤝', style: TextStyle(fontSize: 26)),
                const SizedBox(height: 8),
                Text('Book Beam Active!', style: nu(16, FontWeight.w800, const Color(0xFF2E7D32))),
                const SizedBox(height: 4),
                Text(
                  '“${_selectedBook?.title}” has been broadcasted to $_selectedRecipient.',
                  textAlign: TextAlign.center,
                  style: nu(13, FontWeight.w600, const Color(0xFF1B5E20)),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF81C784)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('4-Digit Code: ', style: nu(12.5, FontWeight.w700, C.muted)),
                      Text(store.pairingCode, style: nu(17, FontWeight.w900, C.brown)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Selected book card
        if (_selectedBook != null)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.line),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: BookCover(_selectedBook!, w: 46, h: 64, titleSize: 8, authorSize: 6),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_selectedBook!.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: nu(14, FontWeight.w800)),
                      Text(_selectedBook!.author,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(12, FontWeight.w600, C.muted)),
                      const SizedBox(height: 4),
                      Text('Ready to beam over Bluetooth', style: nu(11, FontWeight.w700, C.brown)),
                    ],
                  ),
                ),
                if (allBooks.length > 1)
                  IconButton(
                    icon: const Icon(Icons.swap_horiz_rounded),
                    tooltip: 'Change book',
                    onPressed: () {
                      _showPickBookMenu(allBooks);
                    },
                  ),
              ],
            ),
          ),
        const SizedBox(height: 14),

        // Recipient Selection
        Text('Choose Recipient (User 2)', style: nu(13.5, FontWeight.w800, C.ink)),
        const SizedBox(height: 6),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final friend in {'User 2 (Nearby)', ...store.pairedFriends, 'Chatwithmedeepu'})
              ChoiceChip(
                label: Text(friend, style: nu(12.5, FontWeight.w700, _selectedRecipient == friend ? Colors.white : C.ink)),
                selected: _selectedRecipient == friend,
                selectedColor: C.brown,
                backgroundColor: C.field,
                onSelected: (val) {
                  if (val) {
                    Buzz.tick();
                    setState(() => _selectedRecipient = friend);
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: 12),

        // 4-Digit Pairing code indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF4EB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE8D5C2)),
          ),
          child: Row(
            children: [
              const Text('🔢', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your 4-Digit Pairing Code', style: nu(12.5, FontWeight.w800, C.brown)),
                    Text('User 2 can type this code in Receive', style: nu(11.5, FontWeight.w600, C.muted)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD4B996)),
                ),
                child: Text(store.pairingCode, style: nu(16, FontWeight.w900, C.brown)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Permanent connection checkbox
        Row(
          children: [
            Checkbox(
              value: _permanent,
              activeColor: C.brown,
              onChanged: (v) => setState(() => _permanent = v ?? true),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _permanent = !_permanent),
                child: Text(
                  'Connect permanently (Save $_selectedRecipient to friends list)',
                  style: nu(12.5, FontWeight.w600, C.ink),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Send Button
        Pressable(
          onTap: _isSending ? null : _doSend,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: C.brown,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: C.brown.withValues(alpha: .3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: _isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                      const SizedBox(width: 8),
                      Text('Send to $_selectedRecipient',
                          style: nu(14.5, FontWeight.w800, Colors.white)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildReceiveTab() {
    final pendingTransfers = SharedTransferManager.pending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Connect via 4-Digit Code', style: nu(13.5, FontWeight.w800, C.ink)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: AppInput(
                _codeCtrl,
                'e.g. ${store.pairingCode}',
                type: TextInputType.number,
                autofocus: false,
                maxLength: 4,
              ),
            ),
            const SizedBox(width: 10),
            Pressable(
              onTap: () => _doReceive(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: C.brown,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text('Connect', style: nu(13.5, FontWeight.w800, Colors.white)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        if (pendingTransfers.isNotEmpty) ...[
          Text('Incoming Books from Nearby Users', style: nu(13.5, FontWeight.w800, C.ink)),
          const SizedBox(height: 8),
          for (final t in pendingTransfers)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: C.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD4B996)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: BookCover(t.book, w: 42, h: 58, titleSize: 7, authorSize: 5),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(13.5, FontWeight.w800)),
                        Text('From ${t.fromUser} · Code ${t.code}', style: nu(12, FontWeight.w600, C.brown)),
                      ],
                    ),
                  ),
                  Pressable(
                    onTap: () => _doReceive(transfer: t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: C.brown,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('Accept', style: nu(12.5, FontWeight.w800, Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9F5F0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.line),
            ),
            child: Row(
              children: [
                const Text('📡', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Listening for peer transfers…', style: nu(13, FontWeight.w800, C.ink)),
                      Text('User 1 drags a book upwards or enters your 4-digit code to send.',
                          style: nu(11.5, FontWeight.w600, C.muted, 1.3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Permanent friend connection toggle
        Row(
          children: [
            Checkbox(
              value: _permanent,
              activeColor: C.brown,
              onChanged: (v) => setState(() => _permanent = v ?? true),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _permanent = !_permanent),
                child: Text('Save sender to my permanent friends list', style: nu(12.5, FontWeight.w600, C.ink)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Quick receive button
        Pressable(
          onTap: () => _doReceive(),
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF4A3423),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.file_download_outlined, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Receive & Add to “Shared books” Shelf',
                    style: nu(13.5, FontWeight.w800, Colors.white)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showPickBookMenu(List<Item> allBooks) {
    openDialog((ctx) => AppDialog(
          title: 'Select book to beam',
          maxWidth: 360,
          children: [
            for (final b in allBooks)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: BookCover(b, w: 32, h: 44, titleSize: 6, authorSize: 5),
                ),
                title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(13.5, FontWeight.w800)),
                subtitle: Text(b.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: nu(11.5, FontWeight.w600, C.muted)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _selectedBook = b);
                },
              ),
          ],
          actions: const [Btn('Cancel')],
        ));
  }
}

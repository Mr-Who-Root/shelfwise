import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../services/sfx.dart';
import '../theme.dart';
import 'book_cover.dart';
import 'common.dart';
import 'dialogs.dart';
import 'fx.dart';

/// Real peer-to-peer .shelfbook archive package helper.
/// Packages the book's metadata, progress, cover image, and attached PDF/EPUB copy.
class ShelfBookPackage {
  static Future<File> export(Item book) async {
    final archive = Archive();

    // 1. Metadata
    final jsonBytes = utf8.encode(jsonEncode(book.toJson()));
    archive.addFile(ArchiveFile('book.json', jsonBytes.length, jsonBytes));

    // 2. Cover image
    if (book.cover != null) {
      final cFile = store.imageFile(book.cover!);
      if (cFile.existsSync()) {
        final cBytes = await cFile.readAsBytes();
        archive.addFile(ArchiveFile('cover.img', cBytes.length, cBytes));
      }
    }

    // 3. Attached PDF or EPUB copy
    if (book.file != null) {
      final bFile = store.bookFile(book.file!);
      if (bFile.existsSync()) {
        final fBytes = await bFile.readAsBytes();
        archive.addFile(ArchiveFile('content.dat', fBytes.length, fBytes));
      }
    }

    final zipBytes = ZipEncoder().encode(archive);
    final tempDir = await getTemporaryDirectory();
    final safeTitle = book.title.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]+'), '_').trim();
    final outName = safeTitle.isEmpty ? 'shelfwise_book' : safeTitle;
    final file = File('${tempDir.path}/$outName.shelfbook');
    await file.writeAsBytes(zipBytes, flush: true);
    return file;
  }

  static Future<Item?> unpack(Uint8List zipBytes, {required String fromUser, bool permanent = false}) async {
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes);
      Item? book;
      Uint8List? coverBytes;
      Uint8List? contentBytes;

      for (final f in archive) {
        if (f.name == 'book.json') {
          final content = f.content as List<int>;
          final map = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
          book = Item.fromJson(map);
        } else if (f.name == 'cover.img') {
          coverBytes = Uint8List.fromList(f.content as List<int>);
        } else if (f.name == 'content.dat') {
          contentBytes = Uint8List.fromList(f.content as List<int>);
        }
      }

      if (book == null) return null;

      // Save unpacked cover
      if (coverBytes != null) {
        final coverName = '${newId()}.jpg';
        final coverFile = store.imageFile(coverName);
        await coverFile.writeAsBytes(coverBytes, flush: true);
        book.cover = coverName;
      }

      // Save unpacked book copy
      if (contentBytes != null && book.file != null) {
        final ext = book.file!.endsWith('.epub') ? 'epub' : 'pdf';
        final fileName = '${newId()}.$ext';
        final bFile = store.bookFile(fileName);
        await bFile.writeAsBytes(contentBytes, flush: true);
        book.file = fileName;
      }

      return store.receiveSharedBook(book, fromUser: fromUser, permanent: permanent);
    } catch (e) {
      debugPrint('Error unpacking .shelfbook package: $e');
      return null;
    }
  }
}

/// In-memory queue for live active wireless transfers.
class SharedTransferItem {
  final String id;
  final Item book;
  final String fromUser;
  final String toUser;
  final String code;
  final DateTime sentAt;
  final Uint8List? rawBytes;

  SharedTransferItem({
    required this.id,
    required this.book,
    required this.fromUser,
    required this.toUser,
    required this.code,
    required this.sentAt,
    this.rawBytes,
  });
}

class SharedTransferManager {
  static final List<SharedTransferItem> pending = [];

  static void send({
    required Item book,
    required String fromUser,
    required String toUser,
    required String code,
    Uint8List? rawBytes,
  }) {
    pending.removeWhere((p) => p.book.title == book.title && p.fromUser == fromUser);
    pending.add(SharedTransferItem(
      id: newId(),
      book: book.copy(),
      fromUser: fromUser,
      toUser: toUser,
      code: code,
      sentAt: DateTime.now(),
      rawBytes: rawBytes,
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

/// Real live in-app wireless receiver server listening on port 8942.
class LiveReceiverServer {
  static HttpServer? _server;
  static String? _localIp;

  static bool get isListening => _server != null;
  static String? get localIp => _localIp;

  static Future<String?> refreshIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            _localIp = addr.address;
            return _localIp;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> startServer({
    required BuildContext context,
    required void Function(Item book, String sender) onAccepted,
  }) async {
    if (_server != null) return true;
    try {
      await refreshIp();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8942);
      _server!.listen((HttpRequest request) async {
        if (request.method == 'POST' && request.uri.path == '/send-book') {
          try {
            final sender = request.headers.value('x-sender') ?? 'Nearby Reader';
            final code = request.headers.value('x-pair-code') ?? '';
            final bodyBytes = await request.fold<List<int>>([], (prev, elem) => prev..addAll(elem));

            if (code.isNotEmpty && code != store.pairingCode) {
              request.response
                ..statusCode = HttpStatus.forbidden
                ..write(jsonEncode({'error': 'Incorrect pairing code'}))
                ..close();
              return;
            }

            final archive = ZipDecoder().decodeBytes(bodyBytes);
            ArchiveFile? jsonFile;
            for (final f in archive) {
              if (f.name == 'book.json') {
                jsonFile = f;
                break;
              }
            }

            if (jsonFile == null) {
              request.response
                ..statusCode = HttpStatus.badRequest
                ..write(jsonEncode({'error': 'Invalid book package'}))
                ..close();
              return;
            }

            final map = jsonDecode(utf8.decode(jsonFile.content as List<int>)) as Map<String, dynamic>;
            final candidate = Item.fromJson(map);

            if (!context.mounted) {
              request.response
                ..statusCode = HttpStatus.serviceUnavailable
                ..close();
              return;
            }

            Sfx.play('pop');
            Buzz.medium();
            final accept = await confirm(
              'Incoming Book Share',
              '“${candidate.title}” by ${candidate.author}\n\n'
              'Sent from $sender. Accept and add this book to your “Shared books” shelf?',
              yes: 'Accept Book',
              no: 'Decline',
              kind: Kind.pri,
            );

            if (accept) {
              final received = await ShelfBookPackage.unpack(
                Uint8List.fromList(bodyBytes),
                fromUser: sender,
                permanent: true,
              );
              if (received != null) {
                onAccepted(received, sender);
                request.response
                  ..statusCode = HttpStatus.ok
                  ..write(jsonEncode({'status': 'accepted', 'title': received.title}))
                  ..close();
                return;
              }
            }

            request.response
              ..statusCode = HttpStatus.forbidden
              ..write(jsonEncode({'error': 'Declined by recipient'}))
              ..close();
          } catch (e) {
            request.response
              ..statusCode = HttpStatus.internalServerError
              ..close();
          }
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });
      return true;
    } catch (e) {
      debugPrint('Failed to start LiveReceiverServer: $e');
      return false;
    }
  }

  static void stopServer() {
    _server?.close(force: true);
    _server = null;
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
  late final TextEditingController _targetIpCtrl = TextEditingController();

  String _selectedRecipient = '';
  bool _permanent = true;
  bool _sentSuccess = false;
  bool _isSending = false;
  bool _isExporting = false;
  bool _isLiveReceiverOn = false;
  String? _myIp;

  @override
  void initState() {
    super.initState();
    _selectedBook = widget.book ?? (store.allBooks.isNotEmpty ? store.allBooks.first : null);

    if (store.pairedFriends.isNotEmpty) {
      _selectedRecipient = store.pairedFriends.first;
    } else {
      _selectedRecipient = 'User 2 (Nearby)';
    }

    _initReceiverInfo();
  }

  Future<void> _initReceiverInfo() async {
    _myIp = await LiveReceiverServer.refreshIp();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _targetIpCtrl.dispose();
    super.dispose();
  }

  /// Sends the selected book via native Bluetooth / Quick Share system sheet.
  Future<void> _shareViaBluetooth() async {
    final b = _selectedBook;
    if (b == null) {
      toast('Select a book to share');
      return;
    }

    setState(() => _isExporting = true);
    Buzz.medium();
    Sfx.play('swoosh');

    try {
      final packageFile = await ShelfBookPackage.export(b);
      if (!mounted) return;

      final box = context.findRenderObject() as RenderBox?;
      toast('Scanning for nearest Bluetooth & Quick Share devices…');

      await SharePlus.instance.share(ShareParams(
        files: [XFile(packageFile.path, mimeType: 'application/octet-stream', name: '${b.title}.shelfbook')],
        subject: 'Shelfwise Book: ${b.title}',
        text: 'Sharing “${b.title}” by ${b.author} from Shelfwise. Open with Shelfwise or accept via Bluetooth in Shelfwise!',
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));

      if (mounted) {
        setState(() {
          _isExporting = false;
          _sentSuccess = true;
        });
      }
    } catch (e) {
      debugPrint('Bluetooth share error: $e');
      toast('Couldn’t package book for Bluetooth sharing');
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Sends the selected book directly to a receiver via local Wi-Fi / Hotspot HTTP POST.
  Future<void> _shareViaDirectWifi() async {
    final b = _selectedBook;
    if (b == null) {
      toast('Select a book to send');
      return;
    }

    final targetIp = _targetIpCtrl.text.trim();
    if (targetIp.isEmpty) {
      toast('Enter the receiver’s Wi-Fi / Hotspot IP address');
      return;
    }

    setState(() => _isSending = true);
    Buzz.medium();
    Sfx.play('swoosh');

    try {
      final packageFile = await ShelfBookPackage.export(b);
      final bytes = await packageFile.readAsBytes();

      final sender = store.profile.name.trim().isNotEmpty
          ? store.profile.name.trim()
          : (store.profile.first.isNotEmpty ? store.profile.first : 'Reader');

      final uri = Uri.parse('http://$targetIp:8942/send-book');
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);

      final req = await client.postUrl(uri);
      req.headers.set('x-sender', sender);
      req.headers.set('x-pair-code', store.pairingCode);
      req.headers.set('content-type', 'application/octet-stream');
      req.add(bytes);

      final resp = await req.close();
      final respBody = await utf8.decodeStream(resp);

      if (!mounted) return;
      setState(() => _isSending = false);

      if (resp.statusCode == HttpStatus.ok) {
        Sfx.play('fanfare');
        toast('🎉 “${b.title}” was accepted by $targetIp!');
        setState(() => _sentSuccess = true);
      } else {
        Sfx.play('knock');
        toast('Transfer declined or not accepted by recipient ($respBody)');
      }
    } catch (e) {
      debugPrint('Direct Wi-Fi send error: $e');
      if (mounted) {
        setState(() => _isSending = false);
        toast('Could not reach $targetIp:8942. Ensure receiver is running Live Receiver on the same Wi-Fi/Hotspot.');
      }
    }
  }

  /// Lets receiver pick an incoming .shelfbook file transferred via Bluetooth or downloaded.
  Future<void> _pickAndAcceptBluetoothBook() async {
    Buzz.tick();
    final PlatformFile? f;
    try {
      f = await FilePicker.pickFile(
        type: FileType.any,
        dialogTitle: 'Select received .shelfbook from Bluetooth or Downloads',
      );
    } catch (_) {
      toast('Couldn’t open the file picker');
      return;
    }

    if (f == null) return;
    final bytes = f.path != null && File(f.path!).existsSync()
        ? await File(f.path!).readAsBytes()
        : await f.readAsBytes();

    try {
      // Decode archive to preview
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? jsonFile;
      for (final entry in archive) {
        if (entry.name == 'book.json') {
          jsonFile = entry;
          break;
        }
      }

      if (jsonFile == null) {
        Sfx.play('knock');
        toast('This is not a valid Shelfwise .shelfbook package');
        return;
      }

      final map = jsonDecode(utf8.decode(jsonFile.content as List<int>)) as Map<String, dynamic>;
      final candidate = Item.fromJson(map);

      final ok = await confirm(
        'Accept Bluetooth Book?',
        '“${candidate.title}” by ${candidate.author}\n\n'
        'Received from Bluetooth device. Accept and add this book to your “Shared books” shelf?',
        yes: 'Accept & Add',
        no: 'Decline',
        kind: Kind.pri,
      );

      if (!ok) return;

      final received = await ShelfBookPackage.unpack(bytes, fromUser: 'Bluetooth Peer', permanent: _permanent);
      if (received != null && mounted) {
        Buzz.medium();
        Sfx.play('fanfare');
        final size = MediaQuery.sizeOf(context);
        confetti(Offset(size.width / 2, size.height * .4), count: 40);
        toast('🎉 “${received.title}” added to “Shared books” shelf!');
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Error importing bluetooth book: $e');
      toast('Failed to read or accept this book file');
    }
  }

  void _toggleLiveReceiver(bool on) async {
    setState(() => _isLiveReceiverOn = on);
    if (on) {
      final started = await LiveReceiverServer.startServer(
        context: context,
        onAccepted: (book, sender) {
          if (!mounted) return;
          Buzz.medium();
          Sfx.play('fanfare');
          final size = MediaQuery.sizeOf(context);
          confetti(Offset(size.width / 2, size.height * .4), count: 40);
          toast('🎉 “${book.title}” from $sender added to “Shared books” shelf!');
        },
      );
      if (started) {
        _myIp = LiveReceiverServer.localIp;
        toast('Live Receiver active! Ready to accept incoming wireless transfers.');
      } else {
        setState(() => _isLiveReceiverOn = false);
        toast('Could not start receiver server on port 8942');
      }
    } else {
      LiveReceiverServer.stopServer();
      toast('Live Receiver stopped');
    }
    setState(() {});
  }

  void _doReceiveWithCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      toast('Enter sender’s 4-digit pairing code');
      return;
    }

    final item = SharedTransferManager.findByCode(code);
    if (item == null) {
      toast('No pending transfer found for code $code. Ask sender to send or use Bluetooth file transfer.');
      return;
    }

    final ok = await confirm(
      'Accept Incoming Book?',
      '“${item.book.title}” by ${item.book.author}\n\nFrom ${item.fromUser}. Accept and add to your “Shared books” shelf?',
      yes: 'Accept',
      no: 'Decline',
      kind: Kind.pri,
    );

    if (!ok) return;

    final received = store.receiveSharedBook(
      item.book,
      fromUser: item.fromUser,
      permanent: _permanent,
    );
    SharedTransferManager.pending.remove(item);

    if (mounted) {
      Buzz.medium();
      Sfx.play('fanfare');
      final size = MediaQuery.sizeOf(context);
      confetti(Offset(size.width / 2, size.height * .4), count: 38);
      toast('🎉 “${received.title}” added to “Shared books” shelf!');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Peer-to-Peer Book Share',
      maxWidth: 430,
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
                        const Text('📤 ', style: TextStyle(fontSize: 14)),
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
                        const Text('📥 ', style: TextStyle(fontSize: 14)),
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
      actions: const [
        Btn('Close', onTap: null),
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
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF81C784)),
            ),
            child: Column(
              children: [
                const Text('✨ 📡 🤝', style: TextStyle(fontSize: 26)),
                const SizedBox(height: 6),
                Text('Book Beam Initiated!', style: nu(15.5, FontWeight.w800, const Color(0xFF2E7D32))),
                const SizedBox(height: 4),
                Text(
                  '“${_selectedBook?.title}” packaged and ready for recipient acceptance.',
                  textAlign: TextAlign.center,
                  style: nu(12.5, FontWeight.w600, const Color(0xFF1B5E20)),
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
                      Text('Only this selected book will be shared', style: nu(11, FontWeight.w700, C.brown)),
                    ],
                  ),
                ),
                if (allBooks.length > 1)
                  IconButton(
                    icon: const Icon(Icons.swap_horiz_rounded),
                    tooltip: 'Change selected book',
                    onPressed: () {
                      _showPickBookMenu(allBooks);
                    },
                  ),
              ],
            ),
          ),
        const SizedBox(height: 14),

        // Primary: Bluetooth / Quick Share
        Pressable(
          onTap: _isExporting ? null : _shareViaBluetooth,
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1565C0).withValues(alpha: .35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: _isExporting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bluetooth_searching_rounded, size: 20, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Scan & Share via Bluetooth / Quick Share',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),

        // Secondary: Direct Wi-Fi / Hotspot IP Beam
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFAF7F2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: C.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('📶 ', style: TextStyle(fontSize: 15)),
                  Text('Direct Wireless Beam (Wi-Fi / Hotspot)', style: nu(13, FontWeight.w800, C.ink)),
                ],
              ),
              const SizedBox(height: 6),
              Text('Beam directly to User 2 on the same network running Live Receiver:',
                  style: nu(11.5, FontWeight.w600, C.muted)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: AppInput(
                      _targetIpCtrl,
                      'Receiver IP (e.g. 192.168.1.50)',
                      type: TextInputType.text,
                      autofocus: false,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pressable(
                    onTap: _isSending ? null : _shareViaDirectWifi,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: C.brown,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _isSending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text('Beam', style: nu(13, FontWeight.w800, Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

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
                    Text('Your 4-Digit Security Code', style: nu(12.5, FontWeight.w800, C.brown)),
                    Text('Receiver accepts using this verification code', style: nu(11.5, FontWeight.w600, C.muted)),
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
      ],
    );
  }

  Widget _buildReceiveTab() {
    final pendingTransfers = SharedTransferManager.pending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Accept Received Bluetooth Book
        Pressable(
          onTap: _pickAndAcceptBluetoothBook,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2E7D32).withValues(alpha: .3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.file_download_done_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Import Received Bluetooth Book',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                      const SizedBox(height: 2),
                      Text('Pick & accept .shelfbook file received via Bluetooth',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: .85))),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 2. Live Wireless Receiver Toggle
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: C.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _isLiveReceiverOn ? const Color(0xFF81C784) : C.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('📡 ', style: TextStyle(fontSize: 18)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Live Wireless Receiver', style: nu(13.5, FontWeight.w800, C.ink)),
                        Text(
                          _isLiveReceiverOn
                              ? 'Listening on ${_myIp ?? 'Local Network'}:8942'
                              : 'Accept real-time beams from nearby senders',
                          style: nu(11.5, FontWeight.w600, _isLiveReceiverOn ? const Color(0xFF2E7D32) : C.muted),
                        ),
                      ],
                    ),
                  ),
                  AppSwitch(
                    value: _isLiveReceiverOn,
                    onChanged: _toggleLiveReceiver,
                  ),
                ],
              ),
              if (_isLiveReceiverOn && _myIp != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 6),
                      Text('Sender can beam to IP: $_myIp', style: nu(12, FontWeight.w700, const Color(0xFF2E7D32))),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. Connect via 4-Digit Code
        Text('Accept Transfer with 4-Digit Code', style: nu(13, FontWeight.w800, C.ink)),
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
            const SizedBox(width: 8),
            Pressable(
              onTap: _doReceiveWithCode,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: C.brown,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text('Accept', style: nu(13, FontWeight.w800, Colors.white)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Active incoming list
        if (pendingTransfers.isNotEmpty) ...[
          Text('Incoming Book Transfers', style: nu(13, FontWeight.w800, C.ink)),
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
                    onTap: () async {
                      final ok = await confirm(
                        'Accept Book Transfer?',
                        '“${t.book.title}” by ${t.book.author}\n\nFrom ${t.fromUser}. Add to your “Shared books” shelf?',
                        yes: 'Accept',
                        no: 'Decline',
                        kind: Kind.pri,
                      );
                      if (ok) {
                        final received = store.receiveSharedBook(t.book, fromUser: t.fromUser, permanent: _permanent);
                        SharedTransferManager.pending.remove(t);
                        if (mounted) {
                          Buzz.medium();
                          Sfx.play('fanfare');
                          final size = MediaQuery.sizeOf(context);
                          confetti(Offset(size.width / 2, size.height * .4), count: 38);
                          toast('🎉 “${received.title}” added to “Shared books” shelf!');
                          Navigator.of(context).pop();
                        }
                      }
                    },
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9F5F0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.line),
            ),
            child: Row(
              children: [
                const Text('ℹ️', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No incoming transfers in queue. Senders can beam books via Bluetooth or live network; tap “Import Received Bluetooth Book” above to accept any incoming book file.',
                    style: nu(11.5, FontWeight.w600, C.muted, 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
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

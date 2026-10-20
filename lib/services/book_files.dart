import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:pdfx/pdfx.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../widgets/common.dart';

/// A PDF copied into the app, ready to hang on a book.
class PickedCopy {
  final String file;
  final int pages;
  final String suggestedTitle;
  final int bytes;
  PickedCopy(this.file, this.pages, this.suggestedTitle, this.bytes);
}

/// Lets the person pick a PDF from their phone and copies it into Shelfwise.
/// Returns null when cancelled or when the file isn't a readable PDF.
Future<PickedCopy?> pickBookCopy() async {
  final PlatformFile? f;
  try {
    f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf'], dialogTitle: 'Choose your copy (PDF)');
  } catch (_) {
    toast('Couldn’t open the file picker');
    return null;
  }
  if (f == null) return null;
  if (!f.name.toLowerCase().endsWith('.pdf')) {
    toast('Pick a PDF file');
    return null;
  }
  toast('Copying ${f.name}…');
  final name = '${newId()}.pdf';
  final dest = store.bookFile(name);
  try {
    final src = f.path;
    if (src != null && File(src).existsSync()) {
      await File(src).copy(dest.path);
    } else {
      await dest.writeAsBytes(await f.readAsBytes(), flush: true);
    }
    final doc = await PdfDocument.openFile(dest.path);
    final pages = doc.pagesCount;
    await doc.close();
    if (pages <= 0) throw const FormatException('empty');
    return PickedCopy(name, pages, titleFromFile(f.name), dest.lengthSync());
  } catch (_) {
    if (dest.existsSync()) dest.deleteSync();
    toast('That PDF couldn’t be opened');
    return null;
  }
}

/// "web-hacking-101.pdf" → "Web Hacking 101".
String titleFromFile(String name) {
  final base = name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '').replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  return base
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : (w == w.toLowerCase() ? w[0].toUpperCase() + w.substring(1) : w))
      .join(' ');
}

String fmtSize(int bytes) =>
    bytes > 1 << 20 ? '${(bytes / (1 << 20)).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';

/// Attaches a picked copy to an existing book (replacing any older one).
void attachCopy(Item b, PickedCopy c) {
  final old = b.file;
  b
    ..file = c.file
    ..pages = c.pages
    ..page = 0;
  store.changed();
  if (old != null && old != c.file) {
    final f = store.bookFile(old);
    if (f.existsSync()) f.deleteSync();
  }
}

void detachCopy(Item b) {
  final old = b.file;
  b
    ..file = null
    ..pages = 0
    ..page = 0
    ..readAt = null;
  store.changed();
  if (old != null) {
    final f = store.bookFile(old);
    if (f.existsSync()) f.deleteSync();
  }
}

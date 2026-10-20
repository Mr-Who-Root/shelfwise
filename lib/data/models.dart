import 'dart:math';

final _rnd = Random();
String newId() =>
    DateTime.now().microsecondsSinceEpoch.toRadixString(36) + _rnd.nextInt(1 << 20).toRadixString(36);

/// A bookmark (empty [note]) or a note on one page of a book's copy.
class Mark {
  int page;
  int pos; // EPUB character offset of the page, so marks survive re-pagination
  String note;
  int at;
  Mark({required this.page, this.pos = -1, this.note = '', int? at}) : at = at ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {'p': page, if (pos >= 0) 'o': pos, if (note.isNotEmpty) 'n': note, 'at': at};
  factory Mark.fromJson(Map<String, dynamic> j) => Mark(
        page: (j['p'] as num?)?.toInt() ?? 0,
        pos: (j['o'] as num?)?.toInt() ?? -1,
        note: (j['n'] ?? '') as String,
        at: (j['at'] as num?)?.toInt(),
      );
}

/// Something that sits on a shelf: a book, or a decoration when [gadget] is set.
class Item {
  String id;
  String? gadget;
  String title;
  String author;
  String desc;
  String status; // 'r' reading, 'f' finished
  String? cover; // file name inside the app's images folder
  bool sub; // lives on the sub shelf
  List<String> tags; // headings this book is filed under
  int addedAt;
  int? finishedAt;
  bool lit; // lamps and candles remember whether they're on
  String? file; // attached PDF, inside the app's books folder
  int pages; // page count of the attached PDF
  int page; // last page read (0-based)
  int? readAt; // when it was last opened in the reader
  int pos; // EPUB: character offset of the last page read
  int rating; // 0 = not rated, 1..5 stars
  int readMs; // time spent reading this book's copy
  List<Mark> marks;
  String isbn;

  Item({
    String? id,
    this.gadget,
    this.title = '',
    this.author = '',
    this.desc = '',
    this.status = 'r',
    this.cover,
    this.sub = false,
    List<String>? tags,
    int? addedAt,
    this.finishedAt,
    this.lit = false,
    this.file,
    this.pages = 0,
    this.page = 0,
    this.readAt,
    this.pos = 0,
    this.rating = 0,
    this.readMs = 0,
    List<Mark>? marks,
    this.isbn = '',
  })  : id = id ?? newId(),
        marks = marks ?? [],
        tags = tags ?? [],
        addedAt = addedAt ?? DateTime.now().millisecondsSinceEpoch;

  bool get isDecor => gadget != null;
  bool get hasCopy => file != null;
  bool get isEpub => file != null && file!.toLowerCase().endsWith('.epub');
  bool get finished => status == 'f';

  Item.decor(String key, {bool sub = false}) : this(gadget: key, sub: sub);

  Map<String, dynamic> toJson() => {
        'id': id,
        if (gadget != null) 'g': gadget,
        if (!isDecor) ...{
          't': title,
          'a': author,
          'd': desc,
          's': status,
          if (cover != null) 'img': cover,
          if (tags.isNotEmpty) 'tags': tags,
          if (finishedAt != null) 'fin': finishedAt,
          if (file != null) 'file': file,
          if (pages > 0) 'pages': pages,
          if (page > 0) 'page': page,
          if (readAt != null) 'readAt': readAt,
          if (pos > 0) 'pos': pos,
          if (rating > 0) 'rating': rating,
          if (readMs > 0) 'readMs': readMs,
          if (marks.isNotEmpty) 'marks': marks.map((e) => e.toJson()).toList(),
          if (isbn.isNotEmpty) 'isbn': isbn,
        },
        if (sub) 'sh': 1,
        'at': addedAt,
        if (lit) 'lit': 1,
      };

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'] as String?,
        gadget: j['g'] as String?,
        title: (j['t'] ?? '') as String,
        author: (j['a'] ?? '') as String,
        desc: (j['d'] ?? '') as String,
        status: (j['s'] ?? 'r') as String,
        cover: j['img'] as String?,
        sub: j['sh'] == 1 || j['sh'] == true,
        tags: ((j['tags'] ?? const []) as List).cast<String>().toList(),
        addedAt: (j['at'] as num?)?.toInt(),
        finishedAt: (j['fin'] as num?)?.toInt(),
        lit: j['lit'] == 1 || j['lit'] == true,
        file: j['file'] as String?,
        pages: (j['pages'] as num?)?.toInt() ?? 0,
        page: (j['page'] as num?)?.toInt() ?? 0,
        readAt: (j['readAt'] as num?)?.toInt(),
        pos: (j['pos'] as num?)?.toInt() ?? 0,
        rating: (j['rating'] as num?)?.toInt() ?? 0,
        readMs: (j['readMs'] as num?)?.toInt() ?? 0,
        marks: ((j['marks'] ?? const []) as List).map((e) => Mark.fromJson((e as Map).cast<String, dynamic>())).toList(),
        isbn: (j['isbn'] ?? '') as String,
      );

  Item copy() => Item.fromJson(toJson());
}

class Collection {
  String id;
  String name;
  String emoji;
  List<Item> items;
  bool subOn;
  bool subOpen;

  Collection({String? id, required this.name, this.emoji = '📚', List<Item>? items, this.subOn = false, this.subOpen = false})
      : id = id ?? newId(),
        items = items ?? [];

  Iterable<Item> get books => items.where((i) => !i.isDecor);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'items': items.map((e) => e.toJson()).toList(),
        if (subOn) 'subOn': true,
        if (subOpen) 'subOpen': true,
      };

  factory Collection.fromJson(Map<String, dynamic> j) => Collection(
        id: j['id'] as String?,
        name: (j['name'] ?? 'Shelf') as String,
        emoji: (j['emoji'] ?? '📚') as String,
        items: ((j['items'] ?? const []) as List).map((e) => Item.fromJson((e as Map).cast<String, dynamic>())).toList(),
        subOn: j['subOn'] == true,
        subOpen: j['subOpen'] == true,
      );
}

class Todo {
  String id;
  String text;
  bool done;
  int createdAt;
  int? doneAt;
  int? due; // ms since epoch
  String book;
  List<String> tags;
  bool starred;
  bool edited;

  Todo({
    String? id,
    required this.text,
    this.done = false,
    int? createdAt,
    this.doneAt,
    this.due,
    this.book = '',
    List<String>? tags,
    this.starred = false,
    this.edited = false,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        tags = tags ?? [];

  DateTime? get dueAt => due == null ? null : DateTime.fromMillisecondsSinceEpoch(due!);

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        if (done) 'done': true,
        'at': createdAt,
        if (doneAt != null) 'doneAt': doneAt,
        if (due != null) 'due': due,
        if (book.isNotEmpty) 'book': book,
        if (tags.isNotEmpty) 'tags': tags,
        if (starred) 'star': true,
        if (edited) 'edited': true,
      };

  factory Todo.fromJson(Map<String, dynamic> j) => Todo(
        id: j['id'] as String?,
        text: (j['text'] ?? '') as String,
        done: j['done'] == true,
        createdAt: (j['at'] as num?)?.toInt(),
        doneAt: (j['doneAt'] as num?)?.toInt(),
        due: (j['due'] as num?)?.toInt(),
        book: (j['book'] ?? '') as String,
        tags: ((j['tags'] ?? const []) as List).cast<String>().toList(),
        starred: j['star'] == true,
        edited: j['edited'] == true,
      );
}

class Social {
  String k; // label, e.g. Instagram
  String icon;
  String hint;
  String v;
  bool custom;
  Social(this.k, this.icon, this.hint, [this.v = '', this.custom = false]);

  Map<String, dynamic> toJson() => {'k': k, 'i': icon, 'ph': hint, 'v': v, if (custom) 'c': true};
  factory Social.fromJson(Map<String, dynamic> j) =>
      Social((j['k'] ?? '') as String, (j['i'] ?? '🔗') as String, (j['ph'] ?? '') as String, (j['v'] ?? '') as String, j['c'] == true);

  static List<Social> defaults() => [
        Social('Instagram', '📸', '@username'),
        Social('X (Twitter)', '✖️', '@username'),
        Social('Goodreads', '📗', 'goodreads.com/you'),
        Social('Website', '🌐', 'https://yoursite.com'),
      ];
}

class Profile {
  String name;
  String handle;
  String bio;
  String? photo;
  String email;
  List<Social> socials;

  Profile({this.name = '', this.handle = '', this.bio = '', this.photo, this.email = '', List<Social>? socials})
      : socials = socials ?? Social.defaults();

  String get first => name.trim().isEmpty ? 'Reader' : name.trim().split(RegExp(r'\s+')).first;

  Map<String, dynamic> toJson() => {
        'name': name,
        'handle': handle,
        'bio': bio,
        if (photo != null) 'photo': photo,
        'email': email,
        'socials': socials.map((s) => s.toJson()).toList(),
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        name: (j['name'] ?? '') as String,
        handle: (j['handle'] ?? '') as String,
        bio: (j['bio'] ?? '') as String,
        photo: j['photo'] as String?,
        email: (j['email'] ?? '') as String,
        socials: j['socials'] == null
            ? null
            : (j['socials'] as List).map((e) => Social.fromJson((e as Map).cast<String, dynamic>())).toList(),
      );
}

class Settings {
  bool reminders;
  bool dailyNudge;
  bool sounds;
  bool haptics;
  String theme; // light, dark, system
  int accent;
  String font;
  double textScale;
  String bg; // background colour family
  String pattern; // background pattern
  bool autoUpdate;
  bool backupFiles;
  double epubSize;
  String skipVersion;

  Settings({
    this.reminders = false,
    this.dailyNudge = false,
    this.sounds = true,
    this.haptics = true,
    this.theme = 'light',
    this.accent = 0,
    this.font = 'Nunito',
    this.textScale = 1,
    this.bg = 'cream',
    this.pattern = 'none',
    this.autoUpdate = true,
    this.backupFiles = false,
    this.epubSize = 18,
    this.skipVersion = '',
  });

  Map<String, dynamic> toJson() => {
        'reminders': reminders,
        'nudge': dailyNudge,
        'sounds': sounds,
        'haptics': haptics,
        'theme': theme,
        'accent': accent,
        'font': font,
        'textScale': textScale,
        'bg': bg,
        'pattern': pattern,
        'autoUpdate': autoUpdate,
        'backupFiles': backupFiles,
        'epubSize': epubSize,
        if (skipVersion.isNotEmpty) 'skipVersion': skipVersion,
      };
  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        reminders: j['reminders'] == true,
        dailyNudge: j['nudge'] == true,
        sounds: j['sounds'] != false,
        haptics: j['haptics'] != false,
        theme: (j['theme'] ?? 'light') as String,
        accent: (j['accent'] as num?)?.toInt() ?? 0,
        font: (j['font'] ?? 'Nunito') as String,
        textScale: (j['textScale'] as num?)?.toDouble() ?? 1,
        bg: (j['bg'] ?? 'cream') as String,
        pattern: (j['pattern'] ?? 'none') as String,
        autoUpdate: j['autoUpdate'] != false,
        backupFiles: j['backupFiles'] == true,
        epubSize: (j['epubSize'] as num?)?.toDouble() ?? 18,
        skipVersion: (j['skipVersion'] ?? '') as String,
      );
}

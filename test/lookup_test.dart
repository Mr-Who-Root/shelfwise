import 'package:flutter_test/flutter_test.dart';
import 'package:shelfwise/services/lookup.dart';
import 'package:shelfwise/services/updater.dart';

void main() {
  test('ISBN barcodes are recognised and normalised to ISBN-13', () {
    expect(isbnFromBarcode('9780141439518'), '9780141439518');
    expect(isbnFromBarcode('0-14-143951-3'), '9780141439518'); // ISBN-10
    expect(isbnFromBarcode('9780141439519'), isNull); // bad check digit
    expect(isbnFromBarcode('5012345678900'), isNull); // a product barcode, not a book
  });

  test('version comparison', () {
    expect(Updater.newer('v1.10.0', '1.9.2'), isTrue);
    expect(Updater.newer('1.2.0', '1.2.0'), isFalse);
    expect(Updater.newer('1.1.0', '1.2.0'), isFalse);
    expect(Updater.newer('v2.0', '1.9.9'), isTrue);
  });
}

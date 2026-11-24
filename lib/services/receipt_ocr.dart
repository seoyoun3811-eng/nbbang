import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/settle_item.dart';

/// 영수증 인식 결과 (Gemini / ML Kit 공통)
class ReceiptParseResult {
  final String? store; // 상호명
  final String? datetime; // 거래 일시
  final List<SettleItem> items;
  final int? total; // 결제금액

  ReceiptParseResult({
    this.store,
    this.datetime,
    required this.items,
    this.total,
  });
}

/// 글자 조각 하나 (내용 + 사진 속 위치)
class _Piece {
  final String text;
  final Rect box;
  _Piece(this.text, this.box);
}

/// ML Kit 기반 영수증 읽기 (인터넷이 없거나 AI 호출이 실패할 때 예비용)
///
/// 1) 글자 조각들을 y좌표로 묶어 "진짜 가로줄"로 다시 만들고
/// 2) "상품명/단가/수량/금액" 머리줄 아래 ~ "합계" 줄 위까지만 품목으로 읽음
/// 3) 줄 오른쪽 숫자들을 단가·수량·금액으로 해석
class ReceiptOcr {
  static const _endKeywords = [
    '합계', '총액', '총금액', '결제금액', '받을금액', '공급가액', '공급가',
    '부가세', '과세', '면세', '할인합계',
  ];

  static const _totalKeywords = ['결제금액', '받을금액', '총결제', '합계', '총액', '총금액'];

  static const _skipKeywords = [
    '부가세', '과세', '면세', '공급가', '카드', '현금', '거스름', '포인트', '적립',
    'TEL', '전화', '사업자', '대표', '주소', '승인', '할부', '매입', '가맹점', '번호',
    '일시', '단가', '수량',
  ];

  static Future<ReceiptParseResult> parse(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.korean);
    final pieces = <_Piece>[];
    try {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final t = line.text.trim();
          if (t.isNotEmpty) pieces.add(_Piece(t, line.boundingBox));
        }
      }
    } finally {
      recognizer.close();
    }

    return _parseRows(_groupIntoRows(pieces));
  }

  static List<String> _groupIntoRows(List<_Piece> pieces) {
    pieces.sort((a, b) => a.box.center.dy.compareTo(b.box.center.dy));

    final rows = <List<_Piece>>[];
    for (final p in pieces) {
      if (rows.isNotEmpty) {
        final row = rows.last;
        final cy = row.map((e) => e.box.center.dy).reduce((a, b) => a + b) /
            row.length;
        final h =
            row.map((e) => e.box.height).reduce((a, b) => a + b) / row.length;
        if ((p.box.center.dy - cy).abs() < h * 0.5) {
          row.add(p);
          continue;
        }
      }
      rows.add([p]);
    }

    return rows.map((row) {
      row.sort((a, b) => a.box.left.compareTo(b.box.left));
      return row.map((e) => e.text).join(' ');
    }).toList();
  }

  static String _compact(String s) => s.replaceAll(' ', '');

  static bool _isHeader(String row) {
    final c = _compact(row);
    return c.contains('상품명') ||
        c.contains('품명') ||
        (c.contains('메뉴') && c.contains('금액')) ||
        (c.contains('수량') && (c.contains('단가') || c.contains('금액')));
  }

  static ReceiptParseResult _parseRows(List<String> rows) {
    int? total;
    for (final key in _totalKeywords) {
      for (final row in rows) {
        if (!_compact(row).contains(key)) continue;
        final nums = _trailingNumbers(row).numbers;
        if (nums.isNotEmpty) {
          total = nums.last;
          break;
        }
      }
      if (total != null) break;
    }

    var start = rows.indexWhere(_isHeader);
    start = start == -1 ? 0 : start + 1;
    var end = rows.length;
    for (var i = start; i < rows.length; i++) {
      final c = _compact(rows[i]);
      if (_endKeywords.any(c.contains)) {
        end = i;
        break;
      }
    }

    final items = <SettleItem>[];
    for (var i = start; i < end; i++) {
      final item = _parseItemRow(rows[i]);
      if (item != null) items.add(item);
      if (items.length >= 40) break;
    }

    return ReceiptParseResult(items: items, total: total);
  }

  static final _numberToken = RegExp(r'^\d{1,3}(,\d{3})+$|^\d+$');

  static ({String name, List<int> numbers}) _trailingNumbers(String row) {
    final tokens = row
        .replaceAll('원', ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    final numbers = <int>[];
    while (tokens.isNotEmpty && _numberToken.hasMatch(tokens.last)) {
      numbers.insert(0, int.parse(tokens.removeLast().replaceAll(',', '')));
    }
    return (name: tokens.join(' '), numbers: numbers);
  }

  static SettleItem? _parseItemRow(String row) {
    final c = _compact(row);
    if (_skipKeywords.any((k) => c.toUpperCase().contains(k))) return null;

    final parsed = _trailingNumbers(row);
    final name = parsed.name.replaceAll(RegExp(r'^[\d\-.*#]+\s*'), '').trim();
    final nums = parsed.numbers;

    if (nums.isEmpty || !RegExp(r'[가-힣A-Za-z]').hasMatch(name)) return null;

    int price;
    int qty = 1;
    int amount;

    if (nums.length >= 3) {
      final p = nums[nums.length - 3];
      final q = nums[nums.length - 2];
      amount = nums.last;
      if (q > 0 && q < 100 && p * q == amount) {
        price = p;
        qty = q;
      } else {
        price = amount;
      }
    } else if (nums.length == 2) {
      final a = nums[0];
      amount = nums[1];
      if (a > 0 && a < 100) {
        qty = a;
      } else if (a > 0 && amount % a == 0 && amount ~/ a < 100) {
        qty = amount ~/ a;
      }
      price = amount;
    } else {
      amount = nums.first;
      price = amount;
    }

    if (qty > 1) {
      if (amount % qty == 0) {
        price = amount ~/ qty;
      } else {
        qty = 1;
        price = amount;
      }
    }

    if (price < 10 || amount > 10000000) return null;

    return SettleItem(name: name, price: price, qty: qty);
  }
}

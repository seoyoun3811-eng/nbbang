import 'dart:convert';
import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/settle_item.dart';
import 'receipt_ocr.dart' show ReceiptParseResult;

/// Gemini(Firebase AI Logic)로 영수증 사진을 읽어서 간이 영수증 데이터로 만드는 클래스
class GeminiReceiptReader {
  /// 시도할 모델 이름 (앞에서부터 차례로 시도)
  /// Gemini 모델 이름은 자주 바뀌어서, 하나가 없어져도 다음 것으로 넘어가게 함.
  /// 'gemini-flash-latest'는 항상 최신 Flash 모델을 가리키는 별칭.
  /// 모두 실패하면 Firebase 콘솔 → AI Logic에서 쓸 수 있는 Flash 모델 이름을 확인해서
  /// 이 목록 맨 앞에 추가하면 됨 ('preview'가 붙은 모델은 유료일 수 있어서 피함)
  static const modelNames = [
    'gemini-flash-latest',
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
  ];

  static const _prompt = '''
너는 한국 영수증을 읽는 도우미야. 사진 속 영수증을 읽고 아래 JSON 형식으로만 답해. 설명이나 다른 글은 절대 쓰지 마.

{
  "store": "상호명 (가게 이름)",
  "datetime": "거래 일시, YYYY-MM-DD HH:mm 형식",
  "items": [
    { "name": "상품명", "price": 단가(정수), "qty": 수량(정수), "amount": 금액(정수, 단가×수량) }
  ],
  "total": 결제금액(정수, 실제로 결제한 최종 금액)
}

규칙:
- items에는 실제로 구매한 상품만 넣어. 합계, 부가세, 공급가액, 과세/면세 금액, 할인, 결제 수단, 카드번호, 승인번호, 사업자번호, 바코드 숫자는 넣지 마.
- 상품명은 영수증에 적힌 그대로 써. 옵션(예: 샷 추가)이 별도 금액으로 적혀 있으면 별도 상품으로 넣어.
- 금액은 쉼표와 '원'을 빼고 정수로 써.
- total은 "결제금액", "받을금액", "합계" 순서로 찾아서 실제로 결제한 금액을 써.
- 읽을 수 없거나 없는 값은 null로 써.
- 영수증이 아니면 items를 빈 배열로 해.
''';

  static Future<ReceiptParseResult> read(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final mime =
    imagePath.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';

    final text = await askJson([
      TextPart(_prompt),
      InlineDataPart(mime, bytes),
    ]);
    return parseResultJson(text);
  }

  /// Gemini에 요청해서 JSON 글자를 받아옴 (영수증 읽기, 메뉴 검색 공용)
  /// 모델이 없으면 modelNames의 다음 모델로 넘어감
  static Future<String> askJson(List<Part> parts) async {
    Object? lastError;
    for (final name in modelNames) {
      try {
        final model = FirebaseAI.googleAI().generativeModel(
          model: name,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json', // JSON으로만 답하게
            temperature: 0,
          ),
        );

        final response = await model.generateContent([Content.multi(parts)]);

        final text = response.text;
        if (text == null || text.trim().isEmpty) {
          throw Exception('AI 응답이 비어 있어요');
        }
        debugPrint('Gemini 요청 성공 (모델: $name)');
        return text;
      } catch (e) {
        debugPrint('Gemini 요청 실패 (모델: $name): $e');
        lastError = e;
        // 모델이 없거나 지원하지 않는 경우에만 다음 모델로 넘어감
        final msg = e.toString().toLowerCase();
        final modelProblem = msg.contains('not found') ||
            msg.contains('404') ||
            msg.contains('not supported') ||
            msg.contains('is not available') ||
            msg.contains('deprecated');
        if (!modelProblem) rethrow;
      }
    }
    throw lastError ?? Exception('사용할 수 있는 Gemini 모델이 없어요');
  }

  // ───────────── JSON → 결과 ─────────────

  /// {store, datetime, items, total} 형태의 JSON을 결과로 바꿈 (메뉴 검색도 같이 씀)
  static ReceiptParseResult parseResultJson(String text) {
    // 혹시 ```json ... ``` 으로 감싸서 오면 벗겨냄
    var cleaned = text.trim();
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start != -1 && end > start) cleaned = cleaned.substring(start, end + 1);

    final data = jsonDecode(cleaned) as Map<String, dynamic>;

    final items = <SettleItem>[];
    final rawItems = data['items'];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final item = _toItem(raw);
        if (item != null) items.add(item);
      }
    }

    return ReceiptParseResult(
      store: _toStr(data['store']),
      datetime: _toStr(data['datetime']),
      items: items,
      total: _toInt(data['total']),
    );
  }

  static SettleItem? _toItem(Map raw) {
    final name = _toStr(raw['name']) ?? '';
    var price = _toInt(raw['price']);
    var qty = _toInt(raw['qty']) ?? 1;
    final amount = _toInt(raw['amount']);
    if (qty < 1) qty = 1;

    // 단가가 없으면 금액 ÷ 수량으로 계산
    if (price == null && amount != null) {
      if (amount % qty == 0) {
        price = amount ~/ qty;
      } else {
        price = amount;
        qty = 1;
      }
    }
    // 단가×수량과 금액이 다르면 금액을 믿고 단가를 다시 계산
    if (price != null && amount != null && price * qty != amount) {
      if (amount % qty == 0) {
        price = amount ~/ qty;
      } else {
        price = amount;
        qty = 1;
      }
    }

    if (price == null && name.isEmpty) return null;
    return SettleItem(name: name, price: price ?? 0, qty: qty);
  }

  static String? _toStr(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.round();
    final digits = v.toString().replaceAll(RegExp(r'[^0-9\-]'), '');
    return int.tryParse(digits);
  }
}
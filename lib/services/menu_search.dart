import 'package:firebase_ai/firebase_ai.dart';

import 'gemini_receipt.dart';
import 'receipt_ocr.dart' show ReceiptParseResult;

/// "스타벅스 아메리카노 2잔이랑 라떼 하나" 같은 말을
/// Gemini로 가게 이름 + 품목(이름, 가격, 수량)으로 바꿔주는 클래스
///
/// 가격은 Gemini가 알고 있는 일반적인 가격(예상값)이라 실제와 다를 수 있음
class MenuSearch {
  static String _prompt(String query) => '''
너는 한국 식당·카페 메뉴와 가격을 잘 아는 도우미야.
사용자가 먹은 것을 말로 설명하면, 가게 이름과 품목을 정리해서 아래 JSON 형식으로만 답해. 설명이나 다른 글은 절대 쓰지 마.

{
  "store": "가게 또는 프랜차이즈 이름 (말하지 않았으면 null)",
  "items": [
    { "name": "메뉴 이름", "price": 한 개 가격(정수, 원), "qty": 수량(정수) }
  ]
}

규칙:
- 프랜차이즈라면 공식 메뉴 이름으로 써. 예: "아아" → "아이스 아메리카노"
- price는 한국 매장 기준 가장 일반적인 정가로 써. 사이즈를 말하지 않았으면 기본 사이즈 가격으로 해.
- 가격을 모르면 price를 null로 써.
- 수량을 말하지 않았으면 qty는 1이야. "두 잔", "2개", "하나씩" 같은 표현을 숫자로 바꿔.
- 메뉴가 아닌 말은 무시해.

사용자 입력: "$query"
''';

  static Future<ReceiptParseResult> search(String query) async {
    final text = await GeminiReceiptReader.askJson([TextPart(_prompt(query))]);
    return GeminiReceiptReader.parseResultJson(text);
  }
}
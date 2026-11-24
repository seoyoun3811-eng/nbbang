import 'settle_item.dart';

/// 작성 중인 간이 영수증 (화면을 나갔다 와도 유지됨)
class ReceiptDraft {
  List<SettleItem> items;
  String? store; // 상호명
  String? datetime; // 거래 일시
  int? paymentTotal; // 결제금액
  String? imagePath; // 원본 영수증 사진
  String title; // 화면 제목 ('간이 영수증' / '직접 입력' / '메뉴 검색')
  String? notice; // 화면 위에 띄울 안내 (예: AI 예상 가격)

  ReceiptDraft({
    List<SettleItem>? items,
    this.store,
    this.datetime,
    this.paymentTotal,
    this.imagePath,
    this.title = '간이 영수증',
    this.notice,
  }) : items = items ?? [];

  int get itemsTotal => items.fold(0, (a, it) => a + it.total);

  /// 이어서 하기 카드에 보여줄 한 줄 설명
  String get summary {
    final name = (store == null || store!.isEmpty) ? title : store!;
    final count = items.where((it) => it.total > 0).length;
    return '$name · 품목 $count개';
  }
}

/// 앱이 켜져 있는 동안 마지막으로 작성하던 영수증을 기억하는 곳
class DraftStore {
  static ReceiptDraft? current;
}
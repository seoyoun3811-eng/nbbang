import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/receipt_draft.dart';
import '../models/settle_item.dart';
import '../utils/format.dart';
import 'result_screen.dart';

/// ③ 간이 영수증 화면: 상호명·거래 일시 / 품목 / 결제금액 + 사람 지정
/// AI가 읽은 영수증도, 직접 입력도 모두 이 화면을 씀
class ItemsScreen extends StatefulWidget {
  /// 함께 정산하는 사람들 (이 화면에서 추가하면 인원 화면에도 반영됨)
  final List<String> people;

  /// 작성 중인 영수증. 화면을 나가도 내용이 여기 남아 있어서 이어서 할 수 있음
  final ReceiptDraft draft;

  const ItemsScreen({super.key, required this.people, required this.draft});

  String? get imagePath => draft.imagePath;
  String get title => draft.title;

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

/// 품목 하나 + 그 품목의 입력창 컨트롤러 묶음
class _Row {
  final SettleItem item;
  final TextEditingController name;
  final TextEditingController price;
  final TextEditingController qty;

  _Row(this.item)
      : name = TextEditingController(text: item.name),
        price =
        TextEditingController(text: item.price == 0 ? '' : '${item.price}'),
        qty = TextEditingController(text: '${item.qty}');

  void dispose() {
    name.dispose();
    price.dispose();
    qty.dispose();
  }
}

class _ItemsScreenState extends State<ItemsScreen> {
  final List<_Row> _rows = [];
  final List<_Row> _removed = [];
  final _scrollController = ScrollController();

  late final TextEditingController _storeController;
  late final TextEditingController _dateController;
  late final TextEditingController _payController;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _storeController = TextEditingController(text: d.store ?? '');
    _dateController = TextEditingController(text: d.datetime ?? '');
    _payController = TextEditingController(
        text: d.paymentTotal == null ? '' : '${d.paymentTotal}');

    for (final it in d.items) {
      // 인원 화면에서 빠진 사람은 지정에서도 빼기
      it.assigned.removeWhere((p) => !widget.people.contains(p));
      _rows.add(_Row(it));
    }
    if (_rows.isEmpty) _addItem(scroll: false);
  }

  /// 지금 화면 내용을 draft에 저장 (나갔다 와도 그대로 이어서 할 수 있게)
  void _saveDraft() {
    final d = widget.draft;
    final store = _storeController.text.trim();
    final date = _dateController.text.trim();
    d.store = store.isEmpty ? null : store;
    d.datetime = date.isEmpty ? null : date;
    d.paymentTotal = _payment;
    d.items = _rows.map((r) => r.item).toList();
  }

  @override
  void dispose() {
    _saveDraft();
    for (final r in [..._rows, ..._removed]) {
      r.dispose();
    }
    _storeController.dispose();
    _dateController.dispose();
    _payController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 상품 금액 합계
  int get _sum => _rows.fold(0, (a, r) => a + r.item.total);

  /// 입력된 결제금액 (비어 있으면 null)
  int? get _payment {
    final v = int.tryParse(_payController.text);
    return (v == null || v <= 0) ? null : v;
  }

  void _addItem({bool scroll = true}) {
    setState(() => _rows.add(_Row(SettleItem())));
    if (scroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _removeItem(_Row row) {
    setState(() {
      _rows.remove(row);
      _removed.add(row);
    });
  }

  void _showOriginal() {
    if (widget.imagePath == null) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.file(File(widget.imagePath!)),
        ),
      ),
    );
  }

  // ───────────── 사람 선택 바텀시트 ─────────────

  Future<void> _openPersonPicker(SettleItem item) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          void refresh() {
            setSheetState(() {});
            setState(() {});
          }

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text('누가 먹었나요?',
                      style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                CheckboxListTile(
                  value: item.assignedAll,
                  title: const Text('모두',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  secondary: const Icon(Icons.groups),
                  onChanged: (v) {
                    item.assignedAll = v ?? false;
                    if (item.assignedAll) item.assigned.clear();
                    refresh();
                  },
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in widget.people)
                        CheckboxListTile(
                          value: item.assignedAll
                              ? false
                              : item.assigned.contains(p),
                          title: Text(p),
                          onChanged: (v) {
                            item.assignedAll = false;
                            if (v == true) {
                              item.assigned.add(p);
                            } else {
                              item.assigned.remove(p);
                            }
                            refresh();
                          },
                        ),
                      // 빼먹은 사람 바로 추가
                      ListTile(
                        leading: const Icon(Icons.person_add_alt_1),
                        title: const Text('사람 추가'),
                        onTap: () async {
                          final name = await _askNewPerson();
                          if (name == null) return;
                          widget.people.add(name);
                          if (!item.assignedAll) item.assigned.add(name);
                          refresh();
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('확인'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    setState(() {});
  }

  /// 새 사람 이름 입력 받기
  Future<String?> _askNewPerson() async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('사람 추가'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 10,
          decoration: const InputDecoration(hintText: '이름 입력'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('추가')),
        ],
      ),
    );
    final name = input?.trim() ?? '';
    if (name.isEmpty) return null;
    if (widget.people.contains(name)) {
      _snack('"$name"은(는) 이미 있어요');
      return null;
    }
    return name;
  }

  // ───────────── 완료 ─────────────

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _done() async {
    final valid = _rows.where((r) => r.item.total > 0).toList();
    if (valid.isEmpty) {
      _snack('가격이 입력된 품목이 없어요');
      return;
    }

    // 사람이 지정되지 않은 품목
    final unassigned = valid.where((r) => !r.item.hasTarget).length;
    if (unassigned > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('지정 안 된 품목 $unassigned개'),
          content: const Text('사람이 지정되지 않은 품목은 "모두"로 나눌까요?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('돌아가기')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('모두로 나누기')),
          ],
        ),
      );
      if (ok != true) return;
      for (final r in valid) {
        if (!r.item.hasTarget) r.item.assignedAll = true;
      }
    }

    // 상품 합계와 결제금액이 다를 때: 어느 금액으로 나눌지 선택
    final sum = valid.fold(0, (a, r) => a + r.item.total);
    int? payTotal = _payment;
    if (payTotal != null && payTotal != sum) {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('금액이 달라요'),
          content: Text(
            '상품 합계 ${won(sum)}원\n결제금액 ${won(payTotal!)}원\n\n'
                '결제금액 기준으로 하면 각자 몫을 비율대로 맞춰서, '
                '다 합치면 실제 결제한 금액과 같아져요.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, 'back'),
                child: const Text('돌아가기')),
            TextButton(
                onPressed: () => Navigator.pop(context, 'items'),
                child: const Text('상품 합계로')),
            FilledButton(
                onPressed: () => Navigator.pop(context, 'pay'),
                child: const Text('결제금액으로')),
          ],
        ),
      );
      if (choice == null || choice == 'back') return;
      if (choice == 'items') payTotal = null;
    }

    var n = 1;
    final items = <SettleItem>[];
    for (final r in valid) {
      if (r.item.name.trim().isEmpty) r.item.name = '품목$n';
      items.add(r.item);
      n++;
    }

    if (!mounted) return;
    FocusScope.of(context).unfocus();
    _saveDraft();
    final store = _storeController.text.trim();
    final date = _dateController.text.trim();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          people: widget.people,
          items: items,
          store: store.isEmpty ? null : store,
          datetime: date.isEmpty ? null : date,
          paymentTotal: payTotal,
        ),
      ),
    );
  }

  // ───────────── 화면 ─────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (widget.draft.notice != null) _buildNotice(),
                  if (widget.imagePath != null) _buildReceiptPreview(),
                  _buildReceiptHeader(),
                  _buildColumnTitles(),
                  for (final r in _rows) _buildItemCard(r),
                  _buildAddButton(),
                  _buildPaymentField(),
                ],
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  InputDecoration _plain(String hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    border: InputBorder.none,
    contentPadding: const EdgeInsets.symmetric(vertical: 4),
  );

  /// 맨 위 안내 (예: 메뉴 검색 가격은 AI 예상값)
  Widget _buildNotice() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.draft.notice!,
                style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }

  /// 맨 위: 원본 영수증 사진 미리보기 (탭하면 확대)
  Widget _buildReceiptPreview() {
    return GestureDetector(
      onTap: _showOriginal,
      child: Container(
        height: 160,
        margin: const EdgeInsets.only(bottom: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(widget.imagePath!),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.zoom_in, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text('탭해서 확대',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 영수증 머리: 상호명, 거래 일시
  Widget _buildReceiptHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(children: [
            const Icon(Icons.storefront, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _storeController,
                decoration: _plain('상호명'),
                style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ]),
          const Divider(height: 12),
          Row(children: [
            const Icon(Icons.schedule, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _dateController,
                decoration: _plain('거래 일시 (예: 2026-11-16 12:30)'),
                style: TextStyle(color: Colors.grey.shade800),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildColumnTitles() {
    final style = TextStyle(fontSize: 12, color: Colors.grey.shade600);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      child: Row(children: [
        Text('상품명', style: style),
        const Spacer(),
        Text('단가 × 수량 = 금액', style: style),
      ]),
    );
  }

  /// 품목 카드: 1줄째 상품명 + 사람 선택, 2줄째 단가 × 수량 = 금액
  Widget _buildItemCard(_Row row) {
    final item = row.item;
    final hasTarget = item.hasTarget;
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.name,
                    decoration: _plain('상품명'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    onChanged: (v) => item.name = v,
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: () => _openPersonPicker(item),
                  icon: const Icon(Icons.people, size: 16),
                  label: Text(item.targetLabel(),
                      overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: hasTarget ? primary : Colors.grey,
                    side: BorderSide(
                        color: hasTarget
                            ? primary.withOpacity(0.5)
                            : Colors.grey.shade400),
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: const Size(0, 34),
                  ),
                ),
                IconButton(
                  tooltip: '삭제',
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  onPressed: () => _removeItem(row),
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: row.price,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                        hintText: '단가', suffixText: '원', isDense: true),
                    onChanged: (v) =>
                        setState(() => item.price = int.tryParse(v) ?? 0),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('×', style: TextStyle(color: Colors.grey)),
                ),
                SizedBox(
                  width: 52,
                  child: TextField(
                    controller: row.qty,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                        hintText: '1', suffixText: '개', isDense: true),
                    onChanged: (v) {
                      final q = int.tryParse(v) ?? 1;
                      setState(() => item.qty = q < 1 ? 1 : q);
                    },
                  ),
                ),
                Expanded(
                  child: Text(
                    '${won(item.total)}원',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: OutlinedButton.icon(
        onPressed: _addItem,
        icon: const Icon(Icons.add),
        label: const Text('품목 추가'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 46),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  /// 영수증 바닥: 결제금액 (수정 가능)
  Widget _buildPaymentField() {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Text('결제금액',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: _payController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _plain('비우면 상품 합계로 계산').copyWith(suffixText: '원'),
              style:
              const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  /// 하단 고정: 상품 합계 / 결제금액 비교 + 완료
  Widget _buildBottomBar() {
    final pay = _payment;
    final match = pay == null || pay == _sum;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('상품 합계', style: TextStyle(color: Colors.grey.shade600)),
              const Spacer(),
              Text('${won(_sum)}원',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          if (pay != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(match ? Icons.check_circle : Icons.warning_amber,
                      size: 18, color: match ? Colors.green : Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      match
                          ? '결제금액과 일치해요'
                          : '결제금액 ${won(pay)}원과 ${won((pay - _sum).abs())}원 차이가 있어요',
                      style: TextStyle(
                          fontSize: 12,
                          color: match ? Colors.green : Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: _sum > 0 ? _done : null,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('완료',
                  style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
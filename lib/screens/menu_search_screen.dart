import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/receipt_draft.dart';
import '../models/settle_item.dart';
import '../services/menu_search.dart';
import '../utils/format.dart';

/// 영수증 없을 때: 말이나 글로 먹은 메뉴를 설명하면 AI가 품목과 가격을 찾아주는 화면
/// 결과를 고른 뒤 [간이 영수증으로]를 누르면 ReceiptDraft를 돌려줌
class MenuSearchScreen extends StatefulWidget {
  const MenuSearchScreen({super.key});

  @override
  State<MenuSearchScreen> createState() => _MenuSearchScreenState();
}

/// 검색 결과 한 줄 (담을지 여부 포함)
class _Found {
  final SettleItem item;
  bool selected = true;
  _Found(this.item);
}

class _MenuSearchScreenState extends State<MenuSearchScreen> {
  final _controller = TextEditingController();
  final _speech = SpeechToText();

  final List<_Found> _found = [];
  String? _store;
  bool _searching = false;
  bool _listening = false;
  bool _speechReady = false;

  @override
  void dispose() {
    _speech.stop();
    _controller.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ───────────── 음성 입력 ─────────────

  Future<void> _toggleListen() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }

    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          // 말이 끝나면 자동으로 멈춤
          if ((status == 'done' || status == 'notListening') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (e) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (!_speechReady) {
        _snack('음성 인식을 쓸 수 없어요. 마이크 권한을 확인해 주세요');
        return;
      }
    }

    setState(() => _listening = true);
    await _speech.listen(
      localeId: 'ko_KR',
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 3),
      onResult: (r) {
        setState(() => _controller.text = r.recognizedWords);
        if (r.finalResult && _controller.text.trim().isNotEmpty) {
          _search(); // 말이 끝나면 바로 검색
        }
      },
    );
  }

  // ───────────── 검색 ─────────────

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _searching) return;
    FocusScope.of(context).unfocus();
    if (_listening) {
      await _speech.stop();
      _listening = false;
    }

    setState(() => _searching = true);
    try {
      final result = await MenuSearch.search(query);
      if (!mounted) return;
      if (result.items.isEmpty) {
        _snack('메뉴를 찾지 못했어요. 가게 이름과 메뉴를 같이 말해 주세요');
      } else {
        setState(() {
          _store ??= result.store; // 처음 찾은 가게 이름 사용
          _found.addAll(result.items.map(_Found.new)); // 여러 번 검색하면 이어서 담김
          _controller.clear();
        });
      }
    } catch (e) {
      if (mounted) _snack('검색하지 못했어요: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _finish() {
    final items = _found.where((f) => f.selected).map((f) => f.item).toList();
    if (items.isEmpty) {
      _snack('담을 메뉴를 하나 이상 골라 주세요');
      return;
    }
    Navigator.pop(
      context,
      ReceiptDraft(
        items: items,
        store: _store,
        title: '메뉴 검색',
        notice: '가격은 AI가 예상한 값이에요. 매장마다 다를 수 있으니 확인해 주세요.',
      ),
    );
  }

  // ───────────── 화면 ─────────────

  @override
  Widget build(BuildContext context) {
    final selectedCount = _found.where((f) => f.selected).length;
    final selectedSum = _found
        .where((f) => f.selected)
        .fold(0, (a, f) => a + f.item.total);

    return Scaffold(
      appBar: AppBar(
        title: const Text('메뉴 검색',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_found.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                _found.clear();
                _store = null;
              }),
              child: const Text('모두 지우기'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildInput(),
                  const SizedBox(height: 8),
                  Text(
                    '예: "스타벅스 아이스 아메리카노 2잔이랑 카페라떼 하나"\n'
                        '여러 번 검색하면 결과가 이어서 담겨요.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  if (_searching)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Column(children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('AI가 메뉴를 찾고 있어요...'),
                        ]),
                      ),
                    ),
                  if (_found.isNotEmpty) _buildResults(),
                ],
              ),
            ),
            _buildBottomBar(selectedCount, selectedSum),
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: _listening ? Colors.red.shade300 : Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: _listening ? '듣고 있어요... 말해 주세요' : '먹은 메뉴를 말하거나 입력하세요',
                border: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            tooltip: '음성 입력',
            onPressed: _searching ? null : _toggleListen,
            icon: Icon(_listening ? Icons.stop_circle : Icons.mic,
                color: _listening ? Colors.red : primary),
          ),
          IconButton.filled(
            tooltip: '검색',
            onPressed: _searching ? null : _search,
            icon: const Icon(Icons.search),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(children: [
              const Icon(Icons.storefront, size: 20, color: Colors.grey),
              const SizedBox(width: 8),
              Text(_store ?? '가게 이름 없음',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
          ),
          for (final f in _found)
            CheckboxListTile(
              value: f.selected,
              onChanged: (v) => setState(() => f.selected = v ?? false),
              title: Text(f.item.name),
              subtitle: Text(f.item.price == 0
                  ? '가격 모름 × ${f.item.qty}개 (간이 영수증에서 입력)'
                  : '${won(f.item.price)}원 × ${f.item.qty}개'),
              secondary: Text('${won(f.item.total)}원',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildBottomBar(int count, int sum) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Text('선택한 메뉴 $count개',
                style: TextStyle(color: Colors.grey.shade600)),
            const Spacer(),
            Text('${won(sum)}원',
                style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: count > 0 ? _finish : null,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('간이 영수증으로',
                  style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/receipt_draft.dart';
import '../services/gemini_receipt.dart';
import '../services/receipt_ocr.dart';
import 'items_screen.dart';
import 'menu_search_screen.dart';
import 'total_split_screen.dart';

/// ② 입력 방식 선택 화면 (영수증 O / 영수증 X)
class InputMethodScreen extends StatefulWidget {
  final List<String> people;

  const InputMethodScreen({super.key, required this.people});

  @override
  State<InputMethodScreen> createState() => _InputMethodScreenState();
}

class _InputMethodScreenState extends State<InputMethodScreen> {
  static const _lightBlue = Color(0xFFE3F0FF);
  static const _blueText = Color(0xFF1E5BB8);
  static const _lightRed = Color(0xFFFFE8E8);
  static const _redText = Color(0xFFC0392B);

  bool _busy = false; // 영수증 인식 중

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ───────────── 작성 중인 영수증 ─────────────

  /// 간이 영수증 화면 열기. 돌아오면 화면 갱신 (이어서 하기 카드, 인원 수)
  Future<void> _openItems(ReceiptDraft draft) async {
    DraftStore.current = draft;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemsScreen(people: widget.people, draft: draft),
      ),
    );
    if (mounted) setState(() {});
  }

  /// 이전 영수증이 있으면 새로 시작해도 되는지 확인
  Future<bool> _confirmReplace() async {
    final draft = DraftStore.current;
    if (draft == null) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('새로 시작할까요?'),
        content: Text('작성 중인 영수증(${draft.summary})은 지워져요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('새로 시작')),
        ],
      ),
    );
    return ok == true;
  }

  void _discardDraft() {
    setState(() => DraftStore.current = null);
  }

  // ───────────── 영수증 O ─────────────

  Future<void> _pickReceipt(ImageSource source) async {
    if (_busy) return;
    if (!await _confirmReplace() || !mounted) return;
    final picker = ImagePicker();
    final XFile? file;
    try {
      file = await picker.pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 92,
      );
    } catch (e) {
      _showSnack('사진을 가져오지 못했어요: $e');
      return;
    }
    if (file == null || !mounted) return; // 취소함

    setState(() => _busy = true);
    ReceiptParseResult? result;
    String? notice;
    String? aiError; // AI 실패 이유 (화면에 보여줌)
    try {
      // 1순위: Gemini로 읽기
      result = await GeminiReceiptReader.read(file.path);
    } catch (e) {
      debugPrint('Gemini 인식 실패: $e');
      aiError = e.toString();
      // 2순위: 인터넷이 없거나 실패하면 기본 인식(ML Kit)으로 읽기
      try {
        result = await ReceiptOcr.parse(file.path);
      } catch (e2) {
        debugPrint('ML Kit 인식 실패: $e2');
        result = null;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);

    // AI가 실패했으면 이유를 보여줌 (원인 찾기용)
    if (aiError != null) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('AI로 읽지 못했어요'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('기본 인식으로 읽었어요. 꼭 확인해 주세요.'),
                const SizedBox(height: 12),
                SelectableText(
                  aiError!,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인')),
          ],
        ),
      );
      if (!mounted) return;
    }

    if (result == null || result.items.isEmpty) {
      notice = '품목을 찾지 못했어요. 원본 사진을 보면서 직접 입력해 주세요';
    }
    if (notice != null) _showSnack(notice);

    await _openItems(ReceiptDraft(
      items: result?.items ?? [],
      store: result?.store,
      datetime: result?.datetime,
      paymentTotal: result?.total,
      imagePath: file.path,
      title: '간이 영수증',
    ));
  }

  // ───────────── 영수증 X ─────────────

  Future<void> _openManual() async {
    if (!await _confirmReplace() || !mounted) return;
    await _openItems(ReceiptDraft(title: '직접 입력'));
  }

  void _openTotalSplit() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TotalSplitScreen(people: widget.people),
      ),
    );
  }

  Future<void> _openSearch() async {
    if (!await _confirmReplace() || !mounted) return;
    final draft = await Navigator.push<ReceiptDraft>(
      context,
      MaterialPageRoute(builder: (_) => const MenuSearchScreen()),
    );
    if (draft == null || !mounted) return; // 그냥 뒤로 나옴
    await _openItems(draft);
  }

  // ───────────── 화면 ─────────────

  /// 작성 중인 영수증 이어서 하기 카드
  Widget _buildDraftCard(ReceiptDraft draft) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openItems(draft),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: primary.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.history, color: primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('이전 영수증 이어서 하기',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: primary)),
                    const SizedBox(height: 2),
                    Text(draft.summary,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade700)),
                  ],
                ),
              ),
              IconButton(
                tooltip: '지우기',
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: _discardDraft,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('어떻게 입력할까요?',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('${widget.people.join(', ')} (${widget.people.length}명)',
                    style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 16),
                if (DraftStore.current != null) ...[
                  _buildDraftCard(DraftStore.current!),
                  const SizedBox(height: 16),
                ],
                _MethodCard(
                  title: '영수증 있어요',
                  icon: Icons.receipt_long,
                  background: _lightBlue,
                  foreground: _blueText,
                  options: [
                    _Option(Icons.photo_camera, '사진 촬영',
                            () => _pickReceipt(ImageSource.camera)),
                    _Option(Icons.photo_library, '갤러리에서 선택',
                            () => _pickReceipt(ImageSource.gallery)),
                  ],
                ),
                const SizedBox(height: 16),
                _MethodCard(
                  title: '영수증 없어요',
                  icon: Icons.edit_note,
                  background: _lightRed,
                  foreground: _redText,
                  options: [
                    _Option(Icons.edit, '직접 입력', _openManual),
                    _Option(Icons.search, '메뉴 검색', _openSearch),
                    _Option(Icons.payments, '총액만 나누기', _openTotalSplit),
                  ],
                ),
              ],
            ),
            // 인식 중 로딩 표시
            if (_busy)
              Container(
                color: Colors.black38,
                child: const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 14),
                          Text('AI가 영수증을 읽고 있어요...'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Option {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Option(this.icon, this.label, this.onTap);
}

class _MethodCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color background;
  final Color foreground;
  final List<_Option> options;

  const _MethodCard({
    required this.title,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: foreground),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: foreground)),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in options)
                FilledButton.tonalIcon(
                  onPressed: o.onTap,
                  icon: Icon(o.icon, size: 20),
                  label: Text(o.label),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: foreground,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
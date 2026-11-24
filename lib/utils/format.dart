/// 12345 → "12,345"
String won(num n) {
  final s = n.round().toString();
  return s.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );
}

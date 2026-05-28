// 참조 객체 종류와 실제 크기(mm). W4 단계는 신용카드만 사용.
enum ReferenceObject {
  creditCard(widthMm: 85.6, heightMm: 53.98, label: '신용카드'),
  a4(widthMm: 297.0, heightMm: 210.0, label: 'A4 (가로)'),
  coin100(widthMm: 24.0, heightMm: 24.0, label: '100원 동전'),
  coin500(widthMm: 26.5, heightMm: 26.5, label: '500원 동전');

  const ReferenceObject({
    required this.widthMm,
    required this.heightMm,
    required this.label,
  });

  final double widthMm;
  final double heightMm;
  final String label;
}

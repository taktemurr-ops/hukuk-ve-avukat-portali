import 'package:hukuk_sunucu/hukuk_sunucu.dart';
import 'package:test/test.dart';

void main() {
  final s = AlanSifreleyici(List.generate(32, (i) => i));

  test('şifreler ve çözer; her seferinde farklı nonce', () {
    final a = s.sifrele([1, 2, 3], baglam: 'u1');
    final b = s.sifrele([1, 2, 3], baglam: 'u1');
    expect(a, isNot(equals(b)));
    expect(s.coz(a, baglam: 'u1'), [1, 2, 3]);
  });

  test('başka bağlamda, değiştirilmiş veride veya başka anahtarla çözülmez', () {
    final a = s.sifrele([9, 9, 9], baglam: 'u1');
    expect(() => s.coz(a, baglam: 'u2'), throwsArgumentError);
    final bozuk = [...a]..[a.length - 1] ^= 1;
    expect(() => s.coz(bozuk, baglam: 'u1'), throwsArgumentError);
    expect(() => AlanSifreleyici(List.filled(32, 7)).coz(a, baglam: 'u1'), throwsArgumentError);
    expect(() => AlanSifreleyici([1, 2]), throwsArgumentError);
  });
}

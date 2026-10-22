import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/models.dart' show AppFailure, PhoneVerification;
import 'package:hadi/theme/hadi_colors.dart';

/// Telefonla giriş (Firebase Auth, görünmez reCAPTCHA). Uygulamadaki hesabın telefonu.
/// Uygulama yalnızca ekibe (kurucular, geçici kurucular, yönetici, moderatör ve operasyon rolleri) açılır; diğer hesaplar
/// girişten sonra kapıda durur. Asıl yetki denetimi sunucudadır.
class CrewLoginScreen extends StatefulWidget {
  const CrewLoginScreen({super.key});

  @override
  State<CrewLoginScreen> createState() => _CrewLoginScreenState();
}

class _CrewLoginScreenState extends State<CrewLoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  ConfirmationResult? _confirm;
  PhoneVerification? _demo; // yalnızca yerel demo (PANEL_DEMO)
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  /// 05xx…, 5xx…, 905xx… ya da +90… → +905xxxxxxxxx
  String? _e164(String raw) {
    var d = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (d.startsWith('+')) return RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(d) ? d : null;
    if (d.startsWith('90') && d.length == 12) d = d.substring(2);
    if (d.startsWith('0')) d = d.substring(1);
    return RegExp(r'^5[0-9]{9}$').hasMatch(d) ? '+90$d' : null;
  }

  String _msg(Object e) {
    if (e is AppFailure) return e.message;
    if (e is FirebaseAuthException) {
      return switch (e.code) {
        'invalid-phone-number' => 'Telefon numarası geçersiz.',
        'too-many-requests' => 'Çok fazla deneme yapıldı. Biraz sonra tekrar dene.',
        'invalid-verification-code' => 'Kod yanlış. Kontrol edip tekrar dene.',
        'code-expired' || 'session-expired' => 'Kodun süresi doldu. Yeni kod iste.',
        'captcha-check-failed' => 'Güvenlik doğrulaması başarısız. Sayfayı yenileyip tekrar dene.',
        'unauthorized-domain' => 'Bu alan adı Firebase\'de yetkili değil (README › Kurulum › 3).',
        _ => 'Giriş yapılamadı (${e.code}).',
      };
    }
    return 'Giriş yapılamadı. Bağlantını kontrol edip tekrar dene.';
  }

  Future<void> _send() async {
    final p = _e164(_phone.text);
    if (p == null) {
      setState(() => _error = 'Telefon numaranı 05xx xxx xx xx biçiminde yaz.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final services = SessionScope.read(context).services;
      if (services.isDemo) {
        final v = await services.auth.sendCode(p);
        if (mounted) setState(() => _demo = v);
        return;
      }
      final r = await FirebaseAuth.instance.signInWithPhoneNumber(p);
      if (!mounted) return;
      setState(() => _confirm = r);
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final c = _confirm;
    final code = _code.text.trim();
    if ((c == null && _demo == null) || code.length != 6) {
      setState(() => _error = '6 haneli kodu yaz.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_demo != null) {
        await SessionScope.read(context).services.auth.confirmCode(_demo!, code);
      } else {
        await c!.confirm(code);
      }
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sent = _confirm != null || _demo != null;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('HADİ Crew', textAlign: TextAlign.center, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Uygulamadaki telefon numaranla giriş yap.', textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: HadiColors.ink2)),
              const SizedBox(height: 24),
              if (!sent)
                TextField(
                  controller: _phone,
                  enabled: !_busy,
                  autofocus: true,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: const InputDecoration(labelText: 'Telefon', hintText: '05xx xxx xx xx', prefixIcon: Icon(Icons.phone_rounded)),
                  onSubmitted: (_) => _send(),
                )
              else
                TextField(
                  controller: _code,
                  enabled: !_busy,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  decoration: const InputDecoration(labelText: 'SMS kodu', prefixIcon: Icon(Icons.sms_rounded)),
                  onSubmitted: (_) => _verify(),
                ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: HadiColors.error)),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _busy ? null : (sent ? _verify : _send),
                child: _busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(sent ? 'Giriş yap' : 'Kod gönder'),
              ),
              if (sent)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _confirm = null;
                            _demo = null;
                            _code.clear();
                            _error = null;
                          }),
                  child: const Text('Numarayı değiştir'),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

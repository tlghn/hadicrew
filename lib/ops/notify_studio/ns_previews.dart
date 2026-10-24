// HADİ Crew — Bildirim Stüdyosu: Android / iPhone / Web önizlemeleri ve zengin kart önizlemesi (24 Ekim 2026).
// Görünüm yaklaşıktır: gerçek görünüm telefonun sürümüne, temasına ve tarayıcıya göre biraz değişir.
import 'package:flutter/material.dart';
import 'package:hadi/theme/hadi_colors.dart';

import 'ns_api.dart';

/// {ad} → örnek ad.
String nsSample(String s) => s.replaceAll('{ad}', 'Elif');

class NsPreviews extends StatelessWidget {
  const NsPreviews({super.key, required this.v, this.compact = false});
  final NsVariant v;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Android', _Android(v: v)),
      ('iPhone', _Iphone(v: v)),
      ('Web (tarayıcı)', _Web(v: v)),
      if (v.cardOn) ('Dokununca açılan kart', _CardPreview(v: v)),
    ];
    final t = Theme.of(context).textTheme;
    Widget labeled((String, Widget) x) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(x.$1, style: t.labelLarge?.copyWith(color: HadiColors.ink2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          x.$2,
        ]);
    if (compact) {
      return SizedBox(
        height: v.cardOn ? 420 : 330,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (_, i) => SizedBox(width: 300, child: labeled(items[i])),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final x in items) ...[labeled(x), const SizedBox(height: 18)],
    ]);
  }
}

Widget _img(String? url, {double? h, double r = 10}) {
  if (url == null || url.isEmpty) return const SizedBox.shrink();
  return ClipRRect(
    borderRadius: BorderRadius.circular(r),
    child: Image.network(url, height: h, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(height: h, color: HadiColors.mist)),
  );
}

Widget _logo(double s) => Container(
      width: s,
      height: s,
      decoration: BoxDecoration(color: HadiColors.heyecan, borderRadius: BorderRadius.circular(s * .28)),
      alignment: Alignment.center,
      child: Text('H', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: s * .55)),
    );

/// Android bildirim gölgesi (genişletilmiş).
class _Android extends StatelessWidget {
  const _Android({required this.v});
  final NsVariant v;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFF1F2933), borderRadius: BorderRadius.circular(22)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(color: const Color(0xFFF1F4F7), borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.notifications_rounded, size: 14, color: HadiColors.heyecan),
            const SizedBox(width: 6),
            const Text('HADİ • şimdi', style: TextStyle(fontSize: 11.5, color: Color(0xFF4A5560))),
            const Spacer(),
            const Icon(Icons.expand_less_rounded, size: 16, color: Color(0xFF4A5560)),
          ]),
          const SizedBox(height: 6),
          Text(nsSample(v.title.isEmpty ? 'Başlık' : v.title), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF111111))),
          const SizedBox(height: 2),
          Text(nsSample(v.body.isEmpty ? 'Bildirim metni' : v.body), maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xFF333333), height: 1.3)),
          if (v.image != null) ...[const SizedBox(height: 8), _img(v.image, h: 130)],
          if (v.buttons.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              for (final b in v.buttons)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: TextButton(onPressed: null, child: Text(b.label.toUpperCase(), style: const TextStyle(color: Color(0xFF1A73E8), fontWeight: FontWeight.w700, fontSize: 12.5))),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// iPhone kilit ekranı.
class _Iphone extends StatelessWidget {
  const _Iphone({required this.v});
  final NsVariant v;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3A6073), Color(0xFF16222A)]),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(children: [
        const Text('09:41', style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w300, height: 1)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .78), borderRadius: BorderRadius.circular(18)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _logo(34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(nsSample(v.title.isEmpty ? 'Başlık' : v.title), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Colors.black))),
                  const Text('şimdi', style: TextStyle(fontSize: 11.5, color: Color(0xFF555555))),
                ]),
                const SizedBox(height: 2),
                Text(nsSample(v.body.isEmpty ? 'Bildirim metni' : v.body), maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Colors.black, height: 1.3)),
              ]),
            ),
            if (v.image != null) ...[const SizedBox(width: 8), SizedBox(width: 44, height: 44, child: _img(v.image, h: 44, r: 8))],
          ]),
        ),
        if (v.buttons.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Basılı tutunca: ${v.buttons.map((b) => b.label).join(' · ')}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ]),
    );
  }
}

/// Masaüstü tarayıcı bildirimi (Chrome tarzı).
class _Web extends StatelessWidget {
  const _Web({required this.v});
  final NsVariant v;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF2B2B2B), borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))]),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (v.image != null) ...[_img(v.image, h: 120, r: 6), const SizedBox(height: 10)],
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _logo(36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nsSample(v.title.isEmpty ? 'Başlık' : v.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text(nsSample(v.body.isEmpty ? 'Bildirim metni' : v.body), maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFDDDDDD), fontSize: 12.5, height: 1.3)),
              const SizedBox(height: 4),
              const Text('hadisosyal.com', style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 11.5)),
            ]),
          ),
        ]),
        if (v.buttons.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            for (final b in v.buttons)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(color: const Color(0xFF3C3C3C), borderRadius: BorderRadius.circular(4)),
                  alignment: Alignment.center,
                  child: Text(b.label, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                ),
              ),
          ]),
        ],
        const SizedBox(height: 6),
        const Text('Web\'de ses telefonun/tarayıcının kendi sesidir.', style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 10.5)),
      ]),
    );
  }
}

/// Uygulama içi zengin kart (lib/features/notify_studio/ns_card_screen.dart ile aynı düzen).
class _CardPreview extends StatelessWidget {
  const _CardPreview({required this.v});
  final NsVariant v;

  @override
  Widget build(BuildContext context) {
    final img = v.cardImage ?? v.image;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: HadiColors.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: HadiColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (img != null) ...[AspectRatio(aspectRatio: 16 / 9, child: _img(img, r: 16)), const SizedBox(height: 10)],
        Text(nsSample(v.cardTitle.isEmpty ? v.title : v.cardTitle), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 8),
        if (v.cardAudio != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: HadiColors.aktiviteSoft, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Icon(Icons.play_circle_fill_rounded, color: HadiColors.aktivite, size: 30),
              const SizedBox(width: 8),
              const Expanded(child: Text('Sesli mesaj', style: TextStyle(fontWeight: FontWeight.w700))),
              Text('0:${v.cardAudioSec.toString().padLeft(2, '0')}'),
            ]),
          ),
        Text(nsSample(v.cardBody.isEmpty ? v.body : v.cardBody), maxLines: 6, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.4)),
        const SizedBox(height: 10),
        for (final (i, b) in v.buttons.indexed) ...[
          i == 0 ? FilledButton(onPressed: () {}, child: Text(b.label)) : OutlinedButton(onPressed: () {}, child: Text(b.label)),
          const SizedBox(height: 6),
        ],
      ]),
    );
  }
}

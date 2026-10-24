// HADİ — Kurucu paneli › Fiyatlar › Gelişmiş › "Etkinlik kötüye kullanım ve cezalar".
// Sunucu: yonetim › eventPolicyAdmin (functions/src/event_policy.ts). Okuma yönetim, yazma ana kurucu;
// ceza kaldırma / elle ceza kurucular (gerekçe zorunlu, audit).
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:hadi/data/callables.dart';
import 'package:hadi/data/firebase_services.dart' show kFunctionsRegion;
import 'package:hadi/data/models.dart' show AppFailure;
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/core/ui_gate.dart';

Future<Map<String, Object?>> _call(Map<String, Object?> data) async {
  try {
    final r = await FirebaseFunctions.instanceFor(region: kFunctionsRegion).hadiCallable('eventPolicyAdmin').call(data);
    final d = r.data;
    return d is Map ? d.map((k, v) => MapEntry('$k', v as Object?)) : const {};
  } on FirebaseFunctionsException catch (e) {
    throw AppFailure(e.message ?? 'İşlem tamamlanamadı (${e.code}).');
  }
}

/// Kurucu paneli › Kimlik doğrulama: "Etkinliğe katılımda kimlik doğrulaması" (config/events.idRequirement).
/// Sunucu: yonetim › eventPolicyAdmin { idReqGet | idReqSet } (identity_gate.ts). Değiştirmek kuruculara açık;
/// gerekçe zorunlu (≥10 karakter) ve audit kaydı tutulur. Etkinliğe özel ayar (events/{id}.idRequired) bunun önündedir.
class EventIdRequirementCard extends StatefulWidget {
  const EventIdRequirementCard({super.key});
  @override
  State<EventIdRequirementCard> createState() => _EventIdRequirementCardState();
}

class _EventIdRequirementCardState extends State<EventIdRequirementCard> {
  static const _labels = {'all': 'Tüm etkinlikler', 'paid_only': 'Yalnızca ücretli', 'none': 'Zorunlu değil'};
  String? _value;
  String _reason = '';
  bool _canEdit = false, _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _call({'op': 'idReqGet'});
      if (!mounted) return;
      setState(() {
        _value = '${r['idRequirement'] ?? 'all'}';
        _canEdit = r['canEdit'] == true;
        _reason = '${r['reason'] ?? ''}';
        _err = null;
      });
    } on AppFailure catch (e) {
      if (mounted) setState(() => _err = e.message);
    }
  }

  Future<void> _change(String next) async {
    if (next == _value) return;
    final reason = TextEditingController();
    final ok = await uiOnce(context, () => showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: Text('Kimlik doğrulaması: ${_labels[next]}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(switch (next) {
            'paid_only' => 'Ücretsiz etkinliklere kimlik doğrulaması olmadan katılınabilir; ücretli etkinliklerde istenir.',
            'none' => 'Etkinliklere katılımda kimlik doğrulaması istenmez (etkinliğe özel "Gerekli" ayarı olanlar hariç).',
            _ => 'Her etkinliğe katılımda kimlik doğrulaması istenir (etkinliğe özel "Gerekmez" ayarı olanlar hariç).',
          }),
          const SizedBox(height: 10),
          TextField(controller: reason, maxLength: 300, decoration: const InputDecoration(labelText: 'Gerekçe (zorunlu, en az 10 karakter)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Uygula')),
        ],
      ),
    ));
    final why = reason.text.trim();
    reason.dispose();
    if (ok != true || !mounted) return;
    if (why.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('En az 10 karakterlik bir gerekçe yaz.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await _call({'op': 'idReqSet', 'value': next, 'reason': why});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedildi: ${_labels[next]}.')));
      await _load();
    } on AppFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = _value;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: theme.dividerColor.withValues(alpha: .4))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.event_available_rounded, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Etkinliğe katılımda kimlik doğrulaması', style: theme.textTheme.titleSmall)),
          ]),
          const SizedBox(height: 8),
          if (v == null)
            (_err != null ? Text(_err!, style: TextStyle(color: HadiColors.text(HadiColors.error))) : const LinearProgressIndicator())
          else ...[
            SegmentedButton<String>(
              segments: [
                for (final e in _labels.entries)
                  ButtonSegment(value: e.key, label: FittedBox(fit: BoxFit.scaleDown, child: Text(e.value, maxLines: 1))),
              ],
              selected: {v},
              showSelectedIcon: false,
              onSelectionChanged: (!_canEdit || _busy) ? null : (s) => _change(s.first),
            ),
            const SizedBox(height: 6),
            Text(
              '${_canEdit ? '' : 'Değiştirmek kuruculara açık. '}Etkinliğe özel ayar (etkinlik düzenleme › Katılımda kimlik doğrulaması) bunun önündedir. '
              'Kurucular ve test kullanıcıları her durumda muaftır.${_reason.isNotEmpty ? '\nSon gerekçe: $_reason' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(color: HadiColors.ink2),
            ),
          ],
        ]),
      ),
    );
  }
}

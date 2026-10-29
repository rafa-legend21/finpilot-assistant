import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/voice_input.dart';
import 'clarification_page.dart';
import 'draft_review_page.dart';
import 'models/financial_review_models.dart';

enum _VoiceLanguage {
  zh('中文', 'zh-cn'),
  en('English', 'en-us'),
  fr('Français', 'fr-fr');

  const _VoiceLanguage(this.label, this.localeId);
  final String label;
  final String localeId;
}

class JournalEntryPage extends StatefulWidget {
  const JournalEntryPage({required this.api, this.voiceInput, super.key});
  final FinPilotApi api;
  final VoiceInput? voiceInput;

  @override
  State<JournalEntryPage> createState() => _JournalEntryPageState();
}

class _JournalEntryPageState extends State<JournalEntryPage> {
  final _controller = TextEditingController();
  late final VoiceInput _voice = widget.voiceInput ?? DeviceVoiceInput();
  _VoiceLanguage _language = _VoiceLanguage.en;
  CurrencyCode _currency = CurrencyCode.CAD;
  DateTime? _referenceDate;
  bool _loading = false;
  bool _listening = false;
  int _voiceSession = 0;
  String _voiceBaseText = '';
  String? _error;

  String _t(String zh, String en, String fr) => switch (_language) {
        _VoiceLanguage.zh => zh,
        _VoiceLanguage.en => en,
        _VoiceLanguage.fr => fr,
      };

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _voice.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    setState(() => _error = null);
    try {
      final ready = await _voice.initialize(
        onStatus: (status) {
          if (mounted && (status == 'done' || status == 'notListening')) {
            setState(() => _listening = false);
          }
        },
        onError: () {
          if (mounted) {
            setState(() {
              _listening = false;
              _error = _t(
                  '语音识别失败，请重试或改用文字输入。',
                  'Speech recognition failed. Try again or type your story.',
                  'La reconnaissance vocale a échoué. Réessayez ou saisissez votre récit.');
            });
          }
        },
      );
      if (!mounted) return;
      if (!ready) {
        setState(() => _error = _t(
            '无法使用麦克风。请检查权限或改用文字输入。',
            'Microphone unavailable. Check permissions or type your story.',
            'Microphone indisponible. Vérifiez les autorisations ou saisissez votre récit.'));
        return;
      }
      final locales = await _voice.availableLocales();
      if (!mounted) return;
      final matching = locales.where((id) =>
          id.toLowerCase().split(RegExp('[-_]')).first == _language.name);
      if (matching.isEmpty) {
        setState(() => _error = _t(
            '此设备没有所选语言的语音识别功能。',
            'This device does not support speech recognition in that language.',
            'Cet appareil ne prend pas en charge la reconnaissance vocale dans cette langue.'));
        return;
      }
      final localeId = matching.firstWhere(
        (id) => id.toLowerCase().replaceAll('_', '-') == _language.localeId,
        orElse: () => matching.first,
      );
      _voiceBaseText = _controller.text.trimRight();
      final session = ++_voiceSession;
      setState(() => _listening = true);
      await _voice.listen(
        localeId: localeId,
        onWords: (words) {
          if (!mounted || session != _voiceSession) return;
          final prefix = _voiceBaseText.isEmpty ? '' : '$_voiceBaseText ';
          _controller.text = '$prefix$words';
          _controller.selection =
              TextSelection.collapsed(offset: _controller.text.length);
          setState(() {});
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _listening = false;
          _error = _t(
              '无法启动语音输入，请改用文字输入。',
              'Could not start voice input. Please type your story.',
              'Impossible de démarrer la saisie vocale. Veuillez saisir votre récit.');
        });
      }
    }
  }

  @override
  void dispose() {
    if (_listening) _voice.stop();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading || _listening) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.createDraftFromJournal(
        text: text,
        defaultCurrency: _currency,
        referenceDate: _referenceDate,
        responseLanguage: _language.name,
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => result.clarificationState == 'awaiting_required'
            ? ClarificationPage(
                api: widget.api,
                journal: text,
                initialState: result,
                responseLanguage: _language.name,
              )
            : DraftReviewPage(
                api: widget.api,
                initialDraft: result.draft,
                responseLanguage: _language.name,
              ),
      ));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _t(
            '无法准备草稿，请重试。',
            'Unable to prepare your draft. Please try again.',
            'Impossible de préparer votre brouillon. Veuillez réessayer.'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_t('告诉 FinPilot 你的故事', 'Tell FinPilot your story',
              'Racontez votre histoire à FinPilot'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(_t(
              '自然地说或写。只有在你核对并确认后，记录才会加入账本。',
              'Speak or write naturally. Nothing is added to your ledger until you review and confirm.',
              'Parlez ou écrivez librement. Rien n’est ajouté à vos comptes avant votre vérification et confirmation.')),
          const SizedBox(height: 16),
          DropdownButtonFormField<_VoiceLanguage>(
            key: const Key('voiceLanguage'),
            initialValue: _language,
            decoration: InputDecoration(
                labelText: _t('输入与回复语言', 'Input and reply language',
                    'Langue de saisie et de réponse')),
            items: _VoiceLanguage.values
                .map((language) => DropdownMenuItem(
                    value: language, child: Text(language.label)))
                .toList(),
            onChanged: _loading || _listening
                ? null
                : (value) {
                    if (value != null) setState(() => _language = value);
                  },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('voiceButton'),
            onPressed: _loading ? null : _toggleVoice,
            icon:
                Icon(_listening ? Icons.stop_circle_outlined : Icons.mic_none),
            label: Text(_listening
                ? _t('停止录音', 'Stop listening', 'Arrêter l’écoute')
                : _t('语音输入', 'Speak', 'Parler')),
          ),
          const SizedBox(height: 8),
          Text(_t(
              '请核对下面的转写文字，尤其是金额和付款人。',
              'Check the transcript below, especially amounts and who paid.',
              'Vérifiez la transcription ci-dessous, surtout les montants et qui a payé.')),
          const SizedBox(height: 12),
          TextField(
            key: const Key('journalField'),
            controller: _controller,
            minLines: 7,
            maxLines: 12,
            enabled: !_loading && !_listening,
            decoration: InputDecoration(
              labelText: _t('日记内容', 'Journal entry', 'Entrée du journal'),
              hintText: _t('我和朋友一起吃了晚饭……', 'I had dinner with a friend…',
                  'J’ai dîné avec un ami…'),
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            onChanged: (_) {
              if (!_listening) _voiceSession++;
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<CurrencyCode>(
            initialValue: _currency,
            decoration: InputDecoration(
                labelText: _t('默认货币', 'Default currency', 'Devise par défaut')),
            items: CurrencyCode.values
                .map((currency) => DropdownMenuItem(
                    value: currency, child: Text(currency.name)))
                .toList(),
            onChanged: _loading || _listening
                ? null
                : (value) => setState(() => _currency = value!),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loading || _listening
                ? null
                : () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: _referenceDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (selected != null) {
                      setState(() => _referenceDate = selected);
                    }
                  },
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(_referenceDate == null
                ? _t('添加参考日期（可选）', 'Add reference date (optional)',
                    'Ajouter une date de référence (facultatif)')
                : '${_referenceDate!.year}-${_referenceDate!.month.toString().padLeft(2, '0')}-${_referenceDate!.day.toString().padLeft(2, '0')}'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!,
                key: const Key('journalError'),
                style: TextStyle(color: Colors.red.shade700)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('journalSubmit'),
            onPressed: _controller.text.trim().isEmpty || _loading || _listening
                ? null
                : _submit,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(_loading
                ? _t('正在理解你的故事…', 'Understanding your story…',
                    'Analyse de votre récit…')
                : _t('核对财务事件', 'Review financial events',
                    'Vérifier les événements financiers')),
          ),
        ],
      ),
    );
  }
}

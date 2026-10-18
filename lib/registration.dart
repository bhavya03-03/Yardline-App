import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'controller.dart';
import 'domain.dart';
import 'services.dart';
import 'ui.dart';

class RegistrationScreen extends StatefulWidget {
  final YardController controller;
  final XFile? recovered;
  final VoidCallback? onRecovered;
  const RegistrationScreen({
    super.key,
    required this.controller,
    this.recovered,
    this.onRecovered,
  });
  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final number = TextEditingController(),
      owner = TextEditingController(),
      type = TextEditingController(text: 'Dry'),
      notes = TextEditingController();
  final form = GlobalKey<FormState>();
  final ocr = OcrService();
  late final String yardId;
  int size = 40;
  String? slotId, photoPath, rawText;
  List<String> candidates = [];
  bool working = false,
      restoring = true,
      identityConfirmed = false,
      attach = false;
  Timer? draftTimer;
  YardController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    yardId = c.snapshot!.yard.id;
    restore();
  }

  Future<void> restore() async {
    try {
      final saved = await c.draft();
      if (!mounted) return;
      if (saved != null) {
        final d = jsonDecode(saved) as Json;
        if (d['yardId'] == c.snapshot!.yard.id) {
          number.text = string(d['number']);
          owner.text = string(d['owner']);
          type.text = string(d['type']).isEmpty ? 'Dry' : string(d['type']);
          notes.text = string(d['notes']);
          size = [20, 40, 45].contains(integer(d['size']))
              ? integer(d['size'])
              : 40;
          slotId = d['slotId'] as String?;
          final path = d['photoPath'] as String?;
          if (path != null && await File(path).exists()) photoPath = path;
        }
      }
    } catch (_) {
      /* Damaged local drafts do not affect shared records. */
    } finally {
      if (mounted) setState(() => restoring = false);
    }
    if (widget.recovered != null && mounted) {
      await recognize(widget.recovered!);
      widget.onRecovered?.call();
    }
  }

  Json get draft => {
    'yardId': yardId,
    'number': number.text,
    'size': size,
    'type': type.text,
    'owner': owner.text,
    'notes': notes.text,
    'slotId': slotId,
    'photoPath': photoPath,
  };
  void saveDraft() {
    draftTimer?.cancel();
    final value = draft;
    draftTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        await c.saveDraft(value);
      } catch (_) {
        if (mounted) {
          message(context, 'The draft could not be saved on this device.');
        }
      }
    });
  }

  @override
  void dispose() {
    if (draftTimer?.isActive == true && !restoring) {
      unawaited(c.saveDraft(draft).catchError((Object _) {}));
    }
    draftTimer?.cancel();
    number.dispose();
    owner.dispose();
    type.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> pick(ImageSource source) async {
    // Save text before handing control to the system camera (Android may kill us).
    try {
      await c.saveDraft(draft);
      if (!mounted) return;
      setState(() => working = true);
      final image = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (image != null && mounted) await recognize(image);
    } on PlatformException catch (e) {
      if (mounted) {
        message(
          context,
          e.code.contains('denied')
              ? 'Camera or photo access was denied. Enable it in Android settings, or enter the number manually.'
              : 'The camera could not open. Try the photo library or enter the number manually.',
        );
      }
    } catch (_) {
      if (mounted) {
        message(
          context,
          'Capture was interrupted. Your text draft is saved; you can enter the number manually.',
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> recognize(XFile image) async {
    if (!mounted) return;
    setState(() {
      working = true;
      photoPath = image.path;
      identityConfirmed = false;
      attach = false;
      number.clear();
      rawText = null;
      candidates = [];
    });
    saveDraft();
    try {
      final result = await ocr.recognize(image.path);
      if (!mounted) return;
      setState(() {
        rawText = result.text;
        candidates = result.candidates;
        if (candidates.isNotEmpty) number.text = candidates.first;
      });
      saveDraft();
      if (candidates.isEmpty) {
        message(
          context,
          'No complete container number found. Retake a closer photo or enter the number manually.',
        );
      }
    } catch (_) {
      if (mounted) {
        message(
          context,
          'Text recognition failed. You can still read the photo and type the number.',
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> choosePosition() async {
    await c.refresh();
    if (!mounted) return;
    final selected = await Navigator.push<Slot>(
      context,
      MaterialPageRoute(
        builder: (_) => YardPositions(controller: c, size: size),
      ),
    );
    if (selected != null && mounted) {
      setState(() => slotId = selected.id);
      saveDraft();
    }
  }

  Future<void> submit() async {
    if (!form.currentState!.validate() || !identityConfirmed) return;
    if (!await c.refresh()) {
      if (mounted) message(context, c.error!);
      return;
    }
    if (!mounted) return;
    final n = normalizeNumber(number.text);
    final existing = c.snapshot!.containers
        .where((v) => normalizeNumber(v.number) == n)
        .firstOrNull;
    if (existing != null) {
      openContainer(context, c, existing.id);
      return;
    }
    final selected = c.snapshot!.slot(slotId);
    if (slotId != null &&
        (selected == null ||
            c.snapshot!.destinationProblem(selected, size) != null)) {
      setState(() => slotId = null);
      saveDraft();
      message(
        context,
        'That position is no longer eligible. Choose a new position.',
      );
      return;
    }
    String? photo;
    if (attach && photoPath != null) {
      try {
        photo = await ocr.attachment(XFile(photoPath!));
      } catch (_) {
        /* Missing temporary file is explained below. */
      }
      if (photo == null) {
        if (mounted) {
          message(
            context,
            'This image is too large, unsupported, or no longer on the device. Turn off attachment or capture a smaller JPEG.',
          );
        }
        return;
      }
    }
    if (!mounted) return;
    final confirmed = await confirmOperation(
      context,
      title: 'Register container / gate-in',
      details:
          '$n\n$size ft · ${type.text.trim()}\n${selected?.code ?? 'Register as unassigned'}',
      confirmation: selected == null
          ? 'I checked the identity and confirm this container has arrived at the yard.'
          : 'I physically checked the container identity and its placement at this position.',
      notes: false,
    );
    if (confirmed == null || !mounted) return;
    setState(() => working = true);
    try {
      final id = await c.mutate('register', {
        'yardId': c.snapshot!.yard.id,
        'number': n,
        'size': size,
        'type': type.text.trim(),
        'owner': owner.text.trim(),
        'notes': notes.text.trim(),
        'slotId': slotId,
        'physicalConfirmed': selected != null,
        'allowException': false,
        'photo': ?photo,
      });
      draftTimer?.cancel();
      await c.clearDraft();
      if (!mounted) return;
      setState(() {
        number.clear();
        owner.clear();
        type.text = 'Dry';
        notes.clear();
        slotId = null;
        photoPath = null;
        rawText = null;
        candidates = [];
        identityConfirmed = false;
        attach = false;
      });
      message(context, 'Container registered in the shared yard.');
      if (id != null) openContainer(context, c, id);
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (restoring) {
      return const Center(child: CircularProgressIndicator(color: ink));
    }
    final n = normalizeNumber(number.text), valid = validNumber(number.text);
    final existing = c.snapshot!.containers
        .where((v) => normalizeNumber(v.number) == n && n.isNotEmpty)
        .firstOrNull;
    final selected = c.snapshot!.slot(slotId);
    return Form(
      key: form,
      child: bodyList([
        pageTitle(
          context,
          'Scan. Check.\nKeep it moving.',
          'Read the container number on this device, then confirm what you see.',
        ),
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              eyebrow('01 / Capture identity'),
              const SizedBox(height: 20),
              if (photoPath != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(photoPath!),
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Text(
                      'Capture a new photo to replace the expired image.',
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: working ? null : () => pick(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text(working ? 'Reading image…' : 'Take a photo'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: working ? null : () => pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose a photo'),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Fill the frame with all 11 characters. Avoid glare; use a straight, sharp image. Manual entry is always available.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        eyebrow('02 / Review the number'),
        const SizedBox(height: 16),
        if (candidates.length > 1) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in candidates)
                ActionChip(
                  label: Text(value),
                  onPressed: () {
                    setState(() {
                      number.text = value;
                      identityConfirmed = false;
                    });
                    saveDraft();
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        TextFormField(
          controller: number,
          enabled: !working,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          maxLength: 30,
          style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
          decoration: const InputDecoration(
            labelText: 'Container number',
            hintText: 'MSCU1234566',
          ),
          onChanged: (_) {
            setState(() => identityConfirmed = false);
            saveDraft();
          },
          validator: (v) => validNumber(v ?? '') ? null : 'Use 3 owner letters, U/J/Z, and 7 digits with a valid ISO check digit.',
        ),
        if (number.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            valid ? 'ISO 6346 format and check digit verified.' : 'The number does not pass ISO 6346 validation. Check all characters against the container.',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
        if (rawText != null) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('View recognized text'),
            children: [
              SelectableText(rawText!),
              const SizedBox(height: 8),
              const Text(
                'OCR is a suggestion. O, I, and L in the numeric portion may be suggested as 0 or 1. A check digit is never invented or changed automatically.',
              ),
              const SizedBox(height: 16),
            ],
          ),
        ],
        if (existing != null) ...[
          const SizedBox(height: 20),
          panel(
            color: cream,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Already registered',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                Text(existing.locationCode ?? existing.status),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => openContainer(context, c, existing.id),
                  child: const Text('Open existing container'),
                ),
              ],
            ),
          ),
        ],
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'I checked the number against the physical container.',
          ),
          value: identityConfirmed,
          onChanged: valid && !working
              ? (v) {
                  setState(() => identityConfirmed = v ?? false);
                }
              : null,
        ),
        const SizedBox(height: 28),
        eyebrow('03 / Container & placement'),
        const SizedBox(height: 16),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 20, label: Text('20 ft')),
            ButtonSegment(value: 40, label: Text('40 ft')),
            ButtonSegment(value: 45, label: Text('45 ft')),
          ],
          selected: {size},
          onSelectionChanged: working
              ? null
              : (v) {
                  setState(() {
                    size = v.first;
                    slotId = null;
                  });
                  saveDraft();
                },
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: type,
          enabled: !working,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Container type'),
          onChanged: (_) => saveDraft(),
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'Enter the container type.' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: owner,
          enabled: !working,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Owner (optional)'),
          onChanged: (_) => saveDraft(),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: notes,
          enabled: !working,
          maxLength: 1500,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Registration notes (optional)',
          ),
          onChanged: (_) => saveDraft(),
        ),
        const SizedBox(height: 16),
        panel(
          color: cream,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              eyebrow('Assigned position'),
              const SizedBox(height: 12),
              Text(
                selected?.shortCode ?? 'Unassigned',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Choose the position where the container was physically placed, or register it as unassigned.',
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: working || !c.online ? null : choosePosition,
                child: const Text('Choose yard position'),
              ),
              if (slotId != null)
                TextButton(
                  onPressed: working
                      ? null
                      : () {
                          setState(() => slotId = null);
                          saveDraft();
                        },
                  child: const Text('Keep unassigned'),
                ),
            ],
          ),
        ),
        if (photoPath != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Attach this photo to registration'),
            subtitle: const Text(
              'Optional upload to the shared backend. OCR itself stays on this device.',
            ),
            value: attach,
            onChanged: working ? null : (v) => setState(() => attach = v),
          ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed:
              c.canWrite &&
                  valid &&
                  identityConfirmed &&
                  existing == null &&
                  !working
              ? submit
              : null,
          child: Text(working ? 'Submitting…' : 'Review registration'),
        ),
        const SizedBox(height: 12),
        Text(
          c.online
              ? 'Text drafts are saved on this device. Placement and identity must be reviewed again before submission.'
              : 'Offline: you can scan and save a draft. Reconnect and refresh before submitting.',
        ),
        const SizedBox(height: 20),
      ]),
    );
  }
}

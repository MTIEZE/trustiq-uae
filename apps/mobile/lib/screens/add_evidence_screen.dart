import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:trustiq_core/trustiq_core.dart';

import '../app_state.dart';
import '../data/demo_data.dart';
import '../data/evidence_service.dart';
import '../theme.dart';
import 'dispute_screen.dart' show unreadableNote;
import '../widgets/common.dart';

/// Filing a document against a contract.
///
/// The screen is careful about one thing above all: it never presents a
/// fingerprint the device produced as the one on the record. The digest shown
/// after a successful upload is the one computed from the bytes that were
/// stored. Before that point there is nothing to show, and the screen says so
/// rather than filling the space with a number that would not be the one kept.
class AddEvidenceScreen extends StatefulWidget {
  const AddEvidenceScreen({
    super.key,
    required this.contractId,
    required this.state,
  });

  final String contractId;
  final AppState state;

  @override
  State<AddEvidenceScreen> createState() => _AddEvidenceScreenState();
}

/// What the picker gave us, already read into memory.
class _Chosen {
  const _Chosen({required this.name, required this.contentType, required this.bytes});
  final String name;
  final String contentType;
  final Uint8List bytes;
  int get size => bytes.length;
}

class _AddEvidenceScreenState extends State<AddEvidenceScreen> {
  final _note = TextEditingController();

  _Chosen? _chosen;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf', 'png', 'jpg', 'jpeg', 'webp', 'txt', 'md', 'csv', 'zip', 'doc', 'docx',
        ],
      );
      if (files.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      final file = files.first;
      final bytes = await file.readAsBytes();
      final contentType = _contentTypeFor(file.extension);

      // Tell the person now what the server would tell them after the upload.
      // The server checks the same things again; this is a courtesy, not a
      // control.
      final rejection = checkEvidenceShape(
        filename: file.name,
        contentType: contentType,
        byteSize: bytes.length,
      );

      if (!mounted) return;
      setState(() {
        _busy = false;
        if (rejection != null) {
          _chosen = null;
          _error = evidenceRejectionMessage(rejection);
        } else {
          _chosen = _Chosen(name: file.name, contentType: contentType, bytes: bytes);
          _error = null;
        }
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'That file could not be read: $error';
      });
    }
  }

  Future<void> _upload() async {
    final chosen = _chosen;
    if (chosen == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await widget.state.fileEvidence(
      contractId: widget.contractId,
      filename: chosen.name,
      contentType: chosen.contentType,
      bytes: chosen.bytes,
      note: _note.text,
    );

    if (!mounted) return;

    switch (result) {
      case EvidenceRefused(:final message):
        setState(() {
          _busy = false;
          _error = message;
        });
      case EvidenceUploaded(:final item):
        setState(() => _busy = false);
        await _showRecorded(item);
        if (mounted) Navigator.of(context).pop();
    }
  }

  /// Shows the digest that was recorded, and says plainly whose it is.
  Future<void> _showRecorded(EvidenceItem item) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Filed'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.filename} is on the record and can no longer be changed '
                'or removed, by you or by the other party.',
                style: Type.body,
              ),
              const SizedBox(height: Space.lg),
              const SectionLabel('Fingerprint recorded by TrustIQ'),
              const SizedBox(height: 6),
              SelectableText(
                item.sha256,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  height: 1.4,
                  color: TrustIqColors.inkSoft,
                ),
              ),
              const SizedBox(height: Space.md),
              const RuleNote(
                'This was calculated from the bytes that were stored, not from '
                'anything your device reported. That is what makes it worth '
                'something later.',
                icon: Icons.fingerprint,
              ),
              // Said here rather than left to be discovered later. If the
              // resolution is going to be decided without this document's
              // contents, the moment to learn that is now, while the person is
              // still holding the file and can send a readable version.
              if (!item.extractionStatus.wasRead) ...[
                const SizedBox(height: Space.md),
                RuleNote(
                  unreadableNote(item.extractionStatus),
                  icon: Icons.visibility_off_outlined,
                ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Add evidence',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.section),
        children: [
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('The file'),
                const SizedBox(height: Space.md),
                if (chosen == null)
                  // A target rather than a button. Choosing a file is the
                  // whole point of this screen, so it gets the space that
                  // says so.
                  InkWell(
                    onTap: _busy ? null : _pick,
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: Space.xxl),
                      decoration: BoxDecoration(
                        color: TrustIqColors.surfaceSunken,
                        borderRadius: BorderRadius.circular(Radii.md),
                        border: Border.all(color: TrustIqColors.ruleStrong),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _busy ? Icons.hourglass_empty : Icons.upload_file_outlined,
                            size: 26,
                            color: TrustIqColors.accent,
                          ),
                          const SizedBox(height: Space.md),
                          Text(
                            _busy ? 'Reading the file' : 'Choose a file',
                            style: Type.bodyStrong.copyWith(color: TrustIqColors.accentStrong),
                          ),
                          const SizedBox(height: Space.xs),
                          Text(
                            'PDF, image, document, text or zip',
                            style: Type.caption.copyWith(color: TrustIqColors.inkFaint),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  _ChosenFile(chosen: chosen, onReplace: _busy ? null : _pick),
                if (_error != null) ...[
                  const SizedBox(height: Space.md),
                  _ErrorNote(_error!),
                ],
                const SizedBox(height: Space.lg),
                const RuleNote(
                  'PDFs, images, documents, plain text and zip archives, up to '
                  '50 MB. The other party sees everything you file here.',
                  icon: Icons.folder_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Note (optional)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _note,
                  maxLines: 3,
                  maxLength: 2000,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    hintText: 'What this shows, and why it matters.',
                    counterText: '',
                  ),
                  style: Type.body,
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.xxl),
          FilledButton(
            onPressed: (chosen == null || _busy) ? null : _upload,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text('File this evidence'),
          ),
          const SizedBox(height: Space.md),
          const RuleNote(
            'Once filed, a document cannot be edited or withdrawn. A fingerprint '
            'of it is recorded so either of you can prove, later, that it is the '
            'file that was submitted.',
            icon: Icons.lock_outline,
          ),
        ],
      ),
    );
  }

  /// Maps the picker's extension to the content type the policy accepts.
  ///
  /// Anything unmapped becomes octet-stream, which the policy refuses. That is
  /// the intended outcome: an unrecognised file should be turned away rather
  /// than guessed at.
  static String _contentTypeFor(String? extension) {
    return switch (extension?.toLowerCase()) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'txt' => 'text/plain',
      'md' => 'text/markdown',
      'csv' => 'text/csv',
      'zip' => 'application/zip',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      _ => 'application/octet-stream',
    };
  }
}

class _ChosenFile extends StatelessWidget {
  const _ChosenFile({required this.chosen, required this.onReplace});
  final _Chosen chosen;
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.description_outlined, size: 20, color: TrustIqColors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chosen.name,
                style: Type.bodyStrong,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                humanSize(chosen.size),
                style: const TextStyle(fontSize: 12, color: TrustIqColors.inkFaint),
              ),
            ],
          ),
        ),
        TextButton(onPressed: onReplace, child: const Text('Change')),
      ],
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TrustIqColors.criticalSoft,
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: TrustIqColors.critical, width: 2.5),
        ),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 13,
          height: 1.45,
          color: TrustIqColors.critical,
        ),
      ),
    );
  }
}

/// Exposed for tests, which assert on what a person actually reads.
String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes bytes';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

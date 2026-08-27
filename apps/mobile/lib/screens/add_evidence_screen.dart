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
        _error = context.l.fileCouldNotBeRead('$error');
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
        title: Text(context.l.filed),
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
              SectionLabel(context.l.fingerprintRecorded),
              const SizedBox(height: 6),
              SelectableText(
                item.sha256,
                style: Type.mono.copyWith(
                  fontSize: 10.5,
                  color: context.c.inkSoft,
                ),
              ),
              const SizedBox(height: Space.md),
              RuleNote(
                context.l.fingerprintNote,
                icon: Icons.fingerprint,
              ),
              // Said here rather than left to be discovered later. If the
              // resolution is going to be decided without this document's
              // contents, the moment to learn that is now, while the person is
              // still holding the file and can send a readable version.
              if (!item.extractionStatus.wasRead) ...[
                const SizedBox(height: Space.md),
                RuleNote(
                  unreadableNote(item.extractionStatus, context.l),
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
            child: Text(context.l.done),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final l = context.l;
    final chosen = _chosen;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.addEvidence),
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(Space.lg, Space.md, Space.lg, Space.section),
        children: [
          InfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel(l.theFile),
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
                        color: c.surfaceSunken,
                        borderRadius: BorderRadius.circular(Radii.md),
                        border: Border.all(color: c.ruleStrong),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _busy ? Icons.hourglass_empty : Icons.upload_file_outlined,
                            size: IconSize.xl,
                            color: c.accent,
                          ),
                          const SizedBox(height: Space.md),
                          Text(
                            _busy ? l.readingTheFile : l.chooseAFile,
                            style: Type.bodyStrong.copyWith(color: c.accentStrong),
                          ),
                          const SizedBox(height: Space.xs),
                          Text(
                            l.fileTypesShort,
                            style: Type.caption.copyWith(color: c.inkFaint),
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
                RuleNote(
                  l.fileTypesNote,
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
                SectionLabel(l.noteOptional),
                const SizedBox(height: 8),
                TextField(
                  controller: _note,
                  maxLines: 3,
                  maxLength: 2000,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    hintText: l.noteHint,
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
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: c.onAccent),
                  )
                : Text(l.fileThisEvidence),
          ),
          const SizedBox(height: Space.md),
          RuleNote(
            l.evidencePermanentNote,
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
    final c = context.c;
    return Row(
      children: [
        Icon(Icons.description_outlined, size: IconSize.lg, color: c.accent),
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
                style: TextStyle(fontSize: 12, color: c.inkFaint),
              ),
            ],
          ),
        ),
        TextButton(onPressed: onReplace, child: Text(context.l.change)),
      ],
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.criticalSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: c.critical, width: 2.5),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 13,
          height: 1.45,
          color: c.critical,
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

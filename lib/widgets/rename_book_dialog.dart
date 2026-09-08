import 'package:flutter/material.dart';

import '../theme/book_and_quill_theme.dart';

Future<String?> showRenameBookDialog(
  BuildContext context, {
  required String currentTitle,
}) async {
  return _showRenameDialog(
    context,
    currentValue: currentTitle,
    title: 'Rename book',
    hintText: 'Book name',
  );
}

Future<String?> showRenameShelfDialog(
  BuildContext context, {
  required String currentName,
}) {
  return _showRenameDialog(
    context,
    currentValue: currentName,
    title: 'Rename shelf',
    hintText: 'Shelf name',
  );
}

Future<String?> _showRenameDialog(
  BuildContext context, {
  required String currentValue,
  required String title,
  required String hintText,
}) async {
  final value = await showDialog<String>(
    context: context,
    builder: (dialogContext) => _RenameDialog(
      initialValue: currentValue,
      title: title,
      hintText: hintText,
    ),
  );
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({
    required this.initialValue,
    required this.title,
    required this.hintText,
  });

  final String initialValue;
  final String title;
  final String hintText;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _input;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.initialValue);
    _input.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialValue.length,
    );
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_input.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: BookAndQuillColors.woodDark,
      title: Text(widget.title),
      content: TextField(
        controller: _input,
        autofocus: true,
        maxLength: 32,
        decoration: InputDecoration(hintText: widget.hintText),
        onSubmitted: (_) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('RENAME'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/book_and_quill_theme.dart';

/// The route owns its input controller through the entire dismissal animation.
class BookTextEntryDialog extends StatefulWidget {
  const BookTextEntryDialog({
    required this.title,
    required this.initialValue,
    required this.label,
    required this.submitLabel,
    this.message,
    this.numeric = false,
    this.maxLength,
    super.key,
  });

  final String title;
  final String initialValue;
  final String label;
  final String submitLabel;
  final String? message;
  final bool numeric;
  final int? maxLength;

  @override
  State<BookTextEntryDialog> createState() => _BookTextEntryDialogState();
}

class _BookTextEntryDialogState extends State<BookTextEntryDialog> {
  late final TextEditingController _input =
      TextEditingController(text: widget.initialValue);

  void _submit() => Navigator.of(context).pop(_input.text.trim());

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: BookAndQuillColors.woodDark,
    title: Text(widget.title),
    content: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.message != null) ...<Widget>[
          Text(widget.message!), const SizedBox(height: 14),
        ],
        TextField(
          controller: _input,
          autofocus: true,
          maxLength: widget.maxLength,
          keyboardType: widget.numeric ? TextInputType.number : TextInputType.text,
          textInputAction: TextInputAction.done,
          inputFormatters: widget.numeric
              ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
              : null,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (_) => _submit(),
        ),
      ],
    )),
    actions: <Widget>[
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('CANCEL')),
      TextButton(onPressed: _submit, child: Text(widget.submitLabel)),
    ],
  );
}

import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CopyableLink extends StatefulWidget {
  final String text;

  const CopyableLink({super.key, required this.text});

  @override
  State<CopyableLink> createState() => _CopyableLinkState();
}

class _CopyableLinkState extends State<CopyableLink> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _copy,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border.all(color: air.hairline),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.monoValue(color: air.ink, size: 13),
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              _copied ? Icons.check : Icons.content_copy,
              size: 16,
              color: _copied ? air.connectedInk : air.steel,
            ),
          ],
        ),
      ),
    );
  }
}

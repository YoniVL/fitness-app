import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Compact number field with -/+ buttons. Works for reps (step 1) and weight
/// (step 2.5). Keeps an internal controller in sync with [value].
class NumberStepper extends StatefulWidget {
  const NumberStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.step = 1,
    this.min = 0,
    this.decimals = 0,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double step;
  final double min;
  final int decimals;

  @override
  State<NumberStepper> createState() => _NumberStepperState();
}

class _NumberStepperState extends State<NumberStepper> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.value));

  String _format(double v) =>
      widget.decimals == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(widget.decimals);

  @override
  void didUpdateWidget(NumberStepper old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _parse(_controller.text) != widget.value) {
      _controller.text = _format(widget.value);
    }
  }

  double? _parse(String text) => double.tryParse(text.replaceAll(',', '.'));

  void _bump(double delta) {
    final next = (widget.value + delta).clamp(widget.min, double.infinity);
    widget.onChanged(next.toDouble());
    _controller.text = _format(next.toDouble());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              onPressed: () => _bump(-widget.step),
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 64,
              child: TextField(
                controller: _controller,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: widget.decimals > 0,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: (text) {
                  final parsed = _parse(text);
                  if (parsed != null) widget.onChanged(parsed);
                },
              ),
            ),
            IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              onPressed: () => _bump(widget.step),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}

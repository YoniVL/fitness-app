import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/spacing.dart';

/// Number field with big -/+ tap targets. Works for reps, sets and rest seconds.
class NumberStepper extends StatefulWidget {
  const NumberStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.step = 1,
    this.min = 0,
    this.max = 999,
    this.decimals = 0,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double step;
  final double min;
  final double max;
  final int decimals;

  @override
  State<NumberStepper> createState() => _NumberStepperState();
}

class _NumberStepperState extends State<NumberStepper> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.value));

  String _format(double v) => widget.decimals == 0
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(widget.decimals);

  @override
  void didUpdateWidget(NumberStepper old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _parse(_controller.text) != widget.value) {
      _controller.text = _format(widget.value);
    }
  }

  double? _parse(String text) => double.tryParse(text.replaceAll(',', '.'));

  void _bump(double delta) {
    final next = (widget.value + delta).clamp(widget.min, widget.max).toDouble();
    widget.onChanged(next);
    _controller.text = _format(next);
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.labelMedium),
        Gap.xs,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepButton(
              icon: Icons.remove,
              onTap: widget.value > widget.min ? () => _bump(-widget.step) : null,
            ),
            SizedBox(
              width: 72,
              child: TextField(
                controller: _controller,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: widget.decimals > 0,
                ),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
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
            _StepButton(
              icon: Icons.add,
              onTap: widget.value < widget.max ? () => _bump(widget.step) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: onTap == null
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.4)
            : scheme.secondaryContainer,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon,
                color: onTap == null
                    ? scheme.onSurface.withValues(alpha: 0.3)
                    : scheme.onSecondaryContainer),
          ),
        ),
      ),
    );
  }
}

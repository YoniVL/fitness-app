import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';

/// Number field with big -/+ tap targets. Works for reps, sets and rest seconds.
/// Modernist: a square bordered row — [−] [ big tabular number ] [+].
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
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 9, letterSpacing: 1.1, color: p.mute)),
        const SizedBox(height: 6),
        DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: p.line)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StepButton(
                icon: Icons.remove,
                onTap:
                    widget.value > widget.min ? () => _bump(-widget.step) : null,
                border: Border(right: BorderSide(color: p.line)),
              ),
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _controller,
                  textAlign: TextAlign.center,
                  style: AppTheme.numeric(size: 30, color: p.ink),
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: widget.decimals > 0,
                  ),
                  decoration: const InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
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
                onTap:
                    widget.value < widget.max ? () => _bump(widget.step) : null,
                border: Border(left: BorderSide(color: p.line)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap, required this.border});
  final IconData icon;
  final VoidCallback? onTap;
  final BoxBorder border;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(border: border),
        child: Icon(icon,
            size: 20, color: onTap == null ? p.line : p.ink),
      ),
    );
  }
}

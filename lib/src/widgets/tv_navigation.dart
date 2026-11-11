import 'package:flutter/material.dart';

import '../theme.dart';

class TvMode extends InheritedWidget {
  const TvMode({super.key, required this.enabled, required super.child});

  final bool enabled;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvMode>()?.enabled ?? false;

  @override
  bool updateShouldNotify(TvMode oldWidget) => enabled != oldWidget.enabled;
}

class TvFocusCard extends StatefulWidget {
  const TvFocusCard({
    super.key,
    required this.onPressed,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.autofocus = false,
  });

  final VoidCallback onPressed;
  final Widget child;
  final BorderRadius borderRadius;
  final bool autofocus;

  @override
  State<TvFocusCard> createState() => _TvFocusCardState();
}

class _TvFocusCardState extends State<TvFocusCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final television = TvMode.of(context);
    return FocusableActionDetector(
      autofocus: television && widget.autofocus,
      onShowFocusHighlight: (focused) {
        if (_focused != focused) setState(() => _focused = focused);
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      child: AnimatedScale(
        scale: television && _focused ? 1.055 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: television && _focused
                ? Border.all(color: CasaFlixColors.amber, width: 3)
                : null,
            boxShadow: television && _focused
                ? const [
                    BoxShadow(
                      color: Color(0x884FCEF7),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onPressed,
                canRequestFocus: false,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

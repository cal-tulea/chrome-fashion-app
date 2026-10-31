import 'package:flutter/material.dart';

class ScreenScaffold extends StatelessWidget {
  final Widget child;

  /// Pushes content down slightly on every screen to make top controls easier to tap.
  final double extraTopPadding;

  const ScreenScaffold({
    super.key,
    required this.child,
    this.extraTopPadding = 14,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(top: extraTopPadding),
        child: child,
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// A small original, cross-platform iOS-inspired UI language for O-AGENT.
/// Uses semantic text and theme colors rather than copying a template's assets.
class OVisual {
  static const primary = Color(0xFF5850A9);
  static const ink = Color(0xFF1C1C21);
  static const secondary = Color(0xFF747680);
  static const mint = Color(0xFF15785E);
  static const gold = Color(0xFF9B641C);
  static const rose = Color(0xFFB54F59);

  static Color canvas(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF111116) : const Color(0xFFF6F6F8);
  static Color surface(BuildContext context) =>
    Theme.of(context).colorScheme.surface;
  static Color border(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF30303C) : const Color(0xFFE8E8EC);
  static Color label(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface;
  static Color muted(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;
  static Color state(String status) {
    final state = status.toLowerCase();
    if (const ['online','connected','completed','finished','success','idle']
        .contains(state)) return mint;
    if (const ['running','active','queued','creating'].contains(state))
      return primary;
    if (state.contains('approval') || state == 'pending' ||
        state.contains('waiting')) return gold;
    if (state.contains('failed') || state.contains('error') ||
        state.contains('denied') || state.contains('cancel'))
      return rose;
    return secondary;
  }
}

/// iOS grouped surface: hairline boundary, generous radius, nearly invisible shadow.
class OSurface extends StatelessWidget {
  const OSurface({super.key, required this.child, this.padding = const EdgeInsets.all(18),
    this.onTap, this.tint});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? tint;
  @override
  Widget build(BuildContext context) {
    final box = DecoratedBox(decoration: BoxDecoration(
      color: tint ?? OVisual.surface(context),
      borderRadius: BorderRadius.circular(23),
      border: Border.all(color: OVisual.border(context)),
      boxShadow: Theme.of(context).brightness == Brightness.light ? const [
        BoxShadow(color: Color(0x070A0A30), blurRadius: 16, offset: Offset(0, 5)),
      ] : [],
    ), child: Padding(padding: padding, child: child));
    if (onTap == null) return box;
    return Material(color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(23),
        child: box));
  }
}
class OScreenTitle extends StatelessWidget {
  const OScreenTitle({super.key, required this.eyebrow,
    required this.title, required this.subtitle});
  final String eyebrow, title, subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(eyebrow.toUpperCase(), style: const TextStyle(
        color: OVisual.primary, fontWeight: FontWeight.w800,
        letterSpacing: 1.7, fontSize: 11)),
      const SizedBox(height: 9),
      Text(title, style: TextStyle(color: OVisual.label(context),
        fontWeight: FontWeight.w800, fontSize: 31, height: 1.13,
        letterSpacing: -0.9)),
      const SizedBox(height: 9),
      Text(subtitle, style: TextStyle(
        color: OVisual.muted(context), fontSize: 13, height: 1.48)),
    ],
  );
}
class OSectionTitle extends StatelessWidget {
  const OSectionTitle(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 26, 2, 11),
    child: Row(children: [
      Expanded(child: Text(title, style: TextStyle(
        fontSize: 19, fontWeight: FontWeight.w700,
        letterSpacing: -0.35, color: OVisual.label(context)))),
      if (action != null) TextButton(onPressed: onAction,
        child: Text(action!, style: const TextStyle(fontSize: 13))),
    ]));
}
class OStatePill extends StatelessWidget {
  const OStatePill(this.status, {super.key, this.label});
  final String status;
  final String? label;
  @override
  Widget build(BuildContext context) {
    final tint = OVisual.state(status);
    return Semantics(label: 'Status: ' + (label ?? status), child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: tint)),
        const SizedBox(width: 7),
        Flexible(child: Text(label ?? status.replaceAll('_', ' '),
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tint))),
      ]),
    ));
  }
}
class OIconTile extends StatelessWidget {
  const OIconTile({super.key, required this.icon, required this.title,
    this.subtitle, this.trailing, this.onTap, this.color = OVisual.primary});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => OSurface(
    onTap: onTap,
    child: Row(children: [
      Container(width: 45, height: 45,
        decoration: BoxDecoration(color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(14)),
        child: Icon(icon, size: 22, color: color)),
      const SizedBox(width: 13),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: OVisual.label(context), fontSize: 15,
              fontWeight: FontWeight.w700)),
          if (subtitle != null) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(subtitle!, maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: OVisual.muted(context),
                fontSize: 12, height: 1.4))),
        ])),
      const SizedBox(width: 8),
      trailing ?? Icon(CupertinoIcons.chevron_right, size: 16,
        color: OVisual.muted(context)),
    ]),
  );
}
class OEmptyState extends StatelessWidget {
  const OEmptyState({super.key, required this.icon, required this.title,
    required this.message, this.action});
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => OSurface(child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
    child: Column(children: [
      Container(width: 62, height: 62,
        decoration: BoxDecoration(color: OVisual.primary.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(21)),
        child: Icon(icon, size: 28, color: OVisual.primary)),
      const SizedBox(height: 15),
      Text(title, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
          color: OVisual.label(context))),
      const SizedBox(height: 7),
      Text(message, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, height: 1.5,
          color: OVisual.muted(context))),
      if (action != null) ...[const SizedBox(height: 17), action!],
    ]),
  ));
}
class OLoadingState extends StatelessWidget {
  const OLoadingState({super.key, this.message = 'Connecting to your workspace'});
  final String message;
  @override
  Widget build(BuildContext context) => OSurface(child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 23),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      const CupertinoActivityIndicator(radius: 11),
      const SizedBox(width: 13),
      Flexible(child: Text(message, style: TextStyle(
        fontSize: 13, color: OVisual.muted(context)))),
    ]),
  ));
}

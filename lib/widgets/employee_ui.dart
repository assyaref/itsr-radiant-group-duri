import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/ticket_model.dart';
import '../utils/formatters.dart';

/// Visual language of the employee screens ("Tampilan Karyawan" design).
class EColors {
  EColors._();
  static const blue = Color(0xFF2563EB);
  static const blueDark = Color(0xFF1D4ED8);
  static const blueSoft = Color(0xFFEFF5FF);
  static const page = Color(0xFFF6F8FC);
  static const ink = Color(0xFF0F172A);
  static const text = Color(0xFF334155);
  static const muted = Color(0xFF64748B);
  static const line = Color(0xFFE2E8F0);
  static const red = Color(0xFFEF4444);
  static const amber = Color(0xFFF59E0B);
  static const green = Color(0xFF22C55E);
  static const purple = Color(0xFF8B5CF6);
  static const teal = Color(0xFF14B8A6);
  static const grey = Color(0xFF94A3B8);

  static Color priority(String? p) => switch (p) {
    'critical' || 'high' => red,
    'medium' => amber,
    'low' => green,
    _ => grey,
  };

  static Color status(String? s) => switch (s) {
    'in_progress' || 'pending_user' || 'assigned' => blue,
    'resolved' => green,
    'closed' => grey,
    'reopened' => red,
    _ => purple, // open = "Menunggu"
  };
}

/// Ticket status groups used by the stat cards and the list filter chips.
/// They mirror the counts of the `ticket_stats` RPC.
class StatusGroups {
  StatusGroups._();
  static const waiting = ['open', 'assigned', 'reopened'];
  static const inProgress = ['in_progress', 'pending_user'];
  static const done = ['resolved', 'closed'];
}

/// White page header with a back arrow and a title (design screens 3–11).
class EHeader extends StatelessWidget implements PreferredSizeWidget {
  const EHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.centerTitle = false,
    this.showBack = true,
  });
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final bool centerTitle;
  final bool showBack;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.white,
    foregroundColor: EColors.ink,
    elevation: 0,
    scrolledUnderElevation: 0,
    toolbarHeight: 60,
    automaticallyImplyLeading: false,
    centerTitle: centerTitle,
    titleSpacing: showBack ? 0 : 20,
    leading: showBack
        ? IconButton(
            tooltip: 'Kembali',
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack ?? () => goBack(context),
          )
        : null,
    title: Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: EColors.ink,
      ),
    ),
    actions: [?trailing, const SizedBox(width: 8)],
  );
}

/// Pops when there is history, otherwise goes to [fallback] (deep links).
void goBack(BuildContext context, {String fallback = '/dashboard'}) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

/// Small rounded label, e.g. "High" or "Diproses".
class ETag extends StatelessWidget {
  const ETag(this.text, this.color, {super.key, this.dense = false});
  final String text;
  final Color color;
  final bool dense;

  factory ETag.priority(String p) => ETag(Fmt.priority(p), EColors.priority(p));
  factory ETag.status(String s) => ETag(Fmt.statusId(s), EColors.status(s));

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: dense ? 6 : 8,
      vertical: dense ? 2 : 3,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      maxLines: 1,
      style: TextStyle(
        color: color,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Category → icon + colour for the rounded tile in ticket rows.
(IconData, Color) categoryStyle(String category) {
  final c = category.toLowerCase();
  if (c.contains('hardware') ||
      c.contains('laptop') ||
      c.contains('komputer')) {
    return (Icons.desktop_windows_outlined, EColors.blue);
  }
  if (c.contains('software') ||
      c.contains('aplikasi') ||
      c.contains('application')) {
    return (Icons.apps_rounded, EColors.green);
  }
  if (c.contains('network') ||
      c.contains('jaringan') ||
      c.contains('internet') ||
      c.contains('wifi')) {
    return (Icons.wifi_rounded, EColors.blue);
  }
  if (c.contains('printer') || c.contains('print')) {
    return (Icons.print_outlined, EColors.green);
  }
  if (c.contains('akun') ||
      c.contains('account') ||
      c.contains('password') ||
      c.contains('email')) {
    return (Icons.manage_accounts_outlined, EColors.blue);
  }
  if (c.contains('akses') || c.contains('access') || c.contains('folder')) {
    return (Icons.folder_shared_outlined, EColors.purple);
  }
  return (Icons.support_agent, EColors.purple);
}

class CategoryTile extends StatelessWidget {
  const CategoryTile(this.category, {super.key, this.size = 44});
  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = categoryStyle(category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }
}

/// One ticket in a list (design screens 2 and 3).
class TicketRow extends StatelessWidget {
  const TicketRow(this.ticket, {super.key});
  final TicketModel ticket;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/tickets/${t.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              CategoryTile(t.category),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: EColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${t.ticketNumber} · ${Fmt.date(t.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: EColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ETag.priority(t.priority),
                  const SizedBox(height: 6),
                  ETag.status(t.status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Initials avatar (no photos are stored for users).
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(
    this.name, {
    super.key,
    this.size = 40,
    this.onTap,
    this.solid = false,
  });
  final String name;
  final double size;
  final VoidCallback? onTap;

  /// Opaque white background, for use on the blue header.
  final bool solid;

  static String initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  static const _palette = [
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF0D9488),
    Color(0xFFEA580C),
    Color(0xFFDB2777),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _palette[name.hashCode.abs() % _palette.length];
    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: solid
            ? Color.alphaBlend(color.withValues(alpha: 0.15), Colors.white)
            : color.withValues(alpha: 0.15),
        border: Border.all(color: Colors.white, width: size > 60 ? 4 : 2),
      ),
      alignment: Alignment.center,
      child: Text(
        initials(name),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
    if (onTap == null) return avatar;
    return Semantics(
      button: true,
      label: 'Profil',
      child: GestureDetector(onTap: onTap, child: avatar),
    );
  }
}

/// White rounded card used across the employee screens.
class ECard extends StatelessWidget {
  const ECard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    // Shadow only: the colour is painted by the Material below so ListTile /
    // InkWell splashes inside the card stay visible.
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F0F172A),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Material(
      color: color ?? Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
}

/// Label above a form field: "Judul Masalah *" / "Lokasi (Opsional)".
class FieldLabel extends StatelessWidget {
  const FieldLabel(
    this.text, {
    super.key,
    this.required = false,
    this.optional = false,
  });
  final String text;
  final bool required;
  final bool optional;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text.rich(
      TextSpan(
        text: text,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: EColors.ink,
        ),
        children: [
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: EColors.red),
            ),
          if (optional)
            const TextSpan(
              text: ' (Opsional)',
              style: TextStyle(
                fontWeight: FontWeight.w400,
                color: EColors.muted,
              ),
            ),
        ],
      ),
    ),
  );
}

/// Outlined input style of the design (white, light border, 10 px radius).
InputDecoration eInput({String? hint, Widget? prefix, String? counter}) =>
    InputDecoration(
      hintText: hint,
      prefixIcon: prefix,
      counterText: counter,
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: EColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: EColors.blue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: EColors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: EColors.red, width: 1.5),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );

/// Primary blue button, full width, 52 px high.
class EPrimaryButton extends StatelessWidget {
  const EPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    width: double.infinity,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: EColors.blue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 8),
                  Icon(icon, size: 20),
                ],
              ],
            ),
    ),
  );
}

/// Pill-style segmented filter chip ("Semua 12").
class ESegment extends StatelessWidget {
  const ESegment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? EColors.blueSoft : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFFBFD4FE) : EColors.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? EColors.blue : EColors.text,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? EColors.blue.withValues(alpha: 0.15)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? EColors.blue : EColors.muted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

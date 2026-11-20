import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color _blue = Color(0xFF2563EB);
const Color _violet = Color(0xFF7C3AED);
const Color _pink = Color(0xFFEC4899);

const LinearGradient _bubbleGradient = LinearGradient(
  colors: [_blue, _violet],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Wraps a page with a floating "Komentar" bubble in the bottom-right corner.
/// Tapping it pops [chat] open in a floating panel with a springy animation.
/// The chat stays mounted while closed, so a draft is never lost.
class FloatingChatLayer extends StatefulWidget {
  const FloatingChatLayer({
    super.key,
    required this.open,
    required this.commentCount,
    required this.onToggle,
    required this.chat,
    required this.child,
    this.ticketNumber,
  });

  final bool open;
  final int commentCount;
  final VoidCallback onToggle;
  final Widget chat;
  final Widget child;
  final String? ticketNumber;

  @override
  State<FloatingChatLayer> createState() => _FloatingChatLayerState();
}

class _FloatingChatLayerState extends State<FloatingChatLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    reverseDuration: const Duration(milliseconds: 260),
    value: widget.open ? 1 : 0,
  );
  late final Animation<double> _scale = CurvedAnimation(
    parent: _c,
    curve: Curves.elasticOut,
    reverseCurve: Curves.easeInBack,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 0.35, curve: Curves.easeOut),
    reverseCurve: Curves.easeIn,
  );

  @override
  void didUpdateWidget(FloatingChatLayer old) {
    super.didUpdateWidget(old);
    if (widget.open != old.open) {
      widget.open ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 600;
        final panel = Material(
          color: Colors.white,
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ChatHeader(
                count: widget.commentCount,
                ticketNumber: widget.ticketNumber,
                onClose: widget.onToggle,
              ),
              Expanded(child: widget.chat),
            ],
          ),
        );

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (widget.open) widget.onToggle();
            },
          },
          child: Stack(
            children: [
              Positioned.fill(child: widget.child),
              Positioned(
                right: wide ? 20 : 0,
                left: wide ? null : 0,
                top: wide ? null : 0,
                bottom: wide ? 92 : 86,
                width: wide ? 400 : null,
                height: wide
                    ? math.max(320.0, math.min(600.0, box.maxHeight - 168))
                    : null,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, child) {
                    final hidden = _c.isDismissed;
                    return Offstage(
                      offstage: hidden,
                      child: TickerMode(
                        enabled: !hidden,
                        child: FadeTransition(
                          opacity: _fade,
                          child: ScaleTransition(
                            alignment: Alignment.bottomRight,
                            scale: _scale,
                            child: child,
                          ),
                        ),
                      ),
                    );
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: _violet.withValues(alpha: 0.22),
                          blurRadius: 40,
                          offset: const Offset(0, 16),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: panel,
                  ),
                ),
              ),
              Positioned(
                right: wide ? 20 : 14,
                bottom: wide ? 20 : 14,
                child: _ChatBubbleButton(
                  open: widget.open,
                  count: widget.commentCount,
                  onTap: widget.onToggle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Gradient header of the floating panel.
class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.count,
    required this.onClose,
    this.ticketNumber,
  });
  final int count;
  final String? ticketNumber;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: _bubbleGradient),
      child: Stack(
        children: [
          // Soft decorative circles for a playful look.
          Positioned(right: -18, top: -26, child: _Blob(size: 84, alpha: 0.12)),
          Positioned(
            right: 70,
            bottom: -30,
            child: _Blob(size: 56, alpha: 0.10),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.forum_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Komentar',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          '$count pesan',
                          if (ticketNumber != null && ticketNumber!.isNotEmpty)
                            ticketNumber!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup komentar',
                  onPressed: onClose,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.alpha});
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: alpha),
      shape: BoxShape.circle,
    ),
  );
}

/// The floating bubble: gradient pill that playfully wiggles now and then,
/// squishes when pressed, and morphs into a close button when open.
class _ChatBubbleButton extends StatefulWidget {
  const _ChatBubbleButton({
    required this.open,
    required this.count,
    required this.onTap,
  });
  final bool open;
  final int count;
  final VoidCallback onTap;

  @override
  State<_ChatBubbleButton> createState() => _ChatBubbleButtonState();
}

class _ChatBubbleButtonState extends State<_ChatBubbleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wiggle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  Timer? _timer;
  bool _hover = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    // A one-shot hop + wiggle every few seconds (never a never-ending
    // animation, so the page still settles and stays light on CPU).
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _hop());
    WidgetsBinding.instance.addPostFrameCallback((_) => _hop());
  }

  void _hop() {
    if (!mounted || widget.open || _hover) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _wiggle.forward(from: 0);
  }

  @override
  void didUpdateWidget(_ChatBubbleButton old) {
    super.didUpdateWidget(old);
    if (widget.count > old.count && !widget.open) _hop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _wiggle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.open;
    final scale = _pressed ? 0.9 : (_hover ? 1.06 : 1.0);

    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      height: 58,
      padding: EdgeInsets.symmetric(horizontal: open ? 0 : 18),
      constraints: const BoxConstraints(minWidth: 58),
      decoration: BoxDecoration(
        gradient: open
            ? const LinearGradient(colors: [_violet, _pink])
            : _bubbleGradient,
        borderRadius: BorderRadius.circular(29),
        boxShadow: [
          BoxShadow(
            color: (open ? _pink : _violet).withValues(
              alpha: _hover ? 0.5 : 0.38,
            ),
            blurRadius: _hover ? 24 : 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutBack,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.elasticOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, a) => RotationTransition(
            turns: Tween(begin: -0.25, end: 0.0).animate(a),
            child: ScaleTransition(scale: a, child: child),
          ),
          child: open
              ? const SizedBox(
                  key: ValueKey('close'),
                  width: 58,
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                )
              : Row(
                  key: const ValueKey('chat'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _BubbleIcon(),
                    const SizedBox(width: 10),
                    const Text(
                      'Komentar',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (widget.count > 0) ...[
                      const SizedBox(width: 8),
                      _CountBadge(count: widget.count),
                    ],
                  ],
                ),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: open ? 'Tutup komentar' : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedBuilder(
            animation: _wiggle,
            builder: (context, child) {
              final t = _wiggle.value;
              final fade = 1 - t;
              final hop = -math.sin(t * math.pi) * 10;
              final tilt = math.sin(t * math.pi * 5) * 0.09 * fade;
              final squash = 1 + math.sin(t * math.pi * 2) * 0.04 * fade;
              return Transform.translate(
                offset: Offset(0, hop),
                child: Transform.rotate(
                  angle: tilt,
                  child: Transform.scale(
                    scaleX: squash,
                    scaleY: 2 - squash,
                    child: child,
                  ),
                ),
              );
            },
            child: AnimatedScale(
              scale: scale,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

/// Speech bubble with three little "typing" dots.
class _BubbleIcon extends StatelessWidget {
  const _BubbleIcon();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 26,
    height: 26,
    child: Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 26),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 1.2),
                  decoration: const BoxDecoration(
                    color: _violet,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// White count badge that pops (elastic) whenever the number changes.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(count),
    tween: Tween(begin: 0.3, end: 1),
    duration: const Duration(milliseconds: 700),
    curve: Curves.elasticOut,
    builder: (_, s, child) => Transform.scale(scale: s, child: child),
    child: Container(
      constraints: const BoxConstraints(minWidth: 24),
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: _violet,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    ),
  );
}

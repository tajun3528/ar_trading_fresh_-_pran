import 'package:flutter/material.dart';

import '../design/design_tokens.dart';
import '../motion/motion.dart';

/// A gradient-fill KPI card: icon badge, hero number, label — for a headline
/// metric row above a data table. Bolder than [StatTile] on purpose; use it
/// where a handful of numbers should read before anything else on the page.
///
/// Give it [countTo] and [format] and the figure counts up to its value
/// instead of appearing fully formed; pass a plain [value] string where the
/// figure is not a number.
class BoldStatCard extends StatelessWidget {
  const BoldStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
    this.tooltip,
    this.countTo,
    this.format,
    this.delay = Duration.zero,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  /// Where this figure comes from. Given one, the card becomes a way through
  /// to the page the number was calculated on.
  final VoidCallback? onTap;
  final String? tooltip;

  /// The figure to count up to. When set, [format] turns each interpolated
  /// value into the text shown, and [value] is ignored.
  final double? countTo;
  final String Function(double value)? format;

  /// Staggers this card behind its neighbours in a row of tiles.
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final card = HoverLift(
      onTap: onTap,
      borderRadius: AppRadius.rLg,
      child: _buildCard(context),
    );

    final wrapped = onTap == null
        ? card
        : Tooltip(message: tooltip ?? 'Open', child: card);

    return Reveal(delay: delay, child: wrapped);
  }

  Widget _buildCard(BuildContext context) {
    final counting = countTo != null && format != null;

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        // A gradient rather than a flat fill — the same treatment the brand
        // mark uses, so the tiles read as part of one identity.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.22)!],
        ),
        borderRadius: AppRadius.rLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The arrow shares the badge's row rather than taking a line of its
          // own — this card's height is shared across the row and has no
          // spare vertical space.
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: AppRadius.rSm,
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              if (onTap != null) ...[
                const Spacer(),
                Icon(Icons.arrow_outward, color: Colors.white.withValues(alpha: 0.6), size: 15),
              ],
            ],
          ),
          const SizedBox(height: 14),
          // Flexible + scaleDown so the hero number gives way rather than
          // overflowing: vertically when the row's shared height lands a
          // pixel or two under the natural size, horizontally when the figure
          // is a long one (a full stock valuation in Taka).
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: counting
                  ? CountUp(
                      value: countTo!,
                      format: format!,
                      style: AppType.numericLarge.copyWith(color: Colors.white),
                    )
                  : Text(
                      value,
                      maxLines: 1,
                      style: AppType.numericLarge.copyWith(color: Colors.white),
                    ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.label.copyWith(color: Colors.white.withValues(alpha: 0.92)),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Lays out a role dashboard's headline metrics — each tile is typically a
/// [BoldStatCard] (see core/viz). Wide enough for every tile to sit on one
/// row (desktop/tablet), they get equal width there; narrower, they wrap
/// into a grid instead.
class StatGrid extends StatelessWidget {
  const StatGrid({required this.tiles, super.key});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width >= 900) {
          return IntrinsicHeight(
            child: Row(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: tiles[i]),
                ],
              ],
            ),
          );
        }
        return GridView.count(
          crossAxisCount: width >= 600 ? 3 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: tiles,
        );
      },
    );
  }
}

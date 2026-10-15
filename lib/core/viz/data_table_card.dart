import 'package:flutter/material.dart';

import 'status_palette.dart';

/// A compact records table under a title — the "recent activity" / "top N"
/// table that anchors a dashboard once the headline cards have been read.
class DataTableCard extends StatelessWidget {
  const DataTableCard({
    required this.title,
    required this.columns,
    required this.rows,
    this.emptyLabel = 'Nothing here yet',
    super.key,
  });

  final String title;
  final List<String> columns;
  final List<List<Widget>> rows;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(emptyLabel, style: const TextStyle(color: VizChrome.secondaryInk)),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(VizChrome.tableHeader),
                  headingTextStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: VizChrome.secondaryInk,
                  ),
                  dataTextStyle: const TextStyle(fontSize: 13),
                  columnSpacing: 28,
                  horizontalMargin: 8,
                  columns: [for (final c in columns) DataColumn(label: Text(c))],
                  rows: [for (final r in rows) DataRow(cells: [for (final cell in r) DataCell(cell)])],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

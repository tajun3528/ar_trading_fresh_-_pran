import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../design/design_tokens.dart';
import '../motion/motion.dart';

import 'status_palette.dart';

class TrendPoint {
  const TrendPoint(this.label, this.value);

  /// Short axis label, e.g. "Aug 5".
  final String label;
  final double value;
}

double _niceMaxY(List<TrendPoint> points) {
  final maxValue = points.fold<double>(0, (m, p) => p.value > m ? p.value : m);
  return maxValue <= 0 ? 1 : maxValue * 1.2;
}

/// Thins bottom-axis labels so a 14-point series doesn't collide on a phone
/// width — every other label, plus the last one always shown (per marks
/// guidance: selective direct labels, never one on every point).
Widget _bottomLabel(List<TrendPoint> points, double value) {
  final i = value.toInt();
  if (i < 0 || i >= points.length) return const SizedBox.shrink();
  final isLast = i == points.length - 1;
  if (!isLast && i.isOdd) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(points[i].label, style: const TextStyle(fontSize: 10, color: VizChrome.muted)),
  );
}

/// Trend over time, single series — line + area fill, thin mark, only the
/// most recent point emphasized as a dot. Ships a touch tooltip by default.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({required this.points, required this.color, this.valueFormatter, super.key});

  final List<TrendPoint> points;
  final Color color;
  final String Function(double value)? valueFormatter;

  String _format(double value) => valueFormatter?.call(value) ?? value.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Text('No data yet', style: TextStyle(color: VizChrome.secondaryInk)),
        ),
      );
    }
    final maxY = _niceMaxY(points);
    final gridInterval = maxY / 3;

    // fl_chart only tweens when its data changes, so on a first build the
    // chart simply appears. Driving the values up from zero makes the line
    // draw itself the first time it is seen, which is when it matters.
    return SizedBox(
      height: 180,
      child: _GrowIn(
        builder: (t) => LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY,
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: gridInterval,
              getDrawingHorizontalLine: (_) => const FlLine(color: VizChrome.track, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  interval: gridInterval,
                  getTitlesWidget: (value, meta) =>
                      Text(_format(value), style: const TextStyle(fontSize: 10, color: VizChrome.muted)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  getTitlesWidget: (v, m) => _bottomLabel(points, v),
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => color,
                getTooltipItems: (spots) => spots.map((s) {
                  final i = s.x.toInt();
                  final label = i >= 0 && i < points.length ? points[i].label : '';
                  return LineTooltipItem(
                    '$label\n${_format(s.y)}',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                  );
                }).toList(),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].value * t)],
                isCurved: false,
                color: color,
                barWidth: 2,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                    radius: index == points.length - 1 ? 4 : 0,
                    color: color,
                    strokeWidth: 0,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.02)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compare magnitude across days — thin bars, rounded data-ends, touch
/// tooltip per bar.
class TrendBarChart extends StatelessWidget {
  const TrendBarChart({required this.points, required this.color, this.valueFormatter, super.key});

  final List<TrendPoint> points;
  final Color color;
  final String Function(double value)? valueFormatter;

  String _format(double value) => valueFormatter?.call(value) ?? value.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Text('No data yet', style: TextStyle(color: VizChrome.secondaryInk)),
        ),
      );
    }
    final maxY = _niceMaxY(points);
    final gridInterval = maxY / 3;

    return SizedBox(
      height: 180,
      child: _GrowIn(
        builder: (t) => BarChart(
          BarChartData(
            minY: 0,
            maxY: maxY,
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: gridInterval,
              getDrawingHorizontalLine: (_) => const FlLine(color: VizChrome.track, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  interval: gridInterval,
                  getTitlesWidget: (value, meta) =>
                      Text(_format(value), style: const TextStyle(fontSize: 10, color: VizChrome.muted)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  getTitlesWidget: (v, m) => _bottomLabel(points, v),
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => color,
                getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                  '${points[group.x.toInt()].label}\n${_format(rod.toY)}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < points.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: points[i].value * t,
                      color: color,
                      width: 12,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Drives a chart's values from zero to full once, so it draws itself the
/// first time it appears rather than snapping into place fully formed.
class _GrowIn extends StatelessWidget {
  const _GrowIn({required this.builder});

  /// Receives 0 → 1; multiply the series values by it.
  final Widget Function(double t) builder;

  @override
  Widget build(BuildContext context) {
    if (reduceMotionOf(context)) return builder(1);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.count,
      curve: AppMotion.enter,
      builder: (context, t, _) => builder(t),
    );
  }
}

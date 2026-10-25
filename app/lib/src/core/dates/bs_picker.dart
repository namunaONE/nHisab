import 'package:bikram_sambat/bikram_sambat.dart';
import 'package:flutter/material.dart';

/// Dual AD/BS date picker. Storage stays AD.
///
/// Conversion authority is `bikram_sambat` (verified: 2023-04-14 = 2080-01-01,
/// 2026-10-15 = 2083-06-29). The BS month grid below is drawn from that same
/// table, so picked dates round-trip exactly with zero drift — critical for
/// per-day interest math.
///
/// UX: a compact calendar-choice sheet (AD | BS segmented) remembers the last
/// choice per app lifetime via [_preferBs].
class BsPicker {
  static bool _preferBs = true; // Nepal-first default

  static bool get preferBs => _preferBs;

  /// Convert an AD civil date to a BS civil date without depending on the
  /// machine's timezone.
  ///
  /// `bikram_sambat` converts through UTC. Feeding it local midnight makes the
  /// result depend on the host timezone (a UTC CI runner saw 2083-06-28 for
  /// 2026-10-15 while a Nepal machine saw 2083-06-29). Noon UTC is inside the
  /// same Nepal civil day in every timezone, so the conversion is stable.
  static BikramSambat bsFromAd(DateTime ad) {
    return BikramSambat.fromDateTime(
      DateTime.utc(ad.year, ad.month, ad.day, 12),
    );
  }

  /// Convert a BS civil date to an AD civil date without depending on the
  /// machine's timezone.
  ///
  /// `BikramSambat.toDateTime()` returns a local instant. In UTC that instant
  /// is 18:15 on the previous day, which previously shifted every picked date
  /// one day back in CI. Add the Nepal offset back before taking the civil
  /// date so the result is identical on every host.
  static DateTime adFromBs(BikramSambat bs) {
    final utc = bs.toUtc().add(const Duration(hours: 5, minutes: 45));
    return DateTime(utc.year, utc.month, utc.day);
  }

  /// Show the dual picker. [firstDate]/[lastDate] bound both calendars.
  static Future<DateTime?> pick(
    BuildContext context, {
    required DateTime initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
  }) async {
    final first = firstDate ?? DateTime(2000);
    final last = lastDate ?? DateTime(2100);
    final useBs = await _chooseCalendar(context, initialDate);
    if (useBs == null || !context.mounted) return null;
    _preferBs = useBs;
    if (!useBs) {
      return showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: first,
        lastDate: last,
      );
    }
    final picked = await showDialog<BikramSambat>(
      context: context,
      builder: (_) => _BsMonthPicker(
        initial: bsFromAd(initialDate),
        first: bsFromAd(first),
        last: bsFromAd(last),
      ),
    );
    if (picked == null) return null;
    return adFromBs(picked);
  }

  /// Preview label for the choice sheet (AD `y/m/d`, BS `y-m-d`).
  static String preview(DateTime ad, bool bs) {
    if (!bs) return '${ad.year}/${ad.month}/${ad.day}';
    final n = bsFromAd(ad);
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d BS';
  }

  /// Days in a BS month, derived from the conversion table by probing.
  /// [month] is 1-12; year rollover handled by the constructor guard.
  static int daysInBsMonth(int year, int month) {
    var y = year;
    var m = month;
    while (m > 12) {
      m -= 12;
      y += 1;
    }
    while (m < 1) {
      m += 12;
      y -= 1;
    }
    var days = 0;
    for (var d = 1; d <= 32; d++) {
      try {
        final probe = BikramSambat(y, m, d);
        if (probe.month != m || probe.year != y) break;
        days = d;
      } catch (_) {
        break;
      }
    }
    return days;
  }

  /// Compact calendar-choice sheet. Returns true for BS, false for AD.
  static Future<bool?> _chooseCalendar(
      BuildContext context, DateTime initialDate) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        var selected = _preferBs;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Pick date'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('AD')),
                    ButtonSegment(value: true, label: Text('BS')),
                  ],
                  selected: {selected},
                  onSelectionChanged: (s) =>
                      setLocal(() => selected = s.first),
                ),
                const SizedBox(height: 12),
                Text(
                  preview(initialDate, selected),
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, selected),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// BS month-grid calendar dialog. Navigates by month, confirms a day.
/// All math via `bikram_sambat` (verified table).
class _BsMonthPicker extends StatefulWidget {
  final BikramSambat initial;
  final BikramSambat first;
  final BikramSambat last;

  const _BsMonthPicker({
    required this.initial,
    required this.first,
    required this.last,
  });

  @override
  State<_BsMonthPicker> createState() => _BsMonthPickerState();
}

class _BsMonthPickerState extends State<_BsMonthPicker> {
  late int year;
  late int month;
  BikramSambat? selected;

  static const bsMonths = [
    'Baisakh', 'Jestha', 'Ashadh', 'Shrawan', 'Bhadra', 'Ashwin',
    'Kartik', 'Mangsir', 'Poush', 'Magh', 'Falgun', 'Chaitra',
  ];
  static const weekDays = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

  @override
  void initState() {
    super.initState();
    year = widget.initial.year;
    month = widget.initial.month;
    selected = widget.initial;
  }

  bool get _canPrev {
    if (year > widget.first.year) return true;
    return year == widget.first.year && month > widget.first.month;
  }

  bool get _canNext {
    if (year < widget.last.year) return true;
    return year == widget.last.year && month < widget.last.month;
  }

  void _shift(int delta) {
    var m = month + delta;
    var y = year;
    while (m > 12) {
      m -= 12;
      y += 1;
    }
    while (m < 1) {
      m += 12;
      y -= 1;
    }
    setState(() {
      year = y;
      month = m;
    });
  }

  bool _inRange(int day) {
    final d = BikramSambat(year, month, day);
    return !d.isBefore(widget.first) && !d.isAfter(widget.last);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final daysInMonth = BsPicker.daysInBsMonth(year, month);
    final firstWeekday = BikramSambat(year, month, 1).weekday; // Sunday = 1
    final leading = (firstWeekday - 1) % 7;

    return AlertDialog(
      title: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous month',
            onPressed: _canPrev ? () => _shift(-1) : null,
          ),
          Expanded(
            child: Text(
              '${bsMonths[month - 1]} $year',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next month',
            onPressed: _canNext ? () => _shift(1) : null,
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                for (final w in weekDays)
                  Expanded(
                    child: Text(
                      w,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
              ),
              itemCount: leading + daysInMonth,
              itemBuilder: (_, i) {
                if (i < leading) return const SizedBox.shrink();
                final day = i - leading + 1;
                final enabled = _inRange(day);
                final isSel = selected != null &&
                    selected!.year == year &&
                    selected!.month == month &&
                    selected!.day == day;
                return InkWell(
                  onTap: enabled
                      ? () => setState(
                          () => selected = BikramSambat(year, month, day))
                      : null,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSel ? scheme.primary : null,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 13,
                        color: isSel
                            ? scheme.onPrimary
                            : enabled
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant
                                    .withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: selected == null
              ? null
              : () => Navigator.pop(context, selected),
          child: const Text('Select'),
        ),
      ],
    );
  }
}

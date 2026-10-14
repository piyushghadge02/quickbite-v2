/// LayoutBuilder-based responsive helpers.
///
/// * Phone (narrow, < 720 logical px): single column, edge-to-edge.
/// * Wide (≥ 720): content is centered in a max-width column so lines stay
///   readable and tap targets don't stretch across a monitor.
/// * Two-pane (≥ 1100): used by screens that benefit from a side panel
///   (menu + cart), via [TwoPane].
///
/// Nothing here uses fixed heights for text; combined with the theme (no
/// text-scale clamps) the layouts reflow at 200% OS text scaling instead of
/// overflowing.
library;

import 'package:flutter/material.dart';

class AppBreakpoints {
  static const double wide = 720;
  static const double twoPane = 1100;
  static const double maxContentWidth = 960;
}

/// Centers [child] in a max-width column on wide screens; full-bleed on
/// phones. Adds comfortable horizontal padding everywhere.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.maxContentWidth,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth < AppBreakpoints.wide ? 16.0 : 24.0;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Two-pane layout for wide screens: [main] takes the flexible area, [side]
/// is a fixed-width panel on the right. On phones it renders [main] only —
/// the side content is expected to be reachable through navigation (e.g. the
/// cart screen).
class TwoPane extends StatelessWidget {
  final Widget main;
  final Widget side;
  final double sideWidth;

  const TwoPane({
    super.key,
    required this.main,
    required this.side,
    this.sideWidth = 360,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppBreakpoints.twoPane) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: main),
              SizedBox(
                width: sideWidth,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: side,
                ),
              ),
            ],
          );
        }
        return main;
      },
    );
  }
}

/// Sliver-friendly list that loads the next page when the user scrolls near
/// the end.
class PagedListView extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final bool isLoadingMore;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final Widget? emptyWidget;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const PagedListView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.isLoadingMore,
    required this.hasMore,
    required this.onLoadMore,
    this.emptyWidget,
    this.shrinkWrap = false,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) {
      return emptyWidget ?? const SizedBox.shrink();
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.extentAfter < 400 &&
            hasMore &&
            !isLoadingMore) {
          onLoadMore();
        }
        return false;
      },
      child: ListView.builder(
        shrinkWrap: shrinkWrap,
        physics: physics,
        itemCount: itemCount + (isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= itemCount) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return itemBuilder(context, index);
        },
      ),
    );
  }
}

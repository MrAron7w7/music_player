import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class LoadingShimmer extends StatelessWidget {
  const LoadingShimmer({super.key, this.count = 5});
  final int count;
  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor: Theme.of(context).colorScheme.surface,
    highlightColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (context, index) => const ListTile(
        leading: CircleAvatar(radius: 27),
        title: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: ColoredBox(
            color: Colors.white,
            child: SizedBox(height: 12, width: 170),
          ),
        ),
        subtitle: Padding(
          padding: EdgeInsets.only(top: 6),
          child: ColoredBox(
            color: Colors.white,
            child: SizedBox(height: 9, width: 100),
          ),
        ),
      ),
    ),
  );
}

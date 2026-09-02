import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Trading cards are 63x88mm, so images keep that ratio.
const cardAspectRatio = 63 / 88;

/// The official card image, fetched once and then served from the device's
/// cache.
///
/// The app is offline first: the catalog, the decks and the rules all work with
/// no connection. Images are the one part that needs the network, and only the
/// first time each card is shown, so every failure here is silent and falls
/// back to a placeholder rather than interrupting deck building.
class CardImage extends StatelessWidget {
  const CardImage({super.key, required this.url, required this.width});

  final String? url;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width / cardAspectRatio;
    final radius = BorderRadius.circular(width < 60 ? 4 : 10);
    final address = url;

    if (address == null || address.isEmpty) {
      return _Placeholder(width: width, height: height, radius: radius);
    }

    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        imageUrl: address,
        width: width,
        height: height,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (context, _) =>
            _Placeholder(width: width, height: height, radius: radius),
        errorWidget: (context, _, _) =>
            _Placeholder(width: width, height: height, radius: radius),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: radius,
        border: Border.all(color: AppColors.border),
      ),
      child: Icon(
        Icons.image_outlined,
        size: width < 60 ? 14 : 28,
        color: AppColors.textFaint,
      ),
    );
  }
}

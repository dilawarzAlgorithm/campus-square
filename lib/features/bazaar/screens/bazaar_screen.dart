import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class BazaarScreen extends StatelessWidget {
  const BazaarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.asset(
              isDark
                  ? 'assets/lottie/coming_soon_dark.json'
                  : 'assets/lottie/coming_soon.json',
              height: 240,
            ),
            const SizedBox(height: 20),
            Text(
              'Bazaar',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Coming Soon',
              style: theme.textTheme.titleLarge?.copyWith(color: Colors.green),
            ),
            const SizedBox(height: 8),
            Text(
              'The Campus Marketplace is under development.\n'
              'Soon you will be able to buy, sell and exchange items with fellow students.',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

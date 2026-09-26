import 'package:flutter/material.dart';
import '../../shared/widgets/connect_hub_logo.dart';
import '../legal/terms_screen.dart';
import '../legal/privacy_screen.dart';

Future<void> showAccountPolicyDialog(BuildContext context,
        {required bool privacy}) =>
    showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Row(children: [
                  Expanded(
                      child: Text(
                          privacy ? 'Privacy Policy' : 'Terms of Service')),
                  IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close))
                ]),
                content: SizedBox(
                    width: 640,
                    child: SingleChildScrollView(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          for (final section in privacy
                              ? PrivacyPolicyScreen.accountSections
                              : TermsScreen.accountSections)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(section['title']!,
                                          style: Theme.of(ctx)
                                              .textTheme
                                              .titleMedium),
                                      const SizedBox(height: 8),
                                      Text(section['content']!),
                                    ])),
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'))
                ]));

class PolicyAgreement extends StatelessWidget {
  const PolicyAgreement(
      {super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CheckboxListTile(
            key: const ValueKey('policy-agreement'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: value,
            onChanged: onChanged == null ? null : (v) => onChanged!(v == true),
            title: const Text(
                'I agree to the Terms and acknowledge the Privacy Policy.')),
        Wrap(spacing: 8, children: [
          TextButton(
              onPressed: () => showAccountPolicyDialog(context, privacy: false),
              child: const Text('Terms of Service')),
          TextButton(
              onPressed: () => showAccountPolicyDialog(context, privacy: true),
              child: const Text('Privacy Policy')),
        ]),
      ]);
}

class AuthLayout extends StatelessWidget {
  const AuthLayout(
      {super.key,
      required this.child,
      required this.title,
      required this.subtitle});
  final Widget child;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(child: LayoutBuilder(builder: (ctx, size) {
          final wide = size.maxWidth >= 960;
          final intro =
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const KryinTalkLogo(size: 48, showText: true, textSize: 24),
            const SizedBox(height: 40),
            Text('Good conversations\nstart here.',
                style: theme.textTheme.headlineLarge
                    ?.copyWith(fontWeight: FontWeight.w700, height: 1.15)),
            const SizedBox(height: 24),
            for (final step in [
              '1  Create an account',
              '2  Confirm your email',
              '3  Get access'
            ])
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(step, style: theme.textTheme.titleMedium)),
            const SizedBox(height: 28),
            const Text('A personal account. A shared place to talk.'),
          ]);
          final form = ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!wide) ...[
                      const Align(
                          alignment: Alignment.centerLeft,
                          child: KryinTalkLogo(size: 40, showText: true)),
                      const SizedBox(height: 28)
                    ],
                    Text(title,
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Text(subtitle,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant)),
                    const SizedBox(height: 28),
                    Theme(
                        data: theme.copyWith(
                          inputDecorationTheme: theme.inputDecorationTheme
                              .copyWith(
                                  filled: true,
                                  fillColor: colors.surface,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 16),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12))),
                          filledButtonTheme: FilledButtonThemeData(
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  backgroundColor: colors.primary,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      theme.brightness == Brightness.dark
                                          ? const Color(0xFF44403C)
                                          : const Color(0xFFE7E5E4),
                                  disabledForegroundColor:
                                      theme.brightness == Brightness.dark
                                          ? const Color(0xFFA8A29E)
                                          : const Color(0xFF78716C),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)))),
                        ),
                        child: child),
                  ]));
          return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                  horizontal: wide ? 48 : 20, vertical: 40),
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                  Expanded(
                                      child: Padding(
                                          padding: const EdgeInsets.only(
                                              top: 24, right: 72),
                                          child: intro)),
                                  Expanded(child: form),
                                ])
                          : form)));
        })));
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../shared/widgets/connect_hub_logo.dart';
import 'ribbon_glow.dart';
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
              onPressed: () {
                if (GoRouter.maybeOf(context) != null) {
                  context.go('/terms');
                } else {
                  showAccountPolicyDialog(context, privacy: false);
                }
              },
              child: const Text('Terms of Service')),
          TextButton(
              onPressed: () {
                if (GoRouter.maybeOf(context) != null) {
                  context.go('/privacy');
                } else {
                  showAccountPolicyDialog(context, privacy: true);
                }
              },
              child: const Text('Privacy Policy')),
        ]),
      ]);
}

class AuthLayout extends StatelessWidget {
  const AuthLayout(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.child,
      this.switchLabel,
      this.onSwitch});
  final String title, subtitle;
  final Widget child;
  final String? switchLabel;
  final VoidCallback? onSwitch;
  static const blue = Color(0xFF4779FF);

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final colors = ColorScheme.fromSeed(
        seedColor: blue,
        primary: blue,
        brightness: Brightness.light,
        surface: Colors.white);
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDDE3ED)));
    final text = base.textTheme.apply(
        bodyColor: const Color(0xFF17243B),
        displayColor: const Color(0xFF17243B));
    final theme = base.copyWith(
        brightness: Brightness.light,
        colorScheme: colors,
        scaffoldBackgroundColor: Colors.white,
        textTheme: text,
        inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFFAFBFD),
            labelStyle: const TextStyle(fontSize: 14, color: Color(0xFF637089)),
            helperStyle:
                const TextStyle(fontSize: 12, color: Color(0xFF637089)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            border: border,
            enabledBorder: border,
            disabledBorder: border,
            focusedBorder: border.copyWith(
                borderSide: const BorderSide(color: blue, width: 1.5)),
            errorBorder:
                border.copyWith(borderSide: BorderSide(color: colors.error)),
            focusedErrorBorder: border.copyWith(
                borderSide: BorderSide(color: colors.error, width: 1.5))),
        checkboxTheme: CheckboxThemeData(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            fillColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected) ? blue : null)),
        textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF2455C9),
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600))),
        filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: blue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE9EFFC),
                disabledForegroundColor: const Color(0xFF657393),
                textStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: .1),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))));
    return Theme(
        data: theme,
        child: Builder(
            builder: (context) => Scaffold(
                backgroundColor: Colors.white,
                body: SafeArea(child: LayoutBuilder(builder: (context, size) {
                  final wide = size.maxWidth >= 1000 &&
                      size.maxHeight >= 650 &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.4;
                  final form = Column(children: [
                    Padding(
                        padding: EdgeInsets.fromLTRB(
                            wide ? 28 : 20, 22, wide ? 28 : 20, 12),
                        child: SizedBox(
                            width: double.infinity,
                            child: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 20,
                                runSpacing: 12,
                                children: [
                                  const KryinTalkLogo(
                                      size: 36,
                                      showText: true,
                                      textSize: 19,
                                      backgroundColor: blue,
                                      iconColor: Colors.white),
                                  if (switchLabel != null)
                                    OutlinedButton(
                                        key: const ValueKey('auth-switch'),
                                        onPressed: onSwitch,
                                        style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                const Color(0xFF233956),
                                            backgroundColor: Colors.white,
                                            minimumSize: const Size(0, 44),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 20, vertical: 14),
                                            side: const BorderSide(
                                                color: Color(0xFFDDE3ED)),
                                            textStyle: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12))),
                                        child: Text(switchLabel!))
                                ]))),
                    Expanded(
                        child: LayoutBuilder(
                            builder: (context, area) => SingleChildScrollView(
                                padding: EdgeInsets.symmetric(
                                    horizontal: wide ? 40 : 24, vertical: 28),
                                child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                        minHeight: (area.maxHeight - 56)
                                            .clamp(0, double.infinity)),
                                    child: Center(
                                        child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                maxWidth: 400),
                                            child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Center(
                                                      child: Container(
                                                          width: 60,
                                                          height: 60,
                                                          decoration: BoxDecoration(
                                                              color: const Color(
                                                                  0xFFF0F5FF),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          18),
                                                              border: Border.all(
                                                                  color: const Color(
                                                                      0xFFE0EAFF))),
                                                          child: const Icon(
                                                              Icons
                                                                  .person_rounded,
                                                              size: 31,
                                                              color: blue))),
                                                  const SizedBox(height: 22),
                                                  Text(title,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: text.headlineMedium
                                                          ?.copyWith(
                                                              fontSize: 30,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              height: 1.2,
                                                              letterSpacing:
                                                                  -1)),
                                                  const SizedBox(height: 10),
                                                  Text(subtitle,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: text.bodySmall
                                                          ?.copyWith(
                                                              fontSize: 13,
                                                              color: const Color(
                                                                  0xFF637089),
                                                              height: 1.65)),
                                                  const SizedBox(height: 30),
                                                  child,
                                                ]))))))),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(28, 14, 28, 20),
                        child: SizedBox(
                            width: double.infinity,
                            child: Text(
                                '© ${DateTime.now().year} KryinLabs · KryinTalk',
                                style: text.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: const Color(0xFF637089)))))
                  ]);
                  return Padding(
                      padding: EdgeInsets.all(wide ? 16 : 0),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                  Expanded(child: form),
                                  const SizedBox(width: 16),
                                  const Expanded(child: _ConversationPanel())
                                ])
                          : form);
                })))));
  }
}

class _ConversationPanel extends StatelessWidget {
  const _ConversationPanel();
  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(children: [
        const Positioned.fill(child: RibbonGlow()),
        const Positioned.fill(
            child: IgnorePointer(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
              Color(0x99071025),
              Color(0x00071025),
              Color(0xCC071025)
            ],
                            stops: [
              0,
              .5,
              1
            ]))))),
        Padding(
            padding: const EdgeInsets.all(40),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('A LITTLE CLOSER. A LOT MORE CONNECTED.',
                  style: TextStyle(
                      color: Color(0xFFAFCBFF),
                      fontSize: 10,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              Text('Bring your conversations\ntogether.',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      letterSpacing: -1.5)),
              const SizedBox(height: 18),
              ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 350),
                  child: const Text(
                      'Chats, groups and shared files. A simpler place for your team to stay connected with KryinTalk.',
                      style: TextStyle(
                          color: Color(0xFFD5E3FA),
                          fontSize: 14,
                          height: 1.75))),
              const Spacer(),
              const Text('YOUR PEOPLE. YOUR SPACE.',
                  style: TextStyle(
                      color: Color(0xFFAFCBFF),
                      fontSize: 10,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              const Text(
                  'One place to share ideas,\nand keep the conversation going.',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                      letterSpacing: -.4)),
              const SizedBox(height: 20),
              const Wrap(spacing: 10, runSpacing: 10, children: [
                _FeatureLabel(Icons.forum_outlined, 'Chats'),
                _FeatureLabel(Icons.folder_outlined, 'Shared files'),
                _FeatureLabel(Icons.verified_user_outlined, 'Approved access')
              ]),
            ]))
      ]));
}

class _FeatureLabel extends StatelessWidget {
  const _FeatureLabel(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .08),
          border: Border.all(color: Colors.white.withValues(alpha: .16)),
          borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: const Color(0xFFB9D2FF)),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500))
      ]));
}

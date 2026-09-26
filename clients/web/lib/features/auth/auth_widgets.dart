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
      required this.subtitle,
      this.switchLabel,
      this.onSwitch});
  final Widget child;
  final String title, subtitle;
  final String? switchLabel;
  final VoidCallback? onSwitch;
  static const blue = Color(0xFF4779FF);

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context), dark = base.brightness == Brightness.dark;
    final colors = ColorScheme.fromSeed(
        seedColor: blue,
        primary: blue,
        brightness: base.brightness,
        surface: dark ? const Color(0xFF151E31) : const Color(0xFFF8FAFF));
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
            color: dark ? const Color(0xFF34405A) : const Color(0xFFD4DAE5)));
    final theme = base.copyWith(
        colorScheme: colors,
        textTheme: base.textTheme
            .apply(bodyColor: colors.onSurface, displayColor: colors.onSurface),
        inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: dark ? const Color(0xFF1D2940) : const Color(0xFFF9FAFD),
            labelStyle: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
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
            fillColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected) ? blue : null)),
        textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
                foregroundColor:
                    dark ? const Color(0xFFA7C0FF) : const Color(0xFF2455C9))),
        filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: blue,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    dark ? const Color(0xFF374153) : const Color(0xFFDCE0E7),
                disabledForegroundColor:
                    dark ? const Color(0xFFADB5C4) : const Color(0xFF697181),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))));
    return Theme(
        data: theme,
        child: Builder(
            builder: (context) => Scaffold(
                backgroundColor:
                    dark ? const Color(0xFF101827) : const Color(0xFFEBEDF2),
                body: SafeArea(child: LayoutBuilder(builder: (context, size) {
                  final wide = size.maxWidth >= 1000 &&
                      size.maxHeight >= 650 &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.4;
                  final form = Column(children: [
                    Padding(
                        padding: EdgeInsets.fromLTRB(
                            wide ? 24 : 20, 18, wide ? 24 : 20, 8),
                        child: SizedBox(
                            width: double.infinity,
                            child: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 20,
                                runSpacing: 12,
                                children: [
                                  const KryinTalkLogo(
                                      size: 34,
                                      showText: true,
                                      textSize: 18,
                                      backgroundColor: blue,
                                      iconColor: Colors.white),
                                  if (switchLabel != null)
                                    TextButton(
                                        onPressed: onSwitch,
                                        style: TextButton.styleFrom(
                                            backgroundColor: colors.surface,
                                            side: BorderSide(
                                                color: colors.outlineVariant),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 12)),
                                        child: Text(switchLabel!)),
                                ]))),
                    Expanded(
                        child: LayoutBuilder(
                            builder: (context, area) => SingleChildScrollView(
                                padding: EdgeInsets.symmetric(
                                    horizontal: wide ? 36 : 24, vertical: 24),
                                child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                        minHeight: (area.maxHeight - 48)
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
                                                          width: 48,
                                                          height: 48,
                                                          decoration: BoxDecoration(
                                                              color: colors
                                                                  .surface,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          14),
                                                              border: Border
                                                                  .all(
                                                                      color: colors
                                                                          .outlineVariant),
                                                              boxShadow: [
                                                                BoxShadow(
                                                                    color: blue
                                                                        .withValues(
                                                                            alpha:
                                                                                .08),
                                                                    blurRadius:
                                                                        0,
                                                                    spreadRadius:
                                                                        5)
                                                              ]),
                                                          child: Icon(
                                                              Icons
                                                                  .person_outline_rounded,
                                                              color: colors
                                                                  .onSurface,
                                                              size: 25))),
                                                  const SizedBox(height: 20),
                                                  Text(title,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: theme.textTheme
                                                          .headlineMedium
                                                          ?.copyWith(
                                                              fontSize: 28,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              letterSpacing:
                                                                  -.8)),
                                                  const SizedBox(height: 8),
                                                  Text(subtitle,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                              color: colors
                                                                  .onSurfaceVariant,
                                                              height: 1.6)),
                                                  const SizedBox(height: 24),
                                                  child,
                                                ]))))))),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
                        child: SizedBox(
                            width: double.infinity,
                            child: Text(
                                '© ' +
                                    DateTime.now().year.toString() +
                                    ' KryinLabs · KryinTalk',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant)))),
                  ]);
                  return Padding(
                      padding: EdgeInsets.all(wide ? 14 : 0),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                  Expanded(child: form),
                                  const SizedBox(width: 14),
                                  const Expanded(child: _ConversationPanel()),
                                ])
                          : form);
                })))));
  }
}

class _ConversationPanel extends StatelessWidget {
  const _ConversationPanel();
  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: DecoratedBox(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                Color(0xFFFAFCFF),
                Color(0xFFE8EEFF),
                Color(0xFF9DBAFF),
                Color(0xFF5B87FF)
              ],
                  stops: [
                0,
                .35,
                .7,
                1
              ])),
          child: LayoutBuilder(
              builder: (context, size) => Stack(children: [
                    const Positioned.fill(
                        child: CustomPaint(painter: _ConversationTiles())),
                    Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Bring your conversations\ntogether.',
                                  style: TextStyle(
                                      color: Color(0xFF101A2C),
                                      fontSize: 34,
                                      fontWeight: FontWeight.w600,
                                      height: 1.15,
                                      letterSpacing: -1)),
                              const SizedBox(height: 16),
                              ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: 350),
                                  child: Text(
                                      'Chats, groups and shared files. A simpler place for your team to stay connected with KryinTalk.',
                                      style: TextStyle(
                                          color: Color(0xFF4D5870),
                                          fontSize: 14,
                                          height: 1.65))),
                              const Spacer(),
                              for (final item in [
                                (
                                  Icons.forum_outlined,
                                  'Conversations that stay connected',
                                  'Chats'
                                ),
                                (
                                  Icons.folder_open_rounded,
                                  'Ideas and files, shared in one place',
                                  'Files'
                                ),
                                (
                                  Icons.verified_user_outlined,
                                  'A community with approved access',
                                  'Members'
                                )
                              ])
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 18, vertical: 20),
                                        decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: .14),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: .15))),
                                        child: Row(children: [
                                          Icon(item.$1,
                                              color: const Color(0xFF19356B),
                                              size: 22),
                                          const SizedBox(width: 14),
                                          Expanded(
                                              child: Text(item.$2,
                                                  style: const TextStyle(
                                                      color: const Color(
                                                          0xFF19356B),
                                                      fontSize: 13,
                                                      height: 1.5))),
                                          const SizedBox(width: 16),
                                          Text(item.$3,
                                              style: const TextStyle(
                                                  color: Color(0xFF244576),
                                                  fontSize: 11))
                                        ]))),
                              const SizedBox(height: 4),
                            ])),
                    Positioned(
                        top: size.maxHeight * .28,
                        right: size.maxWidth * .14,
                        child: ExcludeSemantics(
                            child: Transform(
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, .001)
                                  ..rotateX(.4)
                                  ..rotateZ(-.65),
                                alignment: Alignment.center,
                                child: Container(
                                    width: 126,
                                    height: 126,
                                    decoration: BoxDecoration(
                                        color: AuthLayout.blue,
                                        borderRadius: BorderRadius.circular(28),
                                        border: Border.all(
                                            color: const Color(0xFF92B4FF),
                                            width: 3),
                                        boxShadow: [
                                          BoxShadow(
                                              color: const Color(0xFF3268EC)
                                                  .withValues(alpha: .35),
                                              offset: const Offset(-12, 22),
                                              blurRadius: 25)
                                        ]),
                                    child: const Icon(Icons.forum_rounded,
                                        color: Colors.white, size: 64))))),
                  ]))));
}

class _ConversationTiles extends CustomPainter {
  const _ConversationTiles();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6583BC).withValues(alpha: .1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 6; i++) {
      final x = size.width * .4 + i * 125, y = size.height * .19 - i * 66;
      final path = Path()
        ..moveTo(x, y)
        ..lineTo(x + 135, y + 65)
        ..lineTo(x + 10, y + 130)
        ..lineTo(x - 125, y + 65)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ConversationTiles oldDelegate) => false;
}

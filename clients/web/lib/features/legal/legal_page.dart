import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';

import 'privacy_screen.dart';
import 'terms_screen.dart';

const _blue = Color(0xFF4779FF);
const _ink = Color(0xFF15243D);
const _muted = Color(0xFF66738C);
const _line = Color(0xFFE4EAF3);

class LegalTermsPage extends StatelessWidget {
  const LegalTermsPage({super.key});
  @override
  Widget build(BuildContext context) => LegalPageShell(
        title: 'Terms of Service',
        eyebrow: 'KRYINTALK · PLATFORM RULES',
        summary:
            'The agreement for using KryinTalk and participating in an approved workspace.',
        icon: LucideIcons.scale,
        sections: TermsScreen.accountSections,
        active: '/terms',
      );
}

class LegalPrivacyPage extends StatelessWidget {
  const LegalPrivacyPage({super.key});
  @override
  Widget build(BuildContext context) => LegalPageShell(
        title: 'Privacy Policy',
        eyebrow: 'KRYINTALK · YOUR DATA',
        summary:
            'How KryinTalk handles account details, messages, files and security records.',
        icon: LucideIcons.shield_check,
        sections: PrivacyPolicyScreen.accountSections,
        active: '/privacy',
      );
}

class LegalPageShell extends StatefulWidget {
  const LegalPageShell(
      {super.key,
      required this.title,
      required this.eyebrow,
      required this.summary,
      required this.icon,
      required this.sections,
      this.active});
  final String title, eyebrow, summary;
  final IconData icon;
  final List<Map<String, String>> sections;
  final String? active;
  @override
  State<LegalPageShell> createState() => _LegalPageShellState();
}

class _LegalPageShellState extends State<LegalPageShell> {
  final _search = TextEditingController();
  String _query = '';
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final sections = query.isEmpty
        ? widget.sections
        : widget.sections
            .where((s) =>
                '${s['title']} ${s['content']}'.toLowerCase().contains(query))
            .toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(LucideIcons.arrow_left),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/login')),
        title: const Text('KryinTalk',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w800)),
        actions: [
          _nav(context, 'About', '/about'),
          _nav(context, 'Contact', '/contact'),
          Padding(
              padding: const EdgeInsets.only(right: 18),
              child: OutlinedButton(
                  onPressed: () => context.go('/login'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: _ink,
                      side: const BorderSide(color: _line),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: const Text('Back to login'))),
        ],
      ),
      body: LayoutBuilder(builder: (context, size) {
        final wide = size.maxWidth >= 900;
        return SingleChildScrollView(
            padding:
                EdgeInsets.symmetric(horizontal: wide ? 72 : 20, vertical: 34),
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 500),
                              tween: Tween(begin: 0, end: 1),
                              builder: (context, value, child) => Opacity(
                                  opacity: value,
                                  child: Transform.translate(
                                      offset: Offset(0, 18 * (1 - value)),
                                      child: child)),
                              child: _hero(context)),
                          const SizedBox(height: 24),
                          if (widget.active == '/terms' ||
                              widget.active == '/privacy')
                            _policyNav(context),
                          if (widget.active == '/terms' ||
                              widget.active == '/privacy')
                            const SizedBox(height: 16),
                          _searchBar(),
                          const SizedBox(height: 18),
                          if (sections.isEmpty)
                            _empty()
                          else
                            ...sections.map(_sectionCard),
                          const SizedBox(height: 26),
                          _footer(context),
                        ]))));
      }),
    );
  }

  Widget _hero(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
              colors: [Color(0xFFEAF0FF), Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          border: Border.all(color: const Color(0xFFDDE7FF))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: _blue,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x334779FF),
                      blurRadius: 18,
                      offset: Offset(0, 8))
                ]),
            child: Icon(widget.icon, color: Colors.white, size: 25)),
        const SizedBox(width: 18),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.eyebrow,
              style: const TextStyle(
                  color: _blue,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(widget.title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: _ink, fontWeight: FontWeight.w800, letterSpacing: -1)),
          const SizedBox(height: 8),
          Text(widget.summary,
              style: const TextStyle(color: _muted, fontSize: 14, height: 1.6)),
          const SizedBox(height: 16),
          const Text('Last updated · 26 September 2026',
              style: TextStyle(
                  color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
        ])),
      ]));

  Widget _policyNav(BuildContext context) =>
      Wrap(spacing: 10, runSpacing: 10, children: [
        _pill(context, 'Terms of Service', '/terms', LucideIcons.scale),
        _pill(context, 'Privacy Policy', '/privacy', LucideIcons.shield_check),
        _pill(context, 'Acceptable Use', '/acceptable-use',
            LucideIcons.badge_check),
        _pill(context, 'Copyright', '/copyright', LucideIcons.copyright),
      ]);

  Widget _pill(
          BuildContext context, String text, String route, IconData icon) =>
      OutlinedButton.icon(
          onPressed: () => context.go(route),
          icon: Icon(icon, size: 15),
          label: Text(text),
          style: OutlinedButton.styleFrom(
              foregroundColor: widget.active == route ? _blue : _muted,
              backgroundColor: widget.active == route
                  ? const Color(0xFFEAF0FF)
                  : Colors.white,
              side: BorderSide(
                  color:
                      widget.active == route ? const Color(0xFFBED0FF) : _line),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))));

  Widget _searchBar() => TextField(
      controller: _search,
      onChanged: (value) => setState(() => _query = value),
      decoration: InputDecoration(
          hintText: 'Search this page',
          prefixIcon: const Icon(LucideIcons.search, size: 18),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                  icon: const Icon(LucideIcons.x, size: 16)),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _line)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _line)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _blue, width: 1.5))));

  Widget _sectionCard(Map<String, String> section) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _line),
          boxShadow: const [
            BoxShadow(
                color: Color(0x050E1E3A), blurRadius: 18, offset: Offset(0, 6))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(section['title'] ?? '',
            style: const TextStyle(
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1.35)),
        const SizedBox(height: 12),
        Text(section['content'] ?? '',
            style: const TextStyle(
                color: Color(0xFF46536B), fontSize: 14, height: 1.75)),
      ]));

  Widget _empty() => const Padding(
      padding: EdgeInsets.all(40),
      child: Center(
          child:
              Text('No matching sections.', style: TextStyle(color: _muted))));

  Widget _footer(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: const Color(0xFF122342),
          borderRadius: BorderRadius.circular(22)),
      child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 14,
          children: [
            const Text('KryinTalk · built by KryinLabs',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            Wrap(spacing: 16, children: [
              _footerLink(context, 'About', '/about'),
              _footerLink(context, 'Contact', '/contact'),
              _footerLink(context, 'Acceptable Use', '/acceptable-use'),
              _footerLink(context, 'Copyright', '/copyright')
            ]),
          ]));

  Widget _footerLink(
          BuildContext context, String text, String route) =>
      TextButton(
          onPressed: () => context.go(route),
          child: Text(text,
              style: const TextStyle(color: Color(0xFFBBD0FF), fontSize: 12)));
  Widget _nav(BuildContext context, String text, String route) => TextButton(
      onPressed: () => context.go(route),
      child: Text(text,
          style: const TextStyle(color: _muted, fontWeight: FontWeight.w600)));
}

class LegalInfoPage extends StatelessWidget {
  const LegalInfoPage({super.key, required this.type});
  final String type;
  @override
  Widget build(BuildContext context) {
    switch (type) {
      case 'acceptable-use':
        return const LegalPageShell(
            title: 'Acceptable Use',
            eyebrow: 'KRYINTALK · COMMUNITY SAFETY',
            summary:
                'The conduct standards that keep approved workspaces useful and safe.',
            icon: LucideIcons.badge_check,
            active: '/acceptable-use',
            sections: [
              {
                'title': 'Use KryinTalk for real collaboration',
                'content':
                    'Use the service for lawful communication, teamwork, file sharing and organization-approved work. Keep your account details accurate and protect your sign-in credentials.'
              },
              {
                'title': 'Do not harm people or systems',
                'content':
                    'Do not harass, threaten, stalk, impersonate, doxx, discriminate against, or target another person. Do not probe, overload, scrape, reverse engineer, distribute malware, bypass access controls or interfere with the service.'
              },
              {
                'title': 'Respect content and permissions',
                'content':
                    'Only upload content you have the right to share. Do not send unlawful, abusive, sexually exploitative, hateful, deceptive or privacy-invasive material. Respect workspace membership and administrator decisions.'
              },
              {
                'title': 'Reports and enforcement',
                'content':
                    'Report safety, abuse, copyright or access concerns to your organization administrator or KryinLabs support. We may restrict, suspend or remove access when needed to protect users, the workspace or the service.'
              },
            ]);
      case 'copyright':
        return const LegalPageShell(
            title: 'Copyright & Content',
            eyebrow: 'KRYINTALK · CREATOR RIGHTS',
            summary:
                'Who owns content, what license is needed to operate the service, and how to report infringement.',
            icon: LucideIcons.copyright,
            active: '/copyright',
            sections: [
              {
                'title': 'Your content remains yours',
                'content':
                    'You or your organization keep ownership of messages, files, profile assets and other material you submit. KryinTalk receives only the limited permission needed to host, transmit, secure, display and back up that material for the service.'
              },
              {
                'title': 'KryinTalk and KryinLabs material',
                'content':
                    'The KryinTalk name, brand, interface, software, documentation and original visual assets belong to KryinLabs or their licensors. Do not copy, resell or redistribute them without written permission.'
              },
              {
                'title': 'Report infringement',
                'content':
                    'Send a clear notice identifying the copyrighted work, the location of the material, your contact details, a good-faith statement and your authority to act. Start with your organization administrator, or contact KryinLabs through the Contact page.'
              },
              {
                'title': 'Repeat infringement',
                'content':
                    'Accounts that repeatedly share infringing material may lose access, subject to the organization’s rules and applicable law.'
              },
            ]);
      case 'contact':
        return const LegalPageShell(
            title: 'Contact KryinTalk',
            eyebrow: 'KRYINTALK · SUPPORT',
            summary:
                'Choose the right path for account access, privacy, safety or copyright questions.',
            icon: LucideIcons.mail,
            active: '/contact',
            sections: [
              {
                'title': 'Account access and invitations',
                'content':
                    'For approval requests, invite codes, suspended accounts or workspace membership, contact your organization administrator first. They control access to the private workspace.'
              },
              {
                'title': 'Privacy requests',
                'content':
                    'Ask your organization administrator for account correction, access, deletion or retention requests. Include the account email and a short description of the request; never send passwords or authentication codes.'
              },
              {
                'title': 'Safety and abuse',
                'content':
                    'Report threats, harassment, impersonation, security issues or harmful content to your organization administrator. Include the relevant workspace, account and message details when safe to do so.'
              },
              {
                'title': 'KryinLabs support',
                'content':
                    'For product or legal correspondence, email support@kryinlabs.com. We will route organization-controlled account requests to the appropriate administrator.'
              },
            ]);
      default:
        return const LegalPageShell(
            title: 'About KryinTalk',
            eyebrow: 'KRYINTALK · KRYINLABS',
            summary:
                'A focused communication space for approved teams and communities.',
            icon: LucideIcons.message_circle,
            active: '/about',
            sections: [
              {
                'title': 'A calmer place to work together',
                'content':
                    'KryinTalk brings conversations, groups, shared files and notifications into one private workspace. It is designed for teams that need clear communication and deliberate access control.'
              },
              {
                'title': 'Access is intentional',
                'content':
                    'People may create an account, confirm their email and request access. Organization administrators decide who can enter the workspace and which capabilities each role receives.'
              },
              {
                'title': 'Built by KryinLabs',
                'content':
                    'KryinTalk is maintained by KryinLabs. Learn more at kryintalks.vercel.app or contact support@kryinlabs.com for product questions.'
              },
            ]);
    }
  }
}

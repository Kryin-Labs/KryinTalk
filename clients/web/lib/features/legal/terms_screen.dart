/// ConnectHub — Terms of Service Screen & Modal.
///
/// Comprehensive enterprise Terms of Service and Platform Governance Agreement
/// compliant with the Information Technology Act, 2000 (India), IT Intermediary
/// Guidelines Rules 2021, and the Digital Personal Data Protection Act, 2023 (DPDPA).
///
/// Designed in ConnectHub's signature Light Cream & Claymorphism Theme.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../core/theme/app_theme.dart';
import 'privacy_screen.dart';

class TermsScreen extends StatefulWidget {
  static List<Map<String,String>> get accountSections => _TermsScreenState._sections;
  final bool isModal;

  const TermsScreen({super.key, this.isModal = false});

  static Future<void> showModal(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 860),
          child: const TermsScreen(isModal: true),
        ),
      ),
    );
  }

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  static const List<Map<String, String>> _sections = [
    {
      'id': '1',
      'title': '1. Acceptance of Terms, Corporate Governance & Scope of Agreement',
      'content':
          'These Terms of Service ("Agreement", "Terms") constitute a legally binding contractual agreement between you ("User", "Subscriber", "Organization Representative") and the operators, developers, and hosting entities of the ConnectHub / Kryin-Talks platform ("Platform", "ConnectHub", "we", "our", "us"). By registering for an account, accessing the web portal, deploying desktop or mobile client packages (including Android APK binaries), or interacting with any connected Application Programming Interfaces (APIs), you explicitly acknowledge that you have read, understood, and consented to be bound by the entirety of these Terms. If you are entering into this Agreement on behalf of a corporate enterprise, educational institution, governmental body, or other legal entity, you represent and warrant that you possess full legal authority to bind such entity to these provisions. In the event you do not possess such legal authority, or if you do not unconditionally agree with any clause set forth herein, you must immediately cease all access to and use of the platform and its underlying communication services.',
    },
    {
      'id': '2',
      'title': '2. User Account Registration, Identity Verification & Persistent Session Security',
      'content':
          'To utilize ConnectHub, users must maintain valid enterprise credentials established through designated organization administrators or authorized self-registration workflows. You are solely responsible for safeguarding the confidentiality of your authentication identifiers, passwords, and cryptographic multi-factor credentials. When the "Keep me signed in" feature is activated upon authentication, the client application generates persistent JSON Web Token (JWT) Bearer access and refresh credentials stored locally on your physical hardware storage (including browser LocalStorage, IndexedDB subsystems, or mobile Android EncryptedSharedPreferences). These persistent tokens permit uninterrupted session continuity across application restarts and operating system reboots until explicit manual logout. You assume total responsibility and legal accountability for all transmissions, group communications, administrative configurations, and role modifications dispatched through sessions authenticated on your registered devices. You agree to notify organization administrators immediately upon discovering any unauthorized session access or hardware compromise.',
    },
    {
      'id': '3',
      'title': '3. Intermediary Status & Statutory Safe Harbor Protection (Section 79, IT Act, 2000)',
      'content':
          'ConnectHub operates strictly and exclusively as an "Intermediary" as defined under Section 2(1)(w) and Section 79 of the Information Technology Act, 2000 of the Republic of India. The platform functions as a neutral, automated, technological infrastructure conduit designed solely for the transmission, temporary routing, and storage of electronic communications between authorized organization participants. ConnectHub and its operators: (a) do not initiate any electronic communication or transmission; (b) do not select or determine the receiver or recipient of any transmission; (c) do not modify, curate, or manipulate the textual, audio, graphical, or binary content contained in any transmission; and (d) do not exercise pre-emptive editorial screening or discretionary gatekeeping over user-generated communications. In accordance with Section 79(2)(a) and the Information Technology (Intermediary Guidelines and Digital Media Ethics Code) Rules, 2021, ConnectHub shall not be subject to any civil, criminal, or regulatory liability for any user-generated data, files, communications, links, or intellectual property hosted or transmitted via the platform.',
    },
    {
      'id': '4',
      'title': '4. Prohibited Content & Statutory Conduct Standards (Rule 3(1)(b), IT Rules 2021)',
      'content':
          'In strict compliance with statutory obligations established under Rule 3(1)(b) of the Information Technology (Intermediary Guidelines and Digital Media Ethics Code) Rules, 2021, all users and organizations are strictly prohibited from hosting, displaying, uploading, modifying, publishing, transmitting, storing, updating, or sharing any information that: (i) belongs to another person and to which the user does not have any legal right; (ii) is defamatory, obscene, pornographic, pedophilic, invasive of another\'s privacy including bodily privacy, insulting or harassing on the basis of gender, racially or ethnically objectionable, disparaging, relating to or encouraging money laundering or gambling, or otherwise inconsistent with or contrary to the laws in force; (iii) is harmful to minors in any manner; (iv) infringes any patent, trademark, copyright, trade secret, or other proprietary intellectual property rights; (v) violates any law for the time being in force in the Republic of India or relevant international jurisdictions; (vi) deceives or misleads the addressee about the origin of the message or knowingly communicates any misinformation or information which is patently false or misleading; (vii) impersonates another person or entity; (viii) contains software viruses, Trojan horses, worms, time bombs, cancelbots, or any other computer code, files, or programs designed to interrupt, destroy, compromise, or limit the functionality of any computer resource; or (ix) threatens the unity, integrity, defense, security, or sovereignty of India, friendly relations with foreign States, or public order, or causes incitement to the commission of any cognizable offense.',
    },
    {
      'id': '5',
      'title': '5. Role-Based Access Control, Organizational Hierarchy & Administrative Overrides',
      'content':
          'The platform implements a strict multi-tier Role-Based Access Control (RBAC) security architecture governing group visibility, channel access, and messaging capabilities. Organization Owners and Administrators possess authoritative privileges to inspect institutional audit trails, assign custom permission matrices, reorder role hierarchies, and moderate internal workspaces. Standard group privacy settings ensure private groups remain completely invisible and inaccessible to non-members. In institutional emergency, security oversight, or moderation circumstances, authorized Super Administrators possess the platform capability to activate time-bounded administrative overrides (including the SuperAdmin 2-Minute Force Message Override) to dispatch critical platform notifications into groups where they are not standard members, with all actions immutably recorded in the central compliance audit log.',
    },
    {
      'id': '6',
      'title': '6. Limitation of Liability, Absence of Warranties & Operational Disclaimers',
      'content':
          'TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE STATUTORY LAW IN INDIA AND INTERNATIONAL JURISDICTIONS, CONNECTHUB, ITS DEVELOPERS, INFRASTRUCTURE PROVIDERS, DIRECTORS, AGENTS, AND LICENSORS PROVIDE THE PLATFORM STRICTLY ON AN "AS IS", "AS AVAILABLE", AND "WITH ALL FAULTS" BASIS. WE EXPRESSLY DISCLAIM ALL WARRANTIES OF ANY KIND, WHETHER EXPRESS, IMPLIED, STATUTORY, OR OTHERWISE, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, QUIET ENJOYMENT, ACCURACY, TIMELINESS, NON-INFRINGEMENT, AND FREEDOM FROM COMPUTER VIRUSES OR HARMFUL COMPONENTS. UNDER NO CIRCUMSTANCES SHALL CONNECTHUB OR ITS OPERATORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, CONSEQUENTIAL, SPECIAL, PUNITIVE, EXEMPLARY, OR ENHANCED DAMAGES WHATSOEVER, INCLUDING WITHOUT LIMITATION DAMAGES FOR LOSS OF BUSINESS PROFITS, REVENUE, GOODWILL, REPUTATION, USE, DATA INTEGRITY, NETWORK CONNECTIVITY INTERRUPTIONS, LOSS OF ELECTRONIC COMMUNICATIONS, UNAUTHORIZED ACCOUNT HIJACKING RESULTING FROM LOST PASSWORDS OR COMPROMISED USER DEVICES, HARDWARE THEFT, OR ANY DEFAMATORY, ILLEGAL, OR TORTIOUS CONDUCT OF ANY USER, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES IN ADVANCE.',
    },
    {
      'id': '7',
      'title': '7. Customer Data Ownership, Intellectual Property & Software Licenses',
      'content':
          'As between the user and ConnectHub, the organization and its authorized users retain all proprietary rights, ownership title, and copyright in all text messages, uploaded documents, multimedia files, attachments, and profile assets uploaded to the platform ("Customer Data"). You grant ConnectHub a non-exclusive, royalty-free, worldwide license solely to host, transmit, cache, index, and process Customer Data strictly to the extent necessary to deliver the real-time communications service. All underlying software code, database architectures, client user interfaces, graphic designs, trademarks, and documentation associated with ConnectHub are the exclusive proprietary intellectual property of the platform creators and are protected under Indian and international copyright and intellectual property treaties.',
    },
    {
      'id': '8',
      'title': '8. Indemnification & Legal Defense Obligations',
      'content':
          'You agree to defend, indemnify, and hold harmless ConnectHub, its founding developers, hosting providers, affiliates, directors, officers, employees, and authorized agents from and against any and all legal claims, governmental investigations, regulatory penalties, liabilities, losses, damages, judgments, settlements, costs, and expenses (including reasonable attorney fees and legal costs) arising out of or related to: (a) your access to or utilization of the platform; (b) any content, communications, or files uploaded or transmitted through your authenticated user account; (c) your violation of any statutory provision, regulation, or third-party right; or (d) any breach of these Terms of Service.',
    },
    {
      'id': '9',
      'title': '9. Service Modification, Account Deactivation & Data Lifecycle Management',
      'content':
          'ConnectHub reserves the right to deploy updates, bug fixes, feature enhancements, or architectural modifications at any time with or without prior notification. Organization administrators retain the unilateral right to suspend, deactivate, or terminate user accounts within their corporate tenant. Upon account termination or organization workspace deletion, active session tokens are invalidated and user access revoked. Historical audit logs, system telemetry, and compliance records may be retained in encrypted archival stores for statutory compliance periods as mandated under applicable Indian and international regulations.',
    },
    {
      'id': '10',
      'title': '10. Governing Law, Exclusive Jurisdiction & Internal Grievance Redressal',
      'content':
          'This Agreement, its construction, validity, interpretation, and performance shall be governed by applicable laws and institutional enterprise policies without regard to conflict of law principles. Any dispute, claim, or internal inquiry arising out of or in connection with the platform shall be addressed under the governance framework of your hosting organization, institution, or university.\n\nIn compliance with institutional governance and statutory intermediary guidelines, your deploying organization (university administration, corporate IT department, or designated Platform Super Administrator) maintains primary responsibility for receiving and redressing user inquiries, safety concerns, permission disputes, or policy violations. All formal concerns should be submitted directly to your organization\'s internal IT Helpdesk, Department Administrator, or Platform Super Administrator for investigation and timely resolution.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _searchQuery.trim().isEmpty
        ? _sections
        : _sections.where((s) {
            final q = _searchQuery.toLowerCase();
            return s['title']!.toLowerCase().contains(q) ||
                s['content']!.toLowerCase().contains(q);
          }).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.creamBackground,
        borderRadius: BorderRadius.circular(widget.isModal ? 20 : 0),
        border: widget.isModal
            ? Border.all(color: const Color(0xFFE7E5E4), width: 1.2)
            : null,
        boxShadow: widget.isModal
            ? const [
                BoxShadow(
                  color: Color(0x18000000),
                  blurRadius: 36,
                  offset: Offset(0, 16),
                ),
              ]
            : null,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(
              widget.isModal ? LucideIcons.x : LucideIcons.arrow_left,
              color: AppTheme.charcoalForeground,
              size: 20,
            ),
            onPressed: () {
              if (widget.isModal) {
                Navigator.of(context).pop();
              } else if (context.canPop()) {
                context.pop();
              } else {
                context.go('/login');
              }
            },
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppTheme.emeraldLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.emeraldBorder),
                ),
                child: const Icon(LucideIcons.scale, color: AppTheme.primaryTeal, size: 18),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Terms of Service',
                    style: TextStyle(
                      color: AppTheme.charcoalForeground,
                      fontWeight: FontWeight.bold,
                      fontSize: 16.5,
                    ),
                  ),
                  const Text(
                    'Platform Governance & Statutory Framework',
                    style: TextStyle(color: AppTheme.mutedText, fontSize: 11.5),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            // Switch Tab to Privacy Policy
            TextButton.icon(
              onPressed: () {
                if (widget.isModal) {
                  Navigator.of(context).pop();
                  PrivacyPolicyScreen.showModal(context);
                } else {
                  context.go('/privacy');
                }
              },
              icon: const Icon(LucideIcons.shield_check, size: 15, color: AppTheme.primaryTeal),
              label: const Text(
                'Privacy Policy',
                style: TextStyle(
                  color: AppTheme.primaryTeal,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (!widget.isModal)
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/login'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.charcoalForeground,
                    side: const BorderSide(color: Color(0xFFE7E5E4)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(LucideIcons.log_in, size: 15),
                  label: const Text('Back to Login', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: Color(0xFFE7E5E4)),
          ),
        ),
        body: Column(
          children: [
            // Search & Document Info Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      style: const TextStyle(fontSize: 13, color: AppTheme.charcoalForeground),
                      decoration: InputDecoration(
                        hintText: 'Search terms clauses or keywords...',
                        hintStyle: const TextStyle(fontSize: 13, color: AppTheme.mutedText),
                        prefixIcon: const Icon(LucideIcons.search, size: 16, color: AppTheme.mutedText),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(LucideIcons.x, size: 14, color: AppTheme.mutedText),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: AppTheme.creamBackground,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE7E5E4)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE7E5E4)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.primaryTeal, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.emeraldLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.emeraldBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(LucideIcons.globe, color: AppTheme.primaryTeal, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'Jurisdiction: India',
                          style: TextStyle(
                            color: AppTheme.primaryTeal,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE7E5E4)),

            // Main Content Area
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Document Header Intro Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE7E5E4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F4),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFE7E5E4)),
                                ),
                                child: const Text(
                                  'VERSION 2026.2',
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.mutedText),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '• Effective Date: August 18, 2026',
                                style: TextStyle(fontSize: 12, color: AppTheme.mutedText),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'ConnectHub Enterprise Collaboration Agreement',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.charcoalForeground,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Please review this Agreement thoroughly prior to accessing or utilizing ConnectHub enterprise software services. This document delineates binding operational responsibilities, safe harbor statutory protections, multi-tier permissions, and limitation provisions governing institutional communication workloads.',
                            style: TextStyle(fontSize: 13, height: 1.55, color: Color(0xFF44403C)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Filtered Sections
                    if (filtered.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              const Icon(LucideIcons.search_x, size: 36, color: AppTheme.mutedText),
                              const SizedBox(height: 12),
                              Text(
                                'No terms clauses matching "$_searchQuery"',
                                style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...filtered.map((sec) => _buildSectionCard(sec)),

                    const SizedBox(height: 24),

                    // Formal Footer Section
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE7E5E4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(LucideIcons.mail, size: 16, color: AppTheme.primaryTeal),
                              SizedBox(width: 8),
                              Text(
                                'Institutional Support & Compliance Inquiries',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: AppTheme.charcoalForeground,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'For institutional inquiries, compliance verifications, or account permissions, please contact your university / organization IT Helpdesk or designated Platform Super Administrator.',
                            style: TextStyle(fontSize: 12.5, color: Color(0xFF57534E), height: 1.5),
                          ),
                          const SizedBox(height: 16),
                          const Divider(height: 1, color: Color(0xFFE7E5E4)),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '© 2026 ConnectHub Technologies. All rights reserved.',
                                style: TextStyle(fontSize: 11.5, color: AppTheme.mutedText),
                              ),
                              if (widget.isModal)
                                FilledButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.primaryTeal,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: const Text('I Understand & Agree', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(Map<String, String> sec) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7E5E4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sec['title']!,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14.5,
              color: AppTheme.charcoalForeground,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            sec['content']!,
            style: const TextStyle(
              fontSize: 13,
              height: 1.68,
              color: Color(0xFF44403C),
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

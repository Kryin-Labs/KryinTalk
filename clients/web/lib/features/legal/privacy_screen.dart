/// KryinTalks — Privacy Policy Screen & Modal.
///
/// Comprehensive Privacy Policy and Personal Data Governance Disclosure compliant
/// with the Digital Personal Data Protection Act, 2023 (DPDPA), Information Technology
/// Act, 2000, and Information Technology (Reasonable Security Practices and Procedures
/// and Sensitive Personal Data or Information) Rules, 2011.
///
/// Designed in KryinTalks's signature Light Cream & Claymorphism Theme.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../core/theme/app_theme.dart';
import 'terms_screen.dart';

class PrivacyPolicyScreen extends StatefulWidget {
  static List<Map<String,String>> get accountSections => _PrivacyPolicyScreenState._sections;
  final bool isModal;

  const PrivacyPolicyScreen({super.key, this.isModal = false});

  static Future<void> showModal(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 860),
          child: const PrivacyPolicyScreen(isModal: true),
        ),
      ),
    );
  }

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
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
      'title': '1. General Statement of Privacy & Statutory Scope (DPDPA 2023 & IT Act 2000)',
      'content':
          'KryinTalks ("the Platform", "we", "our", "us") recognizes the paramount importance of data privacy, institutional information security, and confidentiality. This Privacy Policy and Personal Data Governance Disclosure delineates the principles, technical methodologies, and regulatory frameworks governing the collection, processing, storage, transit, and lifecycle management of personal data and enterprise communication records within our platform. This policy is executed in comprehensive conformity with the Digital Personal Data Protection Act, 2023 (DPDPA), the Information Technology Act, 2000, and the Information Technology (Reasonable Security Practices and Procedures and Sensitive Personal Data or Information) Rules, 2011 under the laws of the Republic of India. By accessing, deploying, or utilizing KryinTalks through web interfaces, desktop clients, or mobile application packages (including Android APK binaries), you consent to the data governance practices described herein.',
    },
    {
      'id': '2',
      'title': '2. Comprehensive Categories of Information Collected & Processed',
      'content':
          'To deliver real-time collaboration services, authenticate organizational members, and maintain compliance audit trails, KryinTalks processes specific categories of electronic information as detailed below:\n\n'
          '• (a) Account & Identity Information: User full name, display name, registered corporate email address, @username handle, encrypted and cryptographically salted password hashes (Argon2 / bcrypt implementations), profile avatar image assets, assigned enterprise organizational roles, department affiliations, and account status indicators.\n\n'
          '• (b) Hardware Telemetry & Network Identifiers: Browser fingerprints, operating system type and build version, User-Agent strings, display screen resolutions, public IPv4 and IPv6 network addresses, local private IP network metadata, WebSocket connection parameters, and persistent hardware device identifiers on native Android mobile APK installations.\n\n'
          '• (c) Authentication & Session State Tokens: When the "Keep me signed in" configuration is engaged upon authentication, cryptographically signed JSON Web Token (JWT) Bearer access and refresh tokens are stored locally on your physical client device storage (browser LocalStorage, IndexedDB, or Android SharedPreferences) to facilitate continuous session persistence until an explicit manual logout is triggered.\n\n'
          '• (d) Enterprise Communications & Collaborative Media: Direct message transmissions, group chat conversations, threaded replies, uploaded file attachments (including documents, source code, PDF files, images, audio/video media), emoji reaction maps, message pin timestamps, and mention references.\n\n'
          '• (e) Security Telemetry & Immutable Audit Records: Timestamped logging of user authentication events, session renewals, password modifications, role assignments, group creation, member removal, permission reordering, file downloads, and administrative supervisory actions.',
    },
    {
      'id': '3',
      'title': '3. Legal Grounds and Operational Purposes of Data Processing',
      'content':
          'All electronic data collected by KryinTalks is processed strictly pursuant to legitimate operational requirements and authorized corporate purposes, including: (a) authenticating user identity and preventing unauthorized account takeover; (b) establishing secure real-time messaging pipelines and WebSocket channels; (c) enforcing granular Role-Based Access Control (RBAC) permission ceilings; (d) generating regulatory compliance logs and supervisory oversight records for organizational administrators; (e) routing in-app, browser, and mobile notifications for message mentions and group invites; and (f) maintaining platform cyber defense against distributed denial-of-service, malicious script injection, or unauthorized intrusion.',
    },
    {
      'id': '4',
      'title': '4. Hardware Storage Mechanics & "Keep Me Signed In" Session Persistence',
      'content':
          'The activation of "Keep me signed in" during user authentication causes the client software to persist cryptographically secured JWT authentication tokens in local device memory and storage. This persistent credential architecture allows users to remain logged in across application restarts, browser reboots, and operating system cycles without re-entering credentials. You are explicitly advised that persistent session tokens remain active on that specific device until you perform an explicit manual logout. Users accessing KryinTalks from public, shared, or untrusted computer terminals should never enable persistent sign-in and must always execute a manual logout upon session conclusion to purge locally cached tokens.',
    },
    {
      'id': '5',
      'title': '5. Strict Group Isolation, Zero-Leak Partitioning & Administrative Access',
      'content':
          'KryinTalks enforces zero-leak multi-tenant and group-level data isolation. Private groups and unlisted communication channels are mathematically and programmatically isolated from non-members. Non-members cannot discover, index, view metadata for, or inspect messages within private groups. Organization administrators and Super Administrators possess supervisory visibility solely in accordance with statutory compliance and institutional policy frameworks. Any administrative access, role elevation, or utilization of time-bounded emergency overrides (such as the SuperAdmin 2-Minute Force Message Override) is immutably recorded in the central compliance audit trail.',
    },
    {
      'id': '6',
      'title': '6. Zero Commercial Sale Warranty & Third-Party Disclosure Safeguards',
      'content':
          'KryinTalks maintains an unconditional zero commercial sale policy. We do NOT sell, rent, lease, monetize, license, or trade any personal data, user communication records, contact lists, device telemetry, or browser signatures to third-party advertisers, data aggregators, or marketing brokers. Data processed within the platform is accessible strictly by your authorized organization administrators, authorized sub-processors maintaining dedicated cloud or on-premise infrastructure, and statutory law enforcement agencies strictly pursuant to lawful judicial process or formal statutory requests issued under the Information Technology Act, 2000.',
    },
    {
      'id': '7',
      'title': '7. Information Security Architecture & Technical Safeguards',
      'content':
          'KryinTalks implements comprehensive administrative, physical, and technical safeguards engineered to protect electronic data against unauthorized access, destruction, loss, alteration, or disclosure. All data in transit is protected using industry-standard Transport Layer Security (TLS 1.3/1.2). Passwords are cryptographically transformed using salted Argon2/bcrypt algorithms. Role boundaries are evaluated server-side at the API gateway layer prior to executing database queries. However, you acknowledge that no method of electronic storage or internet transmission is mathematically infallible, and the platform disclaims liability for security breaches occurring outside its direct infrastructure control.',
    },
    {
      'id': '8',
      'title': '8. Data Principal Rights under the Digital Personal Data Protection Act, 2023',
      'content':
          'Pursuant to the provisions of the Digital Personal Data Protection Act, 2023 (DPDPA) of India, individual users whose personal data is processed within the platform ("Data Principals") are entitled to statutory rights, including: (i) Right to Access: The right to obtain a summary of personal data being processed and the identities of entities with whom it has been shared; (ii) Right to Correction & Erasure: The right to request the rectification of inaccurate or misleading personal data and the erasure of personal data no longer necessary for the purpose for which it was processed, subject to institutional compliance retention requirements; (iii) Right of Grievance Redressal: The right to have grievances addressed through institutional grievance mechanisms; and (iv) Right to Nominate: The right to nominate another individual to exercise data rights in the event of death or incapacity.',
    },
    {
      'id': '9',
      'title': '9. Data Retention Schedules & Lifecycle Management',
      'content':
          'Customer Data, message histories, and media attachments are retained in accordance with the corporate data retention schedules designated by the organization administrator. When an organization workspace or individual user account is terminated, active session tokens are immediately invalidated. Historical communication records, security audit logs, and compliance telemetry may be retained in encrypted archival databases for statutory compliance periods mandated under Indian cyber security regulations and applicable enterprise governance standards.',
    },
    {
      'id': '10',
      'title': '10. Privacy Inquiries, Data Requests & Administrative Privacy Governance',
      'content':
          'In alignment with privacy protection standards under the Digital Personal Data Protection Act, 2023 (DPDPA) and enterprise data governance best practices, your deploying institution, enterprise organization, or university maintains authority and responsibility over tenant user accounts and data lifecycles.\n\nTo submit requests for data access, correction, account deactivation, or privacy inquiries, please contact your designated Organization IT Administrator or Platform Super Administrator directly through your institutional IT helpdesk.',
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
                child: const Icon(LucideIcons.shield_check, color: AppTheme.primaryTeal, size: 18),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Privacy Policy',
                    style: TextStyle(
                      color: AppTheme.charcoalForeground,
                      fontWeight: FontWeight.bold,
                      fontSize: 16.5,
                    ),
                  ),
                  const Text(
                    'Personal Data Governance & DPDPA 2023 Disclosure',
                    style: TextStyle(color: AppTheme.mutedText, fontSize: 11.5),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            // Switch Tab to Terms of Service
            TextButton.icon(
              onPressed: () {
                if (widget.isModal) {
                  Navigator.of(context).pop();
                  TermsScreen.showModal(context);
                } else {
                  context.go('/terms');
                }
              },
              icon: const Icon(LucideIcons.scale, size: 15, color: AppTheme.primaryTeal),
              label: const Text(
                'Terms of Service',
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
            // Search & Regulatory Info Bar
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
                        hintText: 'Search privacy policy clauses, data categories...',
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
                        Icon(LucideIcons.lock, color: AppTheme.primaryTeal, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'DPDPA 2023 Compliant',
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
                    // Intro Card
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
                                  'DPDPA 2023 DISCLOSURE',
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.mutedText),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '• Revised: August 18, 2026',
                                style: TextStyle(fontSize: 12, color: AppTheme.mutedText),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Personal Data Governance & Privacy Framework',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.charcoalForeground,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'This Privacy Policy details the technical and organizational mechanisms through which KryinTalks processes, stores, and protects organizational communications, device telemetry, and personal data. We adhere strictly to statutory privacy obligations with a permanent zero commercial sale guarantee.',
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
                                'No policy clauses matching "$_searchQuery"',
                                style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...filtered.map((sec) => _buildSectionCard(sec)),

                    const SizedBox(height: 24),

                    // Footer
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
                              Icon(LucideIcons.shield_alert, size: 16, color: AppTheme.primaryTeal),
                              SizedBox(width: 8),
                              Text(
                                'Data Principal Privacy Requests',
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
                            'To exercise your data access, correction, or account deactivation requests under institutional privacy standards, please contact your university / organization IT Administrator or Platform Super Administrator.',
                            style: TextStyle(fontSize: 12.5, color: Color(0xFF57534E), height: 1.5),
                          ),
                          const SizedBox(height: 16),
                          const Divider(height: 1, color: Color(0xFFE7E5E4)),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '© 2026 KryinTalks Technologies. All rights reserved.',
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
                                  child: const Text('I Acknowledge & Agree', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
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

# ConnectHub Discord-Inspired Completion Design

## Purpose

Complete the ConnectHub Flutter web client so it feels like a polished, responsive, enterprise collaboration product with Discord-quality messaging interactions. `NEWREQ.md` is the requirements source of truth; this document makes its implementation boundaries and acceptance criteria explicit.

The work improves ConnectHub rather than cloning Discord. Departments, Teams, Groups, Channels, Files, and the existing five roles remain the product model. There will be no servers, bots, threads, role mentions, mass mentions, custom permission editor, or Discord-style audit log.

## Baseline and constraints

- The verified pre-change archive is `data/backups/full_project_backup_20260812_071446.zip`. It contains the app, database, migrations, configuration templates, frontend, and requirements document.
- The frontend is Flutter Web with Material 3, Riverpod, Dio, GoRouter, WebSockets, and SharedPreferences.
- Existing FastAPI routes provide organization CRUD, messaging CRUD, file upload/download, search, notifications, and administration. The implementation must use those APIs where they exist; any missing flow must receive a minimal, role-protected backend capability rather than a simulated frontend state.
- Authorization stays enforced on the backend. The UI also hides unauthorized controls but is never the security boundary.
- Existing user changes are preserved. The untracked `.claude/` directory is outside this work.

## Product direction

### Visual system

Use a compact, high-contrast collaboration layout: a branded left sidebar, consistent global header, content surface, and context panel only when it adds value. Keep ConnectHub's indigo/violet brand rather than using Discord marks, copy, or server visual language.

The UI uses shared tokens for surfaces, borders, typography, focus rings, status colors, elevation, and motion. All components have deliberate light and dark variants. Primary actions use the brand fill; secondary actions are outlined/tonal; compact controls are ghost or icon buttons with tooltips; destructive actions use an explicit danger treatment.

Motion remains subtle and useful: route/content fades and slides, cards and menus scale/fade in, message toolbars appear on hover/focus, snackbars enter/exit without blocking content, and skeletons animate only while loading. Reduced-motion settings disable nonessential movement.

### Application shell and navigation

The shared scaffold owns the branded sidebar, responsive mobile drawer, active-path navigation, unread/notification badges, and profile controls. The primary navigation remains Dashboard, Messages, Departments, Teams, Groups, Channels, Files, and Search. Friends and Notifications are accessible collaboration utilities. The Admin section contains Users, Logs, Stats, and Backups for authorized roles only.

Every major route uses the same page header contract: title, optional description/breadcrumb, relevant search/filter controls, and a clear right-aligned primary action. Header actions map to real routes or modal actions. On small screens, the sidebar becomes a drawer and page content prioritizes navigation, message history, and composer access rather than shrinking the desktop layout.

### Shared interaction primitives

Create composable primitives for modal dialogs, confirmation dialogs, menus, empty/loading/error states, responsive list/table wrappers, page headers, avatars/presence, entity cards, and feedback snackbars. Dialogs must trap focus, restore focus on close, support Escape, lock background scrolling, show Cancel plus the right-aligned primary action, and fit the mobile viewport. Menus must close on outside click/Escape, support keyboard operation, avoid viewport overflow, and align reliably with their triggers.

Async controls keep a pending state until their request resolves, prevent duplicate submissions, preserve user input on failure, and expose an actionable retry when appropriate. All interactive controls require enabled, disabled, hover, focus, and mobile behavior; icon-only controls receive accessible labels and non-obstructing tooltips.

## Route and feature design

### Dashboard

The dashboard is an actionable summary, not a placeholder. It displays count cards for unread messages/notifications and the organization entities, followed by recent conversations, activity, and role-aware quick actions for New Message, Upload File, and Search. It uses independent skeletons and error/empty states so a single failed metric does not blank the page.

### Messaging and channels

Messages use a master-detail layout. The conversation rail includes search, a New Message action, avatar/presence, unread/mention badges, active selection, and typing state. The message pane contains a conversation header, grouped messages with date separators, timestamps, replies, reactions, attachments, unread divider, and a composer that stays available at narrow widths.

Message hover/focus actions expose reaction, reply, and more without obscuring content. The more menu differentiates own and other messages and includes only actions authorized by existing rules. Editing is inline with Enter to save, Shift+Enter for newline, and Escape to cancel. Deletion is confirmed when appropriate and is only considered complete after a server update and realtime/UI update.

Replies quote one original message and jump back to it; they are not threads. Individual `@user` mentions are selected from an autocomplete that stores structured metadata, renders highlighted/clickable mentions, and creates a recipient notification. The emoji picker provides search, categories, recent choices, close behavior, keyboard support, and viewport-aware positioning. Reactions update their counts and actor list in realtime.

The composer supports multiline text, reply/edit modes, emoji, attachment selection, drag/drop, pasted files, upload progress, cancel/retry, and deduplication. Attachments reuse the existing Files API. Images open in a keyboard-accessible viewer with close, zoom, download, fullscreen/original-link actions. Channels use this same mature message experience while preserving channel grouping and no threads.

### People, profile, presence, and friends

Clickable user identity opens a reusable profile popover with avatar, names, role, presence, custom status when supported, about information, and relevant organization membership. It exposes Message and Add Friend plus a compact contextual menu. The Message action always finds or creates the direct conversation, navigates to it, and focuses the composer. This flow is exercised from every user-bearing route.

Friends are deliberately basic: Friends, Pending, and Blocked states with Add, Accept, Reject, Cancel, Remove, Block, and Unblock operations that call protected APIs. Presence choices are Online, Idle/Away, Do Not Disturb, and Offline, rendered on avatars, profile cards, message rails, and membership lists. There are no suggestions, follower concepts, feeds, or social graph features.

### Organization, file, search, and notification screens

Departments, Teams, and Groups share a polished searchable list/detail pattern. Cards state a description, manager or parent context, membership count, access/privacy where applicable, and last activity. Detail tabs contain only the existing organization relationships: overview, members, related teams/groups/channels, and Files for groups where useful. Authorized creation, edit, invite/member, and delete operations use the shared dialogs and real API calls.

Channels show organized navigation, active/unread state, channel header actions, pinned messages, and the message experience above. Pinned-message lists show author, timestamp, preview, and Jump to Message.

Files provide search, sort/filter, grid/list presentation, preview/icon, metadata, download, rename/delete when the API authorizes it, and Copy Link. The page has loading, empty, and per-operation error states.

Search is a full destination: messages, people, channels, files, departments, teams, and groups render relevant identity, preview, source, timestamp, and click target. Message results navigate to the relevant conversation/channel and scroll to the message. Notifications can be accessed from a header dropdown and the full page, display a clear unread state, support mark-read/mark-all-read, and route to the related resource.

### Administration

Admin UI remains deliberately simple and role-gated. Users has add, search, role/status filtering, profile/edit, and activate/deactivate actions. Roles are fixed to Super Admin, Admin, Manager, Standard User, and Guest User. Logs uses timestamp, user, event, target, result, and basic search/date/event filters. Stats uses responsive, theme-aware metric cards and charts. Backups list date/size/status with create/download/restore/delete controls and explicit confirmation for destructive actions.

## Data, realtime, and backend responsibilities

The frontend uses existing endpoints for conversations, messages, files, organization data, directory search, notifications, and admin management. During implementation, the API audit will identify every interaction with a missing protected endpoint (notably friend relationships, message reactions/pins/replies/mentions/read markers, and any file rename/links that are not yet provided). Missing behavior will be added as minimal schema/model/repository/service/router slices, with migrations and authorization tests where persistence is required.

WebSocket events are normalized by type and update the smallest affected Riverpod state: message creation/edit/deletion, reaction changes, typing, read status, notifications, and friendship changes. Reconnects refresh the affected collection. Reads and unread markers persist server-side whenever a related endpoint exists or is introduced.

## Accessibility, responsiveness, and performance

All new controls use semantic widgets, labels, visible focus, keyboard navigation, and WCAG AA contrast in both themes. Dialogs, menus, tooltips, image viewer, composer autocomplete, and reaction/emoji UI receive explicit keyboard and focus behavior.

Desktop preserves the full sidebar and contextual layout. Tablet condenses rails and caps line length. Mobile uses drawers and single-pane conversation navigation, maintains the composer above browser UI, gives message actions a tap alternative, converts dense tables to cards or horizontal regions, and prevents menus/dialogs from clipping.

Search is debounced. Large message, file, notification, and user lists paginate or lazily load where APIs permit, avoid redundant requests, and use light-weight skeletons. Realtime subscriptions are scoped to the active user/conversation/channel and disposed predictably.

## Verification and acceptance matrix

Each required feature will be tracked against backend, API, UI, visible controls, control logic, loading, error, empty, realtime, mobile, accessibility, and automated/manual verification. A feature remains incomplete if a relevant column is missing.

Acceptance verification includes:

1. Full backup readability before changes (complete).
2. Static and running UI audit of every route and control, including an explicit no-dead-button review.
3. Widget/unit/API tests for each new behavior, written first, plus Flutter analysis/build and Python tests.
4. End-to-end flows: profile-to-DM, full friend lifecycle, send/reply/edit/delete/react/pin, mention notification, upload/attach/preview/download, search navigation, notification navigation.
5. Two-session realtime checks for message lifecycle, reactions, typing, mentions, and friendship changes.
6. Desktop/tablet/mobile checks, light/dark theme checks, keyboard checks, security authorization checks, and final console/build/layout audit.

## Delivery order

1. Establish shared design primitives, responsive scaffold, theme tokens, and test foundations.
2. Complete the messaging/channel experience and its necessary protected backend contracts.
3. Add people/profile/friends/presence and notifications/unread flows.
4. Bring organization, files, search, and administration screens to the shared standard.
5. Run the completion matrix, end-to-end/realtime/security/performance tests, and fix all discovered issues before reporting completion.

## Explicit non-goals

- Discord servers, server discovery, boosts, ownership, server hierarchy, bots, or server role/permission interfaces.
- Threads, mass or role mentions, advanced permission matrices, custom role builders, or Discord audit-log UI.
- Fake frontend-only data mutations or actions that do not call a real protected capability.

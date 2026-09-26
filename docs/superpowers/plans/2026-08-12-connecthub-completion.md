# ConnectHub Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a complete, Discord-inspired ConnectHub collaboration experience with real protected interactions, responsive shared UI, and verified end-to-end flows.

**Architecture:** Preserve the existing Flutter/FastAPI domain structure. Shared Flutter primitives own accessibility, dialogs, menus, state, profile identity, and responsive layout. Messaging and notifications gain only the persistent backend contracts required by visible ConnectHub controls; a small Friends module replaces frontend-only relationship state.

**Tech Stack:** Flutter Web, Material 3, Riverpod, GoRouter, Dio, WebSockets, FastAPI, SQLAlchemy async, Alembic, Pydantic, pytest, flutter_test.

## Global Constraints

- `NEWREQ.md` and `docs/superpowers/specs/2026-08-12-connecthub-discord-inspired-completion-design.md` are the requirements source of truth.
- Keep Dashboard, Messages, Departments, Teams, Groups, Channels, Files, Search, and the four Admin routes. Do not introduce Discord servers, bots, threads, mass/role mentions, custom roles, or advanced permission interfaces.
- Use only the fixed roles: Super Admin, Admin, Manager, Standard User, and Guest User; backend authorization is authoritative.
- Every changed interaction has loading, error, and empty behavior. No frontend-only mutation may represent persisted state.
- New behavior starts with a failing test. Run the named test before and after every implementation step.
- Dialogs support Escape, focus containment/restoration, scroll locking, mobile fit, Cancel, and a right-aligned primary action. Menus close on outside click/Escape, remain inside the viewport, support keyboard use, and icon-only controls have accessible labels/tooltips.

---

### Task 1: Persist message interactions and correct conversation read typing

**Files:**
- Modify: `src/connecthub/modules/messaging/models.py`
- Modify: `src/connecthub/modules/messaging/schemas.py`
- Modify: `src/connecthub/modules/messaging/repository.py`
- Modify: `src/connecthub/modules/messaging/service.py`
- Modify: `src/connecthub/modules/messaging/router.py`
- Modify: `src/connecthub/modules/messaging/websocket_handler.py`
- Create: `migrations/versions/2026_08_12_0009_message_interactions.py`
- Modify: `tests/modules/messaging/conftest.py`
- Modify: `tests/modules/messaging/test_messaging_service.py`

**Interfaces:**
- Consumes: `MessageCreate(content, message_type, parent_id)`, `MessagingService`, and existing participant authorization.
- Produces: `MessageResponse(edited_at, metadata, reactions, is_pinned)`, `ReactionResponse`, and `MessagingService.toggle_reaction(user_id, conversation_id, message_id, emoji)`, `set_pinned(user_id, conversation_id, message_id, is_pinned)`, and `mark_unread(user_id, conversation_id, message_id)`.

- [ ] **Step 1: Write failing tests for reaction and pin authorization**

```python
@pytest.mark.asyncio
async def test_participant_can_toggle_reaction_and_message_exposes_count(
    messaging_service, user_alice, user_bob,
):
    conversation = await messaging_service.start_direct_message(user_alice.id, user_bob.id)
    message = await messaging_service.send_message(
        user_alice.id, conversation.id, MessageCreate(content="Ship it"),
    )
    added = await messaging_service.toggle_reaction(user_bob.id, conversation.id, message.id, "🚀")
    result = await messaging_service.get_messages(user_alice.id, conversation.id)
    assert added.active is True
    assert result.items[0].reactions == [{"emoji": "🚀", "count": 1, "reacted": False}]

@pytest.mark.asyncio
async def test_non_participant_cannot_pin_or_react_to_message(
    messaging_service, user_alice, user_bob, user_charlie,
):
    conversation = await messaging_service.start_direct_message(user_alice.id, user_bob.id)
    message = await messaging_service.send_message(user_alice.id, conversation.id, MessageCreate(content="Private"))
    with pytest.raises(NotFoundError):
        await messaging_service.toggle_reaction(user_charlie.id, conversation.id, message.id, "👍")
    with pytest.raises(NotFoundError):
        await messaging_service.set_pinned(user_charlie.id, conversation.id, message.id, True)
```

- [ ] **Step 2: Run the tests to prove the contract is absent**

Run: `.venv\Scripts\python.exe -m pytest tests/modules/messaging/test_messaging_service.py -q`

Expected: FAIL because `toggle_reaction` and `set_pinned` do not exist.

- [ ] **Step 3: Add minimal persistent domain data**

```python
class MessageReaction(Base, IDMixin, TimestampMixin):
    __tablename__ = "message_reactions"
    __table_args__ = (UniqueConstraint("message_id", "user_id", "emoji", name="uq_message_reaction"),)
    message_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("messages.id"), index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True)
    emoji: Mapped[str] = mapped_column(String(64), nullable=False)

class MessagePin(Base, IDMixin, TimestampMixin):
    __tablename__ = "message_pins"
    __table_args__ = (UniqueConstraint("message_id", name="uq_message_pin"),)
    message_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("messages.id"), index=True)
    pinned_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
```

Add `edited_at` to `Message`; correct `ConversationParticipant.last_read_at` from `Mapped[uuid.UUID | None]` to `Mapped[datetime | None]`; migration `0009` creates the two tables and columns. Repository methods resolve conversation membership before every mutation.

- [ ] **Step 4: Expose the service through REST and realtime**

```python
@router.put("/{conversation_id}/messages/{message_id}/reactions/{emoji}", response_model=ReactionResponse)
async def toggle_reaction(conversation_id: uuid.UUID, message_id: uuid.UUID, emoji: str, request: Request, db: AsyncSession = Depends(get_db_session)) -> ReactionResponse:
    return await MessagingService(db).toggle_reaction(_uid(request), conversation_id, message_id, emoji)

@router.put("/{conversation_id}/messages/{message_id}/pin", response_model=MessageResponse)
async def pin_message(conversation_id: uuid.UUID, message_id: uuid.UUID, data: PinRequest, request: Request, db: AsyncSession = Depends(get_db_session)) -> MessageResponse:
    return await MessagingService(db).set_pinned(_uid(request), conversation_id, message_id, data.is_pinned)
```

After each committed mutation, broadcast `message_updated`, `message_deleted`, `reaction_changed`, or `read_state_changed` only to conversation participants. Realtime handlers call the same service methods and cannot bypass REST authorization.

- [ ] **Step 5: Verify and commit**

Run: `.venv\Scripts\python.exe -m pytest tests/modules/messaging/test_messaging_service.py -q`

Expected: PASS, including current privacy and pagination tests.

```powershell
git add src/connecthub/modules/messaging migrations/versions/2026_08_12_0009_message_interactions.py tests/modules/messaging
git commit -m "feat: persist message interactions"
```

### Task 2: Replace demo friend state with protected persistent relationships

**Files:**
- Create: `src/connecthub/modules/friends/{__init__,models,schemas,repository,service,router}.py`
- Modify: `src/connecthub/main.py`
- Create: `migrations/versions/2026_08_12_0010_friendships.py`
- Create: `tests/modules/friends/{__init__,conftest,test_friend_service}.py`

**Interfaces:**
- Consumes: authenticated `request.state.user_id`, the organization directory, and `NotificationService`.
- Produces: `GET /friends`, `GET /friends/pending`, `GET /friends/blocked`, `POST /friends/requests/{user_id}`, `PUT /friends/requests/{request_id}/accept`, `DELETE /friends/requests/{request_id}`, `PUT /friends/blocked/{user_id}`, and `DELETE /friends/blocked/{user_id}`.

- [ ] **Step 1: Write failing lifecycle tests**

```python
@pytest.mark.asyncio
async def test_friend_request_accept_then_remove(friend_service, user_alice, user_bob):
    request = await friend_service.request(user_alice.id, user_bob.id)
    friendship = await friend_service.accept(user_bob.id, request.id)
    assert {friendship.user_low_id, friendship.user_high_id} == {user_alice.id, user_bob.id}
    await friend_service.remove(user_alice.id, user_bob.id)
    assert (await friend_service.list_friends(user_alice.id)).items == []

@pytest.mark.asyncio
async def test_blocking_revokes_relationship_and_prevents_new_request(friend_service, user_alice, user_bob):
    await friend_service.block(user_alice.id, user_bob.id)
    with pytest.raises(ConflictError):
        await friend_service.request(user_bob.id, user_alice.id)
```

- [ ] **Step 2: Run the test to prove the module is absent**

Run: `.venv\Scripts\python.exe -m pytest tests/modules/friends/test_friend_service.py -q`

Expected: FAIL because the friends module does not exist.

- [ ] **Step 3: Implement the normalized relationship state machine**

```python
class FriendshipRequest(Base, IDMixin, TimestampMixin):
    __tablename__ = "friendship_requests"
    requester_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    recipient_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")

class Friendship(Base, IDMixin, TimestampMixin):
    __tablename__ = "friendships"
    user_low_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    user_high_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
```

Reject self-targeting, cross-organization targets, duplicates, and any target blocked in either direction. Accept creates one ordered friendship; reject/cancel updates the request; block removes related friendship/request state and is private to the blocking user.

- [ ] **Step 4: Add protected routes and notifications**

```python
await notifications.create_notification(
    user_id=recipient_id,
    notification_type=NotificationType.SYSTEM,
    title="Friend request",
    body=f"{actor_name} sent you a friend request",
    resource_type="friend_request",
    resource_id=str(request.id),
)
```

Add `friend_request` and `friend_accepted` notification resource types. Never return relationship records belonging to a different authenticated user.

- [ ] **Step 5: Verify and commit**

Run: `.venv\Scripts\python.exe -m pytest tests/modules/friends tests/modules/notifications -q`

Expected: PASS.

```powershell
git add src/connecthub/modules/friends src/connecthub/main.py migrations/versions/2026_08_12_0010_friendships.py tests/modules/friends
git commit -m "feat: add persistent friend relationships"
```

### Task 3: Build reusable Flutter interaction primitives and tokens

**Files:**
- Create: `clients/web/lib/shared/widgets/{app_dialog,app_menu,app_button,async_state_view,user_identity,profile_popover}.dart`
- Modify: `clients/web/lib/core/theme/app_theme.dart`
- Modify: `clients/web/lib/core/api/api_endpoints.dart`
- Create: `clients/web/test/shared/widgets/{app_dialog_test,app_menu_test,async_state_view_test}.dart`

**Interfaces:**
- Produces: `showAppDialog`, `showConfirmationDialog`, `AppMenuAnchor`, `AppButton`, `AsyncStateView`, `UserIdentity`, and `ProfilePopover.show`.

- [ ] **Step 1: Write failing dialog and state tests**

```dart
testWidgets('confirmation dialog closes on Escape without invoking destructive action', (tester) async {
  var deleted = false;
  await tester.pumpWidget(TestApp(child: Builder(builder: (context) => FilledButton(
    onPressed: () => showConfirmationDialog(context: context, title: 'Delete file', confirmLabel: 'Delete', onConfirm: () async => deleted = true),
    child: const Text('Open'),
  ))));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(find.text('Delete file'), findsNothing);
  expect(deleted, isFalse);
});

testWidgets('error state exposes retry', (tester) async {
  var retries = 0;
  await tester.pumpWidget(TestApp(child: AsyncStateView.error(message: 'Could not load files', onRetry: () => retries++)));
  await tester.tap(find.text('Retry'));
  expect(retries, 1);
});
```

- [ ] **Step 2: Run tests to show the primitives are absent**

Run: `D:\flutter\bin\flutter.bat test test/shared/widgets/app_dialog_test.dart test/shared/widgets/async_state_view_test.dart`

Expected: FAIL because shared primitives do not exist.

- [ ] **Step 3: Implement accessible primitive contracts**

```dart
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String title,
  String? description,
  required Widget body,
  required List<Widget> actions,
}) => showDialog<T>(
  context: context,
  barrierDismissible: false,
  builder: (_) => FocusTraversalGroup(
    child: AppDialog(title: title, description: description, body: body, actions: actions),
  ),
);
```

Use `Shortcuts`/ `Actions` to close on Escape, `SingleChildScrollView` for a mobile-safe body, semantic modal labels, an explicit close button, and Cancel plus primary action. Define light/dark semantic surface, danger, focus, tooltip, outlined-button, icon-button, input, snackbar, and reduced-motion theme values. `AppMenuAnchor` wraps Material `MenuAnchor` with explicit semantic labels and menu items.

- [ ] **Step 4: Add API constants and profile-to-DM behavior**

```dart
static const friends = '/friends';
static const friendPending = '/friends/pending';
static const friendBlocked = '/friends/blocked';
static String friendRequest(String userId) => '/friends/requests/$userId';
static String messageReaction(String conversationId, String messageId, String emoji) =>
    '/messaging/conversations/$conversationId/messages/$messageId/reactions/$emoji';
```

`ProfilePopover` exposes Message, Add Friend, Mention, Copy Username, Block/Unblock, and Remove Friend only when the provided relationship state allows it. Message posts to `conversations/direct`, routes to `/messages/:conversationId`, and signals the composer to focus.

- [ ] **Step 5: Verify and commit**

Run: `D:\flutter\bin\flutter.bat test test/shared/widgets`

Expected: PASS.

```powershell
git add clients/web/lib/core/theme clients/web/lib/core/api clients/web/lib/shared/widgets clients/web/test/shared/widgets
git commit -m "feat: add accessible ConnectHub UI primitives"
```

### Task 4: Make the app shell, header, dashboard, and route actions adaptive

**Files:**
- Modify: `clients/web/lib/shared/widgets/app_scaffold.dart`
- Modify: `clients/web/lib/shared/widgets/global_header.dart`
- Modify: `clients/web/lib/core/router/app_router.dart`
- Modify: `clients/web/lib/features/dashboard/dashboard_screen.dart`
- Create: `clients/web/test/shared/widgets/app_scaffold_test.dart`
- Create: `clients/web/test/features/dashboard/dashboard_screen_test.dart`

**Interfaces:**
- Consumes: shared primitives, unread endpoint, auth state.
- Produces: mobile drawer, sidebar badges, a header bell/popover, standard titles/actions, independent dashboard state cards.

- [ ] **Step 1: Write failing responsive shell tests**

```dart
testWidgets('small layout exposes the navigation drawer instead of a permanent sidebar', (tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  await tester.pumpWidget(TestApp(child: AppScaffold(child: const SizedBox())));
  expect(find.byTooltip('Open navigation'), findsOneWidget);
  expect(find.text('Dashboard'), findsNothing);
});

testWidgets('dashboard renders retry state when metrics request fails', (tester) async {
  await tester.pumpWidget(TestApp(child: DashboardScreen(metricsLoader: () async => throw Exception('offline'))));
  await tester.pumpAndSettle();
  expect(find.text('Could not load dashboard'), findsOneWidget);
  expect(find.text('Retry'), findsOneWidget);
});
```

- [ ] **Step 2: Run failing UI tests**

Run: `D:\flutter\bin\flutter.bat test test/shared/widgets/app_scaffold_test.dart test/features/dashboard/dashboard_screen_test.dart`

Expected: FAIL because compact navigation and injected dashboard loader are absent.

- [ ] **Step 3: Implement compact navigation, standard header, and data isolation**

```dart
final isCompact = MediaQuery.sizeOf(context).width < 900;
return Scaffold(
  drawer: isCompact ? AppNavigationDrawer(items: visibleItems) : null,
  body: Row(children: [if (!isCompact) AppSidebar(items: visibleItems), Expanded(child: child)]),
);
```

Use `Badge` for unread counts, preserve the required primary navigation and the Admin section, and retain Friends/Notifications as collaboration utilities. `GlobalHeader` accepts title, description, contextual search, primary action, notification trigger, and profile trigger. Dashboard uses `AsyncStateView` for each metric collection and quick actions that open real New Message, upload, and Search flows.

- [ ] **Step 4: Verify and commit**

Run: `D:\flutter\bin\flutter.bat test test/shared/widgets/app_scaffold_test.dart test/features/dashboard/dashboard_screen_test.dart`

Expected: PASS.

```powershell
git add clients/web/lib/shared/widgets/app_scaffold.dart clients/web/lib/shared/widgets/global_header.dart clients/web/lib/core/router/app_router.dart clients/web/lib/features/dashboard clients/web/test
git commit -m "feat: make ConnectHub navigation responsive"
```

### Task 5: Extract and complete reusable messaging/channel UI

**Files:**
- Create: `clients/web/lib/features/messaging/{message_models,message_composer,message_item,emoji_picker,image_viewer,pinned_messages_panel}.dart`
- Modify: `clients/web/lib/features/messaging/messages_screen.dart`
- Modify: `clients/web/lib/features/messaging/chat_screen.dart`
- Modify: `clients/web/lib/features/channels/channel_list_screen.dart`
- Modify: `clients/web/lib/core/api/websocket_client.dart`
- Create: `clients/web/test/features/messaging/{message_composer_test,message_item_test}.dart`

**Interfaces:**
- Consumes: Tasks 1 and 3 interfaces.
- Produces: `MessageItem`, `MessageComposer`, `EmojiPicker`, `ImageViewer`, `PinnedMessagesPanel`, and an update dispatcher for realtime message events.

- [ ] **Step 1: Write failing composer/action tests**

```dart
testWidgets('composer sends on Enter and inserts a newline on Shift Enter', (tester) async {
  final sent = <String>[];
  await tester.pumpWidget(TestApp(child: MessageComposer(onSend: (value, {parentId}) async => sent.add(value))));
  await tester.enterText(find.byType(TextField), 'hello');
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
  expect(sent, ['hello']);
  await tester.enterText(find.byType(TextField), 'line one');
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
  expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, contains('\n'));
});

testWidgets('own message more menu exposes edit delete pin and copy', (tester) async {
  await tester.pumpWidget(TestApp(child: MessageItem(message: testMessage(senderId: 'me'), currentUserId: 'me')));
  await tester.tap(find.byTooltip('More message actions'));
  await tester.pumpAndSettle();
  expect(find.text('Edit'), findsOneWidget);
  expect(find.text('Delete'), findsOneWidget);
  expect(find.text('Pin'), findsOneWidget);
});
```

- [ ] **Step 2: Run failing messaging tests**

Run: `D:\flutter\bin\flutter.bat test test/features/messaging/message_composer_test.dart test/features/messaging/message_item_test.dart`

Expected: FAIL because the extracted components do not exist.

- [ ] **Step 3: Implement message grouping, toolbars, replies, edit/delete, reactions, and pins**

```dart
class MessageItem extends StatelessWidget {
  const MessageItem({super.key, required this.message, required this.currentUserId, required this.onReply, required this.onEdit, required this.onDelete, required this.onReaction, required this.onPin});
  final ChatMessage message;
  final String currentUserId;
  final ValueChanged<ChatMessage> onReply;
  final ValueChanged<String> onEdit;
  final Future<void> Function() onDelete;
  final ValueChanged<String> onReaction;
  final ValueChanged<bool> onPin;
}
```

Group consecutive same-author messages with date/unread separators. Render timestamps, edited state, reply preview, attachment cards, and click-to-jump original messages. Hover/focus controls show reaction/reply/more without covering content; mobile uses a tap menu. Own-message actions include edit/delete/copy/link/pin/read; other-user actions include reply/copy/link/pin/report/read only when allowed. Delete uses confirmation and waits for server completion.

- [ ] **Step 4: Implement composer, mentions, emoji, attachments, viewer, and realtime**

```dart
class MessageComposer extends StatefulWidget {
  const MessageComposer({super.key, this.replyTo, this.editing, required this.onSend, required this.onUpload});
  final ChatMessage? replyTo;
  final ChatMessage? editing;
  final Future<void> Function(String content, {String? parentId}) onSend;
  final Future<Attachment> Function(PlatformFile file, void Function(double progress) progress) onUpload;
}
```

Detect trailing `@query`, filter `/auth/directory`, carry selected mention metadata with outgoing messages, and show highlighted click targets. Emoji has Recent, Smileys, People, Nature, Food, Activities, Travel, Objects, and Symbols tabs plus a search/grid/close control constrained in the viewport. File picker, drop, and paste upload through `/files/upload`; failed uploads retain Retry/Cancel state. Viewer supports Escape, zoom, download, fullscreen, and original link. Update active state on `message_updated`, `message_deleted`, `reaction_changed`, `typing`, and reconnect refetch; mark reads on visibility restoration and prevent double sends.

- [ ] **Step 5: Verify and commit**

Run: `D:\flutter\bin\flutter.bat test test/features/messaging`

Expected: PASS.

```powershell
git add clients/web/lib/features/messaging clients/web/lib/features/channels/channel_list_screen.dart clients/web/lib/core/api/websocket_client.dart clients/web/test/features/messaging
git commit -m "feat: complete ConnectHub message interactions"
```

### Task 6: Connect profiles, friends, notifications, unread badges, and presence

**Files:**
- Modify: `clients/web/lib/features/friends/friends_screen.dart`
- Modify: `clients/web/lib/features/notifications/notification_screen.dart`
- Modify: `clients/web/lib/shared/widgets/profile_popover.dart`
- Modify: `clients/web/lib/shared/widgets/app_scaffold.dart`
- Create: `clients/web/lib/features/people/presence.dart`
- Create: `clients/web/test/features/friends/friends_screen_test.dart`
- Create: `clients/web/test/features/notifications/notification_screen_test.dart`

**Interfaces:**
- Consumes: Tasks 2 and 3 endpoints/components.
- Produces: persistent Friends/Pending/Blocked states, notification routing/read state, sidebar/header/conversation unread markers, and avatar presence.

- [ ] **Step 1: Write failing friend and notification tests**

```dart
testWidgets('accepting incoming request calls API and moves user to Friends', (tester) async {
  final api = FakeFriendsApi(incoming: [directoryUser(id: 'sam')]);
  await tester.pumpWidget(TestApp(overrides: [friendsApiProvider.overrideWithValue(api)], child: const FriendsScreen()));
  await tester.tap(find.text('Accept'));
  await tester.pumpAndSettle();
  expect(api.acceptedIds, ['sam-request']);
  expect(find.text('Sam'), findsOneWidget);
});

testWidgets('notification marks itself read then routes to the conversation', (tester) async {
  final api = FakeNotificationsApi(items: [notification(conversationId: 'c-1')]);
  await tester.pumpWidget(TestApp(overrides: [notificationsApiProvider.overrideWithValue(api)], child: const NotificationScreen()));
  await tester.tap(find.text('New message'));
  expect(api.markedReadIds, ['n-1']);
  expect(router.location, '/messages/c-1');
});
```

- [ ] **Step 2: Run failing tests**

Run: `D:\flutter\bin\flutter.bat test test/features/friends/friends_screen_test.dart test/features/notifications/notification_screen_test.dart`

Expected: FAIL because the current Friends page derives data from demo sets.

- [ ] **Step 3: Replace every demo set with repository-backed state**

```dart
abstract class FriendsApi {
  Future<List<FriendRecord>> listFriends();
  Future<List<FriendRequestRecord>> listPending();
  Future<List<DirectoryUser>> listBlocked();
  Future<void> request(String userId);
  Future<void> accept(String requestId);
  Future<void> rejectOrCancel(String requestId);
  Future<void> remove(String userId);
  Future<void> block(String userId);
  Future<void> unblock(String userId);
}
```

Maintain Friends/Pending/Blocked tabs, precise empty copy, pending button state, retryable errors, and confirmation for Remove/Block. Notification clicks mark read then route to conversation/friends/resource. Add unread dots/badges on rails and header. `PresenceIndicator` accepts online, idle, dnd, or offline and supplies semantic text. Do not add an unbacked custom-status editor.

- [ ] **Step 4: Verify and commit**

Run: `D:\flutter\bin\flutter.bat test test/features/friends test/features/notifications`

Expected: PASS.

```powershell
git add clients/web/lib/features/friends clients/web/lib/features/notifications clients/web/lib/features/people clients/web/lib/shared/widgets clients/web/test/features
git commit -m "feat: connect friends and notifications to persistent data"
```

### Task 7: Polish organization, Files, Search, and Admin routes with real actions

**Files:**
- Modify: `clients/web/lib/features/{departments/dept_list_screen,teams/team_list_screen,groups/group_list_screen,channels/channel_list_screen,files/file_list_screen,search/search_screen}.dart`
- Modify: `clients/web/lib/features/admin/{user_management_screen,audit_log_screen,stats_dashboard_screen,backup_screen}.dart`
- Modify: `clients/web/lib/shared/widgets/entity_list_screen.dart`
- Create: `clients/web/test/features/files/file_list_screen_test.dart`
- Create: `clients/web/test/features/search/search_screen_test.dart`

**Interfaces:**
- Consumes: `GlobalHeader`, shared widgets, existing domain endpoints, and Task 5 channel conversation.
- Produces: consistent lists/detail panels, working Files grid/list/search controls, search result navigation, and role-aware Admin actions.

- [ ] **Step 1: Write failing Files and Search tests**

```dart
testWidgets('files toggles grid/list without losing filtered result', (tester) async {
  final api = FakeFilesApi(files: [fileRecord(name: 'plan.pdf')]);
  await tester.pumpWidget(TestApp(overrides: [filesApiProvider.overrideWithValue(api)], child: const FileListScreen()));
  await tester.enterText(find.byType(TextField), 'plan');
  await tester.tap(find.byTooltip('List view'));
  await tester.pumpAndSettle();
  expect(find.text('plan.pdf'), findsOneWidget);
  expect(find.byType(DataTable), findsOneWidget);
});

testWidgets('message search opens its conversation with a jump target', (tester) async {
  await tester.pumpWidget(TestApp(child: SearchScreen(searchApi: FakeSearchApi(messageResults: [messageResult(conversationId: 'c-2', messageId: 'm-7')]))));
  await tester.enterText(find.byType(TextField), 'decision');
  await tester.pumpAndSettle();
  await tester.tap(find.text('decision'));
  expect(router.location, '/messages/c-2?message=m-7');
});
```

- [ ] **Step 2: Run failing route tests**

Run: `D:\flutter\bin\flutter.bat test test/features/files/file_list_screen_test.dart test/features/search/search_screen_test.dart`

Expected: FAIL because the page contracts are not exposed.

- [ ] **Step 3: Apply the shared page/list/detail contract**

```dart
EntityListScreen(
  title: 'Departments',
  description: 'Coordinate the people and work in your organization.',
  primaryAction: AppButton.primary(label: 'Create Department', onPressed: canManage ? openCreate : null),
  empty: AsyncStateView.empty(title: 'No departments yet', actionLabel: canManage ? 'Create Department' : null),
)
```

Departments/Teams/Groups use searchable card/list views, expected description/manager/department/membership/privacy/activity data, member/related-object tabs, and authorized real create/edit/invite/delete actions. Identity in member lists opens the profile popover. Channels keep ConnectHub organization grouping and Task 5 messaging; no server model.

- [ ] **Step 4: Complete Files, Search, and Admin controls**

```dart
enum FileLayout { grid, list }
final visibleFiles = files.where((file) => file.name.toLowerCase().contains(query.toLowerCase())).toList();
```

Files implements Upload, search, sort/filter, grid/list, preview/icon, metadata, download, and a permission-sensitive action menu. Omit Rename/Copy Link if the API audit in Task 8 finds no protected backend contract. Search uses category chips and category-specific empty states. Admin labels are Users, Logs, Stats, Backups; filters are real, stats remain responsive/theme-aware, and restore/delete require confirmation.

- [ ] **Step 5: Verify and commit**

Run: `D:\flutter\bin\flutter.bat analyze && D:\flutter\bin\flutter.bat test test/features/files test/features/search`

Expected: no analyzer errors and all focused tests PASS.

```powershell
git add clients/web/lib/features clients/web/lib/shared/widgets/entity_list_screen.dart clients/web/test/features
git commit -m "feat: polish ConnectHub product routes"
```

### Task 8: Fill only visible API gaps and execute the completion audit

**Files:**
- Modify: `src/connecthub/modules/files/{schemas,service,router}.py`
- Modify: `src/connecthub/modules/search/{schemas,service,router}.py`
- Modify: `tests/modules/files/test_file_service.py`
- Modify: `tests/modules/search/test_search_service.py`
- Create: `docs/completion-matrix-2026-08-12.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: all visible controls from Tasks 1-7.
- Produces: only needed protected endpoints, a pass/fail feature matrix with evidence, and reproducible local UI verification instructions.

- [ ] **Step 1: Write failing API tests for visible missing controls**

```python
@pytest.mark.asyncio
async def test_owner_can_rename_file_and_other_user_cannot(file_service, uploaded_file, user_alice, user_bob):
    renamed = await file_service.rename(user_alice.id, uploaded_file.id, "decision.pdf")
    assert renamed.name == "decision.pdf"
    with pytest.raises(NotFoundError):
        await file_service.rename(user_bob.id, uploaded_file.id, "private.pdf")

@pytest.mark.asyncio
async def test_search_message_result_contains_conversation_and_message_target(search_service, user_alice, message):
    result = await search_service.search(user_alice.id, "decision")
    match = next(item for item in result.items if item.resource_type == "message")
    assert match.resource_id == str(message.id)
    assert match.conversation_id == str(message.conversation_id)
```

- [ ] **Step 2: Run focused API tests**

Run: `.venv\Scripts\python.exe -m pytest tests/modules/files/test_file_service.py tests/modules/search/test_search_service.py -q`

Expected: FAIL only for missing asserted contracts.

- [ ] **Step 3: Implement exactly those backend contracts**

```python
@router.put("/{file_id}/name", response_model=FileResponse)
async def rename_file(file_id: uuid.UUID, data: FileRenameRequest, request: Request, db: AsyncSession = Depends(get_db_session)) -> FileResponse:
    return await FileService(db).rename(_uid(request), file_id, data.name)
```

Search message results include `conversation_id`, `message_id`, timestamp, author/source, and a safe snippet. File routes verify owner/authorized manager access before rename/delete/download and avoid exposing private metadata in error messages.

- [ ] **Step 4: Run all tests, build, and screen audit**

Run: `.venv\Scripts\python.exe -m pytest -q`

Run: `D:\flutter\bin\flutter.bat analyze && D:\flutter\bin\flutter.bat test && D:\flutter\bin\flutter.bat build web`

Expected: all suites pass and a web build completes.

Start the API, serve `clients/web/build/web`, and inspect every requested route at desktop, tablet, and mobile. Exercise profile-to-DM, friend lifecycle, send/reply/edit/delete/react/pin, mention notification, file upload/attach/preview/download, search jump, notification navigation, backup confirmation, admin authorization, light/dark themes, and keyboard-only dialogs/menus. Record each result in the matrix as `PASS`, `NOT APPLICABLE` with a reason, or `FAIL` with a required code change; no `FAIL` remains before completion.

- [ ] **Step 5: Update verification instructions and commit**

```markdown
## Local UI verification

1. Set `DATABASE_URL_OVERRIDE=sqlite+aiosqlite:///d:/conhub/connecthub.db`.
2. Run `.venv\\Scripts\\python.exe -m uvicorn connecthub.main:app --host 127.0.0.1 --port 8000`.
3. Run `D:\\flutter\\bin\\flutter.bat build web` in `clients/web`.
4. Serve `clients/web/build/web` at port 8080 and open `http://127.0.0.1:8080`.
```

Run: `git diff --check && git status --short`

Expected: no whitespace errors; only intended files are staged.

```powershell
git add src/connecthub clients/web migrations tests docs README.md
git commit -m "feat: complete ConnectHub collaboration experience"
```

## Plan self-review

- Every `NEWREQ.md` area maps to a task: persistent/realtime message behavior (Task 1), basic friends (Task 2), UI consistency/accessibility (Tasks 3-4), messages and channels (Task 5), profiles/notifications/unread/presence (Task 6), organization/files/search/admin routes (Task 7), and explicit API, security, responsiveness, performance, and completion verification (Task 8).
- Backend contracts are introduced before the Flutter controls that use them. Shared widgets are introduced before route-level reuse. The interface blocks and test snippets use the same service and endpoint names across tasks.
- The plan contains concrete implementation and test steps for each task. The completion matrix prohibits reporting a phase complete until its relevant UI, button logic, state, realtime, responsive, authorization, and verification columns have evidence.

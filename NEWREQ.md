# CONNECTHUB — FRONTEND COMPLETION, UI/UX POLISH & INTERACTION AUDIT

## IMPORTANT

The current ConnectHub blueprint defines the architecture and feature phases, but the website is still visually and functionally incomplete even though the implementation agent may report that the phases are completed.

This document is a mandatory frontend-completion phase.

A feature is NOT complete merely because its backend, API, database, or basic screen exists.

A feature is complete only when:
- its frontend UI exists
- all expected buttons are present
- buttons are placed correctly
- every interaction works
- loading states exist
- error states exist
- empty states exist
- responsive behavior works
- accessibility works
- the feature looks polished and consistent
- the complete user flow works end-to-end

DO NOT declare the project complete until this entire document has been audited and implemented.

==================================================
0. ABSOLUTE FIRST STEP — FULL BACKUP 🟨 [IN PROGRESS]
==================================================

BEFORE MODIFYING ANYTHING:

1. Identify the complete project root folder.
2. Create a complete A-to-Z backup of the ENTIRE project.
3. Include:
   - frontend
   - backend
   - database
   - migrations
   - configuration
   - assets
   - components
   - routes
   - APIs
   - authentication
   - storage
   - tests
   - package files
   - environment templates
   - documentation
   - hidden project configuration files where appropriate
4. Preserve the exact directory structure.
5. Verify the backup is complete and readable.
6. NEVER modify the backup.
7. The backup must be sufficient to restore the application to its exact pre-implementation state.

Only after the backup has been successfully verified may implementation begin.

==================================================
1. ANALYZE THE EXISTING APPLICATION 🟨 [IN PROGRESS]
==================================================

Before changing the frontend:

Inspect the entire existing project and actual running UI.

Analyze:
- all routes
- all pages
- all components
- all layouts
- all navigation
- all buttons
- all icon buttons
- all dropdowns
- all context menus
- all modals
- all forms
- all APIs
- all database models
- all realtime functionality
- all existing authentication
- all existing roles
- all existing Departments
- all existing Teams
- all existing Groups
- all existing Channels
- all existing Files
- all existing Messages
- all existing Search
- all existing admin pages

Do not assume that something is complete because a backend endpoint exists.

Open and inspect the actual UI.

Create an internal audit of:
- missing screens
- missing buttons
- misplaced buttons
- dead buttons
- incomplete components
- inconsistent components
- missing loading states
- missing error states
- missing empty states
- broken responsive layouts
- missing mobile interactions
- broken navigation
- missing confirmation dialogs

Then implement the missing pieces.

==================================================
2. CONNECTHUB STRUCTURE — DO NOT TURN THIS INTO DISCORD 🟩 [COMPLETED]
==================================================

ConnectHub uses its own organization structure.

Primary navigation:

- Dashboard
- Messages
- Departments
- Teams
- Groups
- Channels
- Files
- Search

Administrative navigation:

ADMIN

- Users
- Logs
- Stats
- Backups

Keep this structure.

DO NOT replace it with Discord servers.

DO NOT introduce:
- Servers
- Server discovery
- Server ownership
- Server boosts
- Server hierarchy
- Discord server roles
- Discord server permissions
- Threads
- @everyone
- @here
- @staff
- role mentions
- advanced Discord permission matrices
- bots

==================================================
3. GLOBAL APPLICATION LAYOUT 🟩 [COMPLETED]
==================================================

Create a consistent application layout.

LEFT SIDEBAR:

- ConnectHub logo/brand
- primary navigation
- active page highlight
- unread badges
- notification indicators
- user profile area at bottom

Sidebar must have:
- correct icon alignment
- consistent spacing
- hover state
- active state
- focus state
- responsive collapse/drawer behavior

MAIN CONTENT:

Every page should have:
- page title
- optional description
- breadcrumb where useful
- primary action in a predictable location
- content area with consistent spacing

RIGHT-SIDE CONTEXT PANEL:

Use only where useful for:
- channel information
- user details
- pinned messages
- search filters

Do not permanently display unnecessary panels.

==================================================
4. GLOBAL HEADER STANDARD 🟩 [COMPLETED]
==================================================

Every major page must have a consistent header.

LEFT:
- title
- optional breadcrumb
- optional description

RIGHT:
- page-specific primary action
- search where relevant
- notification button where relevant
- user/profile menu where relevant

Examples:

Messages:
[New Message]

Departments:
[Create Department]

Teams:
[Create Team]

Groups:
[Create Group]

Channels:
[Create Channel]

Files:
[Upload File]

Users:
[Add User]

Backups:
[Create Backup]

Primary actions must be visually obvious.

==================================================
5. DASHBOARD 🟩 [COMPLETED]
==================================================

Dashboard must not be an empty placeholder.

Include polished summary cards for:
- unread messages
- unread notifications
- departments
- teams
- groups
- channels
- files

Include:
- recent conversations
- recent activity
- quick actions

Quick actions:
- New Message
- Upload File
- Search

Only show actions available to the current user.

==================================================
6. MESSAGES PAGE 🟩 [COMPLETED]
==================================================

Messages must be a complete messaging interface.

LEFT CONVERSATION SIDEBAR:

- Search conversations
- New Message button
- conversation list
- unread badges
- active conversation
- typing indicators
- user avatar/status

MAIN CONVERSATION:

HEADER:
- avatar
- display name
- username if appropriate
- online/status indicator
- conversation search
- more menu

MESSAGE AREA:
- date separators
- message grouping
- avatars
- timestamps
- edited indicator
- replies
- reactions
- attachments
- unread divider
- scroll behavior

BOTTOM COMPOSER:
- attachment button
- text field
- emoji button
- send button
- reply state
- edit state

==================================================
7. MESSAGE HOVER TOOLBAR 🟩 [COMPLETED]
==================================================

Every message must have a compact action toolbar.

Do not hide all functionality in an inaccessible menu.

Primary hover actions:
- Add Reaction
- Reply
- More

More menu for OWN messages:
- Edit
- Delete
- Copy Text
- Copy Link
- Pin/Unpin
- Mark Unread

More menu for OTHER messages:
- Reply
- Copy Text
- Copy Link
- Pin where allowed
- Report where supported
- Mark Unread

Toolbar must:
- appear in the correct position
- never cover important message text
- work on desktop
- have an alternative interaction on mobile

==================================================
8. MESSAGE EDITING 🟩 [COMPLETED]
==================================================

Editing must be inline.

Show:
- textarea/input
- Save
- Cancel

Keyboard:
- Enter = save
- Shift+Enter = newline
- Escape = cancel

After saving:
- update backend
- update UI
- update realtime clients
- show "(edited)"

Do not create duplicate messages.

==================================================
9. MESSAGE DELETION 🟩 [COMPLETED]
==================================================

Users can delete their own messages.

Authorized users can delete/moderate messages according to existing ConnectHub role/access rules.

Deletion must:
- be server-side
- update database
- update current UI
- update other realtime clients

Use confirmation where appropriate.

Never fake deletion only in the frontend.

==================================================
10. REPLIES — NOT THREADS 🟩 [COMPLETED]
==================================================

Implement normal message replies.

Reply mode must show:
- original author
- original message preview
- cancel X

Sent reply must show:
- original message preview
- author
- clickable jump-to-original behavior

DO NOT implement threads.

==================================================
11. @ MENTIONS 🟩 [COMPLETED]
==================================================

Only implement individual user mentions.

Typing:

@Arth

must open user autocomplete.

Support:
- search users
- select user
- structured mention
- highlighted rendering
- clickable mention
- notification to mentioned user

DO NOT implement:
- @everyone
- @here
- @staff
- @department
- @team
- @group
- @role
- mass mentions

==================================================
12. EMOJI AND REACTIONS 🟨 [IN PROGRESS]
==================================================

Implement:
- emoji picker
- emoji search
- emoji categories
- recently used
- add reaction
- remove reaction
- reaction count
- users who reacted

Reactions must update in realtime.

==================================================
13. EMOJI PICKER UI 🟨 [IN PROGRESS]
==================================================

Emoji picker must contain:
- search
- category navigation
- recently used
- scrollable grid
- close button
- keyboard support

Never render it outside the viewport.

==================================================
14. MESSAGE COMPOSER 🟨 [IN PROGRESS]
==================================================

Composer must support:
- text
- multiline
- Enter = send
- Shift+Enter = newline
- emoji
- file attachment
- drag/drop
- pasted images/files
- @ mention autocomplete
- reply mode
- edit mode
- upload progress
- cancel upload
- retry failed upload

Reply mode should clearly display:
Replying to: [user/message] [X]

Edit mode should clearly display:
Editing message [Cancel]

==================================================
15. FILE ATTACHMENTS 🟨 [IN PROGRESS]
==================================================

Integrate with the existing ConnectHub Files system.

Support where existing infrastructure permits:
- images
- PDFs
- documents
- videos
- audio
- common files

Attachment UI:
- preview
- filename
- file size
- upload progress
- cancel
- retry
- download
- open
- error state

Do not create unnecessary duplicate storage infrastructure.

==================================================
16. IMAGE VIEWER 🟨 [IN PROGRESS]
==================================================

Image attachments should open in a polished viewer.

Support:
- fullscreen
- zoom
- close
- download
- open original

Desktop and mobile must both work.

==================================================
17. USER PROFILE POPOVER 🟨 [IN PROGRESS]
==================================================

Clicking a user avatar/name opens a polished profile card.

Show:
- avatar
- display name
- username
- role
- presence
- custom status
- about
- relevant Department/Team/Group information

Primary buttons:
- Message
- Add Friend

More menu:
- Mention
- Copy Username
- Block/Unblock
- Remove Friend when applicable

Do not overload the profile card.

==================================================
18. PROFILE → DIRECT MESSAGE FLOW 🟨 [IN PROGRESS]
==================================================

This exact flow must work everywhere:

User clicks profile
→ Profile popover opens
→ User clicks Message
→ Existing DM opens OR new DM is created
→ Conversation opens
→ Composer receives focus
→ User can immediately type and send

Test this from:
- Messages
- Departments
- Teams
- Groups
- Channels
- Search
- Users
- notifications
- member lists

==================================================
19. BASIC FRIEND SYSTEM 🟨 [IN PROGRESS]
==================================================

Keep the friend system simple.

Support only:
- Add Friend
- Accept Request
- Reject Request
- Cancel Request
- Remove Friend
- Block
- Unblock
- Friends List
- Pending Requests
- Blocked Users

Do NOT add:
- friend suggestions
- followers
- social feeds
- mutual-friend algorithms
- friend groups
- advanced social features

Friends page:

Tabs:
- Friends
- Pending

Incoming:
[Accept] [Reject]

Outgoing:
[Cancel]

Friend:
[Message] [Remove] [Block]

Blocked:
[Unblock]

==================================================
20. PRESENCE 🟨 [IN PROGRESS]
==================================================

Support:
- Online
- Idle/Away
- Do Not Disturb
- Offline

Show presence on:
- avatars
- profiles
- DM list
- member lists

==================================================
21. CUSTOM STATUS 🟨 [IN PROGRESS]
==================================================

If supported by current architecture:

Allow:
- status text
- emoji
- duration
- clear status

Keep UI simple.

==================================================
22. DEPARTMENTS 🟨 [IN PROGRESS]
==================================================

Departments page must include:

Header:
- Department title
- Create Department button for authorized users

Controls:
- Search
- Filter where useful

Department cards/list should show:
- name
- description
- manager
- member count
- last activity

Department details:
- Overview
- Members
- Teams
- Groups
- Channels

Only show authorized actions.

==================================================
23. TEAMS 🟨 [IN PROGRESS]
==================================================

Teams page should be consistent with Departments.

Include:
- Create Team
- Search
- team list
- member count
- department
- groups
- channels

Team details should have:
- Overview
- Members
- Groups
- Channels

==================================================
24. GROUPS 🟨 [IN PROGRESS]
==================================================

Groups page:

- Create Group
- Search
- group list
- member count
- privacy/access indicator
- related channels

Group details:
- Overview
- Members
- Channels
- Files where appropriate

Do not introduce server concepts.

==================================================
25. CHANNELS 🟨 [IN PROGRESS]
==================================================

Channels page must be a complete communication area.

Channel navigation:
- channels grouped according to existing ConnectHub organization
- unread indicators
- active channel state

Channel header:
- channel name
- description
- search
- pinned messages
- more menu

Main area:
- messages
- reactions
- replies
- attachments
- mentions
- unread divider

Composer:
- attachment
- emoji
- message
- send

DO NOT add threads.

==================================================
26. PINNED MESSAGES 🟨 [IN PROGRESS]
==================================================

Where supported:

Message actions:
- Pin
- Unpin

Pinned view:
- list pinned messages
- author
- timestamp
- preview
- Jump to Message

Keep it simple.

==================================================
27. FILES PAGE 🟨 [IN PROGRESS]
==================================================

Files page must contain:

Header:
[Upload File]

Controls:
- Search
- Sort
- Filter
- Grid/List toggle

Each file item:
- preview/icon
- filename
- size
- uploader
- date
- download
- more menu

More menu:
- Download
- Rename where allowed
- Delete where allowed
- Copy Link

==================================================
28. SEARCH PAGE 🟨 [IN PROGRESS]
==================================================

Search must be a complete page, not just an input.

Search categories:
- Messages
- People
- Channels
- Files
- Departments
- Teams
- Groups

Results:
- relevant icon/avatar
- title
- preview/snippet
- timestamp where relevant
- source
- clickable result

Clicking a message result should jump directly to the message.

Empty state:
No results found.

==================================================
29. NOTIFICATIONS 🟨 [IN PROGRESS]
==================================================

Implement a proper notification dropdown/page.

Notifications:
- new DM
- mention
- reply
- friend request
- friend accepted
- relevant organizational/channel activity

Notification item:
- avatar/icon
- title
- preview
- timestamp
- unread indicator

Actions:
- Mark Read
- Mark All Read

Clicking notification should open the related content.

==================================================
30. UNREAD SYSTEM 🟨 [IN PROGRESS]
==================================================

Implement:
- unread DMs
- unread channels
- mention indicators
- unread divider
- mark as read
- mark as unread
- jump to unread/latest

Persist read state.

==================================================
31. USERS ADMIN PAGE 🟨 [IN PROGRESS]
==================================================

Authorized administrators only.

Users page:

Header:
[Add User]

Controls:
- Search
- Role filter
- Status filter where supported

Table/list:
- avatar
- name
- email
- role
- status
- last active
- actions

Actions:
- View Profile
- Edit User
- Activate/Deactivate where supported

Do NOT create an advanced permission editor.

==================================================
32. BASIC ROLES 🟨 [IN PROGRESS]
==================================================

Use the existing five roles:

1. Super Admin
2. Admin
3. Manager
4. Standard User
5. Guest User

Do not create:
- custom role builder
- permission matrix
- Discord-style roles
- permission bitfields
- channel permission overrides
- role hierarchy UI

Existing authorization rules remain the source of truth.

==================================================
33. SIMPLE LOGS 🟨 [IN PROGRESS]
==================================================

Keep logging simple.

The UI should be called Logs, not a Discord-style Audit Log.

Display:
- timestamp
- user
- event
- target
- result

Controls:
- Search
- Date filter
- Event filter

Do not build an advanced Discord audit log.

==================================================
34. STATS 🟨 [IN PROGRESS]
==================================================

Stats page should contain polished metric cards for:
- total users
- active users
- messages
- channels
- files
- departments
- teams
- groups

Charts should:
- be responsive
- have readable labels
- work in dark and light mode

==================================================
35. BACKUPS 🟨 [IN PROGRESS]
==================================================

Backups page:

Header:
[Create Backup]

Backup list:
- date
- size
- status

Actions:
- Download where supported
- Restore where supported
- Delete where supported

Destructive actions require confirmation.

==================================================
36. MODAL DESIGN STANDARD 🟨 [IN PROGRESS]
==================================================

Every modal must have:

- title
- description when needed
- close X
- Cancel
- primary action

Bottom-right actions:

[Cancel] [Save/Create/Delete]

Destructive action must use danger styling.

Modal must:
- trap focus
- support Escape
- prevent background scrolling
- work on mobile

==================================================
37. DROPDOWN AND CONTEXT MENU STANDARD 🟨 [IN PROGRESS]
==================================================

Every dropdown/context menu must:

- align to trigger
- stay inside viewport
- close on outside click
- close on Escape
- support keyboard navigation
- have consistent padding
- have consistent icon alignment

No menu may render partially off-screen.

==================================================
38. BUTTON STANDARD 🟨 [IN PROGRESS]
==================================================

Use consistent button types.

PRIMARY:
Main action:
- Create
- Save
- Send
- Upload
- Add

SECONDARY:
Supporting action:
- Cancel
- Edit
- Search

GHOST/ICON:
Compact controls:
- Reply
- Reaction
- More
- Close
- Search

DANGER:
Destructive:
- Delete
- Remove
- Deactivate
- Restore confirmation where relevant

Do not randomly mix button styles.

==================================================
39. TOOLTIP STANDARD 🟨 [IN PROGRESS]
==================================================

Icon-only buttons that are not immediately obvious must have tooltips.

Examples:
- Add Reaction
- More
- Pin
- Search
- Close
- Notifications

Tooltips must not block interaction.

==================================================
40. LOADING STATES 🟨 [IN PROGRESS]
==================================================

Every major screen requires a loading state.

Use skeletons for:
- message lists
- user lists
- tables
- cards
- file lists

Buttons must show loading indicators during operations.

Prevent accidental duplicate submissions.

==================================================
41. EMPTY STATES 🟨 [IN PROGRESS]
==================================================

Every list must have a useful empty state.

Examples:

No messages yet.
Start a conversation.

No friends yet.
Add a friend to start messaging.

No pending requests.
You have no pending friend requests.

No files.
Upload your first file.

No search results.
Try another search term.

No channels.
No channels are currently available.

Never leave a blank area without explanation.

==================================================
42. ERROR STATES 🟨 [IN PROGRESS]
==================================================

Every failed action must:

- show a useful error
- preserve user input where possible
- offer Retry where appropriate
- avoid exposing sensitive backend information

No silent failures.

==================================================
43. RESPONSIVE DESIGN 🟨 [IN PROGRESS]
==================================================

Desktop:
- full sidebar
- comfortable content
- optional right context panel

Tablet:
- adaptive sidebar
- adaptive content width

Mobile:
- sidebar becomes drawer
- message list/conversation navigation becomes appropriate mobile navigation
- composer remains accessible
- modals fit viewport
- tables become cards or horizontal scroll
- menus remain usable

Do NOT merely shrink the desktop interface.

==================================================
44. DARK MODE + LIGHT MODE 🟨 [IN PROGRESS]
==================================================

Both themes must be independently designed.

Check:
- text contrast
- icon contrast
- borders
- cards
- buttons
- inputs
- menus
- tooltips
- modals
- message bubbles
- unread states
- hover states

No unreadable controls.

==================================================
45. ACCESSIBILITY 🟨 [IN PROGRESS]
==================================================

Verify:
- keyboard navigation
- visible focus
- ARIA labels
- accessible dialogs
- accessible dropdowns
- accessible tooltips
- proper semantic elements
- WCAG AA contrast

==================================================
46. GLOBAL UI CONSISTENCY PASS 🟨 [IN PROGRESS]
==================================================

Inspect every page and make them feel like one product.

Check:
- header alignment
- button positions
- icon sizes
- typography
- spacing
- card radius
- borders
- shadows
- colors
- dark mode
- light mode
- empty states
- loading states
- error states
- modal dimensions
- dropdown positioning

Do not allow different pages to look like they were built by different applications.

==================================================
47. COMPLETE BUTTON AUDIT 🟨 [IN PROGRESS]
==================================================

This is mandatory.

Inspect EVERY:
- button
- icon button
- sidebar item
- dropdown item
- context menu item
- tab
- profile action
- message action
- friend action
- file action
- admin action

For every interactive control verify:

1. It exists.
2. It is visible at the correct location.
3. It has correct label/icon.
4. It has correct hover state.
5. It has correct active state.
6. It has correct disabled state.
7. It has tooltip where needed.
8. It performs its intended action.
9. It calls the correct backend/API.
10. It updates the UI.
11. It handles loading.
12. It handles errors.
13. It works on mobile.
14. It respects authorization.
15. It does not create duplicate actions.

NO DEAD BUTTONS.

==================================================
48. SCREEN-BY-SCREEN AUDIT 🟨 [IN PROGRESS]
==================================================

Manually inspect:

1. Dashboard
2. Messages
3. DM conversation
4. Profile popover
5. Friends
6. Pending requests
7. Departments
8. Department details
9. Teams
10. Team details
11. Groups
12. Group details
13. Channels
14. Channel conversation
15. Files
16. Search
17. Notifications
18. Users
19. Logs
20. Stats
21. Backups
22. Settings/profile pages if present

For each screen ask:

- What should the user do here?
- Is the primary action obvious?
- Are all required controls present?
- Are actions placed where users expect them?
- Does every action work?
- What happens when there is no data?
- What happens while loading?
- What happens on error?
- What happens on mobile?

==================================================
49. FEATURE COMPLETION MATRIX 🟨 [IN PROGRESS]
==================================================

Create an internal completion matrix:

| Feature | Backend | API | UI | Buttons | Button Logic | Loading | Error | Empty | Realtime | Mobile | Tested |
|---------|---------|-----|----|---------|--------------|---------|-------|-------|----------|--------|--------|

A feature cannot be marked COMPLETE if any required column is incomplete.

==================================================
50. END-TO-END TESTING 🟨 [IN PROGRESS]
==================================================

Test:

PROFILE:
User → profile → Message → DM

FRIENDS:
Add → Accept → Friend List → Remove → Block → Unblock

MESSAGES:
Send → Reply → Edit → Delete → React → Pin

MENTIONS:
@ → select user → send → recipient receives notification

FILES:
Upload → attach → send → preview → download

SEARCH:
Search → result → open resource → correct location

NOTIFICATIONS:
Notification → click → correct destination

==================================================
51. MULTI-USER REALTIME TEST 🟨 [IN PROGRESS]
==================================================

Use multiple accounts/browser sessions.

Verify:

User A sends message
→ User B sees it immediately.

User A edits message
→ User B sees edit immediately.

User A deletes message
→ User B sees deletion immediately.

User A reacts
→ User B sees reaction immediately.

User A types
→ User B sees typing indicator.

User A mentions User B
→ User B receives notification.

User A sends friend request
→ User B sees request.

User B accepts
→ User A sees friendship update.

==================================================
52. SECURITY CHECK 🟨 [IN PROGRESS]
==================================================

Even though ConnectHub uses simple roles, backend authorization remains mandatory.

Verify:
- unauthorized users cannot access restricted pages
- unauthorized APIs reject requests
- private messages are protected
- private files are protected
- unauthorized users cannot edit/delete messages
- unauthorized users cannot manage users
- unauthorized users cannot perform admin actions

Hiding a button is NOT security.

==================================================
53. PERFORMANCE CHECK 🟨 [IN PROGRESS]
==================================================

Check:
- large message history
- many users
- many channels
- many files
- many notifications

Use:
- pagination
- lazy loading
- efficient realtime subscriptions
- debounced search
- optimized queries
- virtualization where appropriate

==================================================
54. FINAL PRODUCTION-READINESS AUDIT 🟨 [IN PROGRESS]
==================================================

After implementation:

- remove dead code
- remove unused imports
- remove unused dependencies
- fix console errors
- fix build errors
- fix runtime errors
- fix broken routes
- fix API failures
- fix layout overflow
- fix mobile issues
- fix modal issues
- fix dropdown issues
- fix button issues
- fix dark/light theme issues
- fix accessibility issues

==================================================
55. DEFINITION OF DONE 🟨 [IN PROGRESS]
==================================================

This frontend phase is COMPLETE only when:

- every required screen exists
- every required primary button exists
- buttons are correctly positioned
- message action toolbar is complete
- profile popover is complete
- Profile → Message → DM works
- friend system is complete
- mentions work
- reactions work
- editing works
- deleting works
- replies work
- attachments work
- file UI is complete
- search UI is complete
- notification UI is complete
- admin UI is complete
- logs UI is complete
- stats UI is complete
- backup UI is complete
- loading states exist
- error states exist
- empty states exist
- desktop works
- tablet works
- mobile works
- dark mode works
- light mode works
- accessibility is acceptable
- there are NO dead buttons
- there are NO placeholder controls
- there are NO fake interactions
- there are NO visibly unfinished pages

Most importantly:

DO NOT report "Phase completed" simply because code exists.

The actual WEBSITE must be inspected.

The UI must look complete.

The buttons must exist.

The buttons must be in sensible locations.

The buttons must work.

The entire user flow must work.

==================================================
56. FINAL PRODUCT STANDARD 🟨 [IN PROGRESS]
==================================================

The finished product should feel like:

"ConnectHub with a polished, modern, Discord-inspired messaging experience"

NOT:

"Discord with renamed servers."

ConnectHub's existing organization structure remains the source of truth:

Dashboard
Messages
Departments
Teams
Groups
Channels
Files
Search

Admin:

Users
Logs
Stats
Backups

Use the existing basic roles:

Super Admin
Admin
Manager
Standard User
Guest User

Keep:
- friends basic
- mentions basic
- permissions basic
- messaging feature-rich
- UI highly polished

Do NOT add:
- bots
- servers
- threads
- @everyone
- @here
- @staff
- role mentions
- advanced Discord permission systems
- Discord audit logs

The final standard is not "all phases implemented."

The final standard is:

THE WEBSITE LOOKS COMPLETE, EVERY IMPORTANT CONTROL EXISTS, EVERY CONTROL IS IN THE RIGHT PLACE, AND EVERY USER FLOW WORKS END-TO-END.
# 2. GROUP CREATION, MEMBERS, CUSTOM ROLES & PERMISSIONS

Implement a complete, polished Group management system inside ConnectHub.

This is NOT a Discord server system.

A Group is a managed multi-user communication space with:

* members
* roles
* custom permissions
* group visibility
* group settings
* a default role
* role hierarchy
* member management

The feature must have a proper production-quality UI, not just backend functionality.

---

## 2.1 WHO CAN CREATE GROUPS

Only these existing ConnectHub roles can create a Group:

* Super Admin
* Admin

Managers, Standard Users, and Guest Users cannot create Groups unless this is explicitly changed later.

The Group creation action should appear only for authorized users.

Example:

**Groups**

`[ + Create Group ]`

If the current user cannot create Groups, do not show the button.

---

# 2.2 CREATE GROUP UI

Clicking:

`+ Create Group`

must open a proper creation modal/page.

The creation UI should include:

### Basic Information

* Group Name
* Group Description
* Group Icon / Avatar
* Optional Group Color

### Visibility

Every Group must have a visibility setting during creation:

**Private**

* Only invited/added members can access the Group.

**Organization-wide**

* Users within the organization can discover/access the Group according to the Group's configured access rules.

The selected visibility must be clearly explained using a small information icon.

Example:

**Private**
`ⓘ Only users explicitly added to this Group can access it.`

**Organization-wide**
`ⓘ The Group can be available to users across the organization according to its access configuration.`

### Initial Role

The Group must automatically create the basic default roles required by the system.

At minimum:

* Group Admin
* Group Member

The creator becomes the **Group Owner**.

The creator must have full Group management authority.

### Creation Actions

`Cancel`

`Create Group`

The Create button must remain disabled until all required information is valid.

Show loading while creating.

Show a clear error if creation fails.

After successful creation, open the newly created Group in the existing ConnectHub messaging experience.

Do not create a separate unnecessary Group messaging page or navigation system.

---

# 2.3 GROUP OWNER

The user who creates the Group becomes its permanent **Group Owner**.

The Group Owner is above all normal Group roles.

The Owner must have full Group control, including:

* manage Group settings
* manage members
* add/remove members
* create roles
* edit roles
* delete roles
* manage role hierarchy
* assign roles
* manage permissions
* change default role
* manage Group visibility
* manage Group information
* delete the Group
* manage all Group messages where appropriate

The Owner cannot be:

* removed from the Group
* demoted
* assigned a lower role
* have their permissions reduced by another member

## IMPORTANT — OWNER PROTECTION

Absolutely NO other user can modify the Group Owner.

This includes:

* Group Admin
* custom roles with Manage Roles
* any other role

The Owner is always protected.

Do NOT provide a UI action that allows another user to:

* remove the Owner
* demote the Owner
* edit the Owner's permissions
* delete the Owner's role
* move the Owner lower in the hierarchy

Only the Group Owner can transfer ownership if ownership transfer is implemented later.

---

# 2.4 GROUP MEMBER MANAGEMENT

The Group Owner can add users to the Group.

Other users may add/remove members only when their assigned role explicitly has the relevant permission.

Example permission:

`Manage Members`

If a Group Admin has:

`Manage Members = ON`

they may add/remove members.

If:

`Manage Members = OFF`

they cannot.

The frontend must hide unavailable actions, but the backend must also enforce the permission.

---

# 2.5 GROUP ROLES

Every Group must have a role system.

The initial roles should be:

### Group Owner

Special protected role.

Cannot be edited by other users.

### Group Admin

Administrative Group role.

### Group Member

Normal default member role.

The Group Owner can create additional custom roles.

Examples:

* Moderator
* Editor
* Viewer
* Support
* Team Lead
* Content Manager

Custom role names, colors, descriptions and permissions must be configurable.

---

# 2.6 ROLE UI

The Group Settings → Roles section should have a polished interface inspired by the usability of Discord's role settings, but adapted to ConnectHub.

The layout should contain:

### LEFT SIDE — ROLE LIST

Show roles in hierarchy order.

Example:

```text
Roles

👑 Group Owner
🟣 Group Admin
🔵 Moderator
🟢 Editor
⚪ Group Member
👁 Viewer
```

Each role should display:

* role name
* role color
* optional member count
* drag/reorder control only when the current user is allowed to reorder it

The currently selected role should have a clear active state.

### RIGHT SIDE — ROLE DETAILS

When a role is selected, show:

* Role Name
* Role Color
* Role Description
* Member Count
* Permissions

Include:

`ⓘ` information icons beside permissions.

Hovering or clicking the info icon should explain exactly what the permission allows.

Example:

**View Messages** `ⓘ`

> Allows members with this role to view messages in the Group.

**Send Messages** `ⓘ`

> Allows members with this role to send new messages.

**Delete Other Members' Messages** `ⓘ`

> Allows members with this role to delete messages sent by other members.

This explanation UI must be consistent throughout the permission system.

---

# 2.7 CUSTOM ROLE CREATION

The Group Owner can select:

`+ Create Role`

This opens a proper Create Role UI.

Fields:

* Role Name
* Role Color
* Role Description
* Permissions

Actions:

`Cancel`

`Create Role`

After creation, the role appears in the role list.

The role must have a unique identifier internally.

---

# 2.8 ROLE EDITING

Authorized users can select an existing role and edit:

* name
* color
* description
* permissions

However, authorization rules must always be enforced.

A user cannot modify a role that is above their own role in the hierarchy.

A user cannot grant permissions they themselves do not possess.

A user cannot grant another role more authority than they are allowed to control.

---

# 2.9 ROLE HIERARCHY

Groups must use a clear role hierarchy.

Example:

```text
Group Owner
    ↓
Group Admin
    ↓
Moderator
    ↓
Editor
    ↓
Group Member
    ↓
Viewer
```

Higher roles have greater authority.

The Group Owner is always at the top.

## HIERARCHY RULES

A user may only manage roles below their own highest role.

A user cannot:

* move another role above their own role
* move their own role above a higher role
* move a role above the Group Owner
* edit a higher role
* delete a higher role
* assign a higher role to another member
* grant permissions that exceed their own authority

---

# 2.10 ROLE REORDERING

The role list should support drag-and-drop reordering where the current user has permission to manage roles.

However, hierarchy restrictions MUST be enforced.

Example:

If the current user is:

`Group Admin`

they may reorder roles below Group Admin.

They CANNOT:

* move Group Admin above Group Owner
* move a custom role above Group Admin
* move their controlled hierarchy above their own level
* manipulate the Owner position

The UI should visually prevent invalid movement.

The backend must also reject invalid hierarchy changes.

Never rely only on frontend restrictions.

---

# 2.11 ROLE PERMISSION RESTRICTION

A user who has permission to manage roles must NOT automatically gain unlimited permission-granting ability.

If a Group Admin has:

```text
View Messages = ON
Send Messages = ON
Manage Members = ON
Manage Roles = ON
Delete Other Messages = OFF
```

they cannot create/edit another role and give it:

```text
Delete Other Messages = ON
```

because they themselves do not possess that authority.

Therefore:

> A role manager cannot grant permissions that exceed their own effective authority.

This rule must be enforced by both frontend and backend.

Unavailable permissions should appear disabled or locked in the role editor.

Show a small info/lock indicator explaining why.

Example:

`🔒 Delete Other Members' Messages`

> You cannot grant this permission because your current role does not have this authority.

---

# 2.12 DEFAULT ROLE

Every Group must have exactly ONE default role.

The role editor must include:

`Make this the default role`

or:

`Default Role`

with an ON/OFF control.

Only one role can be the default role at a time.

When enabled for a role:

* the previous default role becomes non-default
* the selected role becomes the new default

When a new user joins/is added to the Group:

`New Member → Automatically receives Default Role`

Example:

```text
Roles

Group Owner
Group Admin
Moderator
Group Member  ← DEFAULT
Viewer
```

A new member automatically receives:

`Group Member`

The Group Owner or authorized role manager can later assign another role.

The Owner and existing administrators must not accidentally be replaced by the default-role system.

The default role applies only to newly added/joining normal members.

---

# 2.13 PERMISSION CATEGORIES

Use a medium-granularity permission system.

Do NOT create an enormous Discord-style permission matrix.

Use clear categories.

## MESSAGES

Permissions should include:

* View Messages
* Send Messages
* Edit Own Messages
* Edit Other Members' Messages
* Delete Own Messages
* Delete Other Members' Messages
* Reply to Messages
* Add Reactions
* Remove Reactions
* Pin Messages
* Unpin Messages
* Send Links
* Send Attachments
* Send Images
* Send Files

Each permission must have an information tooltip.

---

## MEMBERS

Permissions:

* View Members
* Add Members
* Remove Members
* Manage Members
* View Member Profiles

---

## ROLES

Permissions:

* View Roles
* Create Roles
* Edit Roles
* Delete Roles
* Assign Roles
* Manage Role Hierarchy
* Manage Role Permissions

---

## GROUP

Permissions:

* View Group
* Edit Group Name
* Edit Group Description
* Change Group Icon
* Change Group Visibility
* Manage Group Settings
* Delete Group

---

## MENTIONS

Keep mentions simple.

Normal individual user mentions are allowed:

`@Username`

Include:

* Mention Users

Do NOT implement:

* @everyone
* @here
* @staff
* @department
* @team
* @group
* role mentions
* mass mentions

The `Mention Users` permission controls whether a role can mention individual users.

---

# 2.14 PERMISSION UI

The permission editor must be visually clear.

Example:

```text
MESSAGES

☑ View Messages                         ⓘ
☑ Send Messages                         ⓘ
☑ Edit Own Messages                     ⓘ
☐ Edit Other Members' Messages         ⓘ
☑ Delete Own Messages                   ⓘ
☐ Delete Other Members' Messages       ⓘ
☑ Reply to Messages                     ⓘ
☑ Add Reactions                         ⓘ
☐ Remove Reactions                      ⓘ
☑ Send Links                            ⓘ
☑ Send Attachments                      ⓘ
☐ Pin Messages                          ⓘ
```

The info icon must explain the permission.

Hover or click:

`ⓘ`

opens a small tooltip/popover.

The explanation should be understandable to a normal user, not developer terminology.

---

# 2.15 ROLE ASSIGNMENT

Group members can be assigned roles by authorized users.

Member management UI should show:

```text
Member

Avatar
Name
Username

Role:
[ Moderator ▼ ]

Actions:
[ Message ] [ More ]
```

The role dropdown should only show roles the current user is allowed to assign.

A user cannot assign:

* Owner
* roles above their hierarchy
* roles they are not authorized to manage

The backend must enforce this.

---

# 2.16 ROLE DELETION

Custom roles can be deleted by authorized role managers.

Before deletion:

Show confirmation:

**Delete Role?**

Explain:

> Members currently assigned to this role will lose this role. Choose what should happen to those members.

Provide a safe fallback:

`Move members to: [Default Role ▼]`

Actions:

`Cancel`

`Delete Role`

Protected roles cannot be deleted.

Protected roles include:

* Group Owner
* required system/default roles where applicable

---

# 2.17 GROUP SETTINGS

Every Group must have a high-quality Settings interface.

Settings should be organized into sections rather than one extremely long form.

Recommended structure:

### General

* Group Name
* Description
* Icon
* Group Color
* Visibility

### Members

* View Members
* Add Members
* Remove Members
* Member search
* Role assignment

### Roles

* Role list
* Create Role
* Edit Role
* Delete Role
* Role hierarchy
* Default Role
* Permission management

### Permissions

* Role permission configuration
* Permission explanations
* Permission restrictions

### Notifications

Where supported:

* Group notification preferences
* Mention notifications
* Message notifications

### Danger Zone

* Delete Group

Danger Zone must be visually separated.

Group deletion requires strong confirmation.

---

# 2.18 GROUP SETTINGS UI QUALITY

Settings must feel like a real production application.

Use:

* left settings navigation where appropriate
* selected section state
* clear headings
* descriptions
* cards/sections
* switches
* dropdowns
* checkboxes
* tooltips
* confirmation dialogs
* Save buttons where necessary

Do not put every setting into one giant modal.

The user must immediately understand:

* what setting they are editing
* what it does
* what effect it has
* whether they have permission to change it

---

# 2.19 UNSAVED CHANGES

If settings are edited but not saved:

Show an unsaved-changes state.

Provide:

`Save Changes`

`Discard Changes`

Prevent accidental loss of edits.

If the user attempts to leave with unsaved changes, show a confirmation.

---

# 2.20 MEMBER + ROLE INTERACTION

When viewing a Group member:

Profile/member menu can show:

* View Profile
* Message
* Mention
* Current Role
* Change Role if authorized
* Remove Member if authorized
* Block where globally supported

The current user's permissions determine which actions appear.

---

# 2.21 SECURITY RULE

All Group permissions must be enforced server-side.

Frontend restrictions are only for UX.

Never rely on:

* hidden buttons
* disabled buttons
* frontend role checks

The backend must independently verify:

* Group membership
* role hierarchy
* role permissions
* member management
* role creation
* role editing
* role deletion
* role assignment
* permission changes
* Group settings changes
* Group deletion

A malicious user must not be able to bypass the UI and directly call an API to gain permissions.

---

# 2.22 GROUP CREATOR / ADMIN DIFFERENCE

The Group Owner has absolute Group management authority.

A Group Admin is only as powerful as the permissions assigned to their role.

Example:

If Group Admin has:

* Manage Members = ON
* Manage Roles = ON
* Edit Group = ON
* Delete Group = OFF

then they can manage members, roles and editable Group settings, but they CANNOT delete the Group.

This makes the custom role system meaningful.

---

# 2.23 UI RULES FOR UNAUTHORIZED ACTIONS

Do not clutter the UI with actions the user can never use.

For completely unavailable actions:

* hide them where appropriate.

For visible but locked settings:

* show them disabled
* show a lock icon
* explain why using the info tooltip

Example:

`🔒 Delete Other Members' Messages`

`ⓘ You do not have permission to grant or modify this permission.`

This makes the permission system understandable instead of confusing.

---

# 2.24 GROUP CREATION → FIRST CONFIGURATION FLOW

The complete flow should be:

```text
Create Group
      ↓
Enter Group Name
      ↓
Description / Icon
      ↓
Select Visibility
      ↓
Create Group
      ↓
Creator becomes Group Owner
      ↓
Default roles created
      ↓
Default role selected
      ↓
Group opens
      ↓
Owner can configure Members / Roles / Permissions / Settings
```

The Group must be usable immediately after creation.

---

# 2.25 FINAL GROUP SYSTEM REQUIREMENT

The finished Group system should feel like a polished, professional workspace feature inspired by the usability of Discord's role management, but NOT like a copy of Discord's server architecture.

It must support:

* Group creation
* Private / Organization-wide visibility
* Group Owner
* Group Admin
* Group Member
* Custom roles
* Custom role colors
* Custom role descriptions
* Role hierarchy
* Role reordering
* Default role
* Member role assignment
* Member management
* Custom permissions
* Permission categories
* Permission explanations
* Permission locks
* Permission inheritance/authority restrictions where required
* High-quality Group Settings
* Unsaved changes handling
* Confirmation dialogs
* Backend authorization
* Responsive UI
* Loading states
* Error states
* Empty states

Critical hierarchy rules:

1. Group Owner is permanently above all roles.
2. Group Owner cannot be modified by other users.
3. Lower roles cannot move themselves or another role above their authority level.
4. A role manager cannot edit roles above their own hierarchy.
5. A role manager cannot grant permissions that exceed their own authority.
6. A role manager cannot assign roles above their authority.
7. Protected roles cannot be deleted.
8. Default role applies automatically to newly added/joining normal members.
9. Only one default role exists per Group.
10. All permission checks must be enforced by the backend.

The final UI must make all of these rules understandable without requiring the user to understand technical permission systems.

# Presence and authentication visual update

User reference: blue/white split authentication page, adapted to KryinTalk and KryinLabs branding. No OAuth or other unsupported actions were added. Existing agreement, confirmation, pending access and form guards remain.

Presence root cause: saved presence_status values were treated as live indefinitely; last_active_at was ignored. UI consumers watched the notifier rather than its state, so counters could remain stale.

Fix: a shared status check requires a heartbeat within 90 seconds, rejects missing/invalid/far-future timestamps and unknown statuses, preserves live away/busy/focus preferences, and is used by the Supabase bridge, conversation enrichment and presence provider. Dashboard/friends/chat consume presence changes. Sign-out attempts a bounded offline update; a closed browser expires naturally. Network failures still repaint status expiry. No database row reset, identity repair, or privilege change was needed.

UI: local blue theme, pale background, top KryinTalk brand, compact outlined form, split blue illustration with the real brand mark, accessible policy dialogs, gray disabled CTAs, KryinLabs footer. Narrow or large-text layouts use a scrolling single-column form.

Verification: stale-presence tests failed before the change and pass after it. All 35 Flutter tests pass, including desktop blue-theme and split-panel checks plus dark/light forms at 360/768/1440px and 200% text. Analyzer has no errors; pre-existing/style findings remain. Final release preview is built and visually reviewed before upload. Private repository update preserves the original checkout and excludes local credentials/artifacts.

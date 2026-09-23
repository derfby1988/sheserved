# Maestro guide: Find Buddies on CPH1989

Use the regular-user flow by default. Use the admin flow only when the test requires admin-only pages, moderation, or authorization. Choosing the role-specific UI flow also chooses its matching login flow, so test credentials stay in the existing login files.

| Test requirement | Run this flow | Login flow used |
| --- | --- | --- |
| Public discovery, filters, group details, or member actions | `sport_club_ui_user_CPH1989.yaml` | `login_CPH1989.yaml` |
| Admin-only controls or admin authorization | `sport_club_ui_admin_CPH1989.yaml` | `login_admin_CPH1989.yaml` |

For tests that compare both roles, run the appropriate role-specific flow for each scenario rather than reusing an admin session for regular-user assertions.

Both UI flows call `sport_club_entry_CPH1989.yaml` after login. The shared entry flow opens the drawer, collapses `บริการทางการแพทย์` so the community menu is visible, taps `หาเพื่อนออกกำลังกาย`, and waits for the Find Buddies page. Keep this navigation in the shared helper instead of duplicating it in future Sport Club flows.

Run one of the role-specific flows from the repository root:

```sh
maestro test docs/guides/sport_club_ui_user_CPH1989.yaml
maestro test docs/guides/sport_club_ui_admin_CPH1989.yaml
```

The flow is calibrated for CPH1989 running Android 11 at 1080x2340. The shared navigation helper contains no credentials; authentication remains in the existing login flows.

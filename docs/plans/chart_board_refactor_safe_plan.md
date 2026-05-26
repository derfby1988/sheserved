---
description: Safe incremental refactor plan for consultation ChartBoardPage
---

# ChartBoardPage Safe Refactor Plan

## Scope
Target file: `lib/features/consultation/presentation/pages/chart_board_page.dart`

This plan focuses on **safe, incremental refactoring** with minimal risk to performance and behavior.

## Current risk areas
- Large monolithic page with heavy `build()` logic.
- Frequent `setState()` calls from timers, streams, and realtime subscriptions.
- Multiple lifecycle-managed resources:
  - `Timer.periodic`
  - `StreamSubscription`
  - `AnimationController`
  - Supabase realtime channels
- Sensitive consultation flow rules:
  - Patient unlock logic uses local `_hasSubmitted`.
  - Provider-side pending status must remain intact for alerts.
  - Back navigation must preserve existing routing behavior.

## Refactor principles
- Refactor in **small phases** only.
- Keep behavior identical before optimizing performance.
- Prefer extracting pure UI first, then side effects.
- Avoid changing state management architecture in the first pass.
- Preserve all dispose/lifecycle responsibilities.

## Phase 0: Baseline and behavior lock ✅ COMPLETED (retroactive)
### Goal
Document the current behavior before any code changes.

### Verify
- Patient can open, submit, and unlock the chat flow.
- Provider still sees pending alerts.
- Timer starts, updates, and expires correctly.
- Health permission dialogs still appear and respond correctly.
- Back navigation works both before and after submission.

### Exit criteria
- A short checklist exists for manual verification after every refactor step.

### Post-Phase 1 verification (retroactive baseline)
| Check | Status |
|-------|--------|
| Build compiles cleanly (`flutter build apk` / `flutter run`) | ✅ Pass |
| No new exceptions in `chart_board_page.dart` | ✅ Pass |
| Widget tree structure unchanged (only `_build*` methods delegate to extracted widgets) | ✅ Pass |
| `_hasSubmitted` still controls patient chat unlock locally | ✅ Preserved |
| `pending` DB status still preserved for provider alerts | ✅ Preserved |
| Timer badge still uses same state vars (`_remainingSeconds`, `_isTimerRunning`) | ✅ Preserved |
| Chat input overlays (lock + read-only) still use same conditionals | ✅ Preserved |
| `_buildTimerBadge` → `_TimerBadgeWidget` delegates without logic change | ✅ Pass |
| `_buildBodyMapSummary` → `_BodyMapSummaryWidget` delegates without logic change | ✅ Pass |
| `_buildActionButtons` → `_ActionButtonsWidget` delegates without logic change | ✅ Pass |
| `_buildChatInput` → `_ChatInputBarWidget` delegates without logic change | ✅ Pass |

## Phase 1: Extract pure UI widgets ✅ COMPLETED
### Goal
Reduce the size of `build()` without changing logic.

### Candidate widgets
- Header/title area.
- Timer badge.
- Chat input bar.
- Overlays (locked/read-only states).
- Reusable section cards.
- Weight history/chart presentation.

### Rules
- No business logic moves in this phase.
- Pass data through constructors.
- Use `const` where possible.

### Test focus
- Layout matches the previous version.
- No behavior changes.
- No missing text, icons, or spacing regressions.

## Phase 2: Reduce rebuild scope for fast-changing state ✅ COMPLETED
### Goal
Stop rebuilding the whole page for values that change often.

### Candidate states
- Remaining session time.
- Recording indicator.
- Message list updates.
- Loading flags that only affect one section.

### Changes made
| Variable | Old Type | New Type | Widget Isolation |
|----------|----------|----------|------------------|
| `_remainingSeconds` | `int` | `ValueNotifier<int>` | `_TimerBadgeWidget` via `AnimatedBuilder` |
| `_isTimerRunning` | `bool` | `ValueNotifier<bool>` | `_TimerBadgeWidget` via `AnimatedBuilder` |
| `_messages` | `List<ChatMessage>` | `ValueNotifier<List<ChatMessage>>` | `_buildMessagesList()` via `AnimatedBuilder` |
| `_isChatLoading` | `bool` | `ValueNotifier<bool>` | `_buildMessagesList()` via `AnimatedBuilder` |
| `_isRecording` | `bool` | `ValueNotifier<bool>` | `_ChatInputBarWidget` send/mic button via `AnimatedBuilder` |
| `_isSending` | `bool` | `ValueNotifier<bool>` | `_ChatInputBarWidget` send/mic button via `AnimatedBuilder` |

### What changed
- Replaced `setState(() => _x = y)` with `_xNotifier.value = y` for fast-changing states.
- Wrapped affected widget subtrees with `AnimatedBuilder` + `Listenable.merge([...])`.
- Extracted widget classes now accept `ValueListenable<T>` instead of raw values.
- Timer ticks no longer rebuild the entire page — only the badge updates.
- Message stream updates no longer rebuild the entire page — only the list updates.
- Recording/send state changes no longer rebuild the entire page — only the button updates.

### Test focus
- Timer still ticks once per second.
- Messages still appear instantly.
- Input controls still respond.
- Unrelated UI does not flicker or reset.

## Phase 3: Extract side effects and realtime logic ✅ COMPLETED (partial — safe scope)
### Goal
Make lifecycle-sensitive code easier to manage.

### What was extracted
| Controller | Responsibility | Status |
|------------|---------------|--------|
| `_SessionTimerController` | Session countdown timer (`Timer.periodic`), `_remainingSecondsNotifier`, `_isTimerRunningNotifier`, `_onSessionExpired` DB update | ✅ Extracted |
| `_ProfessionsRefreshController` | `Timer.periodic` every 30s for `_loadProfessions()` | ✅ Extracted |

### What remains in page (intentionally)
| Logic | Reason |
|-------|--------|
| `_initChat()` + `_messagesSub` | Tightly coupled to page state (`_consultationRoomId`, `_activeConsultationId`, `_consultationData`, `_isConsultationActive`) and widget lifecycle |
| `_expertStatusSub` + `_fetchExpertStatuses()` | Updates `_expertStatuses` page state and triggers `_startTimer()` |
| `_roomSub` | Updates `_roomStartedAt` and `_timerController.remainingSeconds` — needs page context |
| Health permission polling + realtime channel | Heavy UI interaction (`showDialog`, `ScaffoldMessenger`, `setState`, `context`) embedded throughout |

### Why health permission & chat init stayed in page
Extracting them would require 10+ callbacks (onShowDialog, onShowSnackBar, onUpdateState, etc.) and would make the code harder to follow than keeping the logic colocated with the UI it drives.

### Test focus
- Enter/exit the page repeatedly without duplicate events.
- No leaked timers or subscriptions.
- Realtime events still arrive exactly once.

## Phase 4: Protect consultation flow contracts ✅ COMPLETED
### Goal
Ensure the most sensitive business rules remain stable.

### Contracts verified

#### Contract 1: Patient unlock is controlled by local `_hasSubmitted` ✅
**Evidence:**
- `_hasSubmitted` declared at `@chart_board_page.dart:66`
- Set to `true` in `_submitConsultationRequest()` at `@chart_board_page.dart:3313`
- `_buildChatInput()` uses `isChatActive = _isProvider || _hasSubmitted || status == 'in_progress'` at `@chart_board_page.dart:3217`
- Pain selector and payment card visibility: `!_isProvider && !_hasSubmitted && status == 'pending'` at `@chart_board_page.dart:1297,1312`
- `PopScope.canPop = !_hasSubmitted` and back navigation redirect to `/profile` at `@chart_board_page.dart:1201,1234`

**Conclusion:** Chat unlock is immediate after submit via `_hasSubmitted`, not dependent on async DB re-fetch.

#### Contract 2: DB status remains `pending` for provider alerts ✅
**Evidence:**
- New request created with `status: 'pending'` at `@chart_board_page.dart:3290`
- Provider alert cards query `consultation_requests.status == 'pending'` (external to this page)
- `_isConsultationActive` in `_initChat()` set from DB: `_isConsultationActive = (status == 'in_progress') || _isProvider` at `@chart_board_page.dart:575`
- Only existing `widget.entry` gets `status: 'in_progress'` update at `@chart_board_page.dart:3275`

**Conclusion:** New requests stay `pending` in DB so provider home-header alerts still appear.

#### Contract 3: Provider and patient flows don't conflict ✅
**Evidence:**
- `_isProvider` flag set from `professionId` at `@chart_board_page.dart:132-133`
- Provider always sees chat as active: `isChatActive = _isProvider || ...` at `@chart_board_page.dart:3217`
- Pain selector hidden for providers: `if (!_isProvider ...)` at `@chart_board_page.dart:1297`
- Payment card hidden for providers: `if (!_isProvider ...)` at `@chart_board_page.dart:1312`
- Health permission banner only shows for providers: `if (_isProvider ...)` at `@chart_board_page.dart:1292`

**Conclusion:** Role-based branching is intact and unambiguous.

#### Contract 4: Navigation after submit unchanged ✅
**Evidence:**
- `PopScope.canPop: !_hasSubmitted` at `@chart_board_page.dart:1201`
- Back button: `_hasSubmitted ? Navigator.pushNamedAndRemoveUntil('/profile') : Navigator.pop()` at `@chart_board_page.dart:1234`
- `_hasSubmitted` set immediately after successful submit at `@chart_board_page.dart:3313`

**Conclusion:** After submit, back goes to `/profile` tab 2, not analyze-body.

### Test focus
- Submit flow still unlocks chat immediately.
- Provider alert cards still appear for pending requests.
- No stale lock state after submit.

## Recommended execution order
1. Baseline verification.
2. Pure UI extraction.
3. Rebuild-scope reduction.
4. Side-effect extraction.
5. Contract verification.

## Do not do in the first refactor pass
- Do not switch the whole page to a new state management system.
- Do not change consultation status semantics.
- Do not rewrite navigation and realtime logic at the same time.
- Do not optimize chart calculations before the page is modularized.

## Success criteria
- Same behavior as before.
- Smaller, more readable widgets.
- Less page-wide rebuild pressure.
- Easy to test each phase independently.
- No regression in consultation flow or provider alerts.

---

## Completion Summary

All 5 phases completed on 2026-05-26. Build passes (`flutter analyze` clean, `flutter run` successful).

### What changed
| Phase | Key Changes |
|-------|-------------|
| 0 | Retroactive baseline checklist added to plan |
| 1 | 4 pure UI widgets extracted: `_TimerBadgeWidget`, `_BodyMapSummaryWidget`, `_ActionButtonsWidget`, `_ChatInputBarWidget` |
| 2 | 6 fast-changing states converted to `ValueNotifier` + `AnimatedBuilder`: `_remainingSeconds`, `_isTimerRunning`, `_messages`, `_isChatLoading`, `_isRecording`, `_isSending` |
| 3 | 2 side-effect controllers extracted: `_SessionTimerController`, `_ProfessionsRefreshController` |
| 4 | 4 consultation flow contracts verified with code evidence and line citations |

### What was intentionally NOT changed
- Chat init + message stream logic stayed in page (tight coupling with 10+ page state variables)
- Expert status + room stream logic stayed in page (triggers timer start + updates page state)
- Health permission polling + realtime channel stayed in page (heavy UI interaction throughout)
- State management architecture (still StatefulWidget + `setState` for slow-changing state)
- Consultation status semantics (`pending` for provider alerts, `_hasSubmitted` for patient unlock)
- Navigation flow (`/profile` after submit)

### Build verification
```
flutter analyze lib/features/consultation/presentation/pages/chart_board_page.dart
# Exit code: 0 (no errors)
```

<p align="right">
  <a href="README.md">中文</a> ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

<p align="center">
  <img src="Resources/AppIconREADME.png" width="144" alt="AgentAwake app icon">
</p>

<h1 align="center">AgentAwake</h1>

<p align="center">
  Keep your agent working, then let your Mac rest as usual.
</p>

<p align="center">
  macOS 13+ · Apple Silicon / Intel · Current version 0.5.1
</p>

<p align="center">
  <a href="https://github.com/Raymond711xl/AgentAwake/releases/latest">Download the latest release</a>
</p>

## About

AgentAwake is a lightweight macOS menu bar utility that is ready to use after
download. While a timed mode is active or an agent is working, it prevents
idle sleep with timeout-protected macOS IOKit power assertions. When the task
finishes, the timer expires, the mode is turned off, or the app quits,
AgentAwake immediately releases those assertions and returns control to macOS.

It never calls `pmset`, changes your sleep, lock-screen, or display preferences,
or keeps a persistent `caffeinate` or shell process running.

The current development build now has two progressive levels:
zero-configuration automatic detection and per-agent precise tracking. The old
high-frequency scan has been replaced by a bounded event-driven engine. The
next step is adding one verified third-party adapter at a time. See the
[agent activity detection roadmap](docs/AGENT_ACTIVITY_DETECTION_PLAN.md).
AgentAwake does not read prompts, response bodies, token details, or API keys.

## Core features

- **One five-position slider** — Off, 30 minutes, 1 hour, 2 hours, and Agent.
  The slider is both the selector and the switch.
- **Agent-aware protection** — Detects active local Codex and Claude tasks and
  keeps the system and display awake only while work is in progress.
- **Hooks first, local logs as fallback** — Uses lifecycle Hooks for timely
  state changes. Without Hooks, it incrementally reads local task logs for a
  zero-configuration fallback instead of trusting long-lived process names.
- **Event-driven and bounded** — Agent mode reuses one native macOS file-event
  stream, reads only appended bytes, reconciles every 15 minutes, and caps both
  session state and parser buffers.
- **Universal Bridge** — Third-party agents that can run lifecycle commands can
  send `start`, `heartbeat`, and `stop`. The one-shot helper writes local state
  and exits immediately.
- **Download and run** — Regular users need no Codex, Cloud, Xcode, Swift, or
  terminal. Hooks and login-item behavior are optional settings.
- **Automatic release and renewal** — Agent mode uses a 120-second lease,
  renews it every 60 seconds, and releases it five seconds after the last agent
  finishes. Stale activity also expires automatically.
- **Timeout-protected power assertions** — Both timed and Agent modes use
  temporary IOKit assertions, so no permanent system setting is left behind.
- **Clear menu bar status** — Shows the current mode, countdown, waiting state,
  and active agent. Every launch starts in Off and never silently resumes the
  previous protection mode.
- **Local, lightweight, and account-free** — No network service or sign-in.
  When Off, the app does not scan for agents, keep a timer, or hold an
  assertion.

## Modes

| Mode | Behavior | Automatic end |
| --- | --- | --- |
| Off (`未开启`) | Uses the existing macOS settings; no scan, timer, or assertion | — |
| 30 minutes | Immediately keeps the system and display awake | Releases after 30 minutes and returns to Off |
| 1 hour | Immediately keeps the system and display awake | Releases after 1 hour and returns to Off |
| 2 hours | Immediately keeps the system and display awake | Releases after 2 hours and returns to Off |
| Agent | Only listens when idle; temporarily stays awake while Codex or Claude is working | Releases after the task, but remains in Agent mode to wait for the next one |

## Requirements

- macOS 13 Ventura or later
- Apple silicon and Intel Macs are supported
- The current menu bar interface is in Simplified Chinese

## Usage

### 1. Download and launch

Open [GitHub Releases](https://github.com/Raymond711xl/AgentAwake/releases/latest):

1. Download the image for your Mac:
   - Apple M1, M2, M3, M4, or later: `AgentAwake-x.y.z-Apple-Silicon.dmg`.
   - Intel processor: `AgentAwake-x.y.z-Intel.dmg`.
2. Open the DMG and double-click `AgentAwake.app`. For long-term use, drag the
   app to Applications first, especially before enabling Launch at Login.

To check your processor, open Apple menu  → About This Mac and look for Chip
or Processor.

> **If macOS blocks the first launch:** try opening AgentAwake once and dismiss
> the warning. Open System Settings → Privacy & Security, scroll down, click
> Open Anyway beside AgentAwake, then confirm Open. macOS may ask for your login
> password. This is a one-time exception; future launches work normally.
> This release uses ad-hoc signing and does not show a verified Apple developer.
> No Terminal command is required.

On its first launch, AgentAwake opens its menu bar panel once. It then remains
in the menu bar without a Dock icon. All three timed modes are immediately
available and require no further setup.

### 2. Choose a protection mode

1. Click the four-point sparkle-and-`Z` icon in the menu bar.
2. Drag the slider to 30 minutes, 1 hour, 2 hours, or Agent.
3. To stop immediately, drag it back to Off (`未开启`); the temporary power
   assertions are released at once.

Timed modes start their countdown immediately. Agent mode waits without holding
an assertion, then takes over only when it detects active Codex or Claude work.

### 3. Optional settings

Click Settings at the bottom of the menu bar panel to manage:

- launch at login;
- Codex Hooks;
- Claude Hooks;
- the universal Agent Bridge.

Agent mode reads existing local Codex and Claude activity records by default,
so Hooks are not a prerequisite. Settings reports local detection state and
only enables Hook installation for agents that exist on the Mac. It never
creates configuration for absent software. Only after the user explicitly
selects Install does the app:

- place the one-shot helper at
  `~/Library/Application Support/AgentAwake/bin/AgentAwakeHook`;
- safely merge entries into `~/.codex/hooks.json` and
  `~/.claude/settings.json`;
- create an `.agentawake-backup` before it first changes an existing config;
- update its own entries on repeated runs instead of appending duplicates.

AgentAwake does not install or run a model. Users configure their own agent
software, and the app only reads existing local state.

Codex asks you to review unmanaged command Hooks. After installation, enter
`/hooks` in the Codex CLI, inspect the command path, and trust the new
AgentAwake Hooks. Codex skips them until they are trusted. Claude loads its
user-level settings automatically.

Agent mode still works without Hooks, although state transitions may be less
immediate. Installation, repair, and removal all happen in Settings without a
terminal.

If a third-party agent can execute lifecycle commands, enable Universal Agent
Bridge in Settings. Enter an Agent ID and display name, then copy the separate
Task Start, Running, and Task End commands. Do not run all three commands in a
terminal; place each one in the matching lifecycle hook. Start and stop are
required, while long-running tasks need periodic heartbeats.

Replace `$AGENT_SESSION_ID` in all three commands with the agent's stable task
ID variable, such as `task_id`, `session_id`, or `conversation_id`. If the ID
arrives in a hook's JSON input, read it in the hook script first. Keep the same
value for all events in one task. Bridge is not packet interception and does
not infer activity from a resident process; the agent must invoke it at the
correct lifecycle points.

## Verify that system settings remain unchanged

Enable a timed mode, or let Agent mode detect an active task, and run:

```bash
pmset -g assertions
```

You should see temporary `PreventUserIdleSystemSleep` and
`PreventUserIdleDisplaySleep` assertions whose names begin with `AgentAwake`.
After returning the slider to Off, those assertions should disappear.

Pause Caffeinated, Amphetamine, or similar utilities while testing; assertions
from another app make it harder to verify that sleep control has been returned.

## How agent detection works

AgentAwake does not decide activity by checking whether a `codex` or `claude`
process exists. App servers, sandboxes, and streaming processes may remain
alive long after a task has stopped.

Lifecycle events are the preferred source:

- `UserPromptSubmit` starts an activity lease;
- `PreToolUse`, `PermissionRequest`, and `PostToolUse` refresh it;
- `Stop`, Claude's `StopFailure`, and `SessionEnd` end it.

Once Hook state is available for a session, it overrides a potentially stale
transcript result. Without Hooks, one shared native file-event stream triggers
incremental reads of only the appended bytes in local Codex and Claude task
logs, with a 15-minute reconciliation fallback. A state with no new event for
30 minutes expires automatically.

## Privacy and safety

- All detection happens locally. The app does not contact an external service
  or upload task content.
- Hook leases store only the agent type, session identifier, event name, state,
  and update time — never prompts, responses, tokens, or credentials.
- Local leases live in
  `~/Library/Application Support/AgentAwake/AgentActivity`.
- Quitting the app, turning the mode off, reaching the timer deadline, or
  letting a lease expire all release the power assertions.

## Development and verification

Source builds require a Swift toolchain; Xcode Command Line Tools are
sufficient.

Build the Apple silicon and Intel release images:

```bash
./scripts/package-release.sh
```

Run the dependency-free self-test:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/agentawake-clang-cache \
SWIFT_MODULECACHE_PATH=/private/tmp/agentawake-swift-cache \
swift run --disable-sandbox AgentAwakeSelfTest
```

Repeatedly sample RSS, CPU, threads, and open files for a running app:

```bash
./scripts/measure-resources.sh --pid PID --duration 600 --interval 5
```

Short reference measurements and the pending eight-hour stability gate are
recorded in the
[agent activity detection roadmap](docs/AGENT_ACTIVITY_DETECTION_PLAN.md).

Regenerate the `.icns` file:

```bash
./scripts/build-icon.sh
```

Project layout:

```text
Sources/AgentAwake/          Menu bar UI and app lifecycle
Sources/AgentAwakeCore/      Protection state, agent detection, IOKit assertions
Sources/AgentAwakeSetupCore/ Optional integration detection and management
Sources/AgentAwakeHook/      One-shot lifecycle Hook helper
Sources/AgentAwakeHookSetup/ Hook installer and uninstaller
Resources/                   Info.plist and app icon
scripts/                     App and icon build scripts
docs/RELEASING.md            Dual-architecture DMG and GitHub Release workflow
```

## Current scope

AgentAwake timed modes do not require an agent. Agent-aware mode currently
supports automatic local detection for Codex and Claude, plus precise events
from hook-capable agents connected through Universal Agent Bridge. Agents
without reliable lifecycle hooks are out of scope for now; a process name or
encrypted traffic alone is not treated as support. AgentAwake is not a system
power-settings manager and does not replace macOS sleep policy; it only
postpones idle sleep during the selected protection window.

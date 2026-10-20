# Leader Mode

Leader Mode is an opt-in, side-specific modifier layer, configured in Settings ▸ Leader Mode.
Right Command is the default trigger. Ordinary left Command shortcuts are unchanged.

## Invariants

- **Selecting a group latches navigation.** Hold Right Command and press M to enter Messages;
  release both keys, then press T to run Teams. Holding the trigger throughout works too.
- **Only a group has a visible surface.** A persistent, non-activating pill names the current group;
  entering from the root and direct actions never open the palette or take focus.
- **One tree, one action funnel.** Leaves store `HotKeyAction.defaultsKey` identities and dispatch
  through `HotKeyManager.perform`, preserving feature gates and confirmation dialogs.
- **Consumed downs own their repeats and ups.** Modifier transitions pass through unchanged;
  an unmapped key cancels and is swallowed, never becoming a foreground-app Command shortcut.
- **Enablement stays local.** Backups and settings.json carry the trigger and bindings, never the
  permission to intercept global keys. Enabling in Settings requests Accessibility explicitly.
- **No imported code or dependencies.** Leader Key and Tuna inform the interaction, not the runtime.

## Navigation

Groups nest up to fifteen levels. Each sibling has a unique lowercase ASCII letter or digit.
Matching uses the current ASCII-capable layout's unmodified characters, consistently whether the
trigger is still held or has been released. Changing input sources refreshes the map and cancels
an unfinished sequence.

Escape cancels. Backspace goes up one group (leaving the top-level group cancels).
Running a leaf resets to the root. An unknown key, another modifier, a mouse click or an application
activation cancels. Releasing the trigger alone does not. No timeout or shortcut list is shown.

## Ownership and input

`AppCore` owns `LeaderCoordinator`, which owns its tap and group controller. `LeaderNode` and
`LeaderSequence` are Foundation-only models. `LeaderKeyTap.Session` protects synchronous event decisions
with a mutex; only plain Sendable updates cross to the main actor for presentation and execution.
Queued updates are invalidated when a session is cancelled or reconfigured.

The modifying session event tap exists only while enabled and usable. The shared health ticker
retries an Accessibility grant, detects revocation, and revives disabled taps. Secure Input, sleep,
screen lock, user-session changes, shortcut recording, dialogs and the visible palette pause capture
and clear navigation. Teardown releases the tap and its held-key tracking.

A modifier already used by Hyper Key or a single/double modifier shortcut is a conflict: Leader Mode
stays inactive and Settings explains why. This includes Dictation's modifier trigger. Other modifiers
remain available. Normal key combinations using the chosen modifier are reserved while enabled.

## Persistence

UserDefaults holds `leaderEnabled`, `leaderTrigger` and JSON text under `leaderBindings`, in the app's
own bundle domain. Settings supports creating, renaming, editing and deleting groups and bindings.
The Settings editor is a compact, indented tree with keycaps and app icons, not a folder browser.
Groups start expanded. Their chevrons toggle children; clicking a row opens a separate editor panel.
A group's plus menu adds a binding or group inside it; Add at the bottom adds at the root,
with its plus aligned to the root chevrons.
The ellipsis menu holds Edit and Delete. Expansion affects Settings only, never keyboard navigation.
Drag a binding or group onto a group to move it inside; hovering expands it after a short delay.
The top and bottom edges of rows reorder siblings, with an insertion line showing the destination.
Drop on the bottom Add area to move back to the root. Keys and group contents stay unchanged;
duplicate keys, excessive nesting and moves into the dragged group's own subtree are rejected.
Changes to the stored tree dismiss an unfinished editor to avoid stale paths.
Old settings are not migrated; re-enable Leader Mode and recreate bindings after updating.
New bindings default to Open App: Choose App opens a searchable list with icons, keyboard selection
and a double-click or Choose button. Apps and commands use the selected target's name automatically;
only groups have an editable Name field. Run Command keeps other launcher actions and built-in
commands in a separate picker. Existing bindings retain their selected action when opened for editing.
Missing actions report
an unavailable-action HUD; missing applications are not silently launched as something else.

The settings-file mirror writes structured `leaderMode.bindings` and `leaderMode.trigger`:

```json
"leaderMode": {
  "trigger": "rightCommand",
  "bindings": [
    {
      "key": "m",
      "name": "Messages",
      "children": [
        { "key": "t", "name": "Teams", "action": "hotkey.app.com.microsoft.teams2" }
      ]
    }
  ]
}
```

Invalid or duplicate bindings reject the whole edited tree and retain the previous configuration.
Backups merge validated trigger/binding values without enabling the feature on the destination Mac.

## Verification

`leader-test` compiles the shipped models and checks nesting, release-independent navigation,
actions, cancellation, repeats, balanced key-up suppression, validation, tree editing and atomic moves.
`leader-tap-test` exercises the shipped event router with unposted CGEvents: left/right identity,
release, mouse/modifier cancellation, Secure Input, stale updates, timeout recovery and synthetics.

Manual: enable in the Debug channel, grant Accessibility, create M → Messages → T → Teams, and
check row editing, dragging into/out of groups, sibling reordering, hover expansion, cancelled drags,
rejected duplicate keys/self-nesting, the group plus menu, collapse/reopen and duplicate keys in
different groups. Check both held and released continuation, the pill in Light and Dark, Escape/Backspace,
unknown keys, normal left Command shortcuts, recording, lock/wake, permission revocation and conflicts.

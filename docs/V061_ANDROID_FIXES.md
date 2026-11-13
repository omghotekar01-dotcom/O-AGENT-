# O-AGENT v0.6.1 — tested Android UI stability corrections

## Fixed from actual Android screenshots

- **Projects → Material ancestor crash:** Opening the Projects screen from
  Remote could show "No Material widget found" over a black/red page. The
  Projects route now has its own themed Scaffold, navigation app bar and safe
  content surface, so TextField, ChoiceChip, buttons and ink taps work.
- **Empty square icons:** The official \`cupertino_icons\` 1.x package is
  included in the Flutter dependency manifest, so its font is packaged with
  Android/iOS apps.
- **Misleading remote zero status and "Endpoint not found":** When an older
  backend cannot serve /api/remote/overview, the app now explains to update,
  stop and restart the laptop backend and shows an unknown placeholder instead
  of an unverified zero.
- **Codex Cloud task form lifecycle:** Its route now owns TextEditingController
  instances until the exit animation has completed, preventing premature
  disposal assertions.
- Regression tests cover 360px and 390px screens, simulated 24-project feed
  layout, project search, dialog submit/close and bundled font declaration.

## Install and verify

1. **Laptop:** In the real O-AGENT repository, close the old process:
   double-click STOP-O-AGENT.cmd.
2. Update the code from GitHub:
   \`git pull origin main\`
3. Double-click O-AGENT.cmd to start the matching backend and worker.
   Enable your existing private Tailscale Serve HTTPS if necessary.
4. **Phone:** Install the new v0.6.1 debug APK, retain the existing Android
   app data if signatures are compatible, and connect through
   "My Owner Workspace" to the configured private HTTPS URL with your owner
   token (never paste it into chat). Keep Tailscale connected.
5. Open **Remote** and press Retry if needed. It should no longer display a
   generic 404 when connected to the updated backend.
6. Open **Your workspaces → Projects and repositories**. Confirm you see a
   readable white/light project screen without a red Flutter error, the
   correct server-provided counts, project cards and working Search field.
7. Check that Cupertino-style icons in Remote and connected agent cards are
   visible rather than empty boxes.
8. From a Codex Cloud project, open the new-task form, enter an environment
   and prompt, then cancel or submit and verify the UI does not crash during
   dialog dismissal. **A submitted task still requires a separate approval**
   before any real provider action.

If your phone's Android version reports an APK signature mismatch, an app
uninstall may be required before reinstalling a differently signed debug APK.
Uninstalling deletes saved account connections on that device; do not do it
unless prompted or after saving any locally needed information.

## Important limitations

This patch corrects verified UI/runtime bugs; it does not magically add
permission to an existing ChatGPT website chat, Copilot panel, Cursor IDE tab
or arbitrary laptop desktop. Existing opt-in Claude/Copilot SDK bridges,
Cursor Cloud agent controls, VS Code companion, consented view-only screen
preview and Firebase push pathways retain their respective user-provisioning
and real-account acceptance requirements. Unattended screen streaming and
full mouse/keyboard control are **not provided** by this patch.

This release still uses the existing single-instance backend and user-owned
Tailscale/optional self-hosted cloud deployment. It is not a commissioned,
high-availability managed hosting service.

## Build policy

Changes are grouped into one pull request and **one native Android packaging
run** after automated Flutter/backend checks are green. CI test iterations
do not generate APKs. The v0.6.1 APK cannot be obtained merely by pulling
the repository on the phone; it must be installed from the release artifact.

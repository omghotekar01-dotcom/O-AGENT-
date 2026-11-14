# O-AGENT 0.8.0 — real VS Code workspace browser and text editor

## What is implemented

The owner phone can browse the actual folder enrolled in Visual Studio Code,
open supported text source files, edit their text, review a diff preview,
and request that VS Code save a file back to the laptop.

This is not a GitHub website approximation or a Copilot Chat takeover.
It requires **both** an updated Windows backend, an updated VS Code 0.3.0
companion, and the 0.8.0 mobile application.

## On the laptop: open the right folder

In VS Code select **File → Open Folder**. If your project is
`C:\Users\ASUS\OneDrive\Desktop\O Agent\O-AGENT-`, open that
**specific repository folder**, not its parent `O Agent`.

Then run **O-AGENT: Start Remote Workspace Companion** using the Command
Palette (`Ctrl+Shift+P`). The consent popup now includes the exact folder.
Choose **Enable** to allow the owner phone to list folders and read supported
files within that workspace only. The extension status bar should say
`O-AGENT: connected`.

## On Android: browse and read

Open **Remote → VS Code live file changes → Browse project files**.

Tap folders to open them or use the up arrow to go back. Tap a text file
to see its real content. The phone does not need you to type a relative
path. For this repository the Flutter entry file is
`apps/flutter/lib/main.dart`, **not** `lib/main.drt` unless another
project actually contains that name.

Read access is limited to an explicitly enrolled, trusted VS Code
workspace. Hidden/credential names, symlinks, binaries and files larger
than 48,000 characters are not accessible through this mobile editor.

## On the laptop: permit edits separately

In VS Code, `Ctrl+Shift+P` →
**O-AGENT: Enable Mobile File Editing (30 minutes)** →
**Enable for 30 minutes**.

This time-limited local opt-in is *separate* from workspace browsing
permission. It enables file editing only for the enrolled folder, not
arbitrary files on the device. Restarting/stopping the companion revokes it.

## On the phone: edit and save

Open a file under **Browse project files**. Tap **Edit text**.
Modify the text and tap **Review & save**. Inspect the line-level change
preview and choose **Save to laptop**. O-AGENT only sends the change to
VS Code after the explicit phone confirmation.

VS Code checks the version hash and refuses to overwrite a file that
has changed since mobile preview, or that has unsaved local editor edits.
The extension performs the save through VS Code's WorkspaceEdit and
document-save APIs. The result should report whether it actually saved.

File read/write payloads pass through a short-lived in-memory relay in
the private O-AGENT backend. They are not included in O-AGENT's persistent
task database, events or chat history, and expire after 90 seconds.

## Limits and safety

- **No unsupported claim**: The extension does not control VS Code Copilot
  Chat, Claude, arbitrary ChatGPT sessions, terminals or all device files.
- Supports text files up to 48,000 characters, one existing file at a time.
  It cannot create/delete/rename files or save binary media.
- Not an RDP editor, syntax-aware merge tool or full Git diff viewer. It
  previews proposed text changes and only saves to VS Code after consent.
- No arbitrary path traversal, external symlink access or access to hidden
  / credential files.
- For long-running or multi-file work, use the explicitly paired Windows
  desktop controller and normal desktop applications.

## Release gate

Run Node tests (including `tests/vscode-files.test.mjs`), VS Code
extension checks, Flutter analyze/tests and Windows launcher tests.
Then produce one consolidated APK and VSIX build. Physical
Windows/Android testing is still required before production deployment.

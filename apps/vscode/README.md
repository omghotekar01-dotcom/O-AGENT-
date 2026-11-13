# O-AGENT VS Code Companion

An opt-in extension for the owner of a trusted VS Code workspace.
This extension is **not** a VS Code chat takeover or remote desktop tool.

## Installation

**Do not double-click the `.vsix` file in Windows Explorer.** Windows
may launch the *Visual Studio 2022/2026* VSIXInstaller, which rejects this
**Visual Studio Code** extension with `NoApplicableSKUsException`.

After downloading and extracting the `o-agent-vscode-companion-vsix` artifact:

- Double-click `INSTALL-VSCODE-COMPANION.cmd` in your updated O-AGENT source
  folder. The installer uses the VS Code `code.cmd` command and searches the
  default extracted Downloads path.
- Or open **Visual Studio Code** (blue icon), then **Extensions →
  ... → Install from VSIX...** and choose the extracted `o-agent-vscode-companion.vsix`.
- Or run:
  `code --install-extension "%USERPROFILE%\\Downloads\\o-agent-vscode-companion-vsix\\o-agent-vscode-companion.vsix" --force`
  in a CMD shell with VS Code's `code` command installed.

Do not attempt installation into Visual Studio Community or Visual Studio Installer.

Download the ``o-agent-vscode-companion\` VSIX artifact from the consolidated
GitHub Actions release, then choose **Extensions → ... → Install from VSIX...**
in VS Code. You may also package it from source with
\`npx @vscode/vsce package --no-dependencies --skip-license --allow-missing-repository\`.

Open a trusted workspace. Run **O-AGENT: Configure Secure Companion** and enter
your private HTTPS backend origin and existing **worker** token. Credentials
are stored in VS Code SecretStorage, not in the extension package.

Run **O-AGENT: Start Remote Workspace Companion** and explicitly agree to the
local enrollment dialog. A visible status bar indicates active remote polling.
From the owner phone, choose Remote → VS Code companion. The phone must approve
the requested workspace-relative file path, then the local VS Code user must
also agree to open it. The extension does not copy file contents or edit files.

Stop polling with **O-AGENT: Stop Remote Workspace Companion**. To revoke a
token, rotate your worker token on both the server and trusted devices.

## Restrictions

Only root-level file/directory names can be inventoried; exact open-file
requests are resolved against real paths and checked for workspace escape.
The companion never controls Copilot Chat, Cursor tabs, external terminals,
the desktop mouse or keyboard, and it does not connect automatically.

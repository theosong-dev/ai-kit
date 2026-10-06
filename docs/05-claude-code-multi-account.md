# Claude Code with Multiple Accounts

English | [简体中文](zh-CN/05-Claude-Code-多账号.md)

Goal: run two Claude accounts side by side on one Mac, with sessions, memory, credentials, and browser kept apart.

The conclusions below were set up and verified in practice on macOS + Claude Code 2.1.274; points that were not verified are listed at the end.

## Conclusions

- Give each account its own config directory with `CLAUDE_CONFIG_DIR`, and use an alias to tell the entry points apart. This is the approach given in the official docs (the `env-vars` page).
- The CLI has no built-in account switching, only `/logout` + `/login`. Logging in back and forth in the same config directory mixes history, auto memory, and claude.ai connectors together, so it is not recommended.
- The Chrome integration is paired per **claude.ai account**, not per machine. If the second account needs a browser, it must have a second Chrome profile.

## Directory layout

| Item | Default account | Second account |
|---|---|---|
| Entry point | `claude` | `claude-2` (`~/.zshrc`: `alias claude-2="CLAUDE_CONFIG_DIR=$HOME/.claude-2 claude"`) |
| Config directory | `~/.claude` + `~/.claude.json` | `~/.claude-2` (`.claude.json` lives **inside** the directory) |
| Keychain entry | `Claude Code-credentials` | `Claude Code-credentials-<suffix>` (the suffix is added automatically per directory) |
| Chrome profile | `Default` | Create another (such as `Profile 3`) |

Inside `~/.claude-2` there are three kinds of items:

- **Shared by symlink** (linked to the same-named item in `~/.claude`): `agents/`, `hooks/`, `CLAUDE.md`, the status line script; under `skills/`, each skill is linked to its real directory. Change one place and both sides see it.
- **Do not link `skills/synced`**: it is a sync directory tied to the claude.ai account.
- **Copy `settings.json` instead of linking it**: Claude Code writes it back, which could wipe out a link; the two accounts may also want different permission allowlists and MCP settings. Absolute paths written in hooks (such as `~/.claude/hooks/guard.sh`) do not need changing.
- **Naturally isolated, do not share**: `.claude.json` (account, user-level MCP, project trust), `projects/` (sessions + auto memory), `plugins/`, `history.jsonl`.

One precondition makes this cheap: if skill bodies and global rules already live outside the host config directory (for example `~/.agents/skills`, `~/.ai/AGENTS.md`), then `~/.claude` is mostly symlinks and reusing it for a second directory costs little. Shared assets not living in the host config directory pays off a second time in a multi-account setup.

## Setup steps

1. Create the directory and symlinks, copy `settings.json`, and add the alias.
2. Run `CLAUDE_CONFIG_DIR=~/.claude-2 claude auth status` and confirm `configDirectory` points at the new directory and `loggedIn: false` (no leak from the old login).
3. Run `claude-2` and `/login` with the second account.
4. Verify both coexist: `security dump-keychain | grep '"svce"<blob>="Claude Code'` shows two entries; `claude auth status` on both sides reports `loggedIn: true`, each with the right subscription type.
5. Reinstall the plugins you need under the new directory (`settings.json` records them as enabled, but the plugin files are stored per config directory); re-authorize claude.ai connectors (Gmail / Drive / Notion, etc.) in the new account as needed.

## Chrome

- Basis: the docs say the Chrome integration is disabled when logged in with an API key / `setup-token`, because "the browser extension can't authenticate with those credentials"; the connection goes through the cloud bridge `bridge.claudeusercontent.com`. Testing agreed: in a default-account session, `list_connected_browsers` only shows the extension in its own profile, not the one paired with the second account.
- Procedure: Chrome avatar -> Add -> continue without signing in to Google -> name it and change the theme color; in the new window, sign in to the second account's claude.ai and reinstall the Claude in Chrome extension (extensions are installed per profile); quit Chrome with Cmd+Q and restart; run `claude-2 --chrome`, then Select browser in `/chrome`, and set "Enabled by default" if you want.
- If the matching profile's window is not open, that account has no browser to connect to, and it reports "Browser extension is not connected"; it does not fall back to the other profile. To launch a specific profile from the command line:

  ```bash
  open -na "Google Chrome" --args --profile-directory="Profile 3"   # claude-2
  open -na "Google Chrome" --args --profile-directory="Default"     # default account
  ```

- The native host config (`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json`) exists once per machine, and the two config directories take turns rewriting its `path`. The wrapper scripts on both sides have identical content (`exec claude --chrome-native-host`), so overwriting each other does not affect use; if one side reports not connected, use `/chrome` -> Reconnect extension.

## What is not isolated

- Tokens in `~/.zshrc`, other secret files, and ssh aliases are visible to both accounts alike. If you need a different GitHub identity, switch it at the entry point as well.
- Auto memory lives under `projects/` in the config directory, so opening the same repo under the other account does not show the other's memory. Put anything that must carry across accounts into the repo (such as `.ai/`).
- The desktop app and the claude.ai/code web app each log in independently, one account at a time, and are not affected by `CLAUDE_CONFIG_DIR`. The VS Code extension supports that variable (workspace `terminal.integrated.env.osx`).

## Options abandoned

- Switching accounts automatically by working directory (wrapping a `claude()` function that checks `$PWD`): the choice was just two aliases, which is explicit and has no hidden state.
- Sharing one Chrome profile between the two accounts: with per-account pairing, it either fails to connect or requires logging in back and forth in the extension, and cookies are not isolated.

## Not verified

- Whether the symlinked `agents/` and `hooks/` all load correctly in a `claude-2` session (no problems seen in use, but not confirmed item by item).
- The behavior of the background daemon (`~/.claude/daemon`) when both config directories coexist.
- Whether Claude Code launches Chrome automatically when it is not running (inferred from the docs' troubleshooting steps that it does not).

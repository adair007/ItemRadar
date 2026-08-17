# ItemRadar

[中文](README.md) · [Changelog](CHANGELOG.md)

A macOS menu bar app that discovers and manages local services (projects without a desktop client) — scan, one-click start/stop, and auto-open the web UI in your browser.

> The list only shows **startable** projects: a project appears only when its start command can be resolved. Projects whose command can't be resolved won't show up in the list (you must add a `command` manually to include them).

## Lightweight and power-efficient

ItemRadar is designed as a zero-distraction menu bar resident with deliberately minimal resource usage:

- **Near-zero CPU at idle**: no background polling; everything is event-driven (FSEvents watches the config file, timers fire on demand).
- **Opening the panel doesn't rescan**: clicking the menu bar icon only opens the panel — no file scan or port probe is triggered. A rescan happens only when you click "Refresh", add a new folder, or change the config.
- **No busy-wait threads**: after starting a service, web-URL detection is driven by a `DispatchSourceTimer` with incremental log parsing, and port waiting uses a 1-second interval — no long-held threads.
- **Batched system calls**: running-state detection pulls all listening ports in a single `lsof` call (rather than per-port queries), with a 5-second debounce.
- **Near-zero GPU usage**: pure native SwiftUI/AppKit — no animations, no WebView, no custom drawing.

> For lists of up to 50 projects, CPU and power draw at idle are effectively zero.

## Quick start

### 1. Install

Requires macOS 13+ and the Xcode command-line tools (`xcode-select --install`).

```sh
cd ~/Documents/deepseek/ProjectBar      # source directory
./build.sh                               # builds build/ItemRadar.app
cp -R build/ItemRadar.app ~/Applications/   # install to ~/Applications
open ~/Applications/ItemRadar.app        # launch
```

> After launch it appears in the **menu bar** (top-right corner, as a radar icon) and also in the **Dock**.
> After quitting, click the **Dock icon** or press `Command + Space` and search for `ItemRadar` to reopen it.

### 2. Open the panel

Click the **menu bar icon** → the ItemRadar panel pops up.

### 3. View your projects

The panel lists all **discovered startable projects**, each showing its **name · path · start command**.
To rescan, click the 🔄 **"Refresh"** button (top-right), or use 📁 **"Get from folder"** to add a new folder.

### 4. One-click start / stop

- Click the blue **"Start"** button on a project's right → the service starts; if it serves a web page, it **opens automatically in your default browser**.
- Running projects show a green "Running" status plus a red **"Stop"** button; click "Stop" to shut the service down.

### 5. Not finding a project?

- Click 📁 **"Get from folder"** (top-right) → pick the project's folder and rescan.
- Or click **"Add manually"** at the bottom → fill in the "Project location" and "Start command" ("Auto-detect" fills it in for you), then save.

### 6. Settings

Click ⚙ **"Settings"** (top-right) to: add/remove scan folders, toggle "Also scan home top level", and toggle "**Launch at login**".

### FAQ

| Problem | What to do |
|---|---|
| Nothing happens when I click Start | Check whether the button turned red "Stop" + green "Running"; failures show a red banner at the top |
| It opens the wrong page | Right-click the project → "Edit web URL…" and set the correct URL |
| I don't want the browser to auto-open | Right-click the project → turn off "Auto-open browser" |
| A project shouldn't be listed | Right-click the project → "Remove from list" |

---

## Features

- Menu bar icon: radar symbol
- Click the icon to open the panel: project list (name / path / start command) plus a "Start / Stop" button for each item
- After starting, **auto-detects the web URL and opens it in the browser** (see "Auto-open browser" below)
- 📁 **"Get from folder"** (top-right): opens a folder picker and scans it for startable projects
- ⚙ **"Settings"** (top-right): configure the scan scope (which folders get scanned) and toggle launch-at-login
- **"Add manually"** at the bottom: add a service by hand (for services the scanner can't detect, such as global CLI tools / injected runtimes); validates "path exists, command is usable, web URL format" as you fill it in
- The list supports **drag-to-reorder** (order is remembered)
- Right-click a project row:
  - "Show in Finder", "Open logs", "Open in browser"
  - "Edit start command…", "Edit web URL…", "Copy start command"
  - "Auto-open browser" toggle (per project)
  - "Remove from list"

## Installed locations

- App: `~/Applications/ItemRadar.app`
- Source / repo: https://github.com/adair007/ItemRadar
- Config: `~/.projectbar/config.json`
- Runtime state: `~/.projectbar/state.json`
- Service logs: `~/.projectbar/logs/`

## Default scan scope

- `~/Documents`, `~/Downloads`, `~/Desktop` (depth 3)
- Also scans the home directory top level (depth 1, covering `~/code`, `~/github`, etc.)

> ⚠️ The scanner only recognizes "project directories" (those containing characteristic files such as `package.json` / Python / Docker).
> Services that are "not directory projects" — like **global CLI tools** (`dsh`, `astrbot`) or **injected runtimes** (NapCat injected into QQ) — can't be detected by the scanner. Use "Add manually" at the bottom and fill in the start command and web URL.

## Auto-open browser

After clicking "Start", the app probes the service's web URL in the following order and opens it automatically:

1. The project has a manually configured `url` → use it directly.
2. Parse `http(s)://localhost:port`-style addresses from the start logs (waits up to ~10 seconds).
3. Use `lsof` to find the TCP ports the service's process tree is listening on → `http://localhost:port`.
4. If nothing is found → start only, don't open a browser, and show "No web URL detected".

> Bind addresses like `0.0.0.0` / `::` are automatically rewritten to `localhost`. Running projects also have an "Open in browser" button as a fallback.

## Config file `~/.projectbar/config.json`

```json
{
  "roots": ["~/Documents", "~/Downloads", "~/Desktop"],
  "scanDepth": 3,
  "scanHomeTopLevel": true,
  "projects": [
    {
      "name": "optional display name",
      "path": "~/path/to/project",
      "command": "optional, overrides the start command",
      "url": "optional, web URL, e.g. http://localhost:3000",
      "openBrowser": true,
      "enabled": true
    }
  ]
}
```

Fields:

| Field | Meaning |
|---|---|
| `roots` | List of project root directories to scan (supports `~`). |
| `scanDepth` | Scan depth: 1 = only the direct children of each root. |
| `scanHomeTopLevel` | Whether to also scan the home directory top level (depth 1); defaults to `true`. |
| `projects` | Manual project list; also the "override / exclude" mechanism. |

Each entry in `projects`:

| Field | Meaning |
|---|---|
| `name` | Display name (defaults to the directory name). |
| `path` | Absolute project path (supports `~`). |
| `command` | Manually specified start command; if empty, it's inferred automatically (if it can't be inferred, the project isn't shown). |
| `url` | Web URL; used to open the browser after start. |
| `openBrowser` | Whether to auto-open the browser; defaults to `true`. |
| `enabled` | `false` excludes the project (not shown, and also prevents auto-scan from matching it). |

### Start-command inference rules

1. `package.json` with a `dev` / `start` / `serve` script → uses the corresponding script (package manager resolved by `pnpm-lock.yaml`→pnpm, `yarn.lock`→yarn, `bun`→bun, otherwise npm).
2. `docker-compose.yml` etc. → `docker compose up`.
3. `manage.py` → `python3 manage.py runserver`; `app.py` / `main.py` → `python3 <file>`.
4. `Cargo.toml` → `cargo run`; `go.mod` → `go run .`.
5. `index.php` → `php -S localhost:8000`; `*.csproj` / `*.sln` → `dotnet run`.
6. `Gemfile` + Rails markers (`bin/rails` or `config/routes.rb`) → `bundle exec rails server`.
7. None of the above → the project **won't appear in the list**; add a `command` under `projects` to include it.

> Tip: the app auto-refreshes when the config file is saved — no restart needed. For projects that need a venv (e.g. ComfyUI), write the full command in `command`, for example `./venv/bin/python main.py`.

## Command-line usage (optional)

```sh
BIN=~/Applications/ItemRadar.app/Contents/MacOS/ItemRadar
"$BIN" --scan                 # list discovered projects
"$BIN" --start <path or name> # start
"$BIN" --stop  <path or name> # stop
"$BIN" --status <path or name># show running status
"$BIN" --test-url "<command>" # self-test: probe the web URL a command starts
```

## Rebuild

```sh
cd ~/Documents/deepseek/ProjectBar
./build.sh
cp -R build/ItemRadar.app ~/Applications/ && codesign --force --deep --sign - ~/Applications/ItemRadar.app
```

## Uninstall

```sh
launchctl unload ~/Library/LaunchAgents/local.itemradar.plist
rm -f ~/Library/LaunchAgents/local.itemradar.plist
rm -rf ~/Applications/ItemRadar.app
# rm -rf ~/.projectbar   # also removes config and logs
```

## Notes and limitations

- Only services **started by this app** are tracked; services started manually in a terminal won't show as running.
- Quitting the menu bar app doesn't kill the services it started; they keep running, and the app re-detects their status the next time it opens.
- "Stop" sends SIGTERM, then SIGKILL if still alive after 3 seconds, tearing down the entire process tree.
- If a process exits abnormally within 3 seconds of starting (likely a bad command), it reports "Exited abnormally".

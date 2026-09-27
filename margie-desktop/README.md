<div align="center">

# MARGIE for macOS

**A native application wrapper around the MARGIE front-end.**
<br>
Double-click an icon; choose **this computer** or **your HPC cluster**; no Terminal, no `git clone`, no Homebrew.

</div>

## What this is

`margie-desktop` packages the existing SvelteKit front-end (`../margie-fe`) as a signed macOS
`.app`, delivered in a `.dmg`. It is a **shell**, not a fork: it contains no MARGIE logic at all.

Choosing where MARGIE runs, connecting over SSH, answering ssh's password and two-factor
prompts, driving the pipeline, browsing results — all of that already exists in `margie-fe`
and keeps working exactly as it does under the `margie` terminal command. This project's whole
job is to start that code with the right paths and put a Mac window around it.

That is deliberate. The app and the terminal launcher share one codebase and one settings
file, so they can never disagree about where MARGIE runs.

## How it works

`margie-fe` is built with `adapter-node`. It is not a folder of static files — its
`/api/local` and `/api/connect` routes *are* the thing that drives the pipeline and the SSH
connection. So the app runs that server itself:

```
Electron main process
  ├── restores the PATH a GUI app does not inherit   (src/shell-env.js)
  ├── points the writable paths at Application Support (src/paths.js)
  ├── serves build/handler.js on 127.0.0.1:<random>  (src/server.js)
  └── opens a window on it, at /start?launch=1       (src/main.js)
```

Nothing listens on a public interface, and there is no second runtime to ship: Electron's main
process already is Node, so the SvelteKit server runs inside it.

### Three details that are easy to get wrong

**The window must load `127.0.0.1`, not a custom protocol.** `margie-fe/src/lib/config.ts`
only falls back to the HPC tunnel on `localhost:8000` when the page's hostname is a loopback
name. Under `app://` or `file://`, cluster mode silently loses its API.

**Everything writable lives outside the bundle.** A signed `.app` is read-only, and a file
written inside it breaks the signature. The pipeline, the connection state and the
logs all live under `~/Library/Application Support/MARGIE` and `~/Library/Logs/MARGIE`.

**The app carries margie-pipeline.** `npm run stage` puts the committed code of the
margie-pipeline checkout beside margie-frontend (or `MARGIE_PIPELINE_SRC`) in
`Resources/pipeline`, without its own GUI, stamped with its commit (`margie-bundle.json`). On
start, `src/pipeline.js` copies it to Application Support when it is not there or is from an older
build: files overwritten, nothing deleted, so outputs, databases, logs and
`gui/settings.local.json` stay. A git clone there (earlier versions made one) is left alone. So
local mode needs no git, no GitHub access and no network to get the pipeline. It does **not**
carry margie-build: building containers and databases uses the margie-build folder the user
points Settings at (`SETUP_REPO`), as the cluster uses `margie_sb.build_repo`.

**`ELECTRON_RUN_AS_NODE` must not be set.** Editors that are themselves Electron apps (VS Code,
and terminals it hosts) export it, and any Electron binary launched from such a shell starts as
plain Node instead — no window, and a crash that points nowhere near the cause.
`npm start` goes through `scripts/run-dev.mjs`, which strips it.

## Build and run

```bash
cd margie-desktop
npm install

npm start          # stage the front-end, then run the app from source
npm run pack       # build MARGIE.app only, no installer  → dist/mac-*/
npm run dist:arm64 # build a .dmg for Apple silicon        → dist/
npm run dist       # one universal .dmg (Apple silicon and Intel), dist/MARGIE-<version>-universal.dmg
npm run dist:win   # on Windows: x64 installer + x64/arm64 zips (see Windows below)
```

`npm run stage` is the interesting one. It builds `margie-fe`, then lays the result out the way
the bundle expects, in `.stage/gui`:

| | |
|---|---|
| `build/` | the adapter-node output (~7 MB) |
| `node_modules/` | **production dependencies only** (~60 MB, not the 260 MB dev tree) |
| `scripts/` | `hpc-connect.sh`, `margie-askpass.sh`, `margie-key.sh`, with their exec bits |

That folder is copied to `Contents/Resources/gui` and is deliberately **outside** the asar
archive: `hpc-connect.sh` is spawned by path and has to be a real file on disk.

The app icon is drawn, not stored — `npm run icon` renders a woven double helix at all ten
sizes macOS wants and hands them to `iconutil`. There is no binary asset to keep in sync.

## Windows

`npm run dist:win` builds, on Windows, `MARGIE-<version>-x64-setup.exe` (an installer for
ordinary PCs) and a zip for each of x64 and ARM64 (unzip, then run `MARGIE.exe`). It has to run
on Windows: the web app's build tools are native per platform. It was built and tested in a
Windows 11 ARM virtual machine (Parallels) with Node.js 22, Git for Windows and the Visual C++
runtime (without that runtime Rollup's native module will not load).

What differs from the Mac, and why:

- **Only the HPC.** "This computer" needs Linux for the pipeline (WSL on Windows), which the app
  does not set up yet; the start page says so and picks the HPC.
- **Git for Windows is required.** Windows cannot run `hpc-connect.sh`, so the app runs it in Git
  for Windows' bash (`margie-fe/src/lib/connect/shell.ts`), whose ssh, curl and coreutils the
  scripts use. Not WSL's bash: that runs inside Linux, where Windows paths and localhost differ.
- **The password question comes back through a file**, read and deleted at once, not a named pipe:
  none can pass between a Windows program and Git Bash (`MARGIE_ASKPASS_POLL`).
- **Stopping is a file too** (`hpc-connect.stop`): Windows has no signals for that bash, and ending
  it outright would skip the exit handler that stops the server on the HPC.
- **MARGIE's key goes on the HPC at the first sign-in.** Git for Windows' ssh keeps a master
  connection but cannot run commands through it; each one signs in again. With the key installed
  straight after the first sign-in, a first connect asks twice and later ones not at all
  (`MARGIE_NO_MUX`).
- **No installer for Windows on ARM.** The NSIS installer is an x86 program; emulated on ARM it
  unpacks everything except `MARGIE.exe` and the DLLs. The ARM64 zip works.
- **Unsigned.** Windows SmartScreen warns on first run until the app is signed.

## Signing and notarization

`electron-builder.yml` ships with `notarize: false`, so a local build works with no Apple
account. For a release you need a **Developer ID Application** certificate ($99/yr Apple
Developer Program):

```bash
export APPLE_ID="you@example.com"
export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"   # appleid.apple.com → App-Specific Passwords
export APPLE_TEAM_ID="XXXXXXXXXX"

npm run dist:arm64 -- --config.mac.notarize=true
```

Without notarization macOS quarantines the download, and the first launch needs a
right-click → **Open** (or `xattr -dr com.apple.quarantine /Applications/MARGIE.app`).

The app uses the **hardened runtime but not the App Sandbox**, and `build/entitlements.mac.plist`
explains why: MARGIE runs `ssh` against the user's cluster, reads their `~/.ssh` keys, runs
the pipeline's scripts, and reads and writes genome data wherever the user keeps it. The sandbox
exists to prevent exactly that. Hardened-runtime-without-sandbox is both notarizable and honest.

## Where things go

| | |
|---|---|
| `~/Library/Application Support/MARGIE/margie-pipeline` | the pipeline, copied from the app on start (its outputs, databases and logs live here too) |
| `~/Library/Application Support/MARGIE/state` | `hpc-connect.sh`'s pid, progress, and ssh's pending questions |
| `~/Library/Logs/MARGIE/main.log` | what the app did — **Help → Open Log Folder** |
| `~/.config/margie/margie.env` | where MARGIE runs. **Shared with the `margie` terminal command, on purpose.** |

The last one is the only thing written outside the Mac-standard locations, and it is
intentional: it is the same file `setup.sh` writes and `~/bin/margie` reads.

## What this needed from `margie-fe`

One line, in `src/lib/connect/local.ts`:

```ts
export const PIPELINE_HOME =
	expandHome(process.env.MARGIE_PIPELINE_HOME || '') || path.resolve(APP_DIR, '..', 'margie-pipeline');
```

`clonePipeline()` otherwise targets `<app>/../margie-pipeline`, which inside a bundle is
read-only. Everything else the app needs — `MARGIE_STATE_DIR`, `MARGIE_PIPELINE_ROOT`, `PORT`,
`HOST`, `ORIGIN` — was already an environment variable the front-end respected.

`lib/connect/` is `margie-fe`-only, so this change does **not** need mirroring into
`margie-pipeline/gui/src`. The shared interface files are untouched.

## Known constraints

**Local mode needs a container runtime**, not Python. `margie-backend` is the *cluster*
backend and runs on the login node; "this computer" mode is served by the front-end's own
`/api/local` routes driving `margie-pipeline`. On macOS that means Apple's `container`, Docker
Desktop, or Podman — `margie-fe/src/lib/server/platform.ts` already detects and starts all
three, and deliberately excludes Apptainer as Linux-only.

**Disk, not app size.** The DMG is small, but a local annotation run pulls container images and
reference databases that run to tens of gigabytes.

**SIGTERM does not reach the app on macOS.** Chromium installs its own handlers in the browser
process. Every way a person actually quits — Cmd-Q, the Dock, logging out — arrives as a Quit
Apple Event and is handled, which is what closes the SSH tunnel and stops the backend on the
cluster. If the app is force-quit, `hpc-connect.sh` keeps running and the next launch shows the
connection as still open, with the option to stop it.

## Layout

```
margie-desktop/
├── src/
│   ├── main.js           app lifecycle, window, quit → close the HPC connection
│   ├── electron.js       the one place that touches the 'electron' module (see its comment)
│   ├── server.js         the SvelteKit server, in-process on a loopback port
│   ├── paths.js          Application Support / Logs / the staged front-end
│   ├── shell-env.js      the PATH a Finder-launched app does not inherit
│   ├── settings.js       reads ~/.config/margie/margie.env
│   ├── hpc.js            stops hpc-connect.sh and its process group on quit
│   ├── menu.js           the menu bar (without it, Cmd-C does nothing)
│   └── window-state.js   remembers where the window was
├── scripts/
│   ├── stage.mjs         builds margie-fe and lays out .stage/gui
│   ├── make-icon.mjs     draws icon.icns from scratch
│   └── run-dev.mjs       launches Electron with ELECTRON_RUN_AS_NODE stripped
├── build/
│   └── entitlements.mac.plist
└── electron-builder.yml
```

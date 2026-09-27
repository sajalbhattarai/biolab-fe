<div align="center">

# MARGIE | Graphical User Interface (GUI)

**Mostly Automated Rapid Genome Inference Environment**
<br>
Start a genome-annotation run on your computer or your HPC cluster, watch it, and read your results — in the MARGIE desktop app or your web browser.
<br>
Runs on **macOS** | **Windows** | **Linux**.
<br><br>
[![Live App](https://img.shields.io/badge/Live_App-Open-2ea44f?style=for-the-badge)](https://bsp.anvilcloud.rcac.purdue.edu/)
[![Backend](https://img.shields.io/badge/Backend-bioinformatics--tools-1f6feb?style=for-the-badge)](https://github.com/sajalbhattarai/bioinformatics-tools/tree/margie-backend)
[![Built with SvelteKit](https://img.shields.io/badge/Built_with-SvelteKit-ff3e00?style=for-the-badge&logo=svelte&logoColor=white)](https://kit.svelte.dev/)

<a href="#download"><b>Download the App</b></a> &nbsp;|&nbsp;
<a href="#build-from-source"><b>Build from Source</b></a> &nbsp;|&nbsp;
<a href="#run-mac"><b>How To Run - Mac</b></a> &nbsp;|&nbsp;
<a href="#run-linux"><b>How To Run - Linux</b></a> &nbsp;|&nbsp;
<a href="#run-windows"><b>How To Run - Windows</b></a> &nbsp;|&nbsp;
<a href="#first-run"><b>First Run: This Computer or the HPC</b></a> &nbsp;|&nbsp;
<a href="#further-details"><b>Further Details</b></a>

</div>

## Repo scope

This is the **`margie-frontend`** branch of biolab-fe: MARGIE's interface, desktop app and local pipeline.

| Folder | What it is |
|---|---|
| `margie-fe/` | The interface (SvelteKit): pages, the HPC connection, and the server that drives runs. |
| `margie-desktop/` | The desktop app for macOS and Windows (Electron), built around `margie-fe`. |
| `margie-pipeline/` | The annotation pipeline MARGIE runs on this computer (bash, containers, Python). |

The HPC side (pipeline, CLI, API) lives in **[bioinformatics-tools, branch `margie-backend`](https://github.com/sajalbhattarai/bioinformatics-tools/tree/margie-backend)**.

<a id="download"></a>

## Download the app

The easiest way to use MARGIE: install the desktop app from **[Releases](https://github.com/sajalbhattarai/biolab-fe/releases)**.

| System | File |
|---|---|
| macOS (Apple silicon and Intel) | `MARGIE-<version>-universal.dmg` (or `-arm64.dmg` for Apple silicon only) |
| Windows (64-bit PC) | `MARGIE-<version>-x64-setup.exe` |
| Windows on ARM | `MARGIE-<version>-arm64-win.zip` (unzip, then run `MARGIE.exe`) |

The apps are not yet signed, so the first launch asks for confirmation:
- **macOS:** right-click MARGIE in Applications, choose **Open**, then **Open** again.
- **Windows:** in the SmartScreen notice, choose **More info → Run anyway**.

MARGIE opens on its start page: choose **This computer** or **Your HPC cluster** (see [First run](#first-run)).
- **HPC:** works as soon as you connect.
- **This computer:** the **Install** page sets up the analysis tools and their reference data. It opens once you type this statement exactly (pasting is not allowed): *I have the necessary licenses for the upstream tools and accept the license terms agreement of MARGIE.* This needs the MARGIE build recipes (`margie-build`), which are currently available to reviewers on request. Each tool's licence is shown and accepted by you during installation.

<a id="build-from-source"></a>

## Build the app from source

Needs Node.js 22 or newer and git.

```bash
git clone -b margie-frontend https://github.com/sajalbhattarai/biolab-fe.git
cd biolab-fe/margie-desktop
npm ci
npm start                 # runs the app without packaging it
npm run dist:arm64        # macOS, Apple silicon: dist/MARGIE-<version>-arm64.dmg
npm run dist              # macOS, universal .dmg
npm run dist:win          # on Windows: x64 installer and x64/arm64 zips
```

The build takes the pipeline from `margie-pipeline/` in this branch. See [margie-desktop/README.md](margie-desktop/README.md) for details.

<a id="run-mac"></a>

## HOW TO RUN --MAC USERS

These steps run MARGIE from source in your browser. To use the desktop app instead, see [Download the app](#download).

1. Open Terminal.

2. Install required tools.
If you already have Homebrew:

```bash
brew install node git curl
```

If Homebrew is missing, install it first:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install node git curl
```

If you do not want Homebrew, install from official sources:

- Node.js: https://nodejs.org/
- Git: https://git-scm.com/downloads/mac
- curl (already included with macOS): https://curl.se/
- OpenSSH (already included with macOS): https://www.openssh.com/

3. Verify tools.

```bash
node --version
git --version
ssh -V
curl --version
```

4. Clone and run MARGIE.

```bash
git clone -b margie-frontend https://github.com/sajalbhattarai/biolab-fe.git
cd biolab-fe
./setup.sh --check
./setup.sh          # prepares this computer, then opens MARGIE's start page
```

Next time, just run `margie`.

5. MARGIE opens on its start page. Choose where it runs, **this computer** or **your HPC cluster**, as described in [First run](#first-run).

If you use the HPC, after first login open Profile in the GUI and review workflow paths:

- Shared pipeline paths such as `sif_path`, `db_root`, fingerprint database, operon database, genome pool, historical scoring, final tables, and sqlite snapshot paths are prefilled with shared depot defaults.
- Set `input_path` and `output_path` to your own scratch or working directories.
- If you want to inspect or edit the live config file directly, open the **File Explorer** page in the GUI, go to `~/.config/bioinformatics-tools/`, and edit `config.yaml` there.
- The same config also contains per-tool resource settings such as threads, memory, runtime, and partition overrides.
- GTDB-Tk should remain on the `highmem` partition because it loads a very large reference database into memory.

<a id="run-linux"></a>

## HOW TO RUN --LINUX USERS

1. Open a terminal on your Linux machine.

2. Install required tools.

```bash
sudo apt update
sudo apt install -y git openssh-client curl
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt install -y nodejs
```

3. Verify tools.

```bash
node --version
git --version
ssh -V
curl --version
```

4. Clone and run MARGIE.

```bash
git clone -b margie-frontend https://github.com/sajalbhattarai/biolab-fe.git
cd biolab-fe
./setup.sh --check
./setup.sh          # prepares this computer, then opens MARGIE's start page
```

Next time, just run `margie`.

5. MARGIE opens on its start page. Choose where it runs, **this computer** or **your HPC cluster**, as described in [First run](#first-run).

If you use the HPC, after first login open Profile in the GUI and review workflow paths:

- Shared pipeline paths such as `sif_path`, `db_root`, fingerprint database, operon database, genome pool, historical scoring, final tables, and sqlite snapshot paths are prefilled with shared depot defaults.
- Set `input_path` and `output_path` to your own scratch or working directories.
- If you want to inspect or edit the live config file directly, open the **File Explorer** page in the GUI, go to `~/.config/bioinformatics-tools/`, and edit `config.yaml` there.
- The same config also contains per-tool resource settings such as threads, memory, runtime, and partition overrides.
- GTDB-Tk should remain on the `highmem` partition because it loads a very large reference database into memory.

<a id="run-windows"></a>

## HOW TO RUN --WINDOWS USERS

For the desktop app, use the Windows installer from [Download the app](#download). The steps below run MARGIE from source inside WSL (Linux on Windows), which is also what running analyses on a Windows computer needs.

1. Open PowerShell as Administrator and install WSL + Ubuntu.

```powershell
wsl --install -d Ubuntu
```

2. Restart Windows if prompted.

3. Open Ubuntu.

- Start Menu -> search "Ubuntu" -> open it
- Complete first-run Linux username/password setup

4. Install required tools inside Ubuntu.

```bash
sudo apt update
sudo apt install -y git openssh-client curl
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt install -y nodejs
```

Official package references:

- Ubuntu packages (apt): https://packages.ubuntu.com/
- NodeSource setup script: https://github.com/nodesource/distributions

5. Verify tools inside Ubuntu.

```bash
node --version
git --version
ssh -V
curl --version
```

6. Clone and run MARGIE inside Ubuntu.

```bash
git clone -b margie-frontend https://github.com/sajalbhattarai/biolab-fe.git
cd biolab-fe
./setup.sh --check
./setup.sh          # prepares this computer, then opens MARGIE's start page
```

Next time, just run `margie`.

7. MARGIE opens on its start page. Choose where it runs, **this computer** or **your HPC cluster**, as described in [First run](#first-run).

If you use the HPC, after first login open Profile in the GUI and review workflow paths:

- Shared pipeline paths such as `sif_path`, `db_root`, fingerprint database, operon database, genome pool, historical scoring, final tables, and sqlite snapshot paths are prefilled with shared depot defaults.
- Set `input_path` and `output_path` to your own scratch or working directories.
- If you want to inspect or edit the live config file directly, open the **File Explorer** page in the GUI, go to `~/.config/bioinformatics-tools/`, and edit `config.yaml` there.
- The same config also contains per-tool resource settings such as threads, memory, runtime, and partition overrides.
- GTDB-Tk should remain on the `highmem` partition because it loads a very large reference database into memory.

If browser does not open automatically, open `http://localhost:5173`.

<a id="first-run"></a>

## FIRST RUN: CHOOSING WHERE MARGIE RUNS

`./setup.sh` only prepares this computer (Node.js, the `margie` command, your PATH). MARGIE then opens on its **start page**, which asks where it should run. It remembers your answer: after this, `margie` goes straight to it. To choose again, run `margie --choose`, or open **Customize → Where MARGIE runs → Change** in the app.

Your choices are kept in `~/.config/margie/margie.env`, which both `setup.sh` and the start page update.

### This computer

Uses your computer's own cores, memory and disk. No account and no HPC login.

1. Click **This computer**. MARGIE looks for its pipeline (`margie-pipeline`, next to the app).
2. If it is not there, click **Download the pipeline**, or point MARGIE at a copy you already have.
3. Click **Open MARGIE on this computer**. The **Install** page then sets up the container app, the tools and their reference data.

### Your HPC cluster

1. Click **Your HPC cluster** and enter:
   - your HPC username (for example: `abc`)
   - the HPC's address (for example: `cluster.university.edu`)
   - MARGIE's backend folder on the HPC. The default is `/home/<username>/bioinformatics-tools`, which is where jobs run the pipeline from. If the folder does not exist yet, the HPC clones the backend there and installs it (see [Which code the HPC runs](#hpc-code)).
2. Click **Connect**. Your HPC's own sign-in questions appear on the page, exactly as ssh words them: your password, then two-factor if your cluster uses it (for Duo, type the option number and approve on your phone). MARGIE then finds a free login node, prepares and starts its server there, and opens a secure tunnel to it.
3. **Passwordless login (recommended, once).** MARGIE's server runs your jobs over SSH with a key, and with that key on the HPC you stop typing your password every time MARGIE starts.
   - **Set it up for me:** makes a key just for MARGIE (`~/.ssh/margie_ed25519`, so your everyday key stays yours). It then adds the key's public half to `~/.ssh/authorized_keys` on the HPC over the connection you just made, so there is nothing more to type.
   - **Show me how:** gives you the same steps as commands to run yourself (`ssh-keygen`, `ssh-copy-id`, and a check).
   - Some clusters ask for two-factor even with a key. MARGIE then still asks, but only for that.
4. **Your MARGIE account.** Sign in, or create one. A new account uses the key from step 3, read on this computer and handed to MARGIE's server; you can also paste a private key.

Closing `margie` (Ctrl-C) disconnects: it stops MARGIE's server on the HPC and closes the tunnel. Running workflows are left alone.

<a id="hpc-code"></a>

#### Which code the HPC runs

The HPC runs MARGIE's backend: the code in **[bioinformatics-tools, branch `margie-backend`](https://github.com/sajalbhattarai/bioinformatics-tools/tree/margie-backend)**. As in earlier versions, the HPC fetches it from GitHub itself once you are signed in: it clones it into your home folder, and fetches from GitHub to update it. So the repository must be public.

- **Push first.** The HPC gets what GitHub has. When a checkout of margie-backend sits beside `margie-frontend` on your computer, its current branch is the one used. The start page shows its state before you connect: uncommitted files, commits GitHub does not have, or a branch that is not on GitHub yet. It offers **Push**, or **Commit all and push** with a message you write. `margie --hpc` offers the same in the terminal. Connecting stops, and says why, while the branch is not on GitHub.
- **Asked, never overwritten.** Suppose the backend folder on the HPC is in the way: a broken link, a file, a folder of something else, or a copy of another repository. MARGIE then asks whether to replace it. Replacing moves it aside as `<folder>.old-<date>`; nothing is deleted.
- **Updates.** If the copy on the HPC is behind GitHub, or on another branch, MARGIE asks whether to update it, and restarts its server on the new code. A clean restart updates without asking. A copy with uncommitted changes of its own is left alone.
- **The pipeline runs it too.** Jobs run the pipeline from `~/bioinformatics-tools` on the HPC. If the backend folder is elsewhere, that path is pointed at it; if it is a separate real folder, you are asked first and it is moved aside. The backend is also told which branch it runs (`BSP_MARGIE_SB_REF`), so its own update check before each run keeps to that branch.

To use another repository or branch, set `BACKEND_REPO_URL` and `BACKEND_BRANCH` in `~/.config/margie/margie.env`.

### The terminal way

The same choices can be made in a terminal instead:

- `./setup.sh --local` or `./setup.sh --hpc` answers the start page's question during setup. `--hpc` also asks for the HPC details and offers to set up passwordless login there.
- `margie --local` goes straight to this computer for one run.
- `margie --hpc` connects from the terminal, as earlier versions did. The password and two-factor prompts appear there, and you choose between a safe reattach and a clean restart.

<a id="further-details"></a>

## Further details

### Installation sources and citations

The setup steps above rely on these original projects and package sources:

- Windows Subsystem for Linux (Microsoft): https://learn.microsoft.com/windows/wsl/install
- Ubuntu (Canonical): https://ubuntu.com/wsl
- Homebrew: https://brew.sh/
- Node.js: https://nodejs.org/
- NodeSource distributions: https://github.com/nodesource/distributions
- Git: https://git-scm.com/
- OpenSSH: https://www.openssh.com/
- curl: https://curl.se/
- Debian/Ubuntu package index: https://packages.ubuntu.com/

### AI usage in the project

Phase 9-12 scripts were designed and implemented by **Sajal Bhattarai**.
During script development, **Claude Sonnet 4.6** was used in interactive mode to improve robustness and debug issues.
The core ideas, architecture, and intended behavior were defined by Sajal Bhattarai.
These scripts were manually validated for intended behavior.

Visualization and LLM work, including the operon circular diagram page, HTML creation, and interactive chat mode, were refined with interactive-mode assistance from **Claude Opus 4.8**.
These components were also manually checked and validated for intended purpose.

### Disclaimer

This software is provided "as is", without warranty of any kind, express or implied, including but not limited to warranties of merchantability, fitness for a particular purpose, and noninfringement.

### Cite This Repository

APA 7th (software):

Bhattarai, S., Deemer, D., & Lindemann, S. (2026). *MARGIE: Mostly Automated Rapid Genome Inference Environment* (biolab-fe, branch margie-frontend) [Computer software]. https://github.com/sajalbhattarai/biolab-fe

Use the exact version you ran by checking repository Releases, and include that release version number in your citation.

Please also cite the individual tools and databases you use in the MARGIE pipeline, in accordance with their licensing and referencing requirements. The licensing gates during MARGIE runs provide the relevant licensing details, but you should still cross-check and confirm the requirements before publication.

For machine-readable repository metadata, see [CITATION.cff](CITATION.cff).

## Acknowledgements

I (Sajal) gratefully acknowledge Dane Deemer ([wintermutant](https://github.com/wintermutant)) for his mentoring, and the design and development of the engine and GUI orchestration platform on which the MARGIE(SB) workflow was built. 

Special thanks goes to Dr. Stephen R Lindemann for his vision, supervision and support throughout this development.
I also thank members of Diet-Microbiome-Interactions Laboratory for their feedbacks and intellectual inputs during this development.

We thank Purdue RCAC for providing the research computing environment that supports this work.

We also thank the developers and maintainers of the upstream tools, databases, and scientific software used throughout the pipeline. Their contributions make reproducible computational biology more powerful, more accessible, and more exciting to do.


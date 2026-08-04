<div align="center">

# MARGIE | Graphical User Interface (GUI)

**Mostly Automated Rapid Genome Inference Environment**
<br>
Start a genome-annotation run, watch it on the cluster, and read your results — all from your web browser.
<br>
Runs on **macOS** | **Windows** | **Linux**.
<br><br>
[![Live App](https://img.shields.io/badge/Live_App-Open-2ea44f?style=for-the-badge)](https://bsp.anvilcloud.rcac.purdue.edu/)
[![Backend](https://img.shields.io/badge/Backend-bioinformatics--tools-1f6feb?style=for-the-badge)](https://github.com/sajalbhattarai/bioinformatics-tools)
[![Built with SvelteKit](https://img.shields.io/badge/Built_with-SvelteKit-ff3e00?style=for-the-badge&logo=svelte&logoColor=white)](https://kit.svelte.dev/)

<a href="#run-mac"><b>How To Run - Mac</b></a> &nbsp;|&nbsp;
<a href="#run-linux"><b>How To Run - Linux</b></a> &nbsp;|&nbsp;
<a href="#run-windows"><b>How To Run - Windows</b></a> &nbsp;|&nbsp;
<a href="#further-details"><b>Further Details</b></a>

</div>

## Repo scope

This repository is the **frontend** repository for MARGIE.
It contains GUI code and launcher/setup flow for browser-based usage.
It does **not** contain backend pipeline implementation details.

For backend pipeline, CLI, API, and backend runtime/config details, use **[bioinformatics-tools](https://github.com/sajalbhattarai/bioinformatics-tools)**.

<a id="run-mac"></a>

## HOW TO RUN --MAC USERS

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
git clone https://github.com/sajalbhattarai/biolab-fe.git
cd biolab-fe
./setup.sh --check
./setup.sh
margie
```

5. During setup, enter HPC login details when prompted:

- HPC username (for example: abc)
- HPC address (for example: cluster.university.edu)
- BACKEND_DIR path (press Enter to accept default)

After first login, open Profile in the GUI and review workflow paths:

- Shared pipeline paths such as `sif_path`, `db_root`, fingerprint database, operon database, genome pool, historical scoring, final tables, and sqlite snapshot paths are prefilled with shared depot defaults.
- Set `input_path` and `output_path` to your own scratch or working directories.
- If you want to inspect or edit the live config file directly, open the **File Explorer** page in the GUI, go to `~/.config/bioinformatics-tools/`, and edit `config.yaml` there.
- The same config also contains per-tool resource settings such as threads, memory, runtime, and partition overrides.
- GTDB-Tk should remain on the `highmem` partition because it loads a very large reference database into memory.

If the backend folder does not exist yet on the HPC, MARGIE automatically clones `bioinformatics-tools` into the `BACKEND_DIR` path you provide.

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
git clone https://github.com/sajalbhattarai/biolab-fe.git
cd biolab-fe
./setup.sh --check
./setup.sh
margie
```

5. During setup, enter HPC login details when prompted:

- HPC username (for example: abc)
- HPC address (for example: cluster.university.edu)
- BACKEND_DIR path (press Enter to accept default)

After first login, open Profile in the GUI and review workflow paths:

- Shared pipeline paths such as `sif_path`, `db_root`, fingerprint database, operon database, genome pool, historical scoring, final tables, and sqlite snapshot paths are prefilled with shared depot defaults.
- Set `input_path` and `output_path` to your own scratch or working directories.
- If you want to inspect or edit the live config file directly, open the **File Explorer** page in the GUI, go to `~/.config/bioinformatics-tools/`, and edit `config.yaml` there.
- The same config also contains per-tool resource settings such as threads, memory, runtime, and partition overrides.
- GTDB-Tk should remain on the `highmem` partition because it loads a very large reference database into memory.

If the backend folder does not exist yet on the HPC, MARGIE automatically clones `bioinformatics-tools` into the `BACKEND_DIR` path you provide.

<a id="run-windows"></a>

## HOW TO RUN --WINDOWS USERS

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
git clone https://github.com/sajalbhattarai/biolab-fe.git
cd biolab-fe
./setup.sh --check
./setup.sh
margie
```

7. During setup, enter HPC login details when prompted:

- HPC username (for example: abc)
- HPC address (for example: cluster.university.edu)
- BACKEND_DIR path (press Enter to accept default)

After first login, open Profile in the GUI and review workflow paths:

- Shared pipeline paths such as `sif_path`, `db_root`, fingerprint database, operon database, genome pool, historical scoring, final tables, and sqlite snapshot paths are prefilled with shared depot defaults.
- Set `input_path` and `output_path` to your own scratch or working directories.
- If you want to inspect or edit the live config file directly, open the **File Explorer** page in the GUI, go to `~/.config/bioinformatics-tools/`, and edit `config.yaml` there.
- The same config also contains per-tool resource settings such as threads, memory, runtime, and partition overrides.
- GTDB-Tk should remain on the `highmem` partition because it loads a very large reference database into memory.

If the backend folder does not exist yet on the HPC, MARGIE automatically clones `bioinformatics-tools` into the `BACKEND_DIR` path you provide.

If browser does not open automatically, open `http://localhost:5173`.

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

Bhattarai, S., Deemer, D., & Lindemann, S. (2026). *biolab-fe* [Computer software]. https://github.com/sajalbhattarai/biolab-fe

Use the exact version you ran by checking repository Releases, and include that release version number in your citation.

Please also cite the individual tools and databases you use in the MARGIE pipeline, in accordance with their licensing and referencing requirements. The licensing gates during MARGIE runs provide the relevant licensing details, but you should still cross-check and confirm the requirements before publication.

For machine-readable repository metadata, see [CITATION.cff](CITATION.cff).

## Acknowledgements

I (Sajal) gratefully acknowledge Dane Deemer ([wintermutant](https://github.com/wintermutant)) for his mentoring, and the design and development of the engine and GUI orchestration platform on which the MARGIE(SB) workflow was built. 

Special thanks goes to Dr. Stephen R Lindemann for his vision and support throughout this development.
I also thank members of Diet-Microbiome-Interactions Laboratory for their feedbacks and intellectual inputs during this development.

We thank Purdue RCAC for providing the research computing environment that supports this work.

We also thank the developers and maintainers of the upstream tools, databases, and scientific software used throughout the pipeline. Their contributions make reproducible computational biology more powerful, more accessible, and more exciting to do.


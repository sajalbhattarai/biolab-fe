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

## HOW TP RUN --MAC USERS

Requirements:

- HPC account with SSH access
- Node.js 20.19+ (or 22.12+ or 24+)
- Git
- SSH client
- curl

Install tools (Homebrew):

```bash
brew install node git curl
```

Run:

```bash
git clone https://github.com/sajalbhattarai/biolab-fe.git
cd biolab-fe
./setup.sh --check
./setup.sh
margie
```

If the backend folder does not exist yet on the HPC, MARGIE automatically clones `bioinformatics-tools` into the `BACKEND_DIR` path you provide.

<a id="run-linux"></a>

## HOW TP RUN --LINUX USERS

Requirements:

- HPC account with SSH access
- Node.js 20.19+ (or 22.12+ or 24+)
- Git
- SSH client
- curl

Install tools (Ubuntu/Debian):

```bash
sudo apt update
sudo apt install -y git openssh-client curl
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt install -y nodejs
```

Run:

```bash
git clone https://github.com/sajalbhattarai/biolab-fe.git
cd biolab-fe
./setup.sh --check
./setup.sh
margie
```

If the backend folder does not exist yet on the HPC, MARGIE automatically clones `bioinformatics-tools` into the `BACKEND_DIR` path you provide.

<a id="run-windows"></a>

## HOW TP RUN --WINDOWS USERS

Requirements:

- WSL 2 with Ubuntu
- HPC account with SSH access
- Node.js 20.19+ (or 22.12+ or 24+) inside WSL
- Git, SSH client, curl inside WSL

Install WSL (PowerShell as Administrator):

```powershell
wsl --install -d Ubuntu
```

After restart, open Ubuntu and install tools:

```bash
sudo apt update
sudo apt install -y git openssh-client curl
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt install -y nodejs
```

Run in Ubuntu:

```bash
git clone https://github.com/sajalbhattarai/biolab-fe.git
cd biolab-fe
./setup.sh --check
./setup.sh
margie
```

If the backend folder does not exist yet on the HPC, MARGIE automatically clones `bioinformatics-tools` into the `BACKEND_DIR` path you provide.

If browser does not open automatically, open:

```text
http://localhost:5173
```

<a id="further-details"></a>

## Further details

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


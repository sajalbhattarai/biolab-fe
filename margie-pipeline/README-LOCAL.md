# The pipeline this app runs on your computer

This folder is a copy of `margie-pipeline`, source only: the scripts, the
container recipes and the host scripts, and none of the data. It is what
"Use MARGIE locally" runs, driven by the app beside it (`margie-fe`) through
its routes under `src/routes/api/local`.

Nothing large is copied. `db/`, `output/`, `input/`, `user-input/`, `logs/`
and `processing/containers/sifs/` start empty, and the app points at whatever
folders you name in **Settings → Folders**. If you already have the databases
and images somewhere — from running `margie-pipeline` directly, say — point
`DB_ROOT` and `SIF_DIR` at them rather than downloading 170 GB again. The
build recipes (`SETUP_REPO`) are the `margie-build` checkout.

What this means day to day:

- **A run here is a real run.** `annotate.sh` is executed on this computer,
  with your container runtime, your databases and your cores — exactly as it
  is when you run the pipeline from a terminal.
- **The app is the only thing that changed.** Every script in this folder is
  the pipeline's own; if you improve something in `margie-pipeline`, copy it
  here (or copy this folder back) rather than editing one and forgetting the
  other.
- **Cluster mode is untouched.** It still talks to MARGIE's API over SSH; this
  folder is never used for it.

# The Croc flow project

This directory is an edarunner project for the
[Croc SoC](https://github.com/pulp-platform/croc) at tag `v2.0.0`. It runs
Croc's own scripts from the RTL to a GDS file and a DRC report, either in
the IIC-OSIC-TOOLS image 2025.12 or with natively installed tools. The
walkthrough in the top-level `README.md` shows how to run it.

## Layout

```
edarunner-example/
  rtl/          the Croc clone, with the PDK submodule in ihp13/pdk
  rtl-wt/       one worktree per commit, created by `edr checkout`
  croc/         this project
    data/       the run database, the collected results and the board
```

In `edr.toml`, `source.repo` points at `../rtl` and `source.worktrees` at
`../rtl-wt`. If you give the project its own backend repository, keep the
same arrangement: the RTL clone sits next to the project, never inside it.

## Stages

Each stage calls one of Croc's scripts in its own directory. Every call
starts the tool, runs a single step and saves a checkpoint, so when a
stage fails, the work of the stages before it is still there.

| Stage | Directory | Command | Checked output |
|---|---|---|---|
| `synth` | `yosys/` | `run_synthesis.sh --synth` | `out/croc_yosys.v` |
| `floorplan` | `openroad/` | `run_backend.sh --floorplan` | `save/01_croc.floorplan.zip` |
| `place` | `openroad/` | `run_backend.sh --placement` | `save/02_croc.placed.zip` |
| `cts` | `openroad/` | `run_backend.sh --cts` | `save/03_croc.cts.zip` |
| `route` | `openroad/` | `run_backend.sh --routing` | `save/04_croc.routed.zip` |
| `finishing` | `openroad/`, `klayout/` | `run_backend.sh --finishing`, then `run_finishing.sh --gds` | `out/croc.def`, `out/croc.gds.gz` |
| `drc` | `klayout/` | the IHP PDK's `run_drc.py`, BEOL rules only | `drc/croc.lyrdb` |

Croc's scripts pipe the tool output through `gawk` without setting
`pipefail`, which means a crashed tool still leaves the script with exit
code 0. That is why every stage also checks that its output file from the
last column exists, and fails if it doesn't.

The `drc` stage only runs the BEOL part of the IHP rule deck, which takes
about 12 minutes on eight cores. The standard cells are DRC clean as
delivered, and the metal is what the flow actually draws. In our first
test the full deck, with the FEOL, density and extra rules, was still
running after 50 minutes, so we stopped it. The flow also adds no metal
fill before this stage, so the density rules would fail anyway. The deck
exits with code 1 whenever it finds a violation. The stage therefore
passes as long as the report database exists, and the number of
violations goes into the metrics.

`needs.tools` lists the tools each stage uses. The site file declares
them, and a host with a `tools` list only receives stages it can run.

## The container hook

Every command runs through `hooks/container.sh`. `EDR_CONTAINER` in the
`[env]` table of `edr.toml` names the image that Croc's scripts were
written for, and `EDR_RUNTIME` in the site's `env` says how the site runs
it:

| `EDR_RUNTIME` | What runs |
|---|---|
| `apptainer`, `singularity` | `$EDR_SIF_DIR/iic-osic-tools_2025.12.sif`, or the image straight from the registry if that file is missing |
| `docker` | `docker run` with the run tree mounted at the same path |
| `oseda` | the ETH Zurich wrapper, as `oseda -2025.12` |
| `none` | the command itself, using the tools on `PATH` |

If `EDR_RUNTIME` is not set, the hook takes the first of `oseda`,
`apptainer`, `singularity` and `docker` that it finds on the `PATH`, and
falls back to `none`. When it runs with `none` inside the image, as it
does in CI, it sources the image's shell setup first so the tools are on
the `PATH`.

A compute host can't necessarily see this directory. After each sync,
`sync.after` therefore copies the hook into the `.edr/` directory of the
run tree.

## Metrics

| Metric | Stage | File in the run tree | Read from |
|---|---|---|---|
| `area_cell_um2` | `synth` | `yosys/reports/croc_area.rpt` | `Chip area for top module` |
| `util_core_place` | `place` | `openroad/reports/02_croc.placed.rpt` | `Core Utilization:` |
| `wns_place_ns` | `place` | `openroad/reports/02_croc.placed.rpt` | `wns max` |
| `tns_place_ns` | `place` | `openroad/reports/02_croc.placed.rpt` | `tns max` |
| `util_core_final` | `finishing` | `openroad/reports/05_croc.final.rpt` | `Core Utilization:` |
| `wns_final_ns` | `finishing` | `openroad/reports/05_croc.final.rpt` | `wns max` |
| `tns_final_ns` | `finishing` | `openroad/reports/05_croc.final.rpt` | `tns max` |
| `drc_violations` | `drc` | `klayout/drc/croc.lyrdb` | one per `<item>`, counted by `hooks/drc_count.py` |

The area is the Yosys cell area of `croc_chip`, including the pads and the
SRAM macros. Utilization is given as a fraction of the core area, and a
slack of 0 means the design met its clock. For `v2.0.0` we measured the
following values, and they were the same on every host we tried:

| Metric | Value |
|---|---|
| `area_cell_um2` | 1 602 565.37 um2 |
| `util_core_place` | 0.4446 |
| `util_core_final` | 0.4581 |
| `wns_place_ns`, `tns_place_ns` | 0 ns |
| `wns_final_ns`, `tns_final_ns` | 0 ns |
| `drc_violations` | 925, all of them `Pad.fR` rules at the bond pads |

## Batches

| File | Jobs |
|---|---|
| `jobs/synth.toml` | `ihp13`, running only the `synth` stage |
| `jobs/croc.toml` | `ihp13`, running every stage |

Croc `v2.0.0` has one publicly available PDK, IHP SG13G2 from the
submodule. Its `env.sh` also accepts a `technology/` directory generated
by the ETH Zurich design kit tools, but people outside ETH can't get
those, so no job uses it. If a later Croc version adds another PDK, it
becomes one more `[[job]]` with its own label.

A job can set `overrides = { KEY = "value" }`, which passes `KEY=value` to
any stage that has `{overrides}` in its command. Croc's scripts read
`PROJ_NAME` and `TOP_DESIGN` from the environment rather than from
arguments, so these stages don't take overrides.

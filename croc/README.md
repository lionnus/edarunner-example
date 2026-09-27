# The Croc flow project

An edarunner project for the [Croc SoC](https://github.com/pulp-platform/croc)
at tag `v2.0.0`: the scripts of Croc from the RTL to a GDS and a DRC report,
in the IIC-OSIC-TOOLS image 2025.12 or with native tools. The walkthrough in
the top `README.md` runs it.

## Layout

```
edarunner-example/
  rtl/          the Croc clone, with the PDK submodule ihp13/pdk
  rtl-wt/       one worktree per commit, made by `edr checkout`
  croc/         this project
    data/       the run database, the collected results and the board
```

`source.repo` and `source.worktrees` in `edr.toml` point at `../rtl` and
`../rtl-wt`. A project in its own backend repository keeps the same
layout: the RTL clone next to it, never inside it.

## The stages

Each stage is one call of a Croc script in its directory. A call starts
the tool, runs one step and writes a checkpoint, so a stage that fails
leaves the stages before it intact.

| Stage | Directory | Command | Checks |
|---|---|---|---|
| `synth` | `yosys/` | `run_synthesis.sh --synth` | `out/croc_yosys.v` |
| `floorplan` | `openroad/` | `run_backend.sh --floorplan` | `save/01_croc.floorplan.zip` |
| `place` | `openroad/` | `run_backend.sh --placement` | `save/02_croc.placed.zip` |
| `cts` | `openroad/` | `run_backend.sh --cts` | `save/03_croc.cts.zip` |
| `route` | `openroad/` | `run_backend.sh --routing` | `save/04_croc.routed.zip` |
| `finishing` | `openroad/`, `klayout/` | `run_backend.sh --finishing`, then `run_finishing.sh --gds` | `out/croc.def`, `out/croc.gds.gz` |
| `drc` | `klayout/` | `run_drc.py` of the IHP PDK, BEOL rules | `drc/croc.lyrdb` |

The Croc scripts pipe the tool output through `gawk` without `pipefail`,
so a tool that fails still exits 0. Each stage therefore tests for the
file in the last column, and fails when it is missing.

The `drc` stage runs the BEOL rules of the IHP deck, about 12 min on
eight cores. The standard cells come DRC clean, and the flow draws the
metal. The FEOL, density and extra rules ran for more than 50 min on the
whole chip before the test stopped them, and the flow adds no fill
before this stage. The deck exits 1 when it finds a violation, so the
stage passes when the report database exists, and the count goes into
the metrics.

`needs.tools` names the tools of each stage. The site file declares them,
and a host with a `tools` list gets only the stages it can run.

## The container hook

Every command goes through `hooks/container.sh`. `EDR_CONTAINER` in the
`[env]` table names the image the scripts were written for. `EDR_RUNTIME`
in the site `env` says how a site runs it:

| `EDR_RUNTIME` | What runs |
|---|---|
| `apptainer`, `singularity` | `exec` of `$EDR_SIF_DIR/iic-osic-tools_2025.12.sif`, or of the registry image when that file is missing |
| `docker` | `docker run` of the image, with the run tree mounted at its own path |
| `oseda` | the ETH Zurich wrapper, `oseda -2025.12` |
| `none` | the command itself, with the tools on `PATH` |

Without `EDR_RUNTIME` the first of `oseda`, `apptainer`, `singularity`
and `docker` on `PATH` wins, else `none`. With `none` inside the image,
as in CI, the hook sources the image's own shell setup first.

A compute host may not see this directory, so `sync.after` copies the hook
into `.edr/` of each run tree after the sync.

## The metrics

| Metric | Stage | File under the run tree | Pattern |
|---|---|---|---|
| `area_cell_um2` | `synth` | `yosys/reports/croc_area.rpt` | `Chip area for top module` |
| `util_core_place` | `place` | `openroad/reports/02_croc.placed.rpt` | `Core Utilization:` |
| `wns_place_ns` | `place` | `openroad/reports/02_croc.placed.rpt` | `wns max` |
| `tns_place_ns` | `place` | `openroad/reports/02_croc.placed.rpt` | `tns max` |
| `util_core_final` | `finishing` | `openroad/reports/05_croc.final.rpt` | `Core Utilization:` |
| `wns_final_ns` | `finishing` | `openroad/reports/05_croc.final.rpt` | `wns max` |
| `tns_final_ns` | `finishing` | `openroad/reports/05_croc.final.rpt` | `tns max` |
| `drc_violations` | `drc` | `klayout/drc/croc.lyrdb` | one per `<item>`, by `hooks/drc_count.py` |

For `v2.0.0` the DRC count is 925, all of them `Pad.fR` rules at the
bond pads.

The area is the Yosys cell area of `croc_chip` with the pads and the
SRAM macros. The utilization is a fraction of the core area. A slack of
0 means the stage met the clock.

## The batches

| File | Jobs |
|---|---|
| `jobs/synth.toml` | `ihp13`, the `synth` stage only |
| `jobs/croc.toml` | `ihp13`, every stage |

Croc `v2.0.0` offers one PDK in public, IHP SG13G2 from the submodule. Its
`env.sh` also accepts a `technology/` directory from the ETH Zurich design
kit tools, which a stranger cannot get, so no job uses it. A second PDK in
a later Croc version is one more `[[job]]` with its own label.

A job with `overrides = { KEY = "value" }` passes `KEY=value` to a stage
that has `{overrides}` in its command. The Croc scripts read `PROJ_NAME`
and `TOP_DESIGN` from the environment, not from arguments, so these stages
take no overrides.

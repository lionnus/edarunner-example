# edarunner-example

A complete [edarunner](https://github.com/lionnus/edarunner) setup: a site
template and a flow project for the open-source
[Croc SoC](https://github.com/pulp-platform/croc). The flow runs Yosys,
OpenROAD and KLayout on the IHP SG13G2 PDK, from the RTL to a GDS and a DRC
report. It needs no licence.

```
site/                    the site layer: copy to ~/.config/edarunner/
  site.toml              hosts, scratch, tools, marks, the bot (commented)
  hooks/flexlm_free.sh   the seat probe of a FlexLM feature
  hooks/machine_check.sh free cores, RAM and scratch per host
  hooks/seed_python.sh   a sync hook that puts a venv interpreter on host scratch
croc/                    the project: the flow, the batches, the hooks
  edr.toml               seven stages from synth to drc, and the metrics
  jobs/synth.toml        synthesis alone, the first batch
  jobs/croc.toml         the whole flow
  hooks/container.sh     runs a stage in the tool image, or directly
  hooks/drc_count.py     counts the DRC violations
.github/workflows/ci.yml the walkthrough below, in CI
```

The two halves have two owners. `site/` has the shape of a lab's private
site repository: it names the machines, the licence servers and the chat,
so it stays out of public view. `croc/` has the shape of a project's
backend repository: it names the flow and no machine, so it runs
unchanged in every lab. A new lab copies `site/` once and fills in its
hosts. A new project copies `croc/` and changes the stages and the
metrics.

## What you need

- A Linux machine with Python 3.11 or newer, `git`, `rsync` and
  [uv](https://docs.astral.sh/uv/).
- The tools, in one of two ways:
  - the [IIC-OSIC-TOOLS](https://github.com/iic-jku/IIC-OSIC-TOOLS) image
    by Harald Pretl, version 2025.12, the version Croc supports, run
    through `apptainer`, `singularity` or `docker`;
  - or native installs of Yosys with the yosys-slang plugin, OpenROAD,
    KLayout 0.30.3 or newer and `gawk`, all on `PATH`.
- About 10 GB of free scratch, and 4 GB more for the image.

## Walkthrough on one machine

### 1. Install edarunner

```sh
uv tool install git+https://github.com/lionnus/edarunner
edr --version
```

### 2. Get this repository and Croc

The project expects the Croc clone next to it, in `rtl/`. Pin a tag: the
flow scripts of Croc change between versions, and the stages here call
them by name.

```sh
git clone https://github.com/lionnus/edarunner-example
cd edarunner-example
git clone --branch v2.0.0 https://github.com/pulp-platform/croc rtl
git -C rtl submodule update --init --depth 1 ihp13/pdk
```

The PDK submodule is about 740 MB. `git` ignores `rtl/`.

### 3. Get the tool image

With `apptainer` or `singularity`, pull the image once into a directory
with space:

```sh
mkdir -p ~/sif
singularity pull ~/sif/iic-osic-tools_2025.12.sif docker://hpretl/iic-osic-tools:2025.12
```

The pull takes about 9 min and writes a 3.8 GB file. It leaves about
8 GB in the cache, which `singularity cache clean` frees. Set
`SINGULARITY_TMPDIR` and `SINGULARITY_CACHEDIR` to a scratch directory
when `/tmp` or the home directory is small. With
`docker`, the first stage pulls the image itself. With native tools, skip
this step.

### 4. Install the site file

```sh
mkdir -p ~/.config/edarunner
cp -r site/. ~/.config/edarunner/
```

Do not copy over a site file you already have; merge the tables by hand.
Then edit `~/.config/edarunner/site.toml`:

- `[hosts.local]`: the cores and the RAM of this machine.
- `scratch`: the roots where the run trees may go. The largest writable
  one wins.
- `env`: `EDR_SIF_DIR` names the directory of step 3. `EDR_RUNTIME`
  picks `apptainer`, `singularity`, `docker` or `none`; without it
  `croc/hooks/container.sh` takes the first one on `PATH`. Use `none`
  for native tools.

### 5. Check, plan, launch

```sh
cd croc
edr checkout v2.0.0          # prints b714f2d and the path of a worktree
edr check                    # loads every file, probes the hosts
edr plan synth               # the run id, the host and the run tree
edr launch synth --dry-run   # every path and command; writes nothing
edr launch synth
```

`edr checkout` adds a detached worktree of Croc at `../rtl-wt/b714f2d`
with its own clone of the PDK. Every run copies that tree, so a later
change in `rtl/` never reaches a run that is in progress. Read every path
of the dry run before the real launch.

### 6. Watch

```sh
edr status                   # the board
edr status ihp13@synth       # one run: its stages, metrics and log tail
edr watch --once             # collect the reports and extract the metrics
```

`ihp13@synth` is a handle: the label of the job and the batch. The run
writes a heartbeat once a minute, so `edr status` shows the stage and the
last log lines. The synthesis takes about 4 min on eight cores. Run
`edr watch --once` again after the run ends; that cycle collects the
reports. For a watcher that stays up, start `edr watch` in `tmux`, or as
the systemd unit that `edr init` writes.

### 7. The whole flow

```sh
edr launch croc
```

The batch runs `synth`, `floorplan`, `place`, `cts`, `route`,
`finishing` and `drc` in order on one tree. It takes about 45 min on
eight cores. The watcher adds the metrics of each stage when the stage
ends.

### 8. Results and analysis

Every number lives in one SQLite file, `data/edr.db`, and every number
keeps the path of the report it came from. The design is the short hash
of the Croc commit, because one table holds one design:

```sh
edr metrics --design b714f2d
edr metrics --design b714f2d --csv > metrics.csv
```

After the synthesis the table has one row: the cell area of `croc_chip`
from the Yosys statistics, about 1 602 565 um2. The whole flow adds the
utilization, the worst and the total negative slack after placement and
on the finished layout, and the DRC count; `croc/README.md` lists each metric and
its report.

Each watcher cycle writes the board to `data/board/`. `compare.html` is
one page with the runs and their parameters as columns, the final
metrics side by side with the difference to a ticked run, and plots.
`status.html` is the board at phone width. Open the files in a browser,
or serve the directory:

```sh
cd data/board && python3 -m http.server --bind 127.0.0.1 8000
```

A report, a notebook or a paper reads a snapshot, not the live
database:

```sh
edr export --design b714f2d --out exports/b714f2d
```

The snapshot holds `manifest.json` with the sha256 of every file,
`runs.csv`, `metrics.csv`, and the collected reports of the newest run
per label under `<label>/`. Copy it as it is into the analysis, and name
the hash next to every number you quote.

<!-- mlflow: filled after the analysis release -->

With the Telegram bot of `site.toml` set up, the phone answers the same
questions: `/metric area_cell_um2` gives one metric per run,
`/compare <handle> <handle>` puts two runs side by side, `/csv b714f2d`
sends `metrics.csv`, and `/board` sends the two pages as files.

## Clean up

```sh
edr retire --batch synth --dry-run --why "walkthrough done"
edr retire --batch synth --why "walkthrough done"
```

`retire` deletes the run trees after a guard on each path, and refuses a
tree whose results are not collected. The database, the collected
reports and the snapshots stay on the head node.

## The lab path

The same project runs on a farm. Only the site file changes.

1. Give each compute host a `[hosts.<name>]` table in `site.toml`, with
   its cores and RAM. The head node reaches each host over `ssh` with a
   key and no prompt. A host needs `python3` 3.6 or newer, `rsync` and
   the container runtime or the tools.
2. Put the state directory, `~/.edr/croc` by default, on a filesystem
   that every host mounts. The home directory often is one.
3. Keep the site directory on a shared filesystem too, when a tool probe
   or a hook runs on the hosts.
4. List the tools of a host under `tools` when not every host has every
   tool. `edr plan` then places a stage only on a host that has its tools.
5. Set `EDR_RUNTIME` in the site `env` to the way your hosts run an
   image. A site wrapper can take the place of a runtime: at ETH Zurich,
   `oseda -<version>` runs the IIC-OSIC-TOOLS image, and
   `container.sh` calls it when it is on `PATH`.
6. Delete `host` from the jobs, or set it to `auto`. `edr launch` then
   picks the host with the most free cores that fits the first stage.

`edr hosts` shows the load of every host, and `edr check` names each host
that does not answer.

## Read more

The edarunner documentation is at <https://lionnus.github.io/edarunner/>:

| Page | Read it to |
|---|---|
| [install](https://lionnus.github.io/edarunner/install/) | install `edr` and see what a compute host needs |
| [concepts](https://lionnus.github.io/edarunner/concepts/) | know what a project, a stage, a run, a batch and a snapshot are |
| [configure](https://lionnus.github.io/edarunner/configure/) | turn your own flow into a project like `croc/` |
| [run](https://lionnus.github.io/edarunner/run/) | launch, watch, resume, and clear the hosts |
| [results](https://lionnus.github.io/edarunner/results/) | the database, the compare board and the snapshot |
| [telegram](https://lionnus.github.io/edarunner/telegram/) | the bot, from BotFather to the phone commands |
| [guarantees](https://lionnus.github.io/edarunner/guarantees/) | what `edr` never does, and what a dry run and a guard promise |
| [reference](https://lionnus.github.io/edarunner/reference/) | every command, flag, config key, placeholder and run state |

## Known limitations

- The `docker` branch of `container.sh` is not tested; the IIC-OSIC-TOOLS
  image runs in CI through the `container` key of the workflow instead.
- The DRC stage runs the IHP rule deck without the density rules, because
  the flow adds no fill before it. The count is not a signoff result.

## License

Apache-2.0 for the files of this repository; see `LICENSE`. Croc, the IHP
PDK and the tools carry their own licences.

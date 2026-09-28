# edarunner-example

This repository holds a working [edarunner](https://github.com/lionnus/edarunner)
setup. It runs the open-source [Croc SoC](https://github.com/pulp-platform/croc)
through Yosys, OpenROAD and KLayout on the IHP SG13G2 PDK, all the way from
the RTL to a GDS file and a DRC report. Every tool is open source, so you
don't need a licence to try it.

It bundles a site file and a project so that you can read both in one
place. In a lab the two live apart: the site file in a repository that
the lab shares, and the project where you run `edr`.

```
site/                    a lab's site repository; each user clones it to ~/.config/edarunner/
  site.toml              hosts, scratch, tools, and the lab's bot commands (commented out)
  .gitignore             keeps each user's user.toml and secret files out of git
  hooks/flexlm_free.sh   seat probe for a FlexLM licence feature
  hooks/machine_check.sh free cores, RAM and scratch on each host
croc/                    a project directory, as it sits where you run edr
  edr.toml               seven stages from synth to drc, plus the metrics
  jobs/synth.toml        synthesis only, for a first quick batch
  jobs/croc.toml         the whole flow
  hooks/container.sh     runs a stage inside the tool image, or directly
  hooks/drc_count.py     counts the DRC violations
  AGENTS.md              how any coding agent operates the project
  CLAUDE.md, .claude/    the Claude Code extras: hooks and a skill
AGENTS.md, CLAUDE.md     the rules for agents in the whole repository
.github/workflows/ci.yml the walkthrough below, run in CI
```

`site/` has the shape of a lab's site repository. Every project and every
user of the lab's machines shares the site file, so the lab keeps it in a
private repository of its own, and each user clones that repository to
`~/.config/edarunner/`. It lists the lab's machines and licence servers,
so it never goes into a public project like this one. Each user's chat
and bot token go into a `user.toml` next to the site file, which the
repository's `.gitignore` keeps out of git. A new lab copies `site/` once
into such a repository and fills in its hosts.

`croc/` is a project directory as it sits where you run `edr`, next to the
checkouts of the flow. It describes the flow but names no machine, which
is why the same files run unchanged in any lab. Whether a project
directory goes into git is up to the project. A new project starts from
`croc/` and changes the stages and the metrics.

## What you need

- A Linux machine with Python 3.11 or newer, `git`, `rsync` and
  [uv](https://docs.astral.sh/uv/).
- The EDA tools. The easiest way to get them is the
  [IIC-OSIC-TOOLS](https://github.com/iic-jku/IIC-OSIC-TOOLS) image by
  Harald Pretl in version 2025.12, which is the version Croc supports. You
  can run it with `apptainer`, `singularity` or `docker`. Native installs
  work too, as long as Yosys with the yosys-slang plugin, OpenROAD,
  KLayout 0.30.3 or newer and `gawk` are on your `PATH`.
- About 10 GB of free scratch space, plus 4 GB for the image.

## Walkthrough on one machine

### 1. Install edarunner

```sh
uv tool install git+https://github.com/lionnus/edarunner
edr --version
```

### 2. Get this repository and Croc

The project expects the Croc clone to sit next to it, in `rtl/`. Use a
tag rather than a branch, because the stages call Croc's flow scripts by
name and those scripts change between versions.

```sh
git clone https://github.com/lionnus/edarunner-example
cd edarunner-example
git clone --branch v2.0.0 https://github.com/pulp-platform/croc rtl
git -C rtl submodule update --init --depth 1 ihp13/pdk
```

The PDK submodule is about 740 MB. Git ignores `rtl/` in this repository.

### 3. Get the tool image

If you use `apptainer` or `singularity`, pull the image once into a
directory with enough space:

```sh
mkdir -p ~/sif
singularity pull ~/sif/iic-osic-tools_2025.12.sif docker://hpretl/iic-osic-tools:2025.12
```

On our machine the pull took about 9 minutes and wrote a 3.8 GB file. It
also left about 8 GB in the Singularity cache, which
`singularity cache clean` removes. If `/tmp` or your home directory is
small, point `SINGULARITY_TMPDIR` and `SINGULARITY_CACHEDIR` at a scratch
directory first. With `docker` you can skip this step, since the first
stage pulls the image. With native tools you don't need an image at all.

### 4. Install the site file

```sh
mkdir -p ~/.config/edarunner
cp -r site/. ~/.config/edarunner/
```

Here the copy stands in for the clone of a lab's site repository. If you
already have a site file, don't overwrite it; merge the tables by hand
instead. Then open `~/.config/edarunner/site.toml` and adjust three
things:

- Under `[hosts.local]`, enter the cores and RAM of your machine. No run
  starts while the scratch has less than `host_free_min_gb` free. The
  default is 100 GB, and the example sets 10 so that the walkthrough fits
  on a small disk.
- `scratch` lists the directories where run trees may go. edarunner picks
  the largest writable one.
- In `env`, `EDR_SIF_DIR` is the directory from step 3. You can also set
  `EDR_RUNTIME` to `apptainer`, `singularity`, `docker` or `none`. If you
  leave it out, `croc/hooks/container.sh` uses the first runtime it finds
  on your `PATH`. Set it to `none` if you installed the tools natively.

### 5. Check, plan and launch

```sh
cd croc
edr checkout v2.0.0          # prints b714f2d and the path of a new clone
edr check                    # loads every file and probes the hosts
edr plan synth               # shows the run id, the host and the run tree
edr launch synth --dry-run   # prints every path and command, writes nothing
edr launch synth
```

`edr checkout` makes a local clone of Croc at `../rtl-wt/b714f2d`,
detached at that commit, with its own copy of the PDK. Each run works on
a copy of that clone, so whatever you change in `rtl/` later can't affect
a run in progress. Read the paths in the dry run before you launch for
real.

### 6. Watch the run

```sh
edr status                   # the board
edr status ihp13@synth       # one run, with its stages, metrics and log tail
edr watch --once             # collects the reports and extracts the metrics
```

`ihp13@synth` is a handle, made of the job's label and the batch name. The
run writes a heartbeat every minute, so `edr status` always shows the
current stage and the last lines of the log. Synthesis takes about four
minutes on eight cores. Once the run has finished, run `edr watch --once`
one more time so that it collects the reports.

For a watcher that keeps running, each user runs one supervisor,
`edr serve`, which keeps a watcher for every registered project.
`edr launch` has registered this project already, and `edr register` in a
project directory does the same by hand. Install the supervisor as a
systemd user service:

```sh
mkdir -p ~/.config/systemd/user
edr serve --unit > ~/.config/systemd/user/edr-serve.service
systemctl --user daemon-reload
systemctl --user enable --now edr-serve
```

From then on the supervisor collects the results for you, and
`edr watch --once` exits with code 2, since the project already has a
watcher. The
[run](https://lionnus.github.io/edarunner/guides/run/#keep-a-watcher-behind-the-batch)
guide explains the unit, and
[projects](https://lionnus.github.io/edarunner/guides/projects/) shows one
supervisor for several projects.

### 7. Get alerts on your phone

This step is optional and needs the supervisor from step 6, which also
runs a Telegram bot. The bot sends an alert when a run needs you, keeps a
pinned board and answers commands. The bot and its chat belong to you,
not to the lab, so they go into `~/.config/edarunner/user.toml`, next to
the site file. Make a bot with `/newbot` at @BotFather and save the token
it gives you with mode 600:

```sh
umask 077; echo '<token>' > ~/.config/edarunner/telegram.token
```

Then write `~/.config/edarunner/user.toml`:

```toml
[telegram]
token_file = "~/.config/edarunner/telegram.token"
chat_id = 0   # the one chat the bot answers
user_id = 0   # your Telegram user id; the bot then obeys only you
```

Leave `chat_id` at 0, send the bot a message, and restart the supervisor
with `systemctl --user restart edr-serve`. It logs the id of the chat
that the message came from, which `journalctl --user -u edr-serve` shows.
Enter that id as `chat_id` and restart the supervisor again. A bot such
as @userinfobot tells you your user id. The
[alerts](https://lionnus.github.io/edarunner/guides/alerts/) guide
describes the rest of `user.toml`: ntfy, mail and the daily digest.

### 8. Run the whole flow

```sh
edr launch croc
```

This batch runs `synth`, `floorplan`, `place`, `cts`, `route`, `finishing`
and `drc` one after another on the same tree. It took about 45 minutes on
eight cores in our tests, most of it in detailed routing. The watcher
extracts each stage's metrics as soon as that stage ends.

### 9. Results and analysis

All the numbers end up in a single SQLite file, `data/edr.db`, and each
one remembers which report it came from. You always ask for one source at
a time, named by its source tag: the short hash of the Croc commit that
`edr checkout` printed.

```sh
edr metrics --source b714f2d
edr metrics --source b714f2d --csv > metrics.csv
```

After synthesis there is one row: the cell area of `croc_chip` from the
Yosys statistics, which comes to 1 602 565 um2. The whole flow adds the
core utilization, the worst and total negative slack after placement and
on the finished layout, and the DRC violation count. `croc/README.md`
lists every metric together with the report it is read from.

Every watcher cycle also writes a board to `data/board/`. `compare.html`
puts the runs next to each other with their parameters as columns, shows
how the final metrics differ from a run you tick, and draws a few plots.
`status.html` is the same board sized for a phone. You can open both files
directly in a browser or serve the directory:

```sh
cd data/board && python3 -m http.server --bind 127.0.0.1 8000
```

For a report, a notebook or a paper, export a snapshot instead of reading
the live database:

```sh
edr export --source b714f2d --out exports/b714f2d
```

The snapshot contains `manifest.json` with a sha256 for every file,
`runs.csv`, `metrics.csv`, and the collected reports of the newest run for
each label, under `<label>/`. Copy the directory into your analysis as it
is, and quote the hash next to every number you take from it.

If you prefer MLflow, edarunner 0.3.0 can write the database into a
local MLflow tracking store, which `mlflow ui` then opens. The export
needs the `mlflow` extra of edarunner:

```sh
uv tool install 'edarunner[mlflow] @ git+https://github.com/lionnus/edarunner'
edr export --mlflow exports/mlflow --source b714f2d
uvx mlflow ui --backend-store-uri sqlite:///exports/mlflow/mlflow.db --host 127.0.0.1 --port 5000
```

Each run becomes one MLflow run, with its parameters, its metrics at each
step and the stage times. Running the export again after the next batch
adds only the new runs.

If you set up the bot in step 7, you can ask the same questions from
your phone. `/metric area_cell_um2` lists one metric for every run,
`/compare <handle> <handle>` shows two runs side by side, `/csv b714f2d`
sends the metrics as a CSV file, and `/board` sends both HTML pages.

### 10. Let an agent operate the project

The repository also shows how an LLM coding agent can run the project for
you. Any agent that reads `AGENTS.md` gets the general part. The root
`AGENTS.md` holds the rules for the whole repository, and `croc/AGENTS.md`
says what the agent owns, reads and writes in the project, what it must
never do, and how it drives `edr`: a briefing first, `--json` on every
call, a dry run before anything that writes, and a reason with every stop
or retire.

Claude Code is the default agent here, and it gets three extras. Each
`CLAUDE.md` is a single line that points it to the `AGENTS.md` next to
it. `croc/.claude/settings.json` runs `edr brief` when a session starts,
so the agent begins with the flow, the state and the runs that need a
decision, and it sends a short note through `edr notify` after each turn.
The skill in `croc/.claude/skills/edr-ops/` walks through the triage loop.
`edr brief` needs edarunner 0.4.0 or newer; with an older version the hook
falls back to `edr status --triage`. To reach a session from your phone,
look at the `/claude` command that is commented out in `site/site.toml`.

None of these files name a host, a user or a chat. The hosts belong in
your lab's private site file and the chat in your own `user.toml`, and
neither goes into this repository.

## Clean up

```sh
edr retire --batch synth --dry-run --why "walkthrough done"
edr retire --batch synth --why "walkthrough done"
```

`retire` checks each path before it deletes a run tree, and it refuses to
delete a tree whose results haven't been collected yet. The database, the
collected reports and your snapshots all stay on the head node.

## Moving to a lab farm

The same project runs on a farm of compute hosts. Only the site file
changes.

1. Add a `[hosts.<name>]` table for each compute host in `site.toml`, with
   its cores and RAM. The head node has to reach every host over `ssh` with
   a key and without a password prompt. Each host needs `python3` 3.6 or
   newer, `rsync`, and either the container runtime or the tools.
2. Put the state directory (`~/.edr/croc` by default) on a filesystem that
   every host mounts. A shared home directory works well.
3. If a tool probe or a hook has to run on the hosts, keep the site
   directory on a shared filesystem as well.
4. If some hosts lack a tool, list the tools each host does have under
   `tools`. `edr plan` then only places a stage on a host that can run it.
5. Set `EDR_RUNTIME` in the site's `env` to match how your hosts run an
   image. A site's own wrapper works too. At ETH Zurich, for example,
   `oseda -<version>` starts the IIC-OSIC-TOOLS image, and `container.sh`
   uses it whenever it is on the `PATH`.
6. Remove `host` from the jobs or set it to `auto`. `edr launch` will then
   choose the host with the most free cores that can take the first stage.

`edr hosts` shows how busy each host is, and `edr check` tells you which
hosts don't answer.

## Further reading

The edarunner documentation lives at <https://lionnus.github.io/edarunner/>.

| Page | What you'll find there |
|---|---|
| [install](https://lionnus.github.io/edarunner/install/) | how to install `edr` and what a compute host needs |
| [how it works](https://lionnus.github.io/edarunner/how-it-works/) | what a project, a stage, a run and a batch are, and what `edr` never does |
| [site](https://lionnus.github.io/edarunner/guides/site/) | how to describe the hosts, the tools and their licence seats |
| [project](https://lionnus.github.io/edarunner/guides/project/) | how to turn your own flow into a project like `croc/` |
| [run](https://lionnus.github.io/edarunner/guides/run/) | how to launch, watch and resume runs |
| [projects](https://lionnus.github.io/edarunner/guides/projects/) | how one supervisor watches several projects |
| [results](https://lionnus.github.io/edarunner/guides/results/) | the database, the compare board and snapshots |
| [alerts](https://lionnus.github.io/edarunner/guides/alerts/) | how to set up the bot and use it from a phone |
| [cleanup](https://lionnus.github.io/edarunner/guides/cleanup/) | how to retire runs and clear the hosts |
| [reference](https://lionnus.github.io/edarunner/reference/) | every command, flag, config key, placeholder and run state |

## Known limitations

- The `docker` branch of `container.sh` hasn't been tested. In CI the
  image runs through the workflow's `container` key instead.
- The DRC stage only checks the BEOL rules of the IHP deck, for reasons
  given in `croc/README.md`. Its count is not a signoff result.
- In edarunner 0.3.0, `edr retire --batch` refuses to retire the last
  batch on a commit. It tries to remove the clone `../rtl-wt/<hash>` as
  well, and that path doesn't contain the safety marker `/edr/`. Until
  this is fixed, retire those runs one by one with their handles, for
  example `edr retire ihp13@croc --why "done"`.

## License

The files in this repository are under the Apache-2.0 license (see
`LICENSE`). Croc, the IHP PDK and the tools have their own licences.

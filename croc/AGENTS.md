# Agents in the croc project

The Croc flow runs here through `edr`, and an agent operates it through
`edr` alone. It never calls `ssh`, `rsync`, `rm` or `kill` on a run by
hand, because a hand command skips the guards and leaves no record. The
core's [AGENTS.md](https://github.com/lionnus/edarunner/blob/main/AGENTS.md)
explains the rules in more depth.

## Owns

The agent owns `edr.toml`, `jobs/`, `hooks/`, `.claude/` and any notes in
this directory.

## Reads

It reads the clones that `edr checkout` creates under `../rtl-wt/<hash>`,
but never `../rtl/` directly. It also reads the site file at
`~/.config/edarunner/site.toml` and `data/`, where edr keeps the run
database, the collected results and the board.

## Writes

It writes new batches into `jobs/` and makes snapshots with
`edr export --design <hash> --out exports/<hash>`. Every stop and retire
carries a `--why`, so that `edr events` keeps the record.

## Never

It never kills a process by name or pattern, deletes anything without a
dry run first, or retires a run tree whose results haven't been
collected. It never writes a host, a server, a user or a chat id into a
file of this repository; those belong in the lab's private site file.

## Hands off through

Results leave this project through the export directory and its
manifest. Requests for the site go into `data/handoff/croc_to_site.md`.

## How to operate the project

1. Start each session with `edr brief`, which describes the project, its
   flow, the site as it applies here, and the runs that need a decision.
   `edr brief --run <handle>` prints the history of a single run; read it
   before you debug that run. On edarunner versions before 0.4.0, use
   `edr --json status --triage` instead.
2. Pass `--json` on every call and look at `code` first: 0 means done,
   1 means refused, 2 means there was nothing to do, and 3 means a host
   failed.
3. Before any call that writes (`checkout`, `launch`, `continue`, `keep`,
   `export`, `stop`, `retire`), run it with `--dry-run` and read every
   path it prints.
4. Give `stop` and `retire` a `--why` that states what you saw, for
   example `--why "hung: no progress since 14:02, log stops in detailed routing"`.
5. When a long task ends or needs a person, report it with
   `edr notify "<text>"`.

The design is the short hash of the Croc commit, `b714f2d` for `v2.0.0`.
Pass it to `edr metrics --design` and `edr export --design`, and quote it
next to every number you report.

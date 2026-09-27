---
name: edr-ops
description: Operate the croc project with edr. Use it when the user asks how the runs are doing, what to do about a stopped or failed run, or to launch, stop, resume or clean up a batch.
---

# Operate this project with edr

Work through `edr` only. Never call `ssh`, `rsync`, `rm` or `kill` on a
run yourself, because a hand command skips the guards and leaves no event
behind.

## The loop

1. Look. Run `edr brief` to see the project, its state and the runs
   that need a decision. On edarunner before 0.4.0, run
   `edr --json status --triage` instead. Before you trust a running
   count, confirm it with `edr status --live`.
2. Decide. Before you act on a run, read its story with
   `edr brief --run <handle>`, or `edr status <handle>` and
   `edr events --run <handle>` on an older edarunner. The core's
   `AGENTS.md` says what to check for each state. Resume a `dead` run
   with `--from`, so that it keeps its checkpoints.
3. Act. Run the command with `--dry-run` first and read every path it
   prints. Then run it for real. A stop or a retire needs `--why` with the
   state and the evidence, for example
   `--why "hung: no progress since 14:02, log stops in detailed routing"`.
4. Report. Send one line with `edr notify "<what you did and why>"`,
   and write any decision that should outlive the session into a file.

Go back to step 1 until the triage list only holds runs that a person has
to look at.

## Numbers

`edr metrics --design b714f2d` gives the metrics of Croc `v2.0.0`. Every
row names the report it came from, so read that report before you quote a
number, and give the hash with it.

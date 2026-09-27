# Rules for agents in this repository

These rules apply to any coding agent working here, whether it is Claude
Code or another tool that reads `AGENTS.md`. Before you start, also read the
`AGENTS.md` of the directory you work in; its sections decide what you may
touch there.

- Never run a git command that writes: no add, commit, push, stash or
  reset. When a piece of work is done, propose a one-line commit message
  and let a person commit.
- Use absolute paths. The shell's working directory can change between
  calls.
- Before anything that deletes or stops, run its dry run and read every
  path it prints.
- Before the session ends, write every decision you made into a file, so
  the next session can find it.
- Only read the directories that your directory's `AGENTS.md` names.

The directories are `site/` (the site template, which a lab copies to
`~/.config/edarunner/`), `croc/` (the edarunner project for Croc), `rtl/`
and `rtl-wt/` (the Croc clone and its worktrees, both outside git), and
`.github/` (CI).

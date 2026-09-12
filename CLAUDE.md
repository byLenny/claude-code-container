# Project instructions

## Line endings

This project defaults to CRLF for regular text files (docs, YAML,
`.env.example`, etc.) — enforced by `.gitattributes`.

`*.sh`, `entrypoint.sh`, and `Dockerfile` are the deliberate exception and
must stay **LF**. They run inside the Linux container via bash; a CRLF
shebang line breaks `exec()` outright, and CRLF inside a `<<'EOF'` heredoc
breaks the terminator match. `.gitattributes` already pins these to LF —
don't override it per-file, and don't "fix" a script's line endings to
match the rest of the project.

## Shell scripts

Always run `shellcheck` on every shell script you add or modify —
`entrypoint.sh` and everything under `scripts/` — before considering the
change done. Fix what it reports. If a warning is a deliberate false
positive, suppress it inline with `# shellcheck disable=SCxxxx` and a short
comment saying why, rather than leaving it unaddressed.

Note: on a Windows checkout, working-tree copies of these scripts may show
CRLF locally (a `core.autocrlf` checkout artifact) even though the
committed blob and `.gitattributes` say LF — normalize with `tr -d '\r'`
before running shellcheck if its output is full of `SC1017` errors instead
of real findings.

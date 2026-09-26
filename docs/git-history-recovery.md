# Git history recovery

The Git object database present on 2026-09-26 was corrupt: `git fsck --full
--no-reflogs` reported multiple empty, missing objects. The repository had no
configured remote from which those objects could be recovered. Although the
current `HEAD` tree could still be read, the history cannot be treated as a
reliable record of the server state.

The corrupt `.git` directory is preserved as
`/srv/netboot/.git-corrupt-20260926` for forensic recovery. The repository was
then initialized from the validated current working tree as one baseline
commit. Runtime images, backup containers, temporary editor files, and the
nested abandoned checkout remain ignored and are not part of that baseline.

If an authoritative remote or a healthy clone is found later, compare it with
this baseline before replacing the history. Do not overwrite the current
working tree while attempting object recovery.

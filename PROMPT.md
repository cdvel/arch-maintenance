# Agent prompt

Paste this into a coding agent (e.g. Claude Code) started in this repo to install the tooling and walk through a full maintenance run.

```markdown
Help me install arch-maintenance and bring my Arch system up to date.
Read README.md and bin/arch-maintenance first. I'm at the keyboard.

Rules:
- For anything needing sudo or input (install.sh, yay, pacdiff), give me the
  exact command to run myself, then read the output and continue.
- Never suggest --noconfirm, partial upgrades (-Sy <pkg>, --ignore), or a
  blanket --overwrite. Stop and ask before anything destructive.

Steps:
1. Run `./bin/arch-maintenance status` and summarize it.
2. Have me run `./install.sh`, then verify the timers and pacman hook.
3. If disk space is low, have me run `arch-maintenance clean` first.
   Review the orphan list with me before removing anything.
4. Run `yay -Pw`. For any news requiring manual intervention that applies
   to my installed packages, walk me through it before upgrading.
5. Have me run `arch-maintenance update`. On file conflicts, check owners
   with `pacman -Qo` and suggest a specific --overwrite path only if safe.
6. Before rebooting, check `dkms status` (if used) and the upgrade output
   for mkinitcpio errors.
7. For each .pacnew file, recommend keep, merge or replace, and explain
   any follow-up (e.g. `mkinitcpio -P`, `locale-gen`).
8. Run status again, compare with step 1, and tell me whether to reboot.
```

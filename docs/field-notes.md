# Field notes — what a real migration taught the kit

This kit was built *during* the migration it performed (Intel iMac → M-chip
MacBook Pro, July 2026). Every lesson below was paid for with a real failure,
fixed live, and landed as a permanent behavior. This file is the product's
memory of why it is the way it is.

## Lessons that became design rules

**Verify function, not files.** The `.envrc` files were gitignored and would
have silently not-traveled — caught only by asking "will direnv *work* over
there?" Rule: every discovered item generates a behavioral probe; done = the
probe diff between machines is empty. (→ `verify.sh`)

**Wizards must run things, not just check them.** The user pressed enter
expecting the wizard to *do* the step; it only verified. Rule: every runnable
step gets `[r]un it for me`; verification stays mandatory either way.

**Show the failing check.** A verify loop that says "not detected yet" with no
reason is a wall. Rule: on failure, print the exact command the check runs.

**Regeneration clobbers curation.** `brew bundle dump --force` wiped the
hand-approved cask list; the target Mac quietly lost 9 apps. Rule: manual
additions live in `Brewfile.extras` and are re-applied after every dump;
known-broken entries live in `Brewfile.exclude`.

**Adopt, don't reinstall.** Users hand-install apps mid-migration — that's
normal, not deviant. Rule: `cask_args adopt: true`; pre-existing apps are
adopted into management, never replaced.

**One app, one owner.** Tailscale was listed via both `mas` and a cask and
they fought. Rule: every app has exactly one provisioning source in the
manifest; collisions are resolved once, permanently.

**Auth before transport.** Repo remotes were SSH URLs, but a new machine has
no SSH key yet. Rule: clone over HTTPS (gh's credential helper) until the
machine's key exists and verifies; flip later if desired.

**Ship the platform's dialect.** `--info=stats1` broke on macOS's openrsync.
Rule: stick to portable flags; always show progress (silence reads as hung).

**Names are transport-flexible; reachability is truth.** The user handed a
LAN IP to a script that demanded a tailnet name. Rule: accept tailnet names,
`.local`, and raw IPs equally; the only real gate is "does the port answer."

**Gates get closed by verification, not memory.** Remote Login stayed on
because humans forget. Rule: any door a tool asks the user to open, the tool
refuses to finish until it verifies the door is shut. (→ `pull-claude.sh`)

**Pre-explain the OS's own dialogs.** "Should I allow ruby?!" — macOS names
Homebrew's interpreter, not Homebrew, in its App Management prompt. Rule: the
instruction layer explains every upcoming permission dialog before it fires.

**Agent state is sensitive by default.** MCP configs embed credentials; memory
can contain anything; project keys embed absolute paths. Rules: agent state
travels only in the encrypted lane; restore re-keys paths to the new home;
session transcripts move only peer-to-peer, never through the repo.

**The courier dies after delivery.** Once both machines held the secrets, the
encrypted bundle was purged from git history. Secrets in transit should have
a lifespan measured in the migration, not the repo.

## The one-line thesis this migration proved

**Migration Assistant moves your files; this moves your setup** — and on an
architecture change, moving setup (rebuild natively, translate paths, re-key,
re-auth) is not just cleaner, it's more correct.

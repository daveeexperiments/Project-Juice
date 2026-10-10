---
name: github-setup
description: Set up a repository's branch model, CI and merge hygiene from scratch, or fix an existing one. Load when starting a new project, when a repo has no CI, when asked to add a GitHub Actions workflow or a test gate, when CI runs twice per push, when a green build is not trustworthy, or when a branch or repository-settings change is refused by the sandbox. Carries a proven Godot recipe and the adaptations for other stacks.
---

# Setting up a repository

The end state this produces:

- **`development`** — the default branch, permanent, where work happens.
- **`main`** — the release branch, which only ever receives `development`.
- **CI on both**, running once per push, that fails for the right reasons.
- A clear answer for the handful of things the sandbox cannot do.

## 1. The branch model

```bash
git checkout -b development
git push -u origin development
```

Then ask the person to make `development` the default on GitHub (see §5 — you cannot).

Why a permanent integration branch rather than working on `main`: `main` stays a state the suite
has passed on, and a bad commit never sits on the branch people clone. Merge `development` into
`main` when you want to ship; nothing else writes to `main`.

## 2. CI that actually gates

**The single most important thing in this skill: the exit code is not a gate.**

A test runner that cannot load part of the project will often skip those tests, print a pass line
for the rest, and exit 0. In this repo, deliberately breaking one source file made nine checks
crash and vanish while the runner printed `PASSED 72 checks` and exited **0** — a green build with
tests silently deleted. A workflow that only checks `$?` will tell you everything is fine.

So gate on three things, not one:

1. **Compile/load errors**, read from the build or import step's *output* — such a step often exits
   0 even when it printed errors, so it has to be read rather than trusted.
2. **The suite's own verdict** (the exit code). Necessary, not sufficient.
3. **The check count**, against a floor. This is the one that catches tests going missing. Store the
   floor in the workflow `env`, raise it when checks are added, and never lower it to turn a red
   build green.

### Avoiding the double run

`on: push` for every branch **plus** `on: pull_request` runs the suite twice for any branch with an
open PR. `concurrency` cannot collapse them: `github.ref` is `refs/heads/<branch>` for the push
event and `refs/pull/<n>/merge` for the pull_request event, so they land in different groups and
neither cancels the other.

The fix: `push` covers the long-lived branches, `pull_request` covers everything else, and a
job-level `if` skips the pull_request run when `push` already covers its head branch.

```yaml
on:
  push:
    branches: [main, development]
  pull_request:

concurrency:
  group: tests-${{ github.ref }}
  cancel-in-progress: true

jobs:
  tests:
    if: >-
      github.event_name != 'pull_request' ||
      !contains(fromJSON('["main", "development"]'), github.head_ref)
```

### The shape of the run step

```bash
set -uo pipefail          # NOT -e: the guards below need to run after a failure
log=/tmp/tests.log
<run the suite> 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

if grep -q '<runtime error marker>' "$log"; then
  echo "::error::A runtime error means checks were skipped rather than run."; exit 1
fi
if [ "$status" -ne 0 ]; then
  echo "::error::The suite reported failures."; exit "$status"
fi
count=$(sed -n 's/^PASSED  *\([0-9]\{1,\}\) checks.*/\1/p' "$log" | tail -1)
if [ -z "$count" ]; then
  echo "::error::No result line: the suite did not finish."; exit 1
fi
if [ "$count" -lt "$MIN_CHECKS" ]; then
  echo "::error::Only $count checks ran, expected at least ${MIN_CHECKS}."; exit 1
fi
```

**Pin the toolchain version and verify it**, rather than assuming. Pin hardest when tests assert
exact numeric equality, where results can shift between versions.

## 3. Prove the workflow before committing it

A workflow that goes red on its first run costs a cycle and the reviewers' trust, and you cannot
run GitHub Actions locally. You can do better than hoping:

**Extract the run-step bodies from the YAML and execute them verbatim**, so what you test is what
CI runs rather than a paraphrase of it:

```python
import re, pathlib
y = pathlib.Path('.github/workflows/tests.yml').read_text()
blocks = re.findall(r'\n        run: \|\n(.*?)(?=\n      - name:|\Z)', y, re.S)
# strip the YAML indent, write each to a file, run with the same env vars
```

Run them against a **fresh clone** (`git clone` to a temp dir), not your working tree — a working
tree has build caches and generated directories a CI runner will not have, and those are exactly
what first runs trip over.

Then test the guards by breaking things on purpose. Each should go red for its own reason:

| Scenario | Should fail at |
|---|---|
| Healthy tree | nothing — green, with the expected count |
| One assertion flipped to false | the suite's verdict |
| A source file that will not compile | the build/import guard |
| Floor raised above the real count | the count guard |

Also check the YAML parses (`yaml.safe_load`) — note YAML 1.1 reads the key `on` as boolean `True`,
so look it up as `d.get('on', d.get(True))`.

## 4. Reading CI results

**Be suspicious of a result that is too fast or too clean, and read the log rather than the
conclusion.** A job that "passes" in a few seconds may have skipped the work. Fetch the actual log
and confirm the expected output is in it. (In this repo a 12-second green run turned out to be
genuine — runners are fast — but checking cost one call and would have caught the alternative.)

Equally, a runner can surface what a local run hides. Here, a resting-contact assertion read
`17.039` on the runner against `17.000` locally; it passed only because the check used a tolerance
rather than float equality. **Prefer tolerances to exact equality for anything physical or
timing-dependent**, and keep exact equality for the invariants that genuinely must be exact.

## 5. What the sandbox will not let you do

Two refusals are not permission problems on the person's account, and no amount of retrying fixes
them. Recognise them and hand the task over in one short, concrete instruction:

| Action | Error | Hand over |
|---|---|---|
| Delete a remote branch | `the remote end hung up unexpectedly`, repeatedly, with `Everything up-to-date` | the trash icon on the repo's Branches page |
| Change repo settings (default branch, protection) | `Repository settings writes are not permitted through this proxy` (403) | Settings → Branches → the switch icon by **Default branch** |

A git push-delete is a push of a zero-ref, which is why it fails as a push rather than as a clear
403. Retrying four times proves it is not a flaky network, then stop.

**When handing over, give numbered clicks and nothing else.** Explaining the cause first buries the
instruction — say what to click, then the reason in one line if at all.

## 6. Merging

- Verify CI is green **on the current head** immediately before merging, not on a remembered state.
- Pass `expectedHeadSha` so you cannot merge something other than what you verified.
- Prefer a **merge commit** over a squash when the individual commits carry reasoning worth keeping;
  squash when they are "wip"/"fix typo" noise.
- Before deleting any branch, prove it is fully merged:
  `git merge-base --is-ancestor origin/<branch> origin/main`
- After a merge: unsubscribe from the PR and cancel any check-in you armed. They only existed to
  watch something that is now closed.

**Never merge or approve on your own initiative** — only when the person asks for it in their own
words.

## 7. Adapting to another stack

Only the install step and the run command change. The branch model, the trigger rules, the three
guards and the verification method are the same everywhere.

**Godot** (proven here, Godot 4.7.2 headless):

```bash
# Install: a GitHub release zip. Cache it on the version key.
url="https://github.com/godotengine/godot/releases/download/${V}-stable/Godot_v${V}-stable_linux.x86_64.zip"
# No apt packages needed: the binary links only against core glibc (libc, libdl, libm,
# libpthread, librt) and statically links the rest, so no X11, fontconfig or audio deps.

# REQUIRED first pass, not merely useful: a --script run resolves `class_name` through
# .godot/global_script_class_cache.cfg, which ONLY the editor writes. A fresh checkout has no
# .godot, so without this the suite dies on "Could not find base class".
godot --headless --editor --quit --path .      # read its output: it exits 0 even on parse errors
godot --headless --path . --script tests/run_tests.gd
```

**Node/TypeScript**: `actions/setup-node` with a pinned version + `npm ci`; the count guard reads
the reporter's summary line. **Python**: `actions/setup-python` + a pinned install; parse
`pytest`'s `N passed` line. In both, the "tests vanished" failure mode is just as real — a bad
import collects fewer tests and still exits 0.

## Checklist

- [ ] `development` created, pushed, and (by the person) set as default
- [ ] Workflow covers both long-lived branches, with the `if` guard against double runs
- [ ] Toolchain version pinned **and verified** in a step
- [ ] All three guards present: build errors, suite verdict, check-count floor
- [ ] Run-step bodies extracted and tested verbatim against a fresh clone, all four scenarios
- [ ] First real run's **log** read, not just its conclusion
- [ ] README says which branch is which and what the count floor means

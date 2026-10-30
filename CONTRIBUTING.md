# Contributing to kkore

kkore is a submodule of [kbool](https://github.com/Keksov/kbool), and its tests
need the whole tree. The full guide — the one test command, what CI checks,
what the verdicts mean, the house rules — is
[kbool's CONTRIBUTING.md](https://github.com/Keksov/kbool/blob/main/CONTRIBUTING.md).

Work in the `kkore/` folder of a kbool checkout
(`git clone --recurse-submodules https://github.com/Keksov/kbool.git`) and send
the pull request here, against `main`.

* The suite is `tests/` — gate suite id `kkore`. `kbool.sh` loads these units
  for everything else, so a kkore change is checked with every suite: from the
  kbool root, `bash ktests/tools/gate.sh all`.
* `tests/015_DocExamples.sh` runs the `<!-- doctest -->` examples of
  [README.md](README.md) and of kbool's README; `tests/017_GnuTools.sh` the
  `ktool` resolver. `unit_fixture.sh`, `unit_lint.sh` and `doc_examples.sh` are
  helpers, not test files ([README §8](README.md#8-tests)).
* What the loader and the configuration trust: [README §5](README.md#5-security-notes).
* `tests/018_Bash51Hazards.sh` checks the bash 5.1 floor over the non-test code.
* CI: `.github/workflows/ci.yml` runs kbool's 13 rows with your PR in place of
  kkore; the checks are named `kbool / linux (debian 13)` and so on.

# Evaluating the anti-slop skill

Maintainer tooling for `.claude/skills/anti-slop`. Nothing here ships in the skill: the skill itself never calls a CLI or another model. These scripts stand in for a user, sending each test request through a real `claude -p` session with and without the skill installed, then blind-grading the answers.

The test set is `.claude/skills/anti-slop/evals/evals.json`: the 18 cases in `fixtures/editorial-cases.json`, each phrased as a person would ask, at three Sentence Complexity levels (Balanced, Caveman, Lawyer). That makes 54 tests. Four fixture review rules that named settings prompt 0.3 removed are restated in the eval set. Run it after any change to `prompts/`, the Sentence Complexity guidance or `SKILL.md`. The last recorded run is [evidence/skill-eval-0.3.md](../../evidence/skill-eval-0.3.md); the earlier [evidence/skill-eval.md](../../evidence/skill-eval.md) predates prompt 0.3 and is historical. It uses the signed-in Claude Code account and synthetic fixture text only.

1. **Run the sessions** (about 5 minutes at six at a time):

   ```sh
   python3 app/scripts/skill-eval/run_cli_evals.py --skill .claude/skills/anti-slop \
     --evals .claude/skills/anti-slop/evals/evals.json --workspace /tmp/anti-slop-ws --iteration 1
   ```

   Run it from a plain terminal where `claude auth status` reports `loggedIn: true`. If you start it from inside another Claude Code session, such as the Claude desktop app, prefix the command with `env -i HOME="$HOME" USER="$USER" PATH="$PATH" LANG=en_US.UTF-8 TMPDIR="$TMPDIR"`. Otherwise the test sessions inherit that session's variables, such as its effort setting and sign-in channel.

   Each run gets a fresh folder. With the skill, the folder's `.claude/skills/anti-slop` holds a copy, so Claude Code decides for itself whether to use it, which also measures triggering. Results go to `<workspace>/iteration-N/eval-<id>-<name>/<config>/run-1/`.

2. **Blind the replies** for grading:

   ```sh
   python3 app/scripts/skill-eval/grading_io.py build --evals .claude/skills/anti-slop/evals/evals.json \
     --iteration-dir /tmp/anti-slop-ws/iteration-1 > /tmp/anti-slop-ws/grade-args.json
   ```

   Each reply is written to a file named only by a shuffled letter, so graders never see which configuration produced it.

3. **Grade**: run `grade-workflow.js` with Claude Code's Workflow tool, passing the contents of `grade-args.json` as its `args`. For each case, a blind judge and an adversarial fidelity checker read all six answers, and an independent arbiter settles any disagreement about meaning. Save the workflow's result as `graded.json`.

4. **Write the gradings and the benchmark**:

   ```sh
   python3 app/scripts/skill-eval/grading_io.py write --evals .claude/skills/anti-slop/evals/evals.json \
     --iteration-dir /tmp/anti-slop-ws/iteration-1 --graded graded.json
   ```

   Then use skill-creator's `scripts/aggregate_benchmark.py` and `eval-viewer/generate_review.py --static` for the benchmark and a review page.

`test_skill_scripts.py` is a stdlib unit test for the skill's two helpers (`protected_terms.py` and `validate_response.py`), including a check that the validator's keys and limits match `schemas/rewrite-response.schema.json`. Run `python3 app/scripts/skill-eval/test_skill_scripts.py` after changing either script.

`trigger-eval.json` holds 20 realistic requests, 10 that should use the skill and 10 near-misses that should not (AI detection, new writing, summaries, translation, fact-checking, code cleanup, typo-only proofreading). Use it with skill-creator's `scripts/run_eval.py`. Run that from an empty folder that contains only `.claude/`, so its temporary command file lands there and not in this repository.

Grades come from model judges, not people. Human review of meaning and voice, especially on the legal cases, is still required before claiming editorial quality (see PROMPTING.md).



ust push the code to gitlab as it is and the gitlad pipeline can efficently input custom value, find where the main code is, where test cases are so it automatically adjust small things to fit the code but preserve main core peipleines

Here’s the detailed refactor plan.

## Executive summary

Refactor the universal repo from **input-heavy reusable CI components** into an **Agent AutoCI platform**:

* **one tiny include** in each agent repo
* **runtime discovery** finds code, evals, fixtures, schemas
* **generated child pipeline** runs only the relevant jobs
* **repo-local conventions** replace most CI YAML inputs
* **optional `.ai/agent-ci.yaml`** handles exceptions only

This is the right architecture because GitLab **inputs** and **configuration expressions** are resolved before the pipeline runs, so they are not the right place for “smart detection.” Runtime discovery plus a generated child pipeline is the scalable way to get dynamic behavior. GitLab documents both points directly, and this matches the Auto DevOps pattern of automatic project detection with minimal configuration. ([GitLab Docs][1])

---

# 1. Refactor goals

## Primary goals

* remove most per-repo CI YAML inputs
* let repo owners keep test cases inside their own repos
* auto-detect eval locations and sensible defaults
* preserve one shared core evaluation policy
* keep PR pipelines fast
* make failures easy to debug

## Non-goals

* do not perfectly infer business policy from arbitrary code
* do not auto-guess whether citations are product-required unless declared
* do not force all repos into the exact same folder layout on day 1

---

# 2. Target architecture

## New operating model

### Shared universal repo owns

* discovery engine
* pipeline generator
* eval runner
* common checkers
* artifact contract
* standard reporting

### Each agent repo owns

* code
* eval cases
* fixtures
* schemas
* optional local overrides

## Pipeline shape

### Parent pipeline

Runs:

* existing lint/type/unit tests
* `discover_agent_repo`
* `generate_agent_pipeline`
* `trigger_agent_eval_child`

### Child pipeline

Runs:

* fast smoke evals on merge requests
* regression suites on default branch or schedule
* long-context suites only if present
* optional advisory LLM judge jobs only if enabled

GitLab recommends parent-child pipelines for projects with independently defined components, and supports generating child configs from artifacts. ([GitLab Docs][2])

---

# 3. New repo-consumption UX

## What each agent repo should need

### Default case

Only this in `.gitlab-ci.yml`:

```yaml
include:
  - project: your-group/ai-agent-ci
    file: /templates/bootstrap.yml
    ref: v2.0.0
```

GitLab supports reusing configuration this way with `include`, and using project-hosted shared configuration is a standard pattern. ([GitLab Docs][3])

### Optional override file

Only for exceptions:

```text
.ai/agent-ci.yaml
```

This file is the escape hatch, not the default integration path.

---

# 4. Convention-over-configuration contract

## Preferred repo layout

```text
.ai/
  evals/
    smoke/
    regression/
    long_context/
  fixtures/
  schemas/
  agent-ci.yaml
```

## Supported fallback layouts

Your discovery engine should also support:

```text
evals/
tests/evals/
qa/evals/
agent_evals/
```

## Supported case file patterns

Support these by default:

```text
*.eval.yaml
*.eval.yml
*.case.yaml
smoke.yaml
regression.yaml
cases.yaml
```

## Supported profile conventions

* `smoke/`
* `regression/`
* `long_context/`

This is the key usability move: engineers place files in conventional locations, and the CI platform discovers them automatically.

---

# 5. Discovery engine design

Build a `discover_agent_repo` job that scans the checked-out repo and emits `discovery.json` plus `summary.md`.

## It should detect

### Runtime/language

From:

* `pyproject.toml`
* `requirements.txt`
* `poetry.lock`
* `package.json`
* `pnpm-lock.yaml`
* `yarn.lock`

### Candidate entrypoints

Search and score:

* `src/main.py`
* `app/main.py`
* `main.py`
* `src/agent.py`
* `agent.py`
* `src/index.ts`
* `index.ts`
* `server.ts`
* `*/agent/*.py`
* `*/agent/*.ts`

### Eval directories

By precedence:

1. `.ai/evals/`
2. `evals/`
3. `tests/evals/`
4. `qa/evals/`
5. `agent_evals/`

### Profiles

Detect if these folders exist:

* `smoke`
* `regression`
* `long_context`

### Fixtures and schemas

Search:

* `.ai/fixtures/`
* `.ai/schemas/`
* `evals/fixtures/`
* `evals/schemas/`
* `tests/fixtures/`
* `schemas/`

### Optional local override file

If present:

* `.ai/agent-ci.yaml`

## Output format

Example:

```json
{
  "repo_type": "ai_agent",
  "language": "python",
  "package_manager": "poetry",
  "entrypoint_candidates": [
    {"path": "src/agent.py", "score": 0.93},
    {"path": "main.py", "score": 0.61}
  ],
  "selected_entrypoint": "src/agent.py",
  "eval_dirs_found": [".ai/evals", "tests/evals"],
  "selected_eval_dir": ".ai/evals",
  "profiles_found": ["smoke", "regression"],
  "case_files": [
    ".ai/evals/smoke/basic.eval.yaml",
    ".ai/evals/smoke/happy_path.eval.yaml"
  ],
  "fixtures_dir": ".ai/fixtures",
  "schemas_dir": ".ai/schemas",
  "override_file": ".ai/agent-ci.yaml"
}
```

## Important rule

The discovery step should detect **execution shape**, not silently invent evaluation policy.

Good to detect:

* where files are
* what runtime is
* which test profiles exist

Not safe to infer automatically:

* citation policy
* required tools
* which fields are business-critical
* custom compliance rules

---

# 6. Local override file design

Use `.ai/agent-ci.yaml` only when discovery or defaults need help.

## Suggested schema

```yaml
agent_type: rag           # rag | workflow | structured_generation
entrypoint: src/agent.py
eval_dir: .ai/evals
fixtures_dir: .ai/fixtures
schemas_dir: .ai/schemas

profiles:
  smoke: true
  regression: true
  long_context: false

policy:
  citation_mode: required   # required | optional | forbidden
  required_tools:
    - retrieval.search
  custom_checkers: []
```

## Allowed uses

* override entrypoint
* disable a profile
* set citation policy
* declare required tools
* register a custom checker

## Disallowed uses

* replacing the shared core pipeline
* bypassing required core checks without explicit platform approval

---

# 7. Generated child pipeline design

After discovery, generate `generated-config.yml` and trigger it as a child pipeline.

GitLab explicitly supports generating a YAML file in one job and then triggering a child pipeline from that artifact in another job. ([GitLab Docs][4])

## Why this matters

This is the clean fix for your original problem.

Instead of asking repo owners to predeclare:

* where tests are
* what profile to run
* what paths to pass as component inputs

you compute that at runtime, then generate the exact jobs needed.

## Example generated jobs

### Merge request

Generate only:

* `agent_fast_eval`

### Default branch

Generate:

* `agent_fast_eval`
* `agent_regression_eval`

### Scheduled

Generate:

* `agent_fast_eval`
* `agent_regression_eval`
* `agent_long_context_eval`
* optional `agent_advisory_judge_eval`

---

# 8. Core evaluation framework to preserve

Do **not** throw away your original eval logic. Keep it centralized.

OpenAI recommends eval-driven development with task-specific evals and reproducible scoring, and recommends trace grading for workflow-level failures. ([OpenAI Developers][5])

## Must-pass blocking checks

* `schema_valid`
* `required_fields_present`
* `forbidden_fields_absent`
* `no_unresolved_placeholders`
* `task_relevance`
* `no_unsupported_factual_claims`
* `citation_contract_valid` when applicable
* `required_tool_called` when applicable
* `tool_args_valid` when applicable
* `tool_output_consistency` when applicable
* `max_latency_ms`
* `max_total_tokens`
* `max_turns`
* `max_tool_calls`

## Advisory only

* `llm_judge` for:

  * helpfulness
  * completeness
  * clarity
  * actionability

This aligns with OpenAI’s guidance to use structured, reproducible evaluations and captured traces rather than relying on vague one-number quality judgments. ([OpenAI Developers][5])

---

# 9. Test case ownership model

Your universal CI repo should use test cases that already live inside each agent repo.

## Rule

* shared repo owns **runner and grading**
* agent repo owns **cases and fixtures**

This is very close to Auto Test’s philosophy: it uses tests that already exist in the application and automatically detects the stack where possible. ([GitLab Docs][6])

## Case format

Every case should define semantics, not the pipeline.

Example:

```yaml
id: gitlab_issue_summary_basic
profile: smoke
agent_type: rag

input:
  user: "Summarize issue #123 and explain next step"

fixtures:
  - fixtures/gitlab/issue_123.json

contract:
  output_schema: schemas/issue_summary.v1.json
  citations: required
  required_tools:
    - retrieval.search

must_pass:
  - schema_valid
  - required_fields_present
  - task_relevance
  - no_unsupported_factual_claims
  - citation_contract_valid
  - required_tool_called
  - max_latency_ms
  - max_total_tokens
```

The case file should define evaluation semantics. The pipeline should only discover and execute it.

---

# 10. Artifact contract

Every run should emit the same artifact structure.

```text
artifacts/<case-id>/
  response.json
  trace.jsonl
  inputs.json
  grade.json
  summary.md
```

## Why

OpenAI’s trace grading guidance is explicit that trace-level evaluation is how you find workflow-level errors and regressions in agent systems. ([OpenAI Developers][7])

## Minimum contents

### `response.json`

Final model output

### `trace.jsonl`

* turns
* tool calls
* tool outputs
* timing
* token usage

### `grade.json`

Per-check pass/fail with explanations

Example:

```json
{
  "case_id": "gitlab_issue_summary_basic",
  "passed": true,
  "checks": [
    {"name": "schema_valid", "passed": true},
    {"name": "task_relevance", "passed": true},
    {"name": "citation_contract_valid", "passed": true},
    {"name": "max_latency_ms", "passed": true, "actual": 3510, "limit": 10000}
  ]
}
```

---

# 11. Detailed implementation phases

## Phase 0: freeze and map current state

### Tasks

* inventory current component inputs
* identify most common per-repo custom fields
* group them into:

  * truly necessary
  * discoverable
  * legacy clutter
* map current onboarding pain points

### Deliverables

* input audit doc
* migration candidate list
* compatibility matrix

### Exit criteria

* you know which current inputs can be removed

---

## Phase 1: create bootstrap-only integration

### Tasks

* create `/templates/bootstrap.yml`
* reduce repo integration to one include
* keep old component path working temporarily

### Deliverables

* bootstrap template
* migration instructions
* versioned release tag

### Exit criteria

* a new repo can onboard with one include only

---

## Phase 2: build discovery engine

### Tasks

* implement `discover.py`
* detect runtime, entrypoint, eval dirs, fixtures, schemas
* load `.ai/agent-ci.yaml` if present
* emit `discovery.json`
* emit human-readable `summary.md`

### Deliverables

* discovery module
* scoring rules for entrypoint candidates
* precedence rules for eval directories
* test suite for discovery logic

### Exit criteria

* discovery works on representative Python and TS agent repos

---

## Phase 3: build pipeline generator

### Tasks

* implement `generate_pipeline.py`
* convert discovery output into `generated-config.yml`
* add child pipeline trigger job
* support MR/default branch/scheduled variants

### Deliverables

* generator module
* generated child pipeline templates
* pipeline validation tests

### Exit criteria

* generated child pipeline runs correctly from artifact

---

## Phase 4: standardize repo-local conventions

### Tasks

* publish company convention for `.ai/evals/`
* support fallback layouts
* define case file schema
* define `.ai/agent-ci.yaml` schema

### Deliverables

* case schema
* override schema
* quickstart doc
* migration examples

### Exit criteria

* repo owners know where to place eval files without touching CI YAML

---

## Phase 5: preserve and harden eval core

### Tasks

* centralize built-in checkers
* keep blocking vs advisory split
* standardize artifact bundle
* ensure traces are captured for all supported runners

### Deliverables

* checker library
* artifact schema
* reporting format
* compatibility wrappers for common agent runtimes

### Exit criteria

* all supported repos emit consistent results and artifacts

---

## Phase 6: migration and backward compatibility

### Tasks

* keep old input-heavy interface for a temporary transition window
* map old inputs into discovery overrides where possible
* add warnings for deprecated inputs
* create migration script or doc

### Deliverables

* deprecation plan
* migration guide
* compatibility layer

### Exit criteria

* most repos can migrate without custom CI rewrite work

---

## Phase 7: rollout strategy

### Wave 1

* 2–3 representative repos:

  * one RAG repo
  * one workflow/tool repo
  * one structured generation repo

### Wave 2

* 10 repos with mixed languages and layouts

### Wave 3

* company-wide default onboarding path

### Success metrics

* median per-repo integration time
* number of CI inputs required per repo
* percent of repos needing override file
* percent of repos needing manual intervention
* MR pipeline duration
* eval failure explainability

---

# 12. Discovery rules you should implement

## Eval dir precedence

1. `.ai/evals/`
2. `evals/`
3. `tests/evals/`
4. `qa/evals/`
5. `agent_evals/`

## File inclusion rules

Include:

* `*.eval.yaml`
* `*.eval.yml`
* `*.case.yaml`
* files under `smoke/`, `regression/`, `long_context/`

Ignore:

* `archive/`
* `deprecated/`
* `old/`
* hidden temp directories
* generated files

## Profile selection

### Merge requests

Run only:

* `smoke`

### Default branch

Run:

* `smoke`
* `regression`

### Scheduled

Run:

* `smoke`
* `regression`
* `long_context`
* advisory judge if configured

GitLab pipelines naturally support different execution modes for push, merge request, and schedule events. ([GitLab Docs][3])

---

# 13. Failure behavior

## If no evals are found

Choose one policy:

### Recommended

* if repo clearly looks like an AI repo, warn first for transition period, then fail later
* if repo does not look like an AI repo, noop the agent eval stage

## If multiple candidate entrypoints are found

* choose highest score
* write full ranking to `summary.md`
* allow override in `.ai/agent-ci.yaml`

## If discovery is ambiguous

* fail with actionable message
* print:

  * candidate eval dirs
  * candidate entrypoints
  * expected override file example

This matters because discoverability failures are the main risk in a convention-over-configuration system.

---

# 14. Repo structure for the universal CI repo

```text
ai-agent-ci/
  templates/
    bootstrap.yml
    child-base.yml

  discover/
    discover.py
    rules.py
    scoring.py

  generator/
    generate_pipeline.py
    templates/

  runner/
    run_eval.py

  checkers/
    schema_valid.py
    required_fields_present.py
    forbidden_fields_absent.py
    no_unresolved_placeholders.py
    task_relevance.py
    no_unsupported_factual_claims.py
    citation_contract_valid.py
    required_tool_called.py
    tool_args_valid.py
    tool_output_consistency.py
    budgets.py
    llm_judge.py

  schemas/
    case.schema.json
    override.schema.json
    discovery.schema.json
    grade.schema.json
    trace.schema.json

  docs/
    quickstart.md
    migration.md
    conventions.md
```

---

# 15. Acceptance criteria for the refactor

The refactor is done when:

* a new repo can onboard with **one include**
* most repos need **zero custom CI inputs**
* test cases are auto-discovered from supported locations
* an optional `.ai/agent-ci.yaml` handles edge cases
* child pipelines are generated from runtime discovery
* the original evaluation core still runs consistently
* MR pipelines stay fast
* results are emitted in a standard artifact bundle
* discovery failures are explainable in `summary.md`

---

# 16. What to tell your AI agent to build first

Tell it to implement in this order:

### Step 1

Create `bootstrap.yml` with:

* `discover_agent_repo`
* `generate_agent_pipeline`
* `trigger_agent_eval_child`

### Step 2

Build `discover.py` with:

* eval dir detection
* profile detection
* fixture/schema detection
* entrypoint scoring
* optional `.ai/agent-ci.yaml` loading

### Step 3

Build `generate_pipeline.py` that:

* reads `discovery.json`
* emits `generated-config.yml`
* creates only relevant jobs by pipeline type

### Step 4

Wire the existing eval runner into the child pipeline

### Step 5

Add standard artifacts:

* `discovery.json`
* `summary.md`
* `grade.json`
* `trace.jsonl`

### Step 6

Pilot on 3 repos before broad rollout

---

# 17. Final recommendation

The best refactor is:

**keep your original evaluation core**
but change the integration model to:

**thin include + runtime discovery + generated child pipeline + optional local override file**

That is the most scalable, lowest-friction, professionally correct way to run a company-wide AI agent CI/CD platform on GitLab. It matches GitLab’s strengths around reusable configs, runtime jobs, artifacts, and child pipelines, and it matches OpenAI’s recommendation to build reproducible, trace-backed eval systems with focused, task-specific checks. ([GitLab Docs][4])

I can turn this into a copy-paste implementation spec next.

[1]: https://docs.gitlab.com/ci/inputs/?utm_source=chatgpt.com "CI/CD inputs | GitLab Docs"
[2]: https://docs.gitlab.com/ci/pipelines/pipeline_architectures/?utm_source=chatgpt.com "Pipeline architecture | GitLab Docs"
[3]: https://docs.gitlab.com/ci/pipelines/?utm_source=chatgpt.com "CI/CD pipelines | GitLab Docs"
[4]: https://docs.gitlab.com/ci/pipelines/downstream_pipelines/?utm_source=chatgpt.com "Downstream pipelines | GitLab Docs"
[5]: https://developers.openai.com/api/docs/guides/evaluation-best-practices?utm_source=chatgpt.com "Evaluation best practices | OpenAI API"
[6]: https://docs.gitlab.com/topics/autodevops/stages/?utm_source=chatgpt.com "Stages of Auto DevOps | GitLab Docs"
[7]: https://developers.openai.com/api/docs/guides/trace-grading?utm_source=chatgpt.com "Trace grading | OpenAI API"

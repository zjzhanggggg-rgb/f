:::writing{variant=“standard” id=“18427”}
Build a Stage 1 reusable AI-agent CI eval layer and integrate it into the existing GitLab CI setup without replacing the current basic code-check component. The existing lint, typecheck, and unit test flow stays intact. Your job is to add a small, fast, high-signal eval gate that fits cleanly into the current component-based CI structure. You may choose the best implementation path: adapt the new eval layer to match the current CI conventions, adapt the current CI shape slightly to support the eval layer, or use a hybrid approach. The core functional requirements below are fixed and must not change.

Goal

Create a reusable CI component for AI-agent repos that runs on pushes to main and provides a minimal blocking eval gate for:
	•	structured output contract validity
	•	required fields present
	•	critical regression cases
	•	RAG faithfulness when applicable
	•	tool-call correctness when applicable
	•	runtime safety budgets

This must be:
	•	small
	•	fast
	•	deterministic where possible
	•	easy for other teams to adopt
	•	easy for repos to extend with their own cases later

Do not turn this into a full benchmark platform. This is a CI gate, not a research harness.

Non-negotiable product decisions

These core features must be preserved exactly:
	1.	Keep the existing code-check CI in place
	•	lint, typecheck, unit tests already exist
	•	do not remove or redesign them
	•	integrate the new eval work into the existing component pattern
	2.	The most important reusable abstraction is a normalized run artifact plus a declarative assertion engine
	•	every agent adapter must output the same normalized result shape
	•	test cases should mostly be data/config, not custom eval code
	3.	Stage 1 blocking checks are only these
	•	contract/schema validation
	•	critical smoke cases
	•	faithfulness for RAG-tagged cases only
	•	tool-call correctness for tool-agent-tagged cases only
	•	runtime budget enforcement
	4.	This must support optional expansion later
	•	more cases
	•	long-context cases
	•	slower suites
	•	extra metrics
	•	but those are non-blocking for stage 1

Required architecture

Implement the following reusable pieces.

1. Shared normalized run artifact

Define a versioned JSON schema for a single evaluated agent run. Every agent under test must be adapted into this format.

Minimum fields:

{
  "version": "1",
  "case_id": "string",
  "status": "success | error | timeout",
  "final_output": "string",
  "structured_output": {},
  "tool_calls": [],
  "retrieved_contexts": [],
  "latency_ms": 0,
  "turn_count": 0,
  "error": null,
  "metadata": {}
}

Requirements:
	•	include a strict schema file
	•	support missing sections only when logically optional
	•	final_output must always exist for successful runs, even if empty-string validation later fails
	•	structured_output should be allowed but optional
	•	tool_calls must always be an array
	•	retrieved_contexts must always be an array
	•	latency_ms and turn_count must always be populated
	•	status must be explicit

Also define schemas for nested objects:
	•	tool call entry
	•	retrieved context entry
	•	case definition

2. Declarative case format

Create a simple YAML or JSON case definition format. Keep it human-editable.

Each case should support:

id: refund_window_rag_001
tags: [smoke, critical, rag]
input:
  messages:
    - role: user
      content: "What is the refund window?"
reference: "30 days"
retrieved_contexts:
  - id: doc_12
    text: "Refunds are allowed within 30 days of purchase."
expected:
  assertions:
    - type: json_schema
      schema: answer-v1
    - type: contains_any
      values: ["30 days", "within 30 days"]
    - type: faithfulness
      threshold: 0.9
  budgets:
    max_latency_ms: 3000
    max_turns: 3
    max_tool_calls: 2

Case format must support:
	•	tags
	•	optional reference answer
	•	optional retrieved contexts
	•	optional expected tool calls
	•	assertions list
	•	runtime budgets
	•	optional expected refusal / abstain behavior

Make the format minimal. Do not add many exotic assertion types in stage 1.

3. Assertion engine

Build a reusable assertion engine that reads case files and evaluated run artifacts and returns pass/fail per assertion.

Implement only these built-in assertion types for stage 1:

universal
	•	json_schema
	•	required_fields_present
	•	non_empty_final_output
	•	status_is_success
	•	exact_match
	•	contains_any
	•	regex_match

negative / safety behavior
	•	expect_refusal
	•	expect_insufficient_info

RAG-only
	•	faithfulness

tool-only
	•	tool_call_match

No giant plugin system needed yet, but design code so new assertions can be added later without rewriting the runner.

4. Runtime budget gate

Implement hard checks for:
	•	max latency
	•	max turns
	•	max tool calls
	•	optional max output chars

This must block failures directly and be fast to evaluate.

5. Agent adapter interface

Create a thin adapter contract so each repo can plug in its own agent easily.

The eval runner should call a repo-provided adapter command or module that:
	•	receives a test case input
	•	runs the agent
	•	emits the normalized run artifact

The reusable CI component should not care how the agent is internally implemented.

Support at least:
	•	local python module command
	•	shell command interface

Example:

python -m my_agent.eval_adapter --case path/to/case.yaml --output run.json

Stage 1 blocking policy

Default blocking rules:
	•	schema / contract pass rate: 100%
	•	critical smoke cases: 100%
	•	non-critical smoke overall: configurable, default 90%
	•	faithfulness threshold applies only to cases tagged rag
	•	tool call matching applies only to cases tagged tool
	•	runtime budget failures: 0 allowed
	•	unhandled agent errors in blocking suites: fail job

Use case-level blocking, not only aggregate averages.

Important design constraints

Keep it fast

Target:
	•	small smoke suite only in blocking CI
	•	around 10 to 30 cases total by default
	•	avoid heavy scoring unless tagged and needed
	•	allow teams to add slower suites outside blocking main CI

Keep it high-signal

Prioritize:
	•	contract breakage
	•	obvious output regressions
	•	hallucination on insufficient-evidence cases
	•	broken tool behavior
	•	runaway latency / looping

Keep it reusable

Teams should mostly add:
	•	case files
	•	schemas
	•	adapter command config

They should not need to write new eval code unless absolutely necessary.

Minimum repo/module structure to add

Fit this into the existing repo structure as naturally as possible, but the eval capability must end up equivalent to this:

/ci/components/ai-agent-eval/          # reusable GitLab CI component or equivalent folder in your existing pattern
/evals/schemas/run.schema.json
/evals/schemas/case.schema.json
/evals/assertions/
/evals/runner/
/evals/examples/smoke/
/evals/examples/negative/
/evals/output/                         # artifact output path, gitignored

If the existing repo already has a better location for shared CI component code, reuse that instead.

GitLab CI integration requirements

You are integrating into an existing component-based GitLab CI setup. Do not invent a parallel CI world.

Required behavior:
	•	keep current lint/typecheck/unit-test component usage unchanged unless a tiny compatibility adjustment is clearly better
	•	add a new reusable eval component/stage/job
	•	make it callable by other repos with a small number of inputs
	•	publish JUnit XML so failures are visible in GitLab test reports
	•	upload raw JSON outputs and logs as artifacts
	•	ensure the job exits non-zero on blocking failures

The reusable component should accept inputs like:
	•	stage name
	•	adapter command
	•	case path / suite path
	•	tags filter
	•	threshold profile
	•	timeout
	•	optional strict mode

Example desired include style:

include:
  - component: $CI_SERVER_FQDN/company/ci/ai-agent-eval@1.0.0
    inputs:
      stage: test
      adapter_cmd: "python -m my_agent.eval_adapter"
      suite_path: "evals/smoke"
      tags: "smoke"
      profile: "default"

You may adjust the exact input names to align with current component conventions.

JUnit and artifacts

The runner must output:
	1.	JUnit XML with one testcase per eval case
	2.	machine-readable summary JSON
	3.	per-case normalized run artifact JSON
	4.	optional human-readable markdown or text summary

The job must fail based on the runner exit code, not because GitLab parsed a failed testcase.

Metrics/scoring guidance

Contract checks

Use JSON Schema validation for:
	•	run artifact
	•	structured response shape, when provided
	•	case file shape

Faithfulness

Implement for RAG-tagged cases only.

Behavior:
	•	only run when retrieved contexts exist or case explicitly marks itself as RAG
	•	measure whether the answer is supported by provided retrieved context
	•	make this pluggable behind one assertion type so the backend scorer can be swapped later
	•	stage 1 can start with a simple implementation if needed, but keep the assertion contract stable

Tool-call correctness

Implement only for tool-agent-tagged cases.

Compare:
	•	tool name
	•	required arguments
	•	optional sequence order strictness

Stage 1 can support simple exact matching of a normalized tool call list.

Required initial case packs

Create example built-in suites that ship with the reusable system.

1. smoke

Happy path basic regressions:
	•	exact / contains assertions
	•	structured output schema checks
	•	one or two tool call examples
	•	one or two RAG examples

2. negative

Must include “insufficient evidence” cases.
These are important and should be treated as first-class.
Examples:
	•	missing answer in context
	•	contradictory or irrelevant context
	•	expected abstain / “I don’t know”
	•	tool unavailable / expected graceful failure

This is one of the highest-value reusable case types. Do not skip it.

3. contract

Cases specifically for:
	•	required fields
	•	empty output
	•	malformed structured output
	•	error propagation

Configurability

Support these extension points for downstream repos:
	•	add custom case directories
	•	add tags like slow, long_context, extended
	•	choose which tags are blocking
	•	override thresholds via config
	•	provide custom schemas
	•	provide repo-local adapter

But do not require any of this for basic usage.

Implementation sequencing

Tell the coding agent to implement in this order:

Phase 1: foundation
	•	inspect current CI component structure and naming conventions
	•	integrate new eval component into that existing style
	•	add schemas for run artifact and case file
	•	add adapter contract
	•	add minimal runner that executes case files and writes normalized outputs

Phase 2: assertions
	•	add assertion engine
	•	implement universal assertions first
	•	implement runtime budgets
	•	add JUnit XML output
	•	add summary JSON output
	•	fail job correctly on blocking thresholds

Phase 3: AI-agent-specific checks
	•	add faithfulness assertion hook for RAG-tagged cases
	•	add tool-call matching assertion for tool-tagged cases
	•	add negative insufficient-evidence cases

Phase 4: polish
	•	add example suites
	•	add README usage docs
	•	add sample downstream repo integration snippet
	•	add profile/threshold config
	•	ensure artifacts and logs are clean and understandable

Required deliverables

Ask the coding agent to produce all of the following:
	1.	Architecture decision summary
	•	explain how the new eval layer was integrated into the existing CI/component structure
	•	explain whether it used adaptation of current CI, adaptation of plan, or hybrid
	2.	Implementation
	•	reusable CI component
	•	eval runner
	•	assertion engine
	•	schemas
	•	sample adapter
	•	example suites
	•	JUnit/artifact output
	3.	Documentation
	•	how a downstream repo adopts this
	•	how a repo adds a new case
	•	how a repo adds RAG cases
	•	how a repo adds tool-call cases
	•	how to mark cases as non-blocking or slow
	4.	A concrete example pipeline snippet
	•	showing integration with the existing lint/typecheck/unit-test jobs, not replacing them
	5.	A short rationale for anything intentionally deferred
	•	long-context
	•	retrieval precision/recall
	•	multi-turn memory
	•	broad rubric scoring
	•	adversarial suites
	•	slow research-style evals

Explicitly deferred for stage 1

Do not spend time on:
	•	retrieval precision / recall benchmarking
	•	long-context stress suites in blocking CI
	•	memory evals
	•	pairwise model comparison
	•	broad LLM-judge rubric systems
	•	adversarial red-team packs
	•	dashboarding platform work
	•	flaky heuristic-heavy metrics

These can be designed for later extension but should not delay stage 1.

Definition of done

This work is done when:
	•	existing basic code-check CI still works
	•	the new eval gate runs in CI on main pushes
	•	the new eval gate is reusable by multiple agent repos
	•	teams can add cases without writing new framework code
	•	a broken contract, bad critical response, unsupported RAG answer, wrong critical tool call, or budget regression can fail CI
	•	output is visible in GitLab test reports and artifacts
	•	the stage 1 system stays small and understandable

Final implementation principle

Optimize for:
	•	minimum complexity
	•	maximum reuse
	•	fast feedback
	•	high-signal failures
	•	easy downstream self-service

Whenever there is a choice, prefer the design that lets downstream engineers add test cases and schemas instead of framework code.
:::

# Vaibhav Extension Test Plan

## 1) Fast unit tests (no Pi runtime)

Test pure helpers in `src/helpers.ts`:

- `parseMaxIterations`
  - no flag => default 50
  - valid `--max-iterations 7`
  - invalid values (`0`, negative, non-number) => fallback 50
- `renderOutputs`
  - empty outputs => `(none declared)`
  - all files exist => `hasMissing=false`
  - missing files => `hasMissing=true`

## 2) Runtime behavior tests (with mocked context)

Mock `ExtensionCommandContext` / `ExtensionContext` and assert:

- phase lifecycle
  - `startPhase` creates run + checkpoint label + queues `/skill:...`
  - `markPhaseDone` transitions run to `awaiting_finalize`
  - `finalizeRun` performs rewind path (`switchSession` + `navigateTree`)
- loop lifecycle
  - `startLoop` creates loop and queues `/vaibhav-loop-next`
  - `runLoopIteration` creates child session and sets active iteration session
  - loop stop request is honored after finalize
  - complete marker ends loop
- status updates
  - footer status set/cleared correctly as loop starts/stops

## 3) Command wiring tests

Check each command delegates correctly:

- `/vaibhav-init`, `/vaibhav-prd`, `/vaibhav-convert`
- `/vaibhav-loop-start`, `/vaibhav-loop-next`, `/vaibhav-loop-stop`
- `/vaibhav-loop-open`, `/vaibhav-loop-controller`, `/vaibhav-loop-status`
- `/vaibhav-finalize`

## 4) Tool contract tests

`vaibhav_phase_done`:

- unknown run ID => error
- phase mismatch => error
- happy path => queues `/vaibhav-finalize <runId>` and returns success

## 5) Smoke test in real Pi session

Manual but repeatable:

1. Install package from local path/git
2. Run `/vaibhav-prd auth "Add login"`
3. Complete via `vaibhav_phase_done`
4. Confirm finalize dialog appears
5. Confirm summarize+rewind returns to checkpoint
6. Start `/vaibhav-loop-start --max-iterations 2`
7. Use `/vaibhav-loop-open` and `/vaibhav-loop-controller`
8. Verify loop status indicator and `vaibhav-event` custom entries in session

import { randomUUID } from "node:crypto";
import type {
	BeforeAgentStartEvent,
	ExtensionAPI,
	ExtensionCommandContext,
	ExtensionContext,
} from "@mariozechner/pi-coding-agent";
import { parseMaxIterations, renderOutputs } from "./helpers";
import {
	COMPLETE_MARKER,
	type LoopRun,
	PHASE_KINDS,
	type NonLoopPhaseName,
	type PhaseDoneInput,
	type PhaseRun,
	type VaibhavContext,
} from "./types";

export class VaibhavRuntime {
	private readonly phaseRuns = new Map<string, PhaseRun>();
	private readonly activePhaseBySession = new Map<string, string>();
	private readonly loops = new Map<string, LoopRun>();

	constructor(private readonly pi: ExtensionAPI) {}

	private sessionKey(ctx: VaibhavContext): string {
		const sessionFile = ctx.sessionManager.getSessionFile();
		if (sessionFile) return sessionFile;
		return `memory:${ctx.sessionManager.getSessionId()}`;
	}

	private shortId(prefix: string): string {
		return `${prefix}-${randomUUID().slice(0, 8)}`;
	}

	private queueUserMessage(ctx: VaibhavContext, text: string) {
		if (ctx.isIdle()) {
			this.pi.sendUserMessage(text);
		} else {
			this.pi.sendUserMessage(text, { deliverAs: "followUp" });
		}
	}

	private appendVaibhavEvent(kind: string, data: Record<string, unknown>) {
		this.pi.appendEntry("vaibhav-event", {
			kind,
			timestamp: new Date().toISOString(),
			...data,
		});
	}

	private activeLoop(): LoopRun | undefined {
		return [...this.loops.values()].find((loop) => loop.active);
	}

	private findLoop(requested: string): LoopRun | undefined {
		if (requested.trim()) return this.loops.get(requested.trim());
		return this.activeLoop();
	}

	private updateLoopStatusLine(ctx: VaibhavContext) {
		const loop = this.activeLoop();
		if (!loop) {
			ctx.ui.setStatus("vaibhav-loop", undefined);
			return;
		}
		const suffix = loop.stopRequested ? " · stopping" : "";
		ctx.ui.setStatus("vaibhav-loop", `🔁 ${loop.id} ${loop.iteration}/${loop.maxIterations}${suffix}`);
	}

	private async finalizeNonLoopRun(run: PhaseRun, ctx: ExtensionCommandContext) {
		const outputs = renderOutputs(run.cwd, run.outputs);
		let confirmed = true;

		if (!run.autoConfirm && ctx.hasUI) {
			const message = [
				`Phase: ${run.phase}`,
				`Run: ${run.id}`,
				"",
				"Summary:",
				run.summary ?? "(none)",
				"",
				"Outputs:",
				...outputs.lines,
				"",
				"Summarize branch and return to checkpoint?",
			].join("\n");
			confirmed = await ctx.ui.confirm("Finalize vaibhav phase", message);
		}

		if (!confirmed) {
			this.appendVaibhavEvent("phase_finalize_cancelled", { runId: run.id, phase: run.phase });
			ctx.ui.notify(`Finalize cancelled for ${run.id}. Run /vaibhav-finalize ${run.id} again when ready.`, "info");
			return;
		}

		if (run.checkpointSessionFile && ctx.sessionManager.getSessionFile() !== run.checkpointSessionFile) {
			const switched = await ctx.switchSession(run.checkpointSessionFile);
			if (switched.cancelled) {
				ctx.ui.notify("Could not switch back to checkpoint session.", "error");
				return;
			}
		}

		if (run.checkpointLeafId) {
			const treeResult = await ctx.navigateTree(run.checkpointLeafId, {
				summarize: true,
				label: `vaibhav:${run.phase}:summary:${run.id}`,
			});
			if (treeResult.cancelled) {
				ctx.ui.notify("Tree navigation was cancelled; phase remains finalized but context was not rewound.", "warning");
			}
		} else {
			ctx.ui.notify("No checkpoint leaf was available to rewind to.", "warning");
		}

		run.status = "completed";
		this.appendVaibhavEvent("phase_finalized", {
			runId: run.id,
			phase: run.phase,
			summary: run.summary,
			outputs: run.outputs,
			missingOutputs: outputs.hasMissing,
		});
		ctx.ui.notify(
			`Finalized ${run.phase} (${run.id})${outputs.hasMissing ? " — some declared outputs are missing" : ""}`,
			outputs.hasMissing ? "warning" : "info",
		);
	}

	private async finalizeLoopRun(run: PhaseRun, ctx: ExtensionCommandContext) {
		run.status = "completed";

		if (!run.loopId) {
			ctx.ui.notify(`Loop metadata missing for ${run.id}`, "error");
			return;
		}

		const loop = this.loops.get(run.loopId);
		if (!loop) {
			ctx.ui.notify(`Loop ${run.loopId} not found`, "warning");
			return;
		}

		if (ctx.sessionManager.getSessionFile() !== loop.controllerSessionFile) {
			const switched = await ctx.switchSession(loop.controllerSessionFile);
			if (switched.cancelled) {
				ctx.ui.notify("Could not switch back to loop controller session.", "error");
				return;
			}
		}

		loop.activeIterationSessionFile = undefined;
		this.appendVaibhavEvent("loop_iteration_finalized", {
			loopId: loop.id,
			runId: run.id,
			iteration: loop.iteration,
			sessionFile: run.sessionFile,
			summary: run.summary,
			outputs: run.outputs,
			complete: run.complete ?? false,
		});

		if (run.complete || (run.summary && run.summary.includes(COMPLETE_MARKER))) {
			loop.active = false;
			loop.activeIterationSessionFile = undefined;
			this.updateLoopStatusLine(ctx);
			this.appendVaibhavEvent("loop_completed", { loopId: loop.id, iteration: loop.iteration });
			ctx.ui.notify(`Loop ${loop.id} complete after ${loop.iteration} iteration(s).`, "info");
			return;
		}

		if (loop.stopRequested) {
			loop.active = false;
			loop.activeIterationSessionFile = undefined;
			this.updateLoopStatusLine(ctx);
			this.appendVaibhavEvent("loop_stopped", { loopId: loop.id, iteration: loop.iteration });
			ctx.ui.notify(`Loop ${loop.id} stopped by user after iteration ${loop.iteration}.`, "info");
			return;
		}

		if (loop.iteration >= loop.maxIterations) {
			loop.active = false;
			loop.activeIterationSessionFile = undefined;
			this.updateLoopStatusLine(ctx);
			this.appendVaibhavEvent("loop_max_iterations", {
				loopId: loop.id,
				iteration: loop.iteration,
				maxIterations: loop.maxIterations,
			});
			ctx.ui.notify(`Loop ${loop.id} reached max iterations (${loop.maxIterations}).`, "warning");
			return;
		}

		this.updateLoopStatusLine(ctx);
		this.queueUserMessage(ctx, `/vaibhav-loop-next ${loop.id}`);
	}

	async startPhase(ctx: ExtensionCommandContext, phase: NonLoopPhaseName, args: string) {
		const key = this.sessionKey(ctx);
		const activeRunId = this.activePhaseBySession.get(key);
		if (activeRunId) {
			ctx.ui.notify(`Another vaibhav phase is already active in this session (${activeRunId}).`, "warning");
			return;
		}

		const runId = this.shortId("run");
		const checkpointLeafId = ctx.sessionManager.getLeafId();
		const currentSessionFile = ctx.sessionManager.getSessionFile();

		const run: PhaseRun = {
			id: runId,
			phase,
			status: "running",
			sessionKey: key,
			sessionFile: currentSessionFile,
			checkpointLeafId,
			checkpointSessionFile: currentSessionFile,
			cwd: ctx.cwd,
			createdAt: new Date().toISOString(),
			autoConfirm: false,
		};

		this.phaseRuns.set(runId, run);
		this.activePhaseBySession.set(key, runId);

		if (checkpointLeafId) {
			this.pi.setLabel(checkpointLeafId, `vaibhav:${phase}:checkpoint:${runId}`);
		}

		const skillInvocation = args.trim().length > 0 ? `/skill:${phase} ${args}` : `/skill:${phase}`;
		const kickoff = `${skillInvocation}

Run contract for this phase:
- Keep collaborating with the user until this phase is truly complete.
- When complete, call tool vaibhav_phase_done with:
  - runId: "${runId}"
  - phase: "${phase}"
  - summary: short summary of what was completed
  - outputs: list of key files written/updated
- Only call vaibhav_phase_done when the user-facing task is complete.`;

		this.appendVaibhavEvent("phase_started", { runId, phase, args: args.trim() || undefined });
		ctx.ui.notify(`Started ${phase} (${runId})`, "info");
		this.queueUserMessage(ctx, kickoff);
	}

	async finalizeRun(ctx: ExtensionCommandContext, runId: string) {
		const run = this.phaseRuns.get(runId);
		if (!run) {
			ctx.ui.notify(`Run not found: ${runId}`, "error");
			return;
		}

		if (run.status !== "awaiting_finalize") {
			ctx.ui.notify(`Run ${runId} is not ready to finalize (status: ${run.status}).`, "warning");
			return;
		}

		if (run.phase === "vaibhav-loop-iteration") {
			await this.finalizeLoopRun(run, ctx);
		} else {
			await this.finalizeNonLoopRun(run, ctx);
		}
	}

	async runLoopIteration(ctx: ExtensionCommandContext, loopId: string) {
		const loop = this.loops.get(loopId);
		if (!loop) {
			ctx.ui.notify(`Loop not found: ${loopId}`, "error");
			return;
		}
		if (!loop.active) {
			ctx.ui.notify(`Loop ${loopId} is not active.`, "warning");
			return;
		}
		if (loop.stopRequested) {
			loop.active = false;
			loop.activeIterationSessionFile = undefined;
			this.updateLoopStatusLine(ctx);
			this.appendVaibhavEvent("loop_stopped", { loopId: loop.id, iteration: loop.iteration });
			ctx.ui.notify(`Loop ${loop.id} stopped.`, "info");
			return;
		}
		if (loop.iteration >= loop.maxIterations) {
			loop.active = false;
			loop.activeIterationSessionFile = undefined;
			this.updateLoopStatusLine(ctx);
			this.appendVaibhavEvent("loop_max_iterations", {
				loopId: loop.id,
				iteration: loop.iteration,
				maxIterations: loop.maxIterations,
			});
			ctx.ui.notify(`Loop ${loop.id} reached max iterations (${loop.maxIterations}).`, "warning");
			return;
		}

		if (ctx.sessionManager.getSessionFile() !== loop.controllerSessionFile) {
			const switched = await ctx.switchSession(loop.controllerSessionFile);
			if (switched.cancelled) {
				ctx.ui.notify("Could not switch to loop controller session.", "error");
				return;
			}
		}

		const nextIteration = loop.iteration + 1;
		this.appendVaibhavEvent("loop_iteration_starting", { loopId: loop.id, iteration: nextIteration });

		const child = await ctx.newSession({ parentSession: loop.controllerSessionFile });
		if (child.cancelled) {
			ctx.ui.notify("Creating iteration session was cancelled.", "warning");
			return;
		}

		loop.iteration += 1;
		const currentIterationSessionFile = ctx.sessionManager.getSessionFile();
		loop.activeIterationSessionFile = currentIterationSessionFile;
		if (currentIterationSessionFile) {
			loop.iterationSessionFiles.push(currentIterationSessionFile);
		}
		this.pi.setSessionName(`vaibhav loop ${loop.id} · iter ${loop.iteration}`);

		const key = this.sessionKey(ctx);
		const runId = this.shortId("iter");
		const run: PhaseRun = {
			id: runId,
			phase: "vaibhav-loop-iteration",
			status: "running",
			sessionKey: key,
			sessionFile: ctx.sessionManager.getSessionFile(),
			checkpointLeafId: null,
			checkpointSessionFile: loop.controllerSessionFile,
			cwd: ctx.cwd,
			createdAt: new Date().toISOString(),
			autoConfirm: true,
			loopId: loop.id,
			iteration: loop.iteration,
		};

		this.phaseRuns.set(runId, run);
		this.activePhaseBySession.set(key, runId);

		const kickoff = `/skill:vaibhav-loop

Loop run contract:
- loopId: ${loop.id}
- runId: ${run.id}
- iteration: ${loop.iteration}/${loop.maxIterations}
- Work one story as instructed by the skill.
- When this iteration is complete, call vaibhav_phase_done with:
  - runId: "${run.id}"
  - phase: "vaibhav-loop-iteration"
  - summary: what was completed this iteration
  - outputs: key files changed
  - complete: true only when all stories are done (${COMPLETE_MARKER})`;

		ctx.ui.notify(`Loop ${loop.id}: starting iteration ${loop.iteration}/${loop.maxIterations}`, "info");
		this.updateLoopStatusLine(ctx);
		this.queueUserMessage(ctx, kickoff);
	}

	async startLoop(ctx: ExtensionCommandContext, args: string) {
		const existing = this.activeLoop();
		if (existing) {
			ctx.ui.notify(`Loop already active: ${existing.id}`, "warning");
			return;
		}

		const controllerSessionFile = ctx.sessionManager.getSessionFile();
		if (!controllerSessionFile) {
			ctx.ui.notify("Loop requires a persisted session file (interactive session).", "error");
			return;
		}

		const loopId = this.shortId("loop");
		const loop: LoopRun = {
			id: loopId,
			controllerSessionFile,
			maxIterations: parseMaxIterations(args),
			iteration: 0,
			active: true,
			stopRequested: false,
			createdAt: new Date().toISOString(),
			iterationSessionFiles: [],
		};
		this.loops.set(loopId, loop);

		const leaf = ctx.sessionManager.getLeafId();
		if (leaf) {
			this.pi.setLabel(leaf, `vaibhav:loop:controller:${loopId}`);
		}

		this.appendVaibhavEvent("loop_started", { loopId: loop.id, maxIterations: loop.maxIterations });
		ctx.ui.notify(`Started loop ${loop.id} (max ${loop.maxIterations} iterations)`, "info");
		this.updateLoopStatusLine(ctx);
		this.queueUserMessage(ctx, `/vaibhav-loop-next ${loop.id}`);
	}

	async stopLoop(ctx: ExtensionCommandContext, requested: string) {
		const loop = this.findLoop(requested);
		if (!loop) {
			ctx.ui.notify("No active loop found.", "warning");
			return;
		}
		loop.stopRequested = true;
		this.appendVaibhavEvent("loop_stop_requested", { loopId: loop.id, iteration: loop.iteration });
		this.updateLoopStatusLine(ctx);
		ctx.ui.notify(`Stop requested for loop ${loop.id}. It will stop after current iteration finalizes.`, "info");
	}

	async openLoop(ctx: ExtensionCommandContext, requested: string) {
		const loop = this.findLoop(requested);
		if (!loop) {
			ctx.ui.notify("No active loop found.", "warning");
			return;
		}
		if (!loop.activeIterationSessionFile) {
			ctx.ui.notify("Loop has no active iteration session right now.", "warning");
			return;
		}
		const switched = await ctx.switchSession(loop.activeIterationSessionFile);
		if (switched.cancelled) {
			ctx.ui.notify("Switch to loop session was cancelled.", "warning");
			return;
		}
		ctx.ui.notify(`Switched to loop iteration session for ${loop.id}.`, "info");
	}

	async openLoopController(ctx: ExtensionCommandContext, requested: string) {
		const loop = this.findLoop(requested);
		if (!loop) {
			ctx.ui.notify("No active loop found.", "warning");
			return;
		}
		const switched = await ctx.switchSession(loop.controllerSessionFile);
		if (switched.cancelled) {
			ctx.ui.notify("Switch back to controller was cancelled.", "warning");
			return;
		}
		ctx.ui.notify(`Switched to loop controller session for ${loop.id}.`, "info");
	}

	showLoopStatus(ctx: ExtensionCommandContext) {
		const activeRuns = [...this.phaseRuns.values()].filter((r) => r.status !== "completed");
		const activeLoops = [...this.loops.values()].filter((l) => l.active);

		if (activeRuns.length === 0 && activeLoops.length === 0) {
			ctx.ui.notify("No active vaibhav runs.", "info");
			return;
		}

		const lines: string[] = [];
		if (activeLoops.length > 0) {
			lines.push("Loops:");
			for (const loop of activeLoops) {
				lines.push(`- ${loop.id}: iteration ${loop.iteration}/${loop.maxIterations}${loop.stopRequested ? " (stop requested)" : ""}`);
				if (loop.activeIterationSessionFile) {
					lines.push(`  active iteration session: ${loop.activeIterationSessionFile}`);
				}
			}
			lines.push("  use /vaibhav-loop-open <loopId> to inspect active iteration session");
			lines.push("");
		}

		if (activeRuns.length > 0) {
			lines.push("Phase runs:");
			for (const run of activeRuns) {
				lines.push(`- ${run.id}: ${run.phase} [${run.status}]`);
			}
		}

		ctx.ui.notify(lines.join("\n"), "info");
	}

	markPhaseDone(ctx: ExtensionContext, params: PhaseDoneInput): { ok: boolean; text: string } {
		const run = this.phaseRuns.get(params.runId);
		if (!run) {
			return { ok: false, text: `Run not found: ${params.runId}` };
		}

		if (run.phase !== params.phase) {
			return {
				ok: false,
				text: `Phase mismatch for run ${params.runId}: expected ${run.phase}, got ${params.phase}`,
			};
		}

		run.summary = params.summary;
		run.outputs = params.outputs ?? [];
		run.complete = params.complete ?? false;
		run.status = "awaiting_finalize";
		this.activePhaseBySession.delete(run.sessionKey);
		this.appendVaibhavEvent("phase_done_called", {
			runId: run.id,
			phase: run.phase,
			summary: run.summary,
			outputs: run.outputs,
			complete: run.complete,
		});

		this.queueUserMessage(ctx, `/vaibhav-finalize ${run.id}`);
		return { ok: true, text: `Recorded completion for ${run.phase} (${run.id}). Finalize queued.` };
	}

	handleSessionStart(ctx: ExtensionContext) {
		this.updateLoopStatusLine(ctx);
	}

	handleBeforeAgentStart(event: BeforeAgentStartEvent, ctx: ExtensionContext): { systemPrompt: string } | void {
		const runId = this.activePhaseBySession.get(this.sessionKey(ctx));
		if (!runId) return;
		const run = this.phaseRuns.get(runId);
		if (!run || run.status !== "running") return;

		const toolHint = `\n[VAIBHAV PHASE]\nYou are executing ${run.phase} (runId=${run.id}).\nContinue collaborating with the user until this phase is complete.\nWhen complete, call tool vaibhav_phase_done with:\n{\n  \"runId\": \"${run.id}\",\n  \"phase\": \"${run.phase}\",\n  \"summary\": \"...\",\n  \"outputs\": [\"path1\", \"path2\"]${run.phase === "vaibhav-loop-iteration" ? ',\n  \"complete\": false' : ""}\n}\nDo not call the tool early.`;

		return {
			systemPrompt: event.systemPrompt + "\n\n" + toolHint,
		};
	}

	phaseKinds() {
		return PHASE_KINDS;
	}
}

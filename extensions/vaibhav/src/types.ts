import type { ExtensionCommandContext, ExtensionContext } from "@mariozechner/pi-coding-agent";

export const COMPLETE_MARKER = "<promise>COMPLETE</promise>";

export type PhaseName = "vaibhav-init" | "vaibhav-prd" | "vaibhav-convert" | "vaibhav-loop-iteration";
export type NonLoopPhaseName = Exclude<PhaseName, "vaibhav-loop-iteration">;
export type PhaseStatus = "running" | "awaiting_finalize" | "completed";

export const PHASE_KINDS: readonly PhaseName[] = [
	"vaibhav-init",
	"vaibhav-prd",
	"vaibhav-convert",
	"vaibhav-loop-iteration",
] as const;

export interface PhaseRun {
	id: string;
	phase: PhaseName;
	status: PhaseStatus;
	sessionKey: string;
	sessionFile?: string;
	checkpointLeafId: string | null;
	checkpointSessionFile?: string;
	cwd: string;
	createdAt: string;
	summary?: string;
	outputs?: string[];
	complete?: boolean;
	loopId?: string;
	iteration?: number;
	autoConfirm: boolean;
}

export interface LoopRun {
	id: string;
	controllerSessionFile: string;
	maxIterations: number;
	iteration: number;
	active: boolean;
	stopRequested: boolean;
	createdAt: string;
	activeIterationSessionFile?: string;
	iterationSessionFiles: string[];
}

export interface PhaseDoneInput {
	runId: string;
	phase: PhaseName;
	summary: string;
	outputs?: string[];
	complete?: boolean;
}

export type VaibhavContext = ExtensionContext | ExtensionCommandContext;

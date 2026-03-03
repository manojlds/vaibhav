import { StringEnum } from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import type { VaibhavRuntime } from "./runtime";
import { PHASE_KINDS } from "./types";

export function registerTools(pi: ExtensionAPI, runtime: VaibhavRuntime) {
	pi.registerTool({
		name: "vaibhav_phase_done",
		label: "Vaibhav Phase Done",
		description: "Marks a vaibhav phase as complete and triggers finalize flow (optional tree summarize + rewind).",
		parameters: Type.Object({
			runId: Type.String({ description: "Run ID supplied by the extension" }),
			phase: StringEnum(PHASE_KINDS, { description: "Phase name" }),
			summary: Type.String({ description: "Summary of completed work" }),
			outputs: Type.Optional(Type.Array(Type.String(), { description: "Key files written/updated" })),
			complete: Type.Optional(Type.Boolean({ description: "Set true when loop work is fully complete" })),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const result = await runtime.markPhaseDone(ctx, params);
			return {
				content: [{ type: "text", text: result.text }],
				details: {},
				isError: !result.ok,
			};
		},
	});
}

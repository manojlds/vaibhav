import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import type { VaibhavRuntime } from "./runtime";

export function registerCommands(pi: ExtensionAPI, runtime: VaibhavRuntime) {
	pi.registerCommand("vaibhav-init", {
		description: "Run vaibhav-init skill with completion handshake + tree rewind",
		handler: async (_args, ctx) => {
			await runtime.startPhase(ctx, "vaibhav-init", "");
		},
	});

	pi.registerCommand("vaibhav-prd", {
		description: "Run vaibhav-prd skill with completion handshake + tree rewind",
		handler: async (args, ctx) => {
			const trimmed = args.trim();
			if (!trimmed) {
				ctx.ui.notify("Usage: /vaibhav-prd <name> [description]", "warning");
				return;
			}
			await runtime.startPhase(ctx, "vaibhav-prd", trimmed);
		},
	});

	pi.registerCommand("vaibhav-convert", {
		description: "Run vaibhav-convert skill with completion handshake + tree rewind",
		handler: async (args, ctx) => {
			const trimmed = args.trim();
			if (!trimmed) {
				ctx.ui.notify("Usage: /vaibhav-convert <prd-file>", "warning");
				return;
			}
			await runtime.startPhase(ctx, "vaibhav-convert", trimmed);
		},
	});

	pi.registerCommand("vaibhav-finalize", {
		description: "Finalize an active vaibhav run (internal)",
		handler: async (args, ctx) => {
			const runId = args.trim();
			if (!runId) {
				ctx.ui.notify("Usage: /vaibhav-finalize <runId>", "warning");
				return;
			}
			await runtime.finalizeRun(ctx, runId);
		},
	});

	pi.registerCommand("vaibhav-loop-start", {
		description: "Start automatic fresh-context vaibhav loop",
		handler: async (args, ctx) => {
			await runtime.startLoop(ctx, args);
		},
	});

	pi.registerCommand("vaibhav-loop-next", {
		description: "Run the next vaibhav loop iteration (internal)",
		handler: async (args, ctx) => {
			const loopId = args.trim();
			if (!loopId) {
				ctx.ui.notify("Usage: /vaibhav-loop-next <loopId>", "warning");
				return;
			}
			await runtime.runLoopIteration(ctx, loopId);
		},
	});

	pi.registerCommand("vaibhav-loop-stop", {
		description: "Request stop for active vaibhav loop",
		handler: async (args, ctx) => {
			await runtime.stopLoop(ctx, args);
		},
	});

	pi.registerCommand("vaibhav-loop-open", {
		description: "Switch to active loop iteration session to inspect in-flight work",
		handler: async (args, ctx) => {
			await runtime.openLoop(ctx, args);
		},
	});

	pi.registerCommand("vaibhav-loop-controller", {
		description: "Switch back to loop controller session",
		handler: async (args, ctx) => {
			await runtime.openLoopController(ctx, args);
		},
	});

	pi.registerCommand("vaibhav-loop-status", {
		description: "Show vaibhav phase/loop status",
		handler: async (_args, ctx) => {
			runtime.showLoopStatus(ctx);
		},
	});
}

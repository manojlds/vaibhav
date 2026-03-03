import { describe, expect, it } from "vitest";
import { VaibhavRuntime } from "../src/runtime";
import { createMockCommandContext, createMockExtensionApi, createMockSessionManager } from "./factories/pi";

describe("vaibhav extension unit-test harness", () => {
	it("runs runtime phase startup without a real Pi session", async () => {
		const sessionManager = createMockSessionManager();
		const api = createMockExtensionApi(sessionManager);
		const runtime = new VaibhavRuntime(api as any);
		const ctx = createMockCommandContext({ sessionManager, cwd: "/tmp/vaibhav-project" });

		await runtime.startPhase(ctx as any, "vaibhav-prd", "pi extension unit tests");

		expect(api.sendUserMessages).toHaveLength(1);
		expect(api.sendUserMessages[0].text).toContain("vaibhav_phase_done");
		expect(api.sendUserMessages[0].text).toContain("runId");
		expect(api.labels).toHaveLength(1);
		expect(api.labels[0].label).toContain("vaibhav:vaibhav-prd:checkpoint:run-");
		expect(ctx.ui.notifications.some((n) => n.message.includes("Started vaibhav-prd"))).toBe(true);
	});
});

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { registerCommands } from "./src/commands";
import { registerEvents } from "./src/events";
import { VaibhavRuntime } from "./src/runtime";
import { registerTools } from "./src/tools";

export default function (pi: ExtensionAPI) {
	const runtime = new VaibhavRuntime(pi);
	registerEvents(pi, runtime);
	registerCommands(pi, runtime);
	registerTools(pi, runtime);
}

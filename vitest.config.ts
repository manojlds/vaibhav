import { defineConfig } from "vitest/config";

export default defineConfig({
	test: {
		environment: "node",
		include: ["extensions/vaibhav/test/**/*.test.ts"],
	},
});

#!/usr/bin/env node

import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";

const [, , extensionArgument, stateDirectoryArgument] = process.argv;
assert(extensionArgument, "missing generated Pi extension path");
assert(stateDirectoryArgument, "missing reporter state directory");

const extensionSource = await readFile(resolve(extensionArgument), "utf8");
const extensionURL = `data:text/javascript;base64,${Buffer.from(extensionSource).toString("base64")}`;
const extension = await import(extensionURL);
const handlers = new Map();
extension.default({
  on(event, handler) {
    handlers.set(event, handler);
  },
});

const expectedEvents = [
  "session_start",
  "before_agent_start",
  "tool_execution_start",
  "tool_execution_end",
  "message_end",
  "session_shutdown",
];
assert.deepEqual([...handlers.keys()], expectedEvents);

const stateDirectory = resolve(stateDirectoryArgument);
const context = {
  cwd: "/private/tmp/codewindow-pi-spike",
  sessionManager: { getSessionId: () => "codewindow-pi-spike" },
};
let previousState = "";

async function readChangedState() {
  const deadline = Date.now() + 3_000;
  while (Date.now() < deadline) {
    let files = [];
    try {
      files = (await readdir(stateDirectory)).filter((file) => file.endsWith(".json"));
    } catch {
      // The reporter creates the state directory on its first event.
    }
    if (files.length === 1) {
      const rawState = await readFile(resolve(stateDirectory, files[0]), "utf8");
      if (rawState !== previousState) {
        previousState = rawState;
        return JSON.parse(rawState);
      }
    }
    await new Promise((resolveWait) => setTimeout(resolveWait, 20));
  }
  throw new Error("Pi event did not produce a fresh CodeWindow state within 3 seconds");
}

const latestEvent = (state) => state.feedEvents[state.feedEvents.length - 1];

async function emit(event, payload = {}) {
  const handler = handlers.get(event);
  assert(handler, `missing Pi handler: ${event}`);
  handler(payload, context);
  return readChangedState();
}

const sessionStart = await emit("session_start");
const userPrompt = await emit("before_agent_start", { prompt: "verify Pi integration" });
const toolStart = await emit("tool_execution_start", {
  toolCallId: "pi-tool-1",
  toolName: "bash",
  args: { command: "printf codewindow-pi-spike" },
});
const toolEnd = await emit("tool_execution_end", {
  toolCallId: "pi-tool-1",
  toolName: "bash",
  isError: false,
});
const assistant = await emit("message_end", {
  message: {
    role: "assistant",
    content: [
      { type: "thinking", thinking: "hidden-spike-reasoning" },
      { type: "text", text: "visible spike answer" },
    ],
  },
});
const shutdown = await emit("session_shutdown");

for (const state of [sessionStart, userPrompt, toolStart, toolEnd, assistant, shutdown]) {
  assert.equal(state.agent, "pi");
  assert.equal(state.process.pid, process.pid);
}
assert.equal(sessionStart.activity, "starting");
assert.equal(latestEvent(userPrompt).kind, "user");
assert.equal(userPrompt.taskPreview, "verify Pi integration");
assert.equal(toolStart.action, "runningCommand");
assert.equal(toolStart.actionPreview, "printf codewindow-pi-spike");
assert.equal(latestEvent(toolStart).kind, "toolCall");
assert.equal(latestEvent(toolEnd).kind, "toolResult");
assert.equal(latestEvent(toolEnd).succeeded, true);
assert.equal(latestEvent(toolEnd).operationKey, latestEvent(toolStart).operationKey);
// A finished tool keeps the row it started, instead of falling back to the task prompt.
assert.equal(toolEnd.action, "runningCommand");
assert.equal(toolEnd.actionPreview, "printf codewindow-pi-spike");
assert.equal(latestEvent(assistant).kind, "assistant");
assert.equal(latestEvent(assistant).text, "visible spike answer");
// The closing message is the newest thing that happened, so it owns the row.
assert.equal(assistant.actionPreview, "visible spike answer");
assert(!JSON.stringify(assistant).includes("hidden-spike-reasoning"));
assert.equal(shutdown.activity, "ended");

console.log("PASS generated Pi extension lifecycle");

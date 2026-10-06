/** The main loop's tool calls in the turn running now. */
export type TurnSignalsCounts = { calls: number; failures: number };

/** A tool call that ran and failed, as PostToolUseFailure reported it. */
export type TurnSignalsExecFailure = { id: string; isInterrupt: boolean };

declare module "claude-code" {
  interface PluginState {
    "turn-signals": {
      counts: TurnSignalsCounts;
      execFailed: TurnSignalsExecFailure[];
      agentTypes: { id: string; type: string }[];
    };
  }
}

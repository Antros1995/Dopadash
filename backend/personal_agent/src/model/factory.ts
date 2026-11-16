import type { RuntimeConfig } from "../config/runtime";
import { OpenAiProvider } from "./openai-provider";
import type { AiProvider } from "./types";

export function createAiProvider(
  env: Env,
  config: RuntimeConfig,
): AiProvider {
  switch (config.ai.provider) {
    case "openai":
      return new OpenAiProvider(env.OPENAI_API_KEY, config.ai);
  }
}

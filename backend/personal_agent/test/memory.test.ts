import { describe, expect, it } from "vitest";

import {
  addLongTermMemory,
  appendConversation,
  emptyMemoryState,
} from "../src/memory/service";

describe("Controlled memory", () => {
  it("keeps only a bounded recent conversation", () => {
    let memory = emptyMemoryState();
    for (let index = 0; index < 20; index += 1) {
      memory = appendConversation(memory, "user", `Messaggio ${index}`);
    }
    expect(memory.conversation).toHaveLength(12);
    expect(memory.conversation[0]?.content).toBe("Messaggio 8");
  });

  it("stores explicit long-term memories without duplicates", () => {
    let memory = addLongTermMemory(
      emptyMemoryState(),
      "Preferisco risposte concise",
      new Date(0),
      "memory-1",
    );
    memory = addLongTermMemory(
      memory,
      "preferisco risposte concise",
      new Date(1),
      "memory-2",
    );
    expect(memory.longTerm).toHaveLength(1);
  });

  it("does not append conversation while memory is disabled", () => {
    const memory = appendConversation(
      { ...emptyMemoryState(), enabled: false },
      "user",
      "Non salvare",
    );
    expect(memory.conversation).toHaveLength(0);
  });
});

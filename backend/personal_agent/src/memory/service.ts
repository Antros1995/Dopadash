import type {
  ConversationMemoryItem,
  LongTermMemoryItem,
  MemoryState,
} from "./types";

const MAX_CONVERSATION_ITEMS = 12;
const MAX_CONVERSATION_ITEM_CHARS = 1_500;
const MAX_LONG_TERM_ITEMS = 20;
const MAX_LONG_TERM_ITEM_CHARS = 500;

export function emptyMemoryState(): MemoryState {
  return { enabled: true, conversation: [], longTerm: [] };
}

export function normalizeMemoryState(value: MemoryState | undefined): MemoryState {
  if (!value) return emptyMemoryState();
  return {
    enabled: value.enabled !== false,
    conversation: Array.isArray(value.conversation)
      ? value.conversation.slice(-MAX_CONVERSATION_ITEMS)
      : [],
    longTerm: Array.isArray(value.longTerm)
      ? value.longTerm.slice(-MAX_LONG_TERM_ITEMS)
      : [],
  };
}

export function appendConversation(
  state: MemoryState,
  role: ConversationMemoryItem["role"],
  content: string,
  now = new Date(),
): MemoryState {
  if (!state.enabled) return state;
  const item: ConversationMemoryItem = {
    role,
    content: content.trim().slice(0, MAX_CONVERSATION_ITEM_CHARS),
    createdAt: now.toISOString(),
  };
  return {
    ...state,
    conversation: [...state.conversation, item].slice(-MAX_CONVERSATION_ITEMS),
  };
}

export function addLongTermMemory(
  state: MemoryState,
  content: string,
  now = new Date(),
  id = crypto.randomUUID(),
): MemoryState {
  const normalized = content.trim().slice(0, MAX_LONG_TERM_ITEM_CHARS);
  if (normalized.length === 0) throw new Error("Memory cannot be empty");
  const duplicate = state.longTerm.some(
    (item) => item.content.toLocaleLowerCase() === normalized.toLocaleLowerCase(),
  );
  if (duplicate) return state;

  const item: LongTermMemoryItem = {
    id,
    content: normalized,
    createdAt: now.toISOString(),
  };
  return {
    ...state,
    longTerm: [...state.longTerm, item].slice(-MAX_LONG_TERM_ITEMS),
  };
}

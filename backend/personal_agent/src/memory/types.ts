export interface ConversationMemoryItem {
  role: "user" | "assistant";
  content: string;
  createdAt: string;
}

export interface LongTermMemoryItem {
  id: string;
  content: string;
  createdAt: string;
}

export interface MemoryState {
  enabled: boolean;
  conversation: ConversationMemoryItem[];
  longTerm: LongTermMemoryItem[];
}

export interface MemoryView {
  enabled: boolean;
  conversationItems: number;
  longTerm: LongTermMemoryItem[];
}

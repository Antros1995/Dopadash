import type { EmailClassification } from "./classifier";

export interface GraphEmailAddress {
  name?: string;
  address?: string;
}

export interface GraphMailMessage {
  id: string;
  conversationId?: string;
  subject?: string;
  receivedDateTime?: string;
  sentDateTime?: string;
  bodyPreview?: string;
  importance?: string;
  from?: { emailAddress?: GraphEmailAddress };
  toRecipients?: Array<{ emailAddress?: GraphEmailAddress }>;
}

export interface GraphCollection<T> {
  value: T[];
  "@odata.nextLink"?: string;
}

export interface ImportantEmailView {
  id: string;
  classification: Exclude<EmailClassification, "INFORMATIONAL">;
  reason: string;
  subject: string;
  senderName: string;
  senderAddress: string;
  receivedDateTime: string | null;
  preview: string;
}

export interface ImportantEmailMonitorState {
  enabled: boolean;
  scheduleId: string | null;
  lastScanAt: string | null;
  notifiedMessageIds: string[];
}

export function emptyImportantEmailMonitorState(): ImportantEmailMonitorState {
  return {
    enabled: false,
    scheduleId: null,
    lastScanAt: null,
    notifiedMessageIds: [],
  };
}

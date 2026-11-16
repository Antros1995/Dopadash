export type EmailClassification =
  | "INFORMATIONAL"
  | "IMPORTANT"
  | "ACTION_REQUIRED";

export interface ClassifiableEmail {
  subject?: string;
  bodyPreview?: string;
  importance?: string;
}

export interface EmailClassificationResult {
  classification: EmailClassification;
  reason: string;
}

const ACTION_REQUIRED_PATTERNS = [
  /\baction required\b/iu,
  /\bapproval required\b/iu,
  /\bplease (?:approve|confirm|provide|reply|respond|review|sign)\b/iu,
  /\b(?:approvazione|azione|conferma|firma) richiesta\b/iu,
  /\b(?:devi|occorre|serve) (?:approvare|confermare|firmare|rispondere)\b/iu,
  /\b(?:rispondi|rispondere|rispondete|conferma|confermare|approva|approvare|firma|firmare)\b/iu,
  /\bentro (?:oggi|domani|luned[iì]|marted[iì]|mercoled[iì]|gioved[iì]|venerd[iì]|sabato|domenica|il \d{1,2})\b/iu,
  /\b(?:deadline|scadenza)\b/iu,
];

const IMPORTANT_PATTERNS = [
  /\b(?:urgent|urgente|importante|high priority|priorit[aà] alta)\b/iu,
  /\b(?:security alert|avviso di sicurezza|accesso sospetto)\b/iu,
  /\b(?:incident|outage|servizio non disponibile|interruzione)\b/iu,
  /\b(?:pagamento rifiutato|payment failed|fattura scaduta)\b/iu,
  /\b(?:meeting|riunione|appuntamento).*(?:cancelled|canceled|annullat|spostat|rescheduled)\b/iu,
];

function normalizedText(email: ClassifiableEmail): string {
  return `${email.subject ?? ""}\n${email.bodyPreview ?? ""}`
    .replace(/\s+/gu, " ")
    .trim()
    .slice(0, 4_000);
}

export function classifyEmail(
  email: ClassifiableEmail,
): EmailClassificationResult {
  const text = normalizedText(email);
  if (ACTION_REQUIRED_PATTERNS.some((pattern) => pattern.test(text))) {
    return {
      classification: "ACTION_REQUIRED",
      reason: "Il testo contiene una richiesta esplicita o una scadenza.",
    };
  }

  if (email.importance?.toLocaleLowerCase() === "high") {
    return {
      classification: "IMPORTANT",
      reason: "Il mittente ha contrassegnato il messaggio con priorità alta.",
    };
  }

  if (IMPORTANT_PATTERNS.some((pattern) => pattern.test(text))) {
    return {
      classification: "IMPORTANT",
      reason: "Il testo contiene un segnale importante o urgente.",
    };
  }

  return {
    classification: "INFORMATIONAL",
    reason: "Non sono presenti richieste, scadenze o segnali di priorità.",
  };
}

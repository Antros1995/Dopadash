export class ExpenseDownloadError extends Error { status: number; }
export function validateExpenseLink(value: unknown): string;
export function downloadExpenseWorkbook(value: unknown): Promise<Uint8Array>;
export function downloadGraphExpenseWorkbook(value: unknown, getAccessToken: (forceRefresh: boolean) => Promise<string>): Promise<Uint8Array>;

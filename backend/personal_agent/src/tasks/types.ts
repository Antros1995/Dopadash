export type PersonalTaskGroup = "personal" | "work" | "personal_work";

export interface PersonalTask {
  id: string;
  title: string;
  task_group: PersonalTaskGroup;
  scheduled_date: string;
  completed_at: string | null;
  source: "desktop" | "telegram";
  created_at: string;
}

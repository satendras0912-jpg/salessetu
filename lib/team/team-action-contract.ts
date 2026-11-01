export type TeamActionState = {
  status: "idle" | "success" | "error";
  message: string | null;
  fieldErrors: Record<string, string[]>;
};

export const INITIAL_TEAM_ACTION_STATE: TeamActionState = {
  status: "idle",
  message: null,
  fieldErrors: {},
};

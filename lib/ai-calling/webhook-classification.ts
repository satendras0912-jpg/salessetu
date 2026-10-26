import type { JsonObject, JsonValue } from "./providers/contract";

// A heuristic flags conflicting evidence for review, never proves a human answer.
// Do not use call duration or completed=true to override a voicemail label.
function speakerTurns(value: JsonValue | undefined): number {
  if (!Array.isArray(value)) return 0;
  return value.filter((segment) => {
    if (!segment || typeof segment !== "object" || Array.isArray(segment)) return false;
    const role = String(segment.user ?? segment.role ?? segment.speaker ?? "").toLowerCase();
    const text = segment.text ?? segment.content;
    return ["user", "caller", "human"].includes(role)
      && typeof text === "string" && /[\p{L}\p{N}]/u.test(text);
  }).length;
}

export function needsCallClassificationReview(payload: JsonObject, terminalStatus: string): boolean {
  if (terminalStatus !== "voicemail") return false;
  const transcript = typeof payload.concatenated_transcript === "string"
    ? payload.concatenated_transcript : "";
  const lines = transcript.split(/\r?\n/);
  const callerTurns = lines.filter(line => /^\s*(?:user|caller|human)\s*:\s*.*[\p{L}\p{N}]/iu.test(line)).length;
  return Math.max(callerTurns, speakerTurns(payload.transcripts), speakerTurns(payload.corrected_transcript)) >= 2;
}

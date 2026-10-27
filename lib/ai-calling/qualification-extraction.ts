import type { JsonObject, JsonValue } from "./providers/contract";

export type QualificationQuestion = {
  question_code: string;
  question_text: string;
  question_type: string;
  extraction_instructions: string | null;
  options: JsonValue;
  validation_rules: JsonObject;
};

export function normalizeAnswer(
  answer: JsonValue,
) {
  if (
    typeof answer === "string"
  ) {
    return answer.trim() || null;
  }

  return answer;
}

export function buildExtractionQuestion(
  question: QualificationQuestion,
): string {
  const allowedValues =
    question.validation_rules?.allowed_values ??
    question.options;

  const instructions = [
    question.question_text,
    question.extraction_instructions ?? "",
    "Use only the customer's answers from this call. Never fill missing answers from previous calls or lead profile data.",
    "A clear confirmation of the immediately preceding question is evidence only for that question. A general greeting or agreement to talk is not proof of a property enquiry.",
    "Do not treat the assistant's suggestions as customer agreement.",
    "If the answer is missing or ambiguous, return null.",
  ];

  if (
    question.question_type === "single_choice" &&
    Array.isArray(allowedValues) &&
    allowedValues.length > 0
  ) {
    instructions.push(
      `Return exactly one of these codes: ${JSON.stringify(allowedValues)}.`,
      "Return the code unchanged, without explanation or translation.",
      "Do not return the customer's original wording.",
    );
  }

  if (question.question_code === "site_visit_interest") {
    instructions.push(
      "Use the customer's final explicit requested next action.",
      "Mentioning a site visit does not establish agreement.",
      "If they want details before deciding on a visit, return send_details.",
      "Return site_visit only when they explicitly agree to a visit.",
      "An explicit do-not-call request takes priority.",
    );
  }

  if (question.question_code === "budget_range") {
    instructions.push(
      "Extract the total property budget separately from down payment and loan amount. Convert lakh and crore to INR before selecting a budget code: 1 lakh = 100000 INR; 1 crore = 10000000 INR.",
      "Do not substitute a down payment for the total purchase budget. If only a down payment is stated, leave total budget unknown.",
    );
  }
  if (question.question_code === "purchase_timeline") {
    instructions.push(
      "Retain explicit ranges such as two to three months. Select a permitted code only when its meaning covers that range; do not invent an exact date.",
      "Do not interpret an acknowledgement as today or immediate purchase. The caller must explicitly state the timing.",
    );
  }
  if (question.question_code === "unit_preference") {
    instructions.push("Do not infer BHK from budget, location, or an interrupted unanswered question.");
  }

  return instructions.filter(Boolean).join("\n");
}


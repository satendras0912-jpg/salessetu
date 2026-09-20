export type JsonValue =
  | string
  | number
  | boolean
  | null
  | JsonValue[]
  | {
      [key: string]: JsonValue;
    };

export type JsonObject = {
  [key: string]: JsonValue;
};

export type DispatchAiCallInput = {
  attemptId: string;
  jobId: string;
  phoneNumber: string;
  fromPhoneNumber?: string | null;
  voiceId?: string | null;
  languageCode: string;
  task: string;
  firstSentence?: string | null;
  maximumDurationSeconds: number;
  webhookUrl: string;
  recordCall: boolean;
  requestData?: JsonObject;
  metadata?: JsonObject;
};

export type DispatchAiCallResult = {
  providerCallId: string;
  providerResponse: JsonObject;
};

export type AnalyzeAiCallQuestion = {
  questionCode: string;
  questionText: string;
  expectedAnswerType: string;
};

export type AnalyzeAiCallInput = {
  providerCallId: string;
  goal: string;
  questions: AnalyzeAiCallQuestion[];
};

export type AnalyzeAiCallResult = {
  answers: JsonValue[];
  creditsUsed: number | null;
  providerResponse: JsonObject;
};

export interface AiCallProviderAdapter {
  readonly providerCode: string;

  dispatchCall(
    input: DispatchAiCallInput,
  ): Promise<DispatchAiCallResult>;

  analyzeCall(
    input: AnalyzeAiCallInput,
  ): Promise<AnalyzeAiCallResult>;
}
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

export interface AiCallProviderAdapter {
  readonly providerCode: string;

  dispatchCall(
    input: DispatchAiCallInput,
  ): Promise<DispatchAiCallResult>;
}
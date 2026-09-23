"use client";

import {
  useActionState,
} from "react";

import {
  queueLeadAiCallAction,
  registerLeadAiCallConsentAction,
} from "@/app/dashboard/leads/[leadId]/ai-call-actions";

import type {
  QueueAiCallActionState,
  RegisterAiCallConsentState,
} from "@/app/dashboard/leads/[leadId]/ai-call-actions";

const INITIAL_QUEUE_AI_CALL_STATE:
  QueueAiCallActionState = {
    status: "idle",
    message: null,
    fieldErrors: {},
  };

const INITIAL_CONSENT_STATE: RegisterAiCallConsentState = {
    status: "idle",
    message: null,
  };

type LeadAiCallDispatchCardProps = {
  leadId: string;
  requestToken: string;
  canQueueAiCall: boolean;
  hasCallablePhone: boolean;
};

function SubmitButton({
  disabled,
}: {
  disabled: boolean;
}) {
  return (
    <button
      type="submit"
      disabled={disabled}
      className="inline-flex rounded-xl border border-cyan-700 bg-cyan-950/60 px-4 py-2.5 text-sm font-semibold text-cyan-200 transition hover:border-cyan-500 hover:bg-cyan-900/70 disabled:cursor-not-allowed disabled:border-slate-800 disabled:bg-slate-900 disabled:text-slate-600"
    >
      Queue qualification call
    </button>
  );
}

export default function LeadAiCallDispatchCard({
  leadId,
  requestToken,
  canQueueAiCall,
  hasCallablePhone,
}: LeadAiCallDispatchCardProps) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    queueLeadAiCallAction,
    INITIAL_QUEUE_AI_CALL_STATE,
  );

  const [
  consentState,
  consentFormAction,
  isConsentPending,
] = useActionState(
  registerLeadAiCallConsentAction,
  INITIAL_CONSENT_STATE,
);

  const unavailableReason =
    !canQueueAiCall
      ? "You do not have permission to queue AI calls."
      : !hasCallablePhone
        ? "Add a valid phone number before queueing an AI call."
        : null;

  return (
    <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6 sm:p-8">
      <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
        AI Call Action
      </p>

      <h2 className="mt-3 text-2xl font-bold text-white">
        Queue qualification call
      </h2>

      <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
        Create a secure Hinglish qualification call job
        for this lead. A configured dispatch worker may
        subsequently place a real customer call.
      </p>

      {hasCallablePhone ? (
  <form
    action={consentFormAction}
    className="mt-6 space-y-4 rounded-2xl border border-slate-700 bg-slate-950/60 p-5"
  >
    <input type="hidden" name="leadId" value={leadId} />

    <h3 className="text-lg font-semibold text-white">
      Record AI-call consent
    </h3>

    <p className="text-sm leading-6 text-slate-400">
      Record permission already given by the recipient to receive
      AI-assisted calls about their property enquiry. Saving this
      form does not start a call or grant recording consent.
      Consent-management permission is required.
    </p>

    <label className="block">
      <span className="text-sm font-medium text-slate-200">
        How was consent received?
      </span>

      <select
        name="consentSource"
        required
        defaultValue=""
        disabled={isConsentPending}
        className="mt-2 block w-full rounded-xl border border-slate-700 bg-slate-900 px-3 py-2 text-sm text-white"
      >
        <option value="" disabled>Select a source</option>
        <option value="lead_form">Lead form</option>
        <option value="website">Website</option>
        <option value="whatsapp">WhatsApp</option>
        <option value="verbal">Verbal permission</option>
        <option value="written">Written permission</option>
      </select>
    </label>

    <label className="block">
      <span className="text-sm font-medium text-slate-200">
        Consent evidence
      </span>

      <textarea
        name="consentEvidence"
        required
        minLength={10}
        maxLength={2000}
        rows={3}
        disabled={isConsentPending}
        placeholder="Describe when and how permission was given, its scope, and any evidence reference."
        className="mt-2 block w-full rounded-xl border border-slate-700 bg-slate-900 px-3 py-2 text-sm text-white"
      />
    </label>

    <label className="flex items-start gap-3 text-sm leading-6 text-slate-300">
      <input
        type="checkbox"
        name="consentConfirmation"
        value="confirmed"
        required
        disabled={isConsentPending}
        className="mt-1 h-4 w-4"
      />
      <span>
        I confirm that the recipient granted the AI-call permission
        described above and that this record is accurate.
      </span>
    </label>

    {consentState.message ? (
      <p
        role="status"
        className={
          consentState.status === "success"
            ? "text-sm text-emerald-300"
            : "text-sm text-rose-300"
        }
      >
        {consentState.message}
      </p>
    ) : null}

    <button
      type="submit"
      disabled={isConsentPending}
      className="rounded-xl border border-cyan-700 bg-cyan-950/60 px-4 py-2.5 text-sm font-semibold text-cyan-200 disabled:opacity-50"
    >
      {isConsentPending ? "Saving consent..." : "Save AI-call consent"}
    </button>
  </form>
) : null}

      {unavailableReason ? (
        <div className="mt-5 rounded-xl border border-amber-900/70 bg-amber-950/30 px-4 py-3 text-sm text-amber-300">
          {unavailableReason}
        </div>
      ) : (
        <form
          action={formAction}
          className="mt-6 space-y-5"
        >
          <input
            type="hidden"
            name="leadId"
            value={leadId}
          />

          <input
            type="hidden"
            name="requestToken"
            value={requestToken}
          />

          <label className="flex items-start gap-3 rounded-2xl border border-slate-700 bg-slate-950/60 p-4">
            <input
              type="checkbox"
              name="confirmation"
              value="confirmed"
              disabled={isPending}
              className="mt-1 h-4 w-4 rounded border-slate-600 bg-slate-900 text-cyan-500"
            />

            <span>
              <span className="block text-sm font-semibold text-white">
                Confirm customer call
              </span>

              <span className="mt-1 block text-sm leading-6 text-slate-400">
                I understand that queueing this job may
                result in a real AI call to the lead.
              </span>
            </span>
          </label>

          {state.fieldErrors?.confirmation?.map(
            (message) => (
              <p
                key={message}
                className="text-sm text-rose-300"
              >
                {message}
              </p>
            ),
          )}

          {state.status === "error" &&
          state.message ? (
            <div className="rounded-xl border border-rose-900/70 bg-rose-950/30 px-4 py-3 text-sm text-rose-300">
              {state.message}
            </div>
          ) : null}

          <SubmitButton
            disabled={isPending}
          />

          {isPending ? (
            <p className="text-sm text-slate-400">
              Securely creating the call job…
            </p>
          ) : null}
        </form>
      )}
    </section>
  );
}
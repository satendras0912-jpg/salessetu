"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";

import {
  useActionState,
  useEffect,
  useRef,
  type ReactNode,
} from "react";

import {
  LEAD_CONSENT_STATUSES,
  LEAD_CONTACT_CHANNELS,
  LEAD_LIFECYCLE_STAGES,
  LEAD_PRIORITIES,
  LEAD_PURPOSES,
  LEAD_STATUSES,
  LEAD_TEMPERATURES,
  LEAD_TRANSACTION_TYPES,
  formatLeadOptionLabel,
} from "@/lib/leads/lead-form-contract";

import {
  INITIAL_LEAD_ACTION_STATE,
  type LeadActionState,
  type LeadFieldErrors,
  type LeadFormField,
  type LeadFormMode,
  type LeadFormValues,
} from "@/types/lead-actions";

import type { LeadSourceSummary } from "@/types/leads";

type LeadFormAction = (
  previousState: LeadActionState,
  formData: FormData,
) => Promise<LeadActionState>;

type LeadFormProps = {
  mode: LeadFormMode;
  action: LeadFormAction;
  initialValues: LeadFormValues;
  sources: LeadSourceSummary[];
  cancelHref: string;
};

type FieldShellProps = {
  field: LeadFormField;
  label: string;
  errors: LeadFieldErrors;
  helper?: string;
  children: ReactNode;
};

type FormSectionProps = {
  title: string;
  description: string;
  children: ReactNode;
};

const INPUT_CLASS =
  "w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none transition placeholder:text-slate-600 focus:border-cyan-500 focus:ring-2 focus:ring-cyan-500/20";

const ERROR_INPUT_CLASS =
  "border-red-500 focus:border-red-400 focus:ring-red-500/20";

function getInputClass(
  hasError: boolean,
): string {
  return [
    INPUT_CLASS,
    hasError ? ERROR_INPUT_CLASS : "",
  ]
    .filter(Boolean)
    .join(" ");
}

function FormSection({
  title,
  description,
  children,
}: FormSectionProps) {
  return (
    <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6 sm:p-8">
      <div>
        <h2 className="text-xl font-semibold text-white">
          {title}
        </h2>

        <p className="mt-2 text-sm leading-6 text-slate-400">
          {description}
        </p>
      </div>

      <div className="mt-7 grid gap-5 md:grid-cols-2 xl:grid-cols-3">
        {children}
      </div>
    </section>
  );
}

function FieldShell({
  field,
  label,
  errors,
  helper,
  children,
}: FieldShellProps) {
  const fieldErrors = errors[field] ?? [];

  return (
    <div>
      <label
        htmlFor={field}
        className="mb-2 block text-sm font-medium text-slate-300"
      >
        {label}
      </label>

      {children}

      {helper && fieldErrors.length === 0 ? (
        <p className="mt-2 text-xs leading-5 text-slate-500">
          {helper}
        </p>
      ) : null}

      {fieldErrors.length > 0 ? (
        <div
          id={`${field}-error`}
          className="mt-2 space-y-1"
        >
          {fieldErrors.map((message) => (
            <p
              key={message}
              className="text-xs leading-5 text-red-300"
            >
              {message}
            </p>
          ))}
        </div>
      ) : null}
    </div>
  );
}

function ActionMessage({
  state,
}: {
  state: LeadActionState;
}) {
  if (state.status === "idle" || !state.message) {
    return null;
  }

  const classes =
    state.status === "success"
      ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-200"
      : state.status === "conflict"
        ? "border-amber-500/40 bg-amber-500/10 text-amber-200"
        : "border-red-500/40 bg-red-500/10 text-red-200";

  return (
    <div
      aria-live="polite"
      className={`rounded-2xl border px-5 py-4 text-sm leading-6 ${classes}`}
    >
      {state.message}
    </div>
  );
}

export default function LeadForm({
  mode,
  action,
  initialValues,
  sources,
  cancelHref,
}: LeadFormProps) {
  const router = useRouter();

  const navigationStarted = useRef(false);

  const [state, formAction, isPending] =
    useActionState(
      action,
      INITIAL_LEAD_ACTION_STATE,
    );

  useEffect(() => {
    if (
      state.status !== "success" ||
      !state.leadId ||
      navigationStarted.current
    ) {
      return;
    }

    navigationStarted.current = true;

    const resultFlag =
      mode === "create" ? "created" : "updated";

    router.replace(
      `/dashboard/leads/${state.leadId}?${resultFlag}=1`,
    );
  }, [
    mode,
    router,
    state.leadId,
    state.status,
  ]);

  const errors = state.fieldErrors;

  const submitLabel =
    mode === "create"
      ? "Create lead"
      : "Save changes";

  const pendingLabel =
    mode === "create"
      ? "Creating lead..."
      : "Saving changes...";

  return (
    <form
      action={formAction}
      noValidate
      className="space-y-7"
    >
      <input
        type="hidden"
        name="leadId"
        value={initialValues.leadId}
      />

      <input
        type="hidden"
        name="expectedUpdatedAt"
        value={initialValues.expectedUpdatedAt}
      />

      <ActionMessage state={state} />

      <FormSection
        title="Lead identity and contact"
        description="Enter the customer name and at least one usable contact method."
      >
        <FieldShell
          field="firstName"
          label="First name"
          errors={errors}
        >
          <input
            id="firstName"
            name="firstName"
            type="text"
            defaultValue={initialValues.firstName}
            autoComplete="given-name"
            aria-describedby={
              errors.firstName
                ? "firstName-error"
                : undefined
            }
            className={getInputClass(
              Boolean(errors.firstName),
            )}
          />
        </FieldShell>

        <FieldShell
          field="lastName"
          label="Last name"
          errors={errors}
        >
          <input
            id="lastName"
            name="lastName"
            type="text"
            defaultValue={initialValues.lastName}
            autoComplete="family-name"
            aria-describedby={
              errors.lastName
                ? "lastName-error"
                : undefined
            }
            className={getInputClass(
              Boolean(errors.lastName),
            )}
          />
        </FieldShell>

        <FieldShell
          field="fullName"
          label="Full display name"
          errors={errors}
          helper="Leave blank to generate it from first and last name."
        >
          <input
            id="fullName"
            name="fullName"
            type="text"
            defaultValue={initialValues.fullName}
            autoComplete="name"
            aria-describedby={
              errors.fullName
                ? "fullName-error"
                : undefined
            }
            className={getInputClass(
              Boolean(errors.fullName),
            )}
          />
        </FieldShell>

        <FieldShell
          field="countryCode"
          label="Country code"
          errors={errors}
        >
          <input
            id="countryCode"
            name="countryCode"
            type="text"
            inputMode="tel"
            defaultValue={initialValues.countryCode}
            placeholder="+91"
            aria-describedby={
              errors.countryCode
                ? "countryCode-error"
                : undefined
            }
            className={getInputClass(
              Boolean(errors.countryCode),
            )}
          />
        </FieldShell>

        <FieldShell
          field="phone"
          label="Phone"
          errors={errors}
        >
          <input
            id="phone"
            name="phone"
            type="tel"
            inputMode="tel"
            defaultValue={initialValues.phone}
            autoComplete="tel"
            aria-describedby={
              errors.phone
                ? "phone-error"
                : undefined
            }
            className={getInputClass(
              Boolean(errors.phone),
            )}
          />
        </FieldShell>

        <FieldShell
          field="alternatePhone"
          label="Alternate phone"
          errors={errors}
        >
          <input
            id="alternatePhone"
            name="alternatePhone"
            type="tel"
            inputMode="tel"
            defaultValue={
              initialValues.alternatePhone
            }
            className={getInputClass(
              Boolean(errors.alternatePhone),
            )}
          />
        </FieldShell>

        <FieldShell
          field="whatsappNumber"
          label="WhatsApp number"
          errors={errors}
        >
          <input
            id="whatsappNumber"
            name="whatsappNumber"
            type="tel"
            inputMode="tel"
            defaultValue={
              initialValues.whatsappNumber
            }
            className={getInputClass(
              Boolean(errors.whatsappNumber),
            )}
          />
        </FieldShell>

        <FieldShell
          field="email"
          label="Email"
          errors={errors}
        >
          <input
            id="email"
            name="email"
            type="email"
            defaultValue={initialValues.email}
            autoComplete="email"
            className={getInputClass(
              Boolean(errors.email),
            )}
          />
        </FieldShell>
      </FormSection>

      <FormSection
        title="Lead classification"
        description="Set the commercial status, priority and current lifecycle stage."
      >
        <FieldShell
          field="leadStatus"
          label="Lead status"
          errors={errors}
        >
          <select
            id="leadStatus"
            name="leadStatus"
            defaultValue={initialValues.leadStatus}
            className={getInputClass(
              Boolean(errors.leadStatus),
            )}
          >
            {LEAD_STATUSES.map((value) => (
              <option key={value} value={value}>
                {formatLeadOptionLabel(value)}
              </option>
            ))}
          </select>
        </FieldShell>

        <FieldShell
          field="leadTemperature"
          label="Lead temperature"
          errors={errors}
        >
          <select
            id="leadTemperature"
            name="leadTemperature"
            defaultValue={
              initialValues.leadTemperature
            }
            className={getInputClass(
              Boolean(errors.leadTemperature),
            )}
          >
            <option value="">Not specified</option>

            {LEAD_TEMPERATURES.map((value) => (
              <option key={value} value={value}>
                {formatLeadOptionLabel(value)}
              </option>
            ))}
          </select>
        </FieldShell>

        <FieldShell
          field="priority"
          label="Priority"
          errors={errors}
        >
          <select
            id="priority"
            name="priority"
            defaultValue={initialValues.priority}
            className={getInputClass(
              Boolean(errors.priority),
            )}
          >
            {LEAD_PRIORITIES.map((value) => (
              <option key={value} value={value}>
                {formatLeadOptionLabel(value)}
              </option>
            ))}
          </select>
        </FieldShell>

        <FieldShell
          field="lifecycleStage"
          label="Lifecycle stage"
          errors={errors}
        >
          <select
            id="lifecycleStage"
            name="lifecycleStage"
            defaultValue={
              initialValues.lifecycleStage
            }
            className={getInputClass(
              Boolean(errors.lifecycleStage),
            )}
          >
            {LEAD_LIFECYCLE_STAGES.map(
              (value) => (
                <option key={value} value={value}>
                  {formatLeadOptionLabel(value)}
                </option>
              ),
            )}
          </select>
        </FieldShell>

        <FieldShell
          field="leadSourceId"
          label="Lead source"
          errors={errors}
          helper={
            sources.length === 0
              ? "No active source is configured. The lead can still be created."
              : undefined
          }
        >
          <select
            id="leadSourceId"
            name="leadSourceId"
            defaultValue={
              initialValues.leadSourceId
            }
            className={getInputClass(
              Boolean(errors.leadSourceId),
            )}
          >
            <option value="">No source</option>

            {sources.map((source) => (
              <option
                key={source.id}
                value={source.id}
              >
                {source.name}
              </option>
            ))}
          </select>
        </FieldShell>
      </FormSection>

      <FormSection
        title="Property requirement"
        description="Capture the project, location, unit and budget requirement."
      >
        <FieldShell
          field="propertyType"
          label="Property type"
          errors={errors}
        >
          <input
            id="propertyType"
            name="propertyType"
            type="text"
            defaultValue={
              initialValues.propertyType
            }
            placeholder="Apartment, villa, plot..."
            className={getInputClass(
              Boolean(errors.propertyType),
            )}
          />
        </FieldShell>

        <FieldShell
          field="transactionType"
          label="Transaction type"
          errors={errors}
        >
          <select
            id="transactionType"
            name="transactionType"
            defaultValue={
              initialValues.transactionType
            }
            className={getInputClass(
              Boolean(errors.transactionType),
            )}
          >
            <option value="">Not specified</option>

            {LEAD_TRANSACTION_TYPES.map(
              (value) => (
                <option key={value} value={value}>
                  {formatLeadOptionLabel(value)}
                </option>
              ),
            )}
          </select>
        </FieldShell>

        <FieldShell
          field="preferredProject"
          label="Preferred project"
          errors={errors}
        >
          <input
            id="preferredProject"
            name="preferredProject"
            type="text"
            defaultValue={
              initialValues.preferredProject
            }
            className={getInputClass(
              Boolean(errors.preferredProject),
            )}
          />
        </FieldShell>

        <FieldShell
          field="preferredLocation"
          label="Preferred location"
          errors={errors}
        >
          <input
            id="preferredLocation"
            name="preferredLocation"
            type="text"
            defaultValue={
              initialValues.preferredLocation
            }
            className={getInputClass(
              Boolean(errors.preferredLocation),
            )}
          />
        </FieldShell>

        <FieldShell
          field="preferredCity"
          label="Preferred city"
          errors={errors}
        >
          <input
            id="preferredCity"
            name="preferredCity"
            type="text"
            defaultValue={
              initialValues.preferredCity
            }
            className={getInputClass(
              Boolean(errors.preferredCity),
            )}
          />
        </FieldShell>

        <FieldShell
          field="unitType"
          label="Unit type"
          errors={errors}
        >
          <input
            id="unitType"
            name="unitType"
            type="text"
            defaultValue={initialValues.unitType}
            placeholder="2 BHK, 3 BHK..."
            className={getInputClass(
              Boolean(errors.unitType),
            )}
          />
        </FieldShell>

        <FieldShell
          field="bedrooms"
          label="Bedrooms"
          errors={errors}
        >
          <input
            id="bedrooms"
            name="bedrooms"
            type="number"
            min="0"
            max="20"
            step="1"
            defaultValue={initialValues.bedrooms}
            className={getInputClass(
              Boolean(errors.bedrooms),
            )}
          />
        </FieldShell>

        <FieldShell
          field="budgetMin"
          label="Minimum budget"
          errors={errors}
        >
          <input
            id="budgetMin"
            name="budgetMin"
            type="number"
            min="0"
            step="1000"
            defaultValue={initialValues.budgetMin}
            className={getInputClass(
              Boolean(errors.budgetMin),
            )}
          />
        </FieldShell>

        <FieldShell
          field="budgetMax"
          label="Maximum budget"
          errors={errors}
        >
          <input
            id="budgetMax"
            name="budgetMax"
            type="number"
            min="0"
            step="1000"
            defaultValue={initialValues.budgetMax}
            className={getInputClass(
              Boolean(errors.budgetMax),
            )}
          />
        </FieldShell>

        <FieldShell
          field="budgetCurrency"
          label="Budget currency"
          errors={errors}
        >
          <input
            id="budgetCurrency"
            name="budgetCurrency"
            type="text"
            maxLength={3}
            defaultValue={
              initialValues.budgetCurrency
            }
            placeholder="INR"
            className={getInputClass(
              Boolean(errors.budgetCurrency),
            )}
          />
        </FieldShell>
      </FormSection>

      <FormSection
        title="Intent and communication"
        description="Capture the customer timeline, financing, consent and communication preferences."
      >
        <FieldShell
          field="buyingTimeline"
          label="Buying timeline"
          errors={errors}
        >
          <input
            id="buyingTimeline"
            name="buyingTimeline"
            type="text"
            defaultValue={
              initialValues.buyingTimeline
            }
            placeholder="Within 3 months"
            className={getInputClass(
              Boolean(errors.buyingTimeline),
            )}
          />
        </FieldShell>

        <FieldShell
          field="possessionTimeline"
          label="Possession timeline"
          errors={errors}
        >
          <input
            id="possessionTimeline"
            name="possessionTimeline"
            type="text"
            defaultValue={
              initialValues.possessionTimeline
            }
            className={getInputClass(
              Boolean(
                errors.possessionTimeline,
              ),
            )}
          />
        </FieldShell>

        <FieldShell
          field="purpose"
          label="Buying purpose"
          errors={errors}
        >
          <select
            id="purpose"
            name="purpose"
            defaultValue={initialValues.purpose}
            className={getInputClass(
              Boolean(errors.purpose),
            )}
          >
            <option value="">Not specified</option>

            {LEAD_PURPOSES.map((value) => (
              <option key={value} value={value}>
                {formatLeadOptionLabel(value)}
              </option>
            ))}
          </select>
        </FieldShell>

        <FieldShell
          field="financingRequired"
          label="Financing required"
          errors={errors}
        >
          <select
            id="financingRequired"
            name="financingRequired"
            defaultValue={
              initialValues.financingRequired
            }
            className={getInputClass(
              Boolean(errors.financingRequired),
            )}
          >
            <option value="">Not specified</option>
            <option value="true">Yes</option>
            <option value="false">No</option>
          </select>
        </FieldShell>

        <FieldShell
          field="loanStatus"
          label="Loan status"
          errors={errors}
        >
          <input
            id="loanStatus"
            name="loanStatus"
            type="text"
            defaultValue={
              initialValues.loanStatus
            }
            className={getInputClass(
              Boolean(errors.loanStatus),
            )}
          />
        </FieldShell>

        <FieldShell
          field="preferredLanguage"
          label="Preferred language"
          errors={errors}
        >
          <input
            id="preferredLanguage"
            name="preferredLanguage"
            type="text"
            defaultValue={
              initialValues.preferredLanguage
            }
            placeholder="hi-IN"
            className={getInputClass(
              Boolean(errors.preferredLanguage),
            )}
          />
        </FieldShell>

        <FieldShell
          field="preferredContactChannel"
          label="Preferred contact channel"
          errors={errors}
        >
          <select
            id="preferredContactChannel"
            name="preferredContactChannel"
            defaultValue={
              initialValues.preferredContactChannel
            }
            className={getInputClass(
              Boolean(
                errors.preferredContactChannel,
              ),
            )}
          >
            <option value="">Not specified</option>

            {LEAD_CONTACT_CHANNELS.map(
              (value) => (
                <option key={value} value={value}>
                  {formatLeadOptionLabel(value)}
                </option>
              ),
            )}
          </select>
        </FieldShell>

        <FieldShell
          field="consentStatus"
          label="Consent status"
          errors={errors}
        >
          <select
            id="consentStatus"
            name="consentStatus"
            defaultValue={
              initialValues.consentStatus
            }
            className={getInputClass(
              Boolean(errors.consentStatus),
            )}
          >
            {LEAD_CONSENT_STATUSES.map(
              (value) => (
                <option key={value} value={value}>
                  {formatLeadOptionLabel(value)}
                </option>
              ),
            )}
          </select>
        </FieldShell>

        <FieldShell
          field="consentSource"
          label="Consent source"
          errors={errors}
        >
          <input
            id="consentSource"
            name="consentSource"
            type="text"
            defaultValue={
              initialValues.consentSource
            }
            placeholder="Website form, WhatsApp..."
            className={getInputClass(
              Boolean(errors.consentSource),
            )}
          />
        </FieldShell>
      </FormSection>

      <FormSection
        title="Campaign attribution"
        description="Optional marketing attribution and external-system references."
      >
        <FieldShell
          field="campaignName"
          label="Campaign name"
          errors={errors}
        >
          <input
            id="campaignName"
            name="campaignName"
            type="text"
            defaultValue={
              initialValues.campaignName
            }
            className={getInputClass(
              Boolean(errors.campaignName),
            )}
          />
        </FieldShell>

        <FieldShell
          field="utmSource"
          label="UTM source"
          errors={errors}
        >
          <input
            id="utmSource"
            name="utmSource"
            type="text"
            defaultValue={initialValues.utmSource}
            className={getInputClass(
              Boolean(errors.utmSource),
            )}
          />
        </FieldShell>

        <FieldShell
          field="utmMedium"
          label="UTM medium"
          errors={errors}
        >
          <input
            id="utmMedium"
            name="utmMedium"
            type="text"
            defaultValue={initialValues.utmMedium}
            className={getInputClass(
              Boolean(errors.utmMedium),
            )}
          />
        </FieldShell>

        <FieldShell
          field="utmCampaign"
          label="UTM campaign"
          errors={errors}
        >
          <input
            id="utmCampaign"
            name="utmCampaign"
            type="text"
            defaultValue={
              initialValues.utmCampaign
            }
            className={getInputClass(
              Boolean(errors.utmCampaign),
            )}
          />
        </FieldShell>

        <FieldShell
          field="utmTerm"
          label="UTM term"
          errors={errors}
        >
          <input
            id="utmTerm"
            name="utmTerm"
            type="text"
            defaultValue={initialValues.utmTerm}
            className={getInputClass(
              Boolean(errors.utmTerm),
            )}
          />
        </FieldShell>

        <FieldShell
          field="utmContent"
          label="UTM content"
          errors={errors}
        >
          <input
            id="utmContent"
            name="utmContent"
            type="text"
            defaultValue={initialValues.utmContent}
            className={getInputClass(
              Boolean(errors.utmContent),
            )}
          />
        </FieldShell>

        <FieldShell
          field="externalLeadId"
          label="External lead ID"
          errors={errors}
        >
          <input
            id="externalLeadId"
            name="externalLeadId"
            type="text"
            defaultValue={
              initialValues.externalLeadId
            }
            className={getInputClass(
              Boolean(errors.externalLeadId),
            )}
          />
        </FieldShell>

        <FieldShell
          field="externalProvider"
          label="External provider"
          errors={errors}
        >
          <input
            id="externalProvider"
            name="externalProvider"
            type="text"
            defaultValue={
              initialValues.externalProvider
            }
            placeholder="Meta, Google, Interakt..."
            className={getInputClass(
              Boolean(errors.externalProvider),
            )}
          />
        </FieldShell>
      </FormSection>

      <FormSection
        title="Notes and tags"
        description="Add internal sales notes and searchable tags."
      >
        <div className="md:col-span-2 xl:col-span-3">
          <FieldShell
            field="notes"
            label="Notes"
            errors={errors}
          >
            <textarea
              id="notes"
              name="notes"
              rows={6}
              defaultValue={initialValues.notes}
              className={getInputClass(
                Boolean(errors.notes),
              )}
            />
          </FieldShell>
        </div>

        <div className="md:col-span-2 xl:col-span-3">
          <FieldShell
            field="tags"
            label="Tags"
            errors={errors}
            helper="Separate tags with commas or new lines."
          >
            <textarea
              id="tags"
              name="tags"
              rows={3}
              defaultValue={initialValues.tags}
              placeholder="hot-lead, noida, 3-bhk"
              className={getInputClass(
                Boolean(errors.tags),
              )}
            />
          </FieldShell>
        </div>
      </FormSection>

      <footer className="flex flex-col-reverse justify-between gap-4 rounded-2xl border border-slate-800 bg-slate-900/90 p-5 sm:flex-row sm:items-center">
        <Link
          href={cancelHref}
          className="inline-flex justify-center rounded-xl border border-slate-700 px-6 py-3 text-sm font-semibold text-slate-300 transition hover:border-slate-500 hover:bg-slate-800 hover:text-white"
        >
          Cancel
        </Link>

        <button
          type="submit"
          disabled={isPending}
          className="inline-flex min-w-40 items-center justify-center rounded-xl bg-cyan-400 px-6 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {isPending
            ? pendingLabel
            : submitLabel}
        </button>
      </footer>
    </form>
  );
}
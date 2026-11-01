"use server";

import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";

export async function markNotificationReadAction(
  notificationInboxId: string,
): Promise<{ error?: string }> {
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      notificationInboxId,
    )
  ) {
    return { error: "Invalid alert." };
  }

  const supabase = await createClient();
  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user) {
    return { error: "Your session has expired." };
  }

  const { data: inboxItem, error: inboxError } = await supabase
    .from("notification_inbox")
    .select("id, user_id")
    .eq("id", notificationInboxId)
    .maybeSingle();

  if (inboxError || !inboxItem || inboxItem.user_id !== user.id) {
    return { error: "Alert not found." };
  }

  const { error } = await supabase.rpc(
    "mark_notification_read",
    {
      requested_inbox_id: notificationInboxId,
    },
  );

  if (error) {
    return { error: error.message };
  }

  revalidatePath("/dashboard", "layout");

  return {};
}

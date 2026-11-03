import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import {pushTo} from "./referrals";

/**
 * What to tell the doctor when a ticket moves from [before] to [after], or
 * null when there is nothing to say. Only the step to 'resolved' is news.
 * The Super Admin's resolution note is the body when there is one; the
 * doctor's own subject is left off, since a push shows on a lock screen.
 */
export function ticketResolvedNews(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined,
): {uid: string; title: string; body: string} | null {
  if (!after || after.status !== "resolved") return null;
  if (before?.status === "resolved") return null;
  const uid = typeof after.doctorId === "string" ? after.doctorId : "";
  if (!uid) return null;
  const feedback = after.category === "feedback";
  const note = typeof after.resolution === "string" ? after.resolution.trim() : "";
  return {
    uid,
    title: feedback ? "Your feedback was looked at" : "Your issue is resolved",
    body: note ? note.slice(0, 200) : "Thanks for letting us know.",
  };
}

/**
 * Tells the doctor on their phone when the Super Admin resolves a bug
 * report or feedback they sent. Desktop and an open phone app show the same
 * news from their own listener (support_ticket_watcher.dart).
 */
export const onSupportTicketResolved = onDocumentUpdated(
  {
    document: "support_tickets/{ticketId}",
    region: "asia-south1",
  },
  async (event) => {
    const news = ticketResolvedNews(
      event.data?.before.data(),
      event.data?.after.data(),
    );
    if (!news) return;
    await pushTo(news.uid, news.title, news.body, {
      type: "support_ticket",
      ticketId: event.params.ticketId,
    }, "support");
  },
);

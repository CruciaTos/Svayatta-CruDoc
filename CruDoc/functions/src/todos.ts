import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {pushTo} from "./referrals";

/**
 * Tells a person when a colleague gives them a task (a new to-do assigned
 * to them, or one reassigned to them), so a closed phone still hears it.
 * The app shows the same news itself while it is open, and schedules the
 * task's reminder on the device (features/todos).
 */
export const onTodoAssigned = onDocumentWritten(
  {
    document: "clinics/{clinicId}/todos/{todoId}",
    region: "asia-south1",
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after || after.done === true) return;
    const to = after.assignedTo;
    if (typeof to !== "string" || !to || to === after.createdBy) return;
    if (before && before.assignedTo === to) return;

    const from = typeof after.createdByName === "string" &&
      after.createdByName.trim() ? after.createdByName.trim() : "A colleague";
    const title = typeof after.title === "string" ? after.title : "A task";
    await pushTo(
      to,
      `New task from ${from}`,
      title,
      {
        type: "todo",
        clinicId: event.params.clinicId,
        id: event.params.todoId,
      },
      "tasks",
    );
  },
);

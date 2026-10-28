"use client";

import { useEffect } from "react";

const TASK_HASH_PREFIX = "#follow-up-task-";

function scrollToTaskFromHash() {
  const hash = window.location.hash;

  if (!hash.startsWith(TASK_HASH_PREFIX)) {
    return;
  }

  const task = document.getElementById(hash.slice(1));

  if (!task) {
    return;
  }

  task.focus({ preventScroll: true });
  task.scrollIntoView({ block: "start" });
}

export default function FollowUpTaskHashScroller() {
  useEffect(() => {
    const frame = window.requestAnimationFrame(scrollToTaskFromHash);

    window.addEventListener("hashchange", scrollToTaskFromHash);

    return () => {
      window.cancelAnimationFrame(frame);
      window.removeEventListener("hashchange", scrollToTaskFromHash);
    };
  }, []);

  return null;
}

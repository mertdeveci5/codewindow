import { CheckIcon, CopyIcon } from "lucide-react";
import type React from "react";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { SETUP_PROMPT_URL } from "@/lib/site";

type CopyStatus = "loading" | "idle" | "copying" | "copied" | "failed";

export function CopySetupPromptButton({
  className,
}: {
  className?: string;
}): React.ReactElement {
  const [setupPrompt, setSetupPrompt] = useState<string>();
  const [status, setStatus] = useState<CopyStatus>("loading");

  useEffect(() => {
    const controller = new AbortController();

    void fetch(SETUP_PROMPT_URL, {
      headers: { Accept: "text/markdown" },
      signal: controller.signal,
    })
      .then((response) => {
        if (!response.ok) {
          throw new Error(`Setup prompt request failed with ${response.status}`);
        }
        return response.text();
      })
      .then((prompt) => {
        setSetupPrompt(prompt);
        setStatus("idle");
      })
      .catch((error: unknown) => {
        if (!(error instanceof DOMException && error.name === "AbortError")) {
          setStatus("failed");
        }
      });

    return () => controller.abort();
  }, []);

  useEffect(() => {
    if (status !== "copied" && (status !== "failed" || !setupPrompt)) {
      return;
    }

    const timeout = window.setTimeout(() => setStatus("idle"), 2_000);
    return () => window.clearTimeout(timeout);
  }, [setupPrompt, status]);

  const copySetupPrompt = (): void => {
    if (!setupPrompt) {
      return;
    }

    setStatus("copying");
    void navigator.clipboard.writeText(setupPrompt).then(
      () => setStatus("copied"),
      () => setStatus("failed"),
    );
  };

  const copied = status === "copied";
  const unavailable = status === "failed" && !setupPrompt;
  let label = "Copy setup prompt";
  if (copied) {
    label = "Setup prompt copied";
  } else if (unavailable) {
    label = "Setup prompt unavailable";
  } else if (status === "failed") {
    label = "Copy failed";
  }

  return (
    <Button
      aria-live="polite"
      className={className}
      disabled={unavailable}
      loading={status === "loading" || status === "copying"}
      onClick={copySetupPrompt}
      size="lg"
      variant="outline"
    >
      {copied ? <CheckIcon aria-hidden="true" /> : <CopyIcon aria-hidden="true" />}
      {label}
    </Button>
  );
}

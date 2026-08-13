import { ArrowDownToLineIcon } from "lucide-react";
import type React from "react";
import { Button } from "@/components/ui/button";
import { captureDownloadClicked, type DownloadLocation } from "@/lib/analytics";
import { DOWNLOAD_URL } from "@/lib/site";

interface DownloadButtonProps {
  children: React.ReactNode;
  className?: string;
  location: DownloadLocation;
  size: "lg" | "sm";
}

export function DownloadButton({
  children,
  className,
  location,
  size,
}: DownloadButtonProps): React.ReactElement {
  return (
    <Button
      className={className}
      render={<a href={DOWNLOAD_URL} onClick={() => captureDownloadClicked(location)} />}
      size={size}
    >
      <ArrowDownToLineIcon aria-hidden="true" />
      {children}
    </Button>
  );
}

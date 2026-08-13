import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "@/App";
import "@/index.css";
import { initializeAnalytics } from "@/lib/analytics";

const container = document.getElementById("root");

if (!container) {
  throw new Error("Root container #root was not found");
}

initializeAnalytics();

createRoot(container).render(
  <StrictMode>
    <App />
  </StrictMode>,
);

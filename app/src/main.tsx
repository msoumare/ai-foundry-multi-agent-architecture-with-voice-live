import React from "react";
import { createRoot } from "react-dom/client";
import { Full } from "./Full";
import "./styles.css";

createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <Full />
  </React.StrictMode>,
);
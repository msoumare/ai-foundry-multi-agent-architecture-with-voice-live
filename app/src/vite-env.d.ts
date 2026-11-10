/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_VOICE_LIVE_ENDPOINT?: string;
  readonly VITE_VOICE_LIVE_API_VERSION?: string;
  readonly VITE_TOKEN_TIMEOUT_SECONDS?: string;
  readonly VITE_VOICE_LIVE_DEBUG_LOGGING?: string;
  readonly VITE_FOUNDRY_PROJECT_ENDPOINT?: string;
  readonly VITE_EXPECTED_AGENT_NAME?: string;
  readonly VITE_FOUNDRY_RESOURCE_OVERRIDE_DEFAULT?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
# DevJourney

DevJourney is a native macOS SwiftUI application for agent-assisted software delivery. The app is the primary product surface; MCP is supported as an interoperability layer, not the main runtime.

## Runtime Architecture

- `DevJourney/DevJourney` contains the shipping SwiftUI macOS app.
- Agent execution runs in-app through a BYO-provider runtime with three provider modes:
  - Anthropic
  - OpenAI
  - OpenAI-compatible endpoints with a custom base URL
- Provider configuration is persisted per project and API keys are stored via Keychain-backed references.
- Ticket progress is driven by persisted workflow artifacts instead of transient chat state:
  - `PlanningSpec`
  - `DesignSpec`
  - `DevExecution`
  - `DebugReport`
  - review decisions and clarification threads
- `TicketWorkflowService` owns stage execution, handover gates, clarification routing, and review transitions.

## MCP Support

- The app exposes an MCP stdio server for external clients.
- MCP tools are artifact-centric and feed the same workflow state as the native UI.
- External MCP usage is optional; the default product flow is native execution inside the macOS app.

## Current Scope

- Primary shell: SwiftUI on macOS
- Provider scope: Anthropic, OpenAI, OpenAI-compatible
- Integrations preserved: GitHub context/status tooling, Figma references in design artifacts

## Repository Notes

- `devjourney-web/` is a legacy web prototype and is not the primary architecture for the product.

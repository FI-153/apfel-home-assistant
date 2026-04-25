# apfel-home-assistant

On-device LLM for Home Assistant, powered by Apple Intelligence's foundation model.
Every token stays on your Mac: no cloud, no API key to pay for, no model downloads, full privacy.

Homebrew wrapper around [apfel](https://github.com/Arthur-Ficial/apfel), pre-configured as a
conversation and AI Task backend for [Home Assistant](https://www.home-assistant.io/) via the
[**Apfel AI**](https://github.com/FI-153/apfel-home-assistant-integration) custom integration.

<img width="1326" height="949" alt="Screen Shot 2026-04-21 at 10 00 19 PM" src="https://github.com/user-attachments/assets/83fd5236-dbbe-4473-b14f-e44b63e336bc" />

## Requirements

- macOS 26 (Tahoe) or later on Apple Silicon (M1+).
- Apple Intelligence enabled in **System Settings → Apple Intelligence & Siri**.
- [Home Assistant](https://www.home-assistant.io) with
  [HACS](https://hacs.xyz/) installed (for the Apfel AI custom integration).

The model runs fully on-device through Apple's
[**FoundationModels**](https://developer.apple.com/documentation/foundationmodels) framework —
no network calls leave your Mac, and there are no usage limits.

> [!NOTE]
> The server runs with apfel's `--permissive` flag so Apple's content guardrails are relaxed —
> smart-home commands and routine household prompts are less likely to be refused.

## Install (Homebrew) 🍺

```bash
brew tap FI-153/tap
brew install apfel-home-assistant
apfel-home-assistant setup
brew services start apfel-home-assistant
```

> [!NOTE]
> `setup` picks a free port, mints an API token, and prints the **Base URL**, **API Key**,
> and **Model ID** to paste into Home Assistant. The server starts at login.

## Connect to Home Assistant 🏠

### Apfel AI (recommended)

Supports both conversation and the AI Task platform — the richest integration path.

1. **Install the custom integration via HACS.**
   In HACS → Integrations → ⋮ → **Custom repositories**, add:
   - **URL:** `https://github.com/FI-153/apfel-home-assistant-integration`
   - **Category:** Integration

   Then search for "Apfel AI" and install it, and restart Home Assistant.

2. **Add the integration.** Go to **Settings → Devices & services → Add integration →
   Apfel AI**, then paste the values printed by `setup` (or `show-config`):

   - **Base URL** — `http://<your-mac-lan-ip>:<port>/v1`
   - **API Key** — the token minted by `setup`
   - **Model** — `apple-foundationmodel`

3. **(Optional) Enable device control.** In the integration options, select
   **"Home Assistant"** (Assist) under **LLM API** to let the model control devices.

4. **Wire it into a voice pipeline (optional).** Go to **Settings → Voice assistants**,
   pick a pipeline, and set its **Conversation agent** to the Apfel AI agent.

### Extended OpenAI Conversation (legacy)

Conversation only — does not support the AI Task platform. Use this if you prefer an
integration that does not require a HACS custom repository.

1. **Add the integration.** In Home Assistant, open **Settings → Devices & services →
   Add integration → Extended OpenAI Conversation** and paste the values from `setup`:

   - **Base URL** — `http://<your-mac-lan-ip>:<port>/v1`
   - **API Key** — the token minted by `setup`

2. **Point it at the local model.** On the integration card, click the gear icon and:

   - Set **chat_model** to `apple-foundationmodel`.
   - Clear the default **Functions** field and enter `[]`.
   - Disable **Use Tools**.
   - Adjust the Context Threshold to 4000.
   - Submit.

> [!IMPORTANT]
> The Mac and Home Assistant must be on the same LAN, or Home Assistant must otherwise
> be able to reach the Mac's IP on the chosen port.

## Configuration ⚙️

Config lives at `$(brew --prefix)/etc/apfel-home-assistant.conf`. You rarely need to edit it —
the CLI wraps the common operations:

```bash
apfel-home-assistant show-config     # reprint the Home Assistant integration block
apfel-home-assistant rotate-token    # mint a fresh API key
apfel-home-assistant setup --force   # re-run setup, overwriting port + token
```

After any manual edit:

```bash
brew services restart apfel-home-assistant
```

Logs live at `$(brew --prefix)/var/log/apfel-home-assistant.log`.

> [!IMPORTANT]
> For the server to start on boot without user intervention you need to enable
> [automatic login](https://support.apple.com/en-us/102316) from the Mac's settings.

## Uninstall 🗑️

```bash
brew services stop apfel-home-assistant
brew uninstall apfel-home-assistant
```

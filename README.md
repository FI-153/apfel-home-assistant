# apfel-home-assistant

On-device LLM for Home Assistant, powered by Apple Intelligence's foundation model.
Every token stays on your Mac: no cloud, no API key to pay for, no model downloads, full privacy.

Homebrew wrapper around [apfel](https://github.com/Arthur-Ficial/apfel), pre-configured as a
conversation backend for [Home Assistant](https://www.home-assistant.io/) via the community
[**Extended OpenAI Conversation**](https://github.com/jekalmin/extended_openai_conversation) integration.

## Requirements

- macOS 26 (Tahoe) or later on Apple Silicon (M1+) — inherited from apfel.
- Apple Intelligence enabled in **System Settings → Apple Intelligence & Siri**.
- [Home Assistant](https://www.home-assistant.io) with the
  [Extended OpenAI Conversation](https://github.com/jekalmin/extended_openai_conversation)
  custom integration (installable via [HACS](https://hacs.xyz/)).

The model runs fully on-device through Apple's
[**FoundationModels**](https://developer.apple.com/documentation/foundationmodels) framework —
no network calls leave your Mac, and there are no usage limits.

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

1. **Add the integration.** In Home Assistant, open **Settings → Devices & services →
   Add integration → Extended OpenAI Conversation**, then paste the values that `setup`
   printed:

   - **Base URL** — `http://<your-mac-lan-ip>:<port>/v1`
   - **API Key** — the token minted by `setup`

2. **Point it at the local model.** On the integration's card, click the gear icon next to
   the conversation agent entry and:

   - Set **chat_model** to `apple-foundationmodel`.
   - Clear the default **Functions** field and enter `[]`.
   - Disable **Use Tools**.
   - Adjust the Context Threshold to 4000
   - Submit.

3. **Test it.** Open the conversation agent's entity and use the **Assist** tab to send
   a prompt — the reply should come back from the local model.

4. **Wire it into a voice pipeline (optional).** Go to **Settings → Voice assistants**,
   pick a pipeline, and set its **Conversation agent** to the one you just configured.

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

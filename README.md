# apfel-home-assistant

Homebrew formula that runs [apfel](https://github.com/Arthur-Ficial/apfel) pre-configured as a
conversation backend for [Home Assistant](https://www.home-assistant.io/) via the community
**OpenAI Extended Conversation** integration.

## Install

    brew install FI-153/tap/apfel-home-assistant
    apfel-home-assistant setup
    brew services start apfel-home-assistant

`setup` prints the exact Base URL, API Key, and Model ID to paste into Home Assistant.

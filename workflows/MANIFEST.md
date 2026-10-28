# Workflow manifest — v1.3.0 — 2026-08-29

n8n instance: `https://YOUR_N8N_HOST`
Project: personal (`3tciZCkO4dtYHBy3`)

Filenames follow `<kebab-name>__<n8n-workflow-id>.json`. Restore by matching the id in
the filename, not the name, since names change — `RIXG7dG23n7vH6Y1` was renamed from
"compose question" to "compose reply" in this version, and its file with it.

| Workflow | ID | Published | Active version at export |
|---|---|---|---|
| LQS - Channel: Telegram inbound | `5Vk45QAHDDyTes0W` | yes | `87aa1847-fd51-410b-ae8b-3a111129e4a4` |
| LQS - Core: handle inbound message | `K0NKtJfBGWcU5vYS` | yes | `e7569cdc-d264-4f45-bd6b-c7985582819b` |
| LQS - Channel: send message | `1uHZWNuI2G1IOzVs` | yes | `6ad23222-35b7-492c-84f0-c793ffd9497f` |
| LQS - Lead: resolve identity | `sC0lt9OPiKgENGAz` | yes | `62b4d63c-ebed-457b-abe9-a0247c45237a` |
| LQS - Subworkflow: extract facts | `FDtQFdAlFwsguA6v` | yes | `3f823add-5d1b-4cfa-bd15-683de0dffd97` |
| LQS - Qualification: save answers | `HYIWkq4eUBhmXXHR` | yes | `ef11920d-5d61-44cb-a14d-f16113043b59` |
| LQS - Qualification: decide next step | `hpe6dyktPusHzO8O` | yes | `e5b99a8c-8d3f-4c16-af5e-5269770bee20` |
| LQS - Subworkflow: compose reply | `RIXG7dG23n7vH6Y1` | yes | `0ddf6cb1-b4b3-4022-a477-61144488bc9c` |
| LQS - Listings: search | `RIrTl94qW1hkHG2d` | yes | `4eab910e-b5cf-413a-ae0c-e32e6ef10c3c` |
| LQS - Listings: answer question | `necx1vepzlBnd58Q` | yes | `ed69024a-2e27-44e8-872a-21019ec0ce45` |
| LQS - Booking: offer slots | `YyN9d1h9K66UBKU5` | yes | `b7951bed-63c6-48d5-badc-308573d831b4` |
| LQS - Booking: confirm | `jHZl26o8Ra4xnWPh` | yes | `1d9877de-03fc-4c54-9c4f-ff9c56ab4d97` |
| LQS - Brief: generate and deliver | `WrLLLmNkBCycCyZH` | yes | `863b9a9e-4eb9-4692-8e70-353f338e5921` |
| LQS - Escalation: hand to human | `VjeV6TM8Yi6J729i` | yes | `1222c92b-51cb-4705-9a69-a0776db3d39f` |
| LQS - Error: notify | `f2C3GiauR1vJiIxw` | yes | `5163b5e9-df08-4101-8d5b-d74557a0372b` |

Deliberately not built: `Scheduled: nudge idle conversations` (spec 7.15 and 12).

## What changed in v1.3.0

Six workflows. `LQS - Channel: Telegram inbound` was unpublished while the work was done
and republished unchanged, so it carries a new version id but identical content.

The nine untouched workflows in this folder are byte-identical to their v1.2.0 copies.
The six changed ones were reconciled against the live definitions read back after
publishing; `core-handle-inbound-message` was written directly from the live export, and
the other five were rebuilt from the v1.2.0 base with the published parameter values.

## Credentials referenced

The exports carry credential ids and names so an import binds straight back to the same
credentials on this instance. They contain no secrets.

| Type | Name | ID |
|---|---|---|
| `telegramApi` | (your credential) | `CREDENTIAL_ID` |
| `postgres` | (your credential) | `CREDENTIAL_ID` |
| `googleCalendarOAuth2Api` | (your credential) | `CREDENTIAL_ID` |
| `gmailOAuth2` | (your credential) | `CREDENTIAL_ID` |
| `googlePalmApi` | (your credential) | `CREDENTIAL_ID` |

The new `Mark Booking Declined` node in core uses the existing `postgres` credential.

## Restoring

1. Restore the database first — see `../schema/`. The workflows are useless without the
   `lqs` schema and its seed rows. Migrations 005 to 007 are new in this version.
2. Import each JSON into n8n. Import the sub-workflows before the callers: every
   `Execute Sub-workflow` node references a target by the id above, so if you import into
   a different instance those ids will not resolve and each one must be re-pointed.
   `Compose Reply` in core points at `RIXG7dG23n7vH6Y1`.
3. Publish everything except `LQS - Channel: Telegram inbound`.
4. Publish `LQS - Channel: Telegram inbound` last, and only deliberately — it is the
   switch that puts the bot in front of real people.

## A note on the MCP surface

This version was built through the **official** n8n MCP server (`mcp__claude_ai_n8n__*`),
not the community `n8n-mcp` server that `.claude/CLAUDE.md` and the skills pack assume.
The tool names differ: `get_workflow_details` for `n8n_get_workflow`, `update_workflow`
(operation objects) for `n8n_update_partial_workflow`, and `validate_workflow` takes SDK
code rather than workflow JSON, so it cannot check a partial edit. Verification here was
read-back with `get_workflow_details` plus offline fixtures. There is no `n8n_instances`
tool, so the instance was not switchable and did not need confirming.

Edits land on a **draft**; `publish_workflow` promotes a draft to the active version. A
draft edit therefore cannot affect a running bot, which is a stronger guarantee than the
"edit deactivated" rule in CLAUDE.md assumes.

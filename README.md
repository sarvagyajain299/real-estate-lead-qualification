# Real Estate Lead Qualification System

A Telegram bot, built from 15 n8n workflows and a Postgres schema, that qualifies property enquiries, books a meeting with a sales agent, and sends the agent a briefing before the call.

## The Problem

Property agents get enquiries at all hours from people with very different levels of intent.

- Replies are slow, so serious buyers go to whoever answers first.
- Agents spend time on browsers who have no budget or no timeline.
- The agent starts each call cold, without knowing the buyer's budget, how they plan to pay, or when they want to buy.
- Scripted bots ask the same fixed questions in the same order, repeat themselves, and ignore what the person just said.
- Booking a meeting means a manual back and forth over times.

## The Solution

1. A lead messages the Telegram bot.
2. The bot waits a few seconds to collect any follow-up messages, then reads them together.
3. An LLM pulls structured facts out of the free text (purpose, budget, payment method, timeline, contact).
4. A rules step picks the next action: ask a question, answer a listing question, offer meeting times, or hand over to a person.
5. An LLM writes the reply in its own words from the goal of that turn.
6. When enough is known, the bot offers free slots from the agent's Google Calendar and confirms the one the lead picks.
7. The agent receives a written briefing by Telegram and email, and it is attached to the calendar event.

## How It Helps

- The lead gets a reply within seconds, at any hour.
- The agent sees budget, payment method, timeline, and purpose before the call.
- Low-intent leads (small budget, "just browsing") are marked for nurture and are not offered a meeting.
- Large cash buyers, people who ask for a human, and conversations that stall are escalated to the agent right away.
- The lead can ask about the property catalogue mid-chat and get answers from the database, not from the model's memory.
- A refusal is recorded. After a lead declines a meeting, the bot stops pushing it.

## What Makes It Different

| Feature | How it works here |
|---|---|
| Question order | Rules in SQL (`slot_definitions`): 5 required questions, then optional ones, with conditions and priorities |
| Wording | The model writes each reply from a goal; a stored question is only a fallback if the model fails |
| Message batching | Debounce wait, then a check that no newer message arrived before replying |
| Duplicate protection | Duplicate inbound messages are detected and skipped |
| Escalation rules | Thresholds live in the database, not in workflow code |
| Safe rollout | Workflows are separate; the Telegram trigger is published last |

## How It Works

```
Telegram message
      |
      v
 Channel: Telegram inbound --> Core: handle inbound message
                                      |
     resolve lead -> save message -> debounce -> gate check
                                      |
                  extract facts (LLM) -> save answers
                                      |
                  escalation check --yes--> hand to human
                                      |no
                  decide next step (rules)
                 /        |           \          \
            ask        answer       offer       nurture
         question     listing       slots
              \          |            |
               compose reply (LLM) --> send --> Telegram
                                      |
                       lead picks slot -> confirm booking
                                      |
                  Google Calendar event + agent briefing
```

## Tech Stack

| Part | Tool |
|---|---|
| Orchestration | n8n (15 workflows) |
| Database | Postgres (Supabase), schema `lqs` |
| LLM | Google Gemini (extraction, reply writing, briefing, listing answers) |
| Channel | Telegram Bot API |
| Scheduling | Google Calendar |
| Briefing delivery | Telegram and Gmail |

## Run It Locally

You need an n8n instance, a Postgres database, and your own accounts.

1. Run `schema/001` through `schema/007` in order against Postgres.
2. Edit the seed agent row in `001` (Telegram chat id, email, calendar id).
3. In n8n, create credentials: Telegram, Postgres, Gemini, Google Calendar, Gmail.
4. Import every file in `workflows/`, sub-workflows first.
5. Re-point each Execute Sub-workflow node to the new workflow ids. See `workflows/MANIFEST.md`.
6. Replace placeholders in the JSON: `CREDENTIAL_ID`, `TELEGRAM_CHAT_ID`, `YOUR_EMAIL@example.com`.
7. Publish all workflows except the Telegram inbound one, then publish that one last.

## Warnings

- This bot talks to real people once the Telegram inbound workflow is published.
- Gemini is a paid API. Each lead message triggers several model calls.
- Lead names, phone numbers, and emails are stored in Postgres. Check the data protection rules that apply to you.
- The sample projects, prices, and market settings are demo data (UAE off-plan, AED).
- The workflows have no login of their own. Access control is your n8n and database setup.
- Never commit real tokens or chat ids.

## Status

Done: Telegram channel, extraction, qualification rules, listing search and answers, slot booking, briefing delivery, escalation, error alert.

Not built: the scheduled nudge for idle conversations (`CHANGES.txt`, `MANIFEST.md`). WhatsApp, web chat, and email channels exist in the schema but have no workflow. Only Telegram is wired up.

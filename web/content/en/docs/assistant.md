---
title: Assistant
description: Describe the ride you want in a sentence and Velorki turns it into a route, with your consent, a rounded position at most, and no route history sent.
order: 12
---

The assistant turns a sentence like "a gravel loop of about 80 km with a café stop" into a route on the planner. It is the one part of Velorki that sends what you typed to a server, so it asks for your consent first and tells you exactly what goes.

The assistant is part of [Velorki Plus](./velorki-plus).

## Open it

Tap **Ask** in the toolbar of the route sheet on the **Plan** tab. The sheet is titled **Ask for a route**: "Describe the ride you have in mind. Velorki turns it into a request and plans the route on your phone."

If the **Ask** button is not there, this build of Velorki has no server address at all, which is the case for a self-built copy with no relay of its own.

## Consent, and what leaves the phone

The first time you send something, Velorki shows **Before the assistant asks**:

> What you type is sent to the Velorki server, which forwards it to our AI provider. Nothing else goes with it: no name, no account, no route history.
>
> If you allow it, your position is sent as well, rounded to about one kilometre, so "from here" means something.

Three answers:

- **Allow, with my rough position** sends your text and a position rounded to roughly a kilometre.
- **Allow, text only** sends your text and nothing else.
- **Not now** sends nothing and switches the assistant off.

What actually travels: your text, optionally the rounded position, your language and unit settings so the answer fits, and, for a route description, a short summary of the route. No identifier of you or your phone is put into the prompt, and the model never sees your track.

Change your mind at any time under **Settings → AI assistant → What is sent**, whose subtitle always says which of the four states you are in, with a **Change** button beside it.

## Ask for something

Type a sentence and tap **Ask**. Three examples are there to tap:

- **A flat 30 km loop from here**
- **60 km to Freiburg on quiet roads**
- **A gravel loop of about 80 km with a café stop**

Other things that work well: a distance and a direction, a place to ride past, a surface, how much climbing you want, a start that is not where you are.

The sheet shows **Thinking…** while the model answers, then **Looking up the places…** while the place names are turned into coordinates. Then it summarises what it understood: "Loop of about 80 km", "Starting where you are" or "Starting at Freiburg", and a chip per place to ride past.

If a name matches more than one place far apart, Velorki asks **Which Freiburg?** with up to three choices. Tapping one resolves it on the phone, with no second trip to the model.

## What happens with the answer

The sheet closes itself and the planner takes over:

- **A loop with no particular place to pass** opens the [loop sheet](./loops) with the search already running.
- **A loop through named places** becomes waypoints with the loop closed, and Velorki says "The route is on the map."
- **A point-to-point route** becomes waypoints with the bike profile set, and again "The route is on the map."

From there it is an ordinary plan: edit it, ask for variants, save it.

## What it does not do

The model never returns coordinates and never computes a route. It returns a structured request, a distance, a shape, some place names and a preference or two, and everything after that happens on your phone. That is why the assistant works as a way to express what you want, and not as a source of facts about roads.

It can also be wrong. If it says something you did not mean, rephrase with a clear distance and a clear place.

## Describe this route

The other thing the assistant does is write a paragraph about a route you already have. Open a route in the library and tap **Describe this route**; the sheet starts writing at once, and **Save as description** stores the text with the route. **Write again** asks for another go.

Only the figures go up: the distance, the ascent, the paved and unpaved shares and the waypoint names. The geometry stays on the phone.

The button is not offered for a route imported from Strava, because Strava's terms do not allow their data to be given to an AI provider.

## Limits and errors

The assistant is rate limited: twenty requests an hour and a hundred a day.

| What the sheet says | What it means |
|---|---|
| "Too many requests. Try again in 90 seconds." | you hit the rate limit |
| "The AI assistant is part of Velorki Plus." | no subscription |
| "The assistant needs your consent before it can send anything." | consent is missing or refused |
| "I am not sure I understood that. Try naming a distance and a place." | the model was not confident |
| "I could not find "Freiburg". Try another spelling or a nearby town." | the place name did not resolve |
| "I need to know where to start. Turn on location, or name a starting place." | "from here" with no position |
| "The assistant could not answer:" | the server or the model failed |

**Try again** clears the error and keeps what you typed.

## Reporting a bad answer

**Settings → AI assistant → Report AI output** opens a mail to us: "Tell us about an answer that was wrong or inappropriate." Please use it. Wrong and inappropriate answers are how the prompts get fixed.

## Related

- [Velorki Plus](./velorki-plus)
- [Loops](./loops)
- [Planning a route](./planning-a-route)
- [Privacy on the phone](./privacy-on-the-phone)

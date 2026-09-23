---
title: Strava and Ride with GPS
description: Connect your Strava or Ride with GPS account to upload recorded rides and import routes, and see why sending a route to Strava is a file.
order: 11
---

Velorki can talk to Strava and to Ride with GPS on your behalf: upload a ride you recorded, and pull your routes from those accounts into your library. Connecting either service is part of [Velorki Plus](./velorki-plus); GPX and FIT files stay free and do the same job by hand.

Nothing is sent to either service until you connect the account yourself and then ask for something.

## Connect an account

1. Open **Settings** and find the **Connections** section.
2. Tap **Connect with Strava** or **Connect with Ride with GPS**.
3. The service's own sign-in page opens in a browser. Sign in there and approve the access.
4. You come back to Velorki, and the row shows your name instead of **Not connected**.

Your phone keeps the access token in the phone's secure storage, in a form only the Velorki server can open. From then on every upload and import passes through that server, which checks your subscription, counts the transfer, opens the token for that one request and forwards it. It keeps neither the file nor the token, and cannot use the token on its own.

If a connect attempt fails, Velorki says "Could not connect:" with the reason. Cancelling the sign-in page says nothing at all.

A row reading **Not available in this build** means this build of Velorki was compiled without that service's keys, which is the case for a self-built copy until you supply your own.

## Disconnect

Tap **Disconnect** on the connected row. Velorki asks "Disconnect Strava?" and explains: "Velorki forgets the access token. Routes and rides already in the library stay."

Disconnecting also tells the service to revoke Velorki's access, when the server can be reached. It removes nothing from Strava or Ride with GPS, and nothing from your library.

## Upload a ride

1. Open the ride in **Library → Rides**.
2. Tap the cloud button at the top right, labelled **Upload**.
3. Choose **Upload to Strava** or **Upload to Ride with GPS**.

Velorki says "Uploading to Strava…", then "Uploaded to Strava" with a **View on Strava** action that opens it. A ride that is already up there is never uploaded twice: the menu entry becomes **View on Strava** or **Open on Ride with GPS** instead.

A Strava upload can take a while, because Strava processes the file before it exists as an activity; Velorki waits for it and links to the result.

## Import routes

1. Open the **Library** tab.
2. Tap the cloud button at the top right and choose **Import from Strava** or **Import from Ride with GPS**.
3. The list is titled **Strava routes** or **Ride with GPS routes**. Each row shows the name, the distance, the ascent and the date.
4. Tap **Import** on the one you want. It lands in your library as an ordinary route, and Velorki says "Alpine loop imported".

The footer says **Read 16 Sept 2026**, the moment the list was fetched. Velorki caches it for up to seven days, as Strava's terms require, and **Refresh** at the top right fetches it again.

If the account is not connected the screen says "Connect Strava in Settings → Connections first."

## Sending a route to Ride with GPS

Open the route, tap **Send**, choose **Send to Ride with GPS**. It is uploaded to your account and Velorki offers **Open** to see it there.

## Sending a route to Strava

Strava's API can read routes but it cannot create them, so there is nothing for Velorki to upload to. Choosing **Send to Strava** therefore opens an explanation:

> **Strava cannot receive routes.** Strava's API can read routes but not create them. Velorki exports a GPX file instead: share it, then import it on strava.com.

Tap **Export GPX**, save or send the file, and upload it as a route on strava.com. That path is free and needs no connection at all.

## What is free, and what needs Plus

| | Needs Plus |
|---|---|
| Connecting Strava or Ride with GPS | yes |
| Uploading a ride to either | yes |
| Importing routes from either | yes |
| Sending a route to Ride with GPS | yes |
| Exporting GPX or FIT and uploading it yourself | no |
| Importing a GPX or FIT file from either service | no |

## A note about the assistant and Strava

**Describe this route** is not offered for a route that came from Strava. Strava's API terms do not allow their data to be sent to an AI provider, so Velorki hides the button rather than break them.

## Related

- [Velorki Plus](./velorki-plus)
- [Import and export](./import-and-export)
- [Library](./library)
- [Assistant](./assistant)
- [Privacy on the phone](./privacy-on-the-phone)

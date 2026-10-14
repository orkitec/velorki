---
title: Strava and Ride with GPS
description: Velorki works with Strava and Ride with GPS, for free. Connect an account to upload recorded rides and import routes, and see why sending a route to Strava is a file.
order: 13
---

Velorki is compatible with Strava and with Ride with GPS: it can upload a ride you recorded, and pull your routes from those accounts into your library. Connecting either service is free, with or without [Velorki Plus](./velorki-plus). Velorki is not made, endorsed or sponsored by Strava or Ride with GPS.

Nothing is sent to either service until you connect the account yourself and then ask for something.

## Connect an account

1. Open **Settings** and find the **Connections** section.
2. Tap **Connect with Strava** or **Connect with Ride with GPS**.
3. The service's own sign-in page opens in a browser. Sign in there and approve the access.
4. You come back to Velorki, and the row shows your name instead of **Not connected**.

Velorki asks Strava for two permissions only: **read**, your public profile (your id and name, shown in Settings), and **activity:write**, to upload the rides you choose to upload. It does not read your activities.

Your phone keeps the access token in the phone's secure storage, in a form only the Velorki server can open, and leaves it out of backups. From then on every upload and import passes through that server, which opens the token for that one request and forwards it. It keeps neither the file nor the token, nor any record of the call, and cannot use the token on its own.

If a connect attempt fails, Velorki says "Could not connect:" with the reason. Cancelling the sign-in page says nothing at all.

A row reading **Not available in this build** means this build of Velorki was compiled without that service's keys, which is the case for a self-built copy until you supply your own.

## Disconnect

Tap **Disconnect** on the connected row and confirm. Disconnecting also tells the service to revoke Velorki's access, when the server can be reached. It removes nothing from your Strava or Ride with GPS account.

**Strava.** Disconnecting deletes every piece of Strava data from the phone: the access token, the routes you imported from Strava and routes you edited from them, the cached route list, and the links from your rides to their Strava activities. Your rides themselves stay. Velorki then says "Your Strava data has been deleted from this phone."

If you remove Velorki from your Strava account on strava.com instead, Velorki notices at its next Strava call, deletes the same data and tells you.

**Ride with GPS.** Velorki forgets the access token. Routes and rides already in the library stay.

## Upload a ride

1. Open the ride in **Library → Rides**.
2. Tap the cloud button at the top right, labelled **Upload**.
3. Choose **Upload to Strava** or **Upload to Ride with GPS**.

Velorki says "Uploading to Strava…", then "Uploaded to Strava" with a **View on Strava** action that opens it. Velorki keeps the activity's link with the ride for that, until you disconnect. A ride that is already up there is never uploaded twice: the menu entry becomes **View on Strava** or **Open on Ride with GPS** instead.

A Strava upload can take a while, because Strava processes the file before it exists as an activity; Velorki waits for it and links to the result.

## Import routes

1. Open the **Library** tab.
2. Tap the cloud button at the top right and choose **Import from Strava** or **Import from Ride with GPS**.
3. The list is titled **Strava routes** or **Ride with GPS routes**. Each row shows the name, the distance, the ascent and the date.
4. Tap **Import** on the one you want. It lands in your library, and Velorki says "Alpine loop imported". A route imported from Strava stays on the phone: it is never sent to the assistant, put in a share link or sent to Ride with GPS or any other service, and disconnecting Strava deletes it.

A route from Strava, and any route you edit from it, stays only while it still exists on Strava. While Velorki is open, online and connected, it checks such a route against Strava again every 48 hours; your edits stay as long as the route is still there. If it was deleted on Strava, or could not be checked for 7 days (offline, disconnected, or the checks failing), Velorki removes it and says "A route from Strava was removed: it no longer exists on Strava, or could not be checked for 7 days."

The footer says **Read 16 Sept 2026**, the moment the list was fetched. Velorki keeps the list on the phone for at most 48 hours, and **Refresh** at the top right fetches it again.

If the account is not connected the screen says "Connect Strava in Settings → Connections first."

## Sending a route to Ride with GPS

Open the route, tap **Send**, choose **Send to Ride with GPS**. It is uploaded to your account and Velorki offers **Open** to see it there.

## Sending a route to Strava

Strava's API can read routes but it cannot create them, so there is nothing for Velorki to upload to. Choosing **Send to Strava** therefore opens an explanation:

> **Strava cannot receive routes.** Strava's API can read routes but not create them. Velorki exports a GPX file instead: share it, then import it on strava.com.

Tap **Export GPX**, save or send the file, and upload it as a route on strava.com. That path is free and needs no connection at all.

## It is all free

Connecting Strava or Ride with GPS, uploading a ride, importing routes and sending a route to Ride with GPS are free, as are GPX, FIT and TCX files, which do the same job by hand. None of it needs Velorki Plus.

## Strava data stays on the phone

Strava data is only ever shown to you. Strava's API terms do not allow their data to be given to an AI provider or to other services, so Velorki never sends a route that came from Strava to the assistant, never puts it in a share link and never sends it to Ride with GPS or anywhere else. **Describe this route**, for one, is not offered for it.

We hold no Strava data on our servers: all of it is on your phone. Questions, or a request to delete data, go to [ride@velorki.com](mailto:ride@velorki.com); see the [privacy policy](/privacy).

## Related

- [Velorki Plus](./velorki-plus)
- [Import and export](./import-and-export)
- [Library](./library)
- [Assistant](./assistant)
- [Privacy on the phone](./privacy-on-the-phone)

---
title: Search
description: Find places, streets, house numbers and things like drinking water or toilets, on the phone in downloaded areas and online when you choose.
order: 4
---

The search field at the top of the Plan tab finds towns, streets, house numbers and points of interest such as cafés, drinking water and bike shops. Over a downloaded area it answers from the phone, instantly and with no signal; everywhere else nothing is searched until you choose between an online geocoder and the areas you have downloaded.

## How to search

1. Open the **Plan** tab and tap the field at the top, hinted **Search for a place**.
2. Type at least three characters. Results appear in a card under the field as you type.
3. Tap a result. The map moves to the place, pins it and opens its card.

Coordinates typed or pasted into the field, `40.71747, -73.94840` or `40,71747° N, 73,94840° W` as map apps copy them, are the place itself: one result at that spot, with nothing looked up and nothing sent. A place shared from another app opens the same way, see [import and export](./import-and-export#a-place-from-another-app).

## The place card

A search result, a [stop on the map](./stops-on-the-map) or a place shared from another app opens a card with the place's name, what it is, its town, how far it is from you and, with a route, how far off the route. Nothing changes until you pick an action, which depends on the plan:

- **Nothing planned yet**: **Route here** rides from where you are to the place; **Start here** makes it the first point of the route.
- **Only a start**: **Destination** makes it the end of the route.
- **A route**: **Add as a stop** puts it into the route where it lies along the way; **Destination** adds it at the end.

On the Record tab the card only tells, with no actions.

Under them:

- **Details** fetches the place from OpenStreetMap, only when you tap it: opening hours with whether it is open now, website, phone number, cuisine, wheelchair access, outdoor seating and its Wikipedia article, as far as they are mapped. Details are kept on the phone for a week, so the place shows them at once the next time. The button is missing for streets and for places without an OpenStreetMap id.
- **Open in…** shows the place in Apple Maps, in Google Maps when it is installed (iPhone), in a map app you pick (Android) or on OpenStreetMap in the browser, or hands it to **Share…**.

Closing the card (the **X**, a swipe down or a tap on the map) changes nothing and clears the search.

## Offline or online

Velorki decides by the **map centre**, not by your connection. Each downloaded routing tile brings a search index of its area with it.

- **Map centre over a downloaded area**: the query is answered on the phone. The last row of the result card, **Search online for "…"**, runs the same text online.
- **Anywhere else** (the map centre is over an area that is not downloaded, nothing is downloaded at all, or there is no map centre): nothing is searched and nothing leaves the phone until you pick **Search online for "…"** or, when you have downloaded areas, **Search downloaded areas**, which searches every one of them, nearest to the map first. Your pick holds for the following keystrokes until you clear the search. With a map centre the list also shows a notice, **This area isn't downloaded**, a line saying why and a **Download** button that opens the offline screen for the visible area. Online results come under the caption **Online results**, and the last row, **Show offline results**, switches to the downloaded areas; results from the phone end in **Search online for "…"**.
- **No online search configured**: the downloaded areas answer.

The notice stays visible while you scroll the list, and when the search failed it sits above the error message, which is where it matters most.

## What it finds

- **Places**: cities, towns, villages, hamlets, suburbs, neighbourhoods, localities and islands.
- **Streets**, with house numbers.
- **Points of interest**, each with its own icon and label: Cafe, Restaurant, Fast food, Ice cream, Petrol station, Air pump, Drinking water, Toilets, Bike repair station, Bike shop, Bike rental, Bike parking, E-bike charging, Shelter, Campsite, Hotel, Hostel, Mountain hut, Supermarket, Bakery, Pharmacy, Picnic site, Station, Ferry terminal, Airport, Viewpoint, Peak, Mountain pass, Park, Beach, Water, Nature reserve, Attraction, Museum, Historic site, Place of worship, Hospital, University, Sports venue, Shopping centre, Tower, Lighthouse, Building.

- **Well-known places in your language**: "Parigi" finds Paris, and a famous landmark comes before its namesakes.

Offline rows show the kind, the distance and the town under the name, as far as each is known: "Drinking water · 350 m", "Street · Manhattan". A tap, a toilet, a shelter or a bike stand with no name of its own is listed under its kind instead.

## Searching by kind

Type the name of a kind rather than the name of a place. "drinking water", "bakery", "toilets" and the rest all work, in the language the app is running in.

The list then opens with the five nearest of that kind to the map centre, each with its distance, and the ordinary name matches follow underneath. Velorki looks in a box that grows from 5 to 50 km around the map centre until it has enough. This is the quick way to answer "where is the nearest tap" in the middle of a ride.

A search by kind ignores the group switches described below.

## House numbers

Type the number where your country puts it: "Hauptstrasse 12", "400 W 42nd", "Via Roma 12/A", "Budapest, Fő utca 12". Velorki finds the street and answers at the number's own position along it; the row is the address as you typed it, "400 West 42nd Street". A town before the street with a comma, or after it, says which place's street you mean. A postcode is left out, and a number that belongs to a street's name, "Route 66", stays part of the name.

Where the number falls between two the index knows, Velorki estimates its position and the row says **≈ 400** so you can see it is a guess.

## Typos, short forms and other alphabets

Offline search forgives a letter or two wrong, a word written together or apart, and short forms such as "St" or "Str.". Names in Cyrillic or Greek can be typed in Latin letters, "aleksandar nevski" or "Nafplio". When nothing answers well, Velorki tries the likeliest words from the index instead and the card says **Showing results for "…"** above the list, with what it actually searched for.

## Ordering the groups

Offline results are grouped, and you decide which groups appear and in which order.

1. Open **Settings**.
2. Tap **Search**, subtitled "What offline search shows, and in which order. Drag to change the priority."
3. Drag a row by its handle to move it up or down. Use the switch on the right to turn a group off.

The eight groups, in their default order: **Places**, **Streets and addresses**, **Landmarks**, **Cycling stops**, **Overnight**, **Nature**, **Transport**, **Services**.

There is no save button; changes take effect on your next keystroke. A group that is switched off disappears from name matches, and the order breaks ties between results that match the text equally well.

## When search does not work

- **"Nothing found."** The text matched nothing, offline or online. Try the trailing row to switch source, or fewer words.
- **"Search failed."** with a reason means the online geocoder could not be reached. Offline search keeps working where you have downloaded an area.
- **"No search server configured, set one in Settings → Advanced."** means this build has neither a geocoder address nor any downloaded index. The field is disabled until one exists.

## Related

- [Stops on the map](./stops-on-the-map)
- [Offline maps and routing](./offline-maps-and-routing)
- [Planning a route](./planning-a-route)
- [Settings and appearance](./settings-and-appearance)
- [Privacy on the phone](./privacy-on-the-phone)

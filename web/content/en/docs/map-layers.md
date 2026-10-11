---
title: Map layers
description: The offline cycle map and its parts, the online cycle map, rain radar, clouds and the stops, all in the Layers sheet.
order: 6
---

**Layers** sits in the button column on the right of the map, on the Plan and the Record tab. Its sheet holds the cycle map, the online cycle map, the rain radar, the clouds and the stops. The button is highlighted while one of them is on.

<!-- screenshot: layers -->

## Cycle map

**Cycle map**: "Bike lanes, paths and cycle routes from your downloaded areas · works offline · shown when zoomed in". Drawn by the app from the routing data on the phone, so it needs no connection, and only where an area is downloaded.

The cycle map fades in between zoom 12 and 13, and out again when you zoom out. It draws what the routing data knows about riding a bike. With it on, a chip per part unfolds below the switch, each with a sample of its line as legend. Tap a chip to show or hide the part; the choice is kept. Arrows and dots shown from zoom 15 fade in over the zoom step before.

| Part | Drawn as |
| --- | --- |
| **Bike lanes & tracks** | Cycleways solid blue, cycle streets with a pale band; tracks solid and lanes dashed, at the road's edge, farther out on bigger roads. Shared lanes (bus lanes bikes may use, lanes marked only with bike symbols, shoulders, sidewalks bikes may use) as a sparse light-blue dash beside the road. Two-way cycleways and two-way tracks and lanes are drawn wider than one-way ones |
| **One-way arrows** | Chevrons in the lane's own blue show which way to ride: on cycleways and paths ridden one way from zoom 15, and on one-way tracks and lanes beside the road from about zoom 15.5 |
| **Shared paths** | Paths shared with walkers dashed teal, footways bikes may use dotted grey-blue |
| **One-way streets** | A grey chevron in the middle of streets that are one-way for bikes too, pointing the way the traffic goes, from zoom 15. One-way streets bikes may ride both ways show the two-colour sign of **Two-way for bikes** instead. Where a lane or track beside the street shows its own way, the street gets no chevron of its own |
| **Two-way for bikes** | On one-way streets that bikes may ride both ways, from zoom 15 a grey chevron shows the traffic's way and a blue one the bikes' way against it |
| **National routes**, **Regional routes**, **Local routes** | Signed cycle routes as a violet halo, stronger the farther the route reaches |
| **Unpaved & bumpy** | Gravel an ochre dash, rugged ground for mountain bikes a brown dash, bumpy paving red ticks |
| **Barriers & steps** | Gates, bollards and stiles as dots from zoom 15; red where the bike has to be carried. Steps as brown rungs from zoom 15, with a blue strip beside them where there is a ramp for bikes |
| **Calm streets** | Streets tinted by how calm they are: cyan for 30 km/h (20 mph) or less, green for 20 km/h or living streets, pale green for walking pace, bright green without motor traffic; roads closed to bikes in grey |
| **Mountain bike** | Difficulty ticks on trails from zoom 14: blue for easy (S0–S1), red for S2, black for S3 and harder (white on the night map); mountain-bike routes as an orange halo |
| **Climbs** | Steep pieces of the ways a bike may use, as a band: yellow from 6 %, orange from 10 %, red from 15 %; chevrons point uphill from zoom 15. The heights come from the terrain model in the routing data. A climb only counts when it keeps going for at least 150 m and 10 m of height, so short ramps are left out; in city centres with tall buildings it can still show a climb that isn't there or miss one. Bridges and tunnels are left out. In the dense cores of the biggest cities, where the heights are the buildings', no climbs are drawn. |

All parts are on by default except **Unpaved & bumpy**, **One-way streets**, **Calm streets**, **Mountain bike** and **Climbs**. A part added in a later version starts as its default; choices made before are kept.

On the Plan tab, with the cycle map on over an area that is not downloaded, a chip says **No cycle map here — area not downloaded**, with **Download**; a tap opens the download for the visible area. If the stops chip applies too, it comes first.

## Online cycle map

**Online cycle map**: "CyclOSM's map with bike shops and parking · needs a connection". CyclOSM's overlay, fetched online. The two cycle maps take turns: turning one on turns the other off.

## Rain radar and clouds

**Rain radar**: "Now: radar in Germany and the US, a satellite estimate elsewhere in Europe and Africa. Ahead: radar forecast for 2 hours in Germany, model forecast up to 24 hours (hourly in Europe, every 6 hours elsewhere)". **Clouds**: "Europe, Africa and the Americas · updated hourly in Europe". Both are free, off until you turn them on, and need a connection.

The rain comes from three kinds of source. Now: radar from the Deutscher Wetterdienst over Germany and its borders and from the US National Weather Service over the US, and around them, over the rest of Europe, Africa and the Atlantic, rain estimated from the Meteosat satellite by EUMETSAT's H SAF, every ten minutes. A satellite estimate is coarser than radar and misses some light rain; it never covers the radars' areas, so the two never disagree on the map. The next two hours: in Germany the Deutscher Wetterdienst's nowcast, the radar's rain moved on in quarter hours; everywhere else, and from three hours on everywhere, the forecast of its ICON weather model, hour by hour over Europe and in six-hour steps elsewhere. The app looks for newer images every five minutes. Zoomed out further than about a continent, the rain is not drawn, except the radar drawn **As measured**.

With the rain radar on, its time control sits at the top of the Plan sheet and on the Record card, under the figures during a ride: a slider from **Now** in quarter hours to two hours ahead, then in hours to 24 hours ahead. Its label says the step, the time of the image over the middle of the map and, ahead, what it is, such as **Now · 20:25**, **+45 min · 21:30 · Nowcast** or **+3 h · 23:00 · Forecast**. The step is the same on every tab and goes back to **Now** when the app returns after more than half an hour away. The Library shows the time in a small label on the map.

The clouds are satellite images drawn in white over the map: Meteosat from EUMETSAT over Europe, Africa and around, a new image every full hour, and the GOES satellites through NASA over the Americas. They always show their latest image, whatever the rain's slider says, and a small label on the map says its time. The thickest, coldest clouds are brightest; fog and low cloud show faintly or not at all.

If a service does not answer, the map says **Rain radar unavailable right now**, **Satellite rain unavailable right now**, **Rain forecast unavailable right now** or **Clouds unavailable right now**, so an empty map is not taken for a dry, clear day. The app loads the images straight from the Deutscher Wetterdienst, NOAA, NASA and EUMETSAT, not through Velorki, so those services see the map area requested. Their credits are in the line at the bottom of the map while a layer is drawn.

## Stops

**Stops** is a switch in the same sheet, off until you turn it on. It draws drinking water, cafés, toilets, bike repair stations and more from the place index on the phone. The kinds, the area you look at and the route ahead are described in [stops on the map](./stops-on-the-map).

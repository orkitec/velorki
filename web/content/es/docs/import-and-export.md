---
title: Importar y exportar
description: Abre archivos GPX, FIT y TCX desde cualquier parte del teléfono, guárdalos como rutas o salidas y exporta las tuyas a Komoot, Garmin o donde quieras.
order: 10
---

Velorki lee y escribe archivos GPX, FIT y TCX, que es como las rutas y las salidas pasan entre la app y el resto del mundo. Todo es gratis, no necesita cuenta ni conexión, y funciona con Komoot, Garmin Connect, Strava, un ciclocomputador o un simple archivo en el teléfono.

## Meter un archivo

Hay tres maneras, y las tres terminan en la misma pantalla de importación.

**Abrir con.** Toca un archivo GPX, FIT o TCX en tu app de archivos, en un correo o en las descargas del navegador, y elige Velorki. En un iPhone es "Abrir en Velorki" desde Archivos, Mail o Safari.

**Menú de compartir.** En otra app, comparte el archivo y elige Velorki. Así llega una ruta desde Komoot o desde el mensaje de un amigo.

**El selector.** En la pestaña **Biblioteca**, toca **Importar archivo** arriba a la derecha y elige tú el archivo.

**Un enlace de Ride with GPS.** Comparte el enlace de una ruta desde la app de Ride with GPS o desde un navegador y elige Velorki, y la ruta llega a la pantalla de importación. Una ruta pública no necesita nada más; una privada se descarga a través de tu cuenta de Ride with GPS conectada, y sin ella la pantalla dice "Esta ruta de Ride with GPS es privada. Conecta Ride with GPS en Ajustes para abrirla."

Un archivo que no se puede importar abre la misma pantalla con el motivo: no es un archivo GPX, FIT o TCX, no se puede leer, está vacío o es un enlace que no se pudo descargar.

Velorki averigua qué es el archivo leyendo sus primeros bytes, sin fiarse de su nombre ni de su tipo, así que un `.gpx` que en realidad es un archivo FIT se importa igual. Un archivo TCX se reconoce por su elemento raíz.

## Un lugar desde otra app

Velorki también acepta un único lugar al que ir, y lo abre en la pestaña **Planificar** igual que se abre un resultado de búsqueda: marcado en el mapa, en su [ficha](./search#la-ficha-de-un-lugar).

- **Menú de compartir.** Comparte un lugar desde Google Maps, Apple Maps, OpenStreetMap, un navegador o una app de mensajería y elige Velorki. Funcionan un enlace de mapa, coordenadas como `52.5200, 13.4050` o `52°31'12"N 13°24'18"E`, o una dirección; la dirección va al campo de búsqueda, que la encuentra.
- **Abrir con** (Android). Una ubicación que abre otra app (un enlace `geo:`) ofrece Velorki en el selector.
- **Los enlaces cortos** como `maps.app.goo.gl/…`, `maps.apple/p/…` u `osm.org/go/…` solo dicen adónde apuntan cuando se abren. Con conexión, Velorki los abre (una petición a ese servicio, sin enviar nada más) y llega al lugar; sin conexión te lo dice: abre primero el enlace en un navegador y comparte el lugar desde allí.

**Para desarrolladores de apps**, Velorki abre estos enlaces:

| Enlace | Abre |
|---|---|
| `velorki://navigate?lat=52.52&lon=13.405&name=Brandenburger%20Tor` | el lugar en esas coordenadas, con la etiqueta `name` (opcional) |
| `velorki://navigate?q=Pariser%20Platz%201%2C%20Berlin` | una búsqueda de la dirección o el nombre del lugar |

Las coordenadas van en grados decimales (WGS 84); todos los valores van codificados para URL. En Android también funciona un intent `geo:` (`geo:LAT,LON`, `geo:0,0?q=LAT,LON(Label)`, `geo:0,0?q=address`).

## La pantalla de importación

Con el título **Importar**, muestra:

- una vista previa del track en el mapa, con los puntos de paso del archivo como pequeños marcadores con su nombre: los puntos de interés con los que venía una ruta, una zona para bajarse de la bici, una fuente, un tramo en mal estado, en el color de su tipo,
- un campo **Nombre**, rellenado a partir del nombre del archivo,
- el formato y el tamaño, "GPX · 4812 puntos",
- el intervalo de tiempo, "16 sept 2026, 09:12 – 16 sept 2026, 13:40", o "El archivo no tiene marcas de tiempo.",
- la distancia, el desnivel positivo, el desnivel negativo y la duración,
- **GUARDAR COMO**, un selector entre **Ruta** y **Salida**.

El mapa se queda arriba mientras las páginas de debajo se desplazan, con puntos bajo el mapa que indican qué página está a la vista. Un deslizamiento a la izquierda muestra el perfil de altitud. Si el archivo tiene giros o puntos de interés, un deslizamiento más muestra la **HOJA DE RUTA**, cada giro y punto de interés con su distancia desde el inicio, plegada a ocho líneas con **Ver los …** (todas). Toca una línea y el mapa se desplaza hasta allí con el zoom que tengas, marcada con su nombre; toca un marcador en el mapa y aparece la hoja de ruta con su línea seleccionada y a la vista. Una línea seleccionada se abre con lo que hay que saber: la nota de un peligro o la maniobra simple bajo las palabras del autor.

Una ruta GPX con hoja de ruta, la exportación de rutas de Ride with GPS o un recorrido de Garmin, trae sus giros: cada indicación se convierte en una instrucción de giro con las palabras del autor, que se muestra en el banner de giros y en la página de la hoja de ruta y que dice la voz. Un track GPX no trae hoja de ruta; el banner de giros propio de Velorki funciona igualmente con él a partir de la forma de la ruta.

Velorki adivina **Ruta** o **Salida** según si los puntos llevan horas: una grabación sí, una ruta planificada no. Un recorrido FIT se reconoce como recorrido y se toma por ruta, diga lo que diga su base de tiempo sintética, y lo mismo un recorrido TCX; sus puntos del recorrido se convierten en la hoja de ruta (giros) y en los puntos de interés (agua, comida, peligros, lugares con nombre). No se guarda nada hasta que tocas **Guardar**.

Una ruta se abre con la bici que indica su archivo: un `<type>` de GPX como `road_biking` o `mountain_biking`, o el subdeporte de un recorrido o una actividad FIT (carretera, montaña, gravel), se convierte en **Carretera**, **MTB**, **Gravel** o **Trekking**. Un archivo que no indica ninguna se abre con la última bici con la que saliste. Una ruta exportada escribe su bici de la misma forma; un archivo TCX no tiene forma de indicarla.

Una actividad FIT de un ciclocomputador trae más que su track: las vueltas que marcó el dispositivo sustituyen a los parciales fijos en la página de la salida, los totales que escribió el dispositivo (distancia, tiempo en movimiento, desnivel, calorías) se muestran en **Según lo grabó el dispositivo** cuando difieren de lo que Velorki calcula a partir de las posiciones, y la temperatura, si el dispositivo la registró, tiene su propio gráfico. Una salida GPX trae del mismo modo la frecuencia cardiaca, la cadencia, la potencia y la temperatura de sus extensiones. Un archivo GPX con varios tracks, por ejemplo un viaje de varios días, los muestra con una casilla cada uno y guarda una salida (o ruta) por cada track marcado.

Después ves "Ruta alpina añadida a la biblioteca" o "Ruta alpina añadida a tus salidas", y llegas a la tarjeta del nuevo elemento en la pestaña Biblioteca.

Si el archivo no se abre, Velorki dice cuál fue el problema: "No es un archivo GPX, FIT ni TCX.", "No se pudo leer el archivo.", "El archivo no tiene puntos de track." o "No se pudo abrir el archivo."

## Sacar un archivo

**Desde una ruta** (Biblioteca → Rutas → ábrela → **Exportar**):

| Formato | Para qué sirve |
|---|---|
| **Ruta GPX** | una ruta planificada para otro planificador, una app del teléfono o un ciclocomputador. Una ruta con hoja de ruta sale como la escribe Ride with GPS: un `<rte>` con los giros, cada uno con su dirección y sus palabras, y un `<trk>` con toda la línea al lado; una ruta sin hoja de ruta guarda todos los puntos en el `<rte>`. |
| **Recorrido FIT** | un ciclocomputador Garmin, Wahoo o similar que espera un recorrido; la hoja de ruta y los puntos de interés van como puntos del recorrido, así que el dispositivo muestra el siguiente giro |
| **Recorrido TCX** | un Garmin antiguo o una web de entrenamiento que lee Training Center XML; la hoja de ruta y los puntos de interés van como puntos del recorrido, con los nombres recortados a los diez caracteres que permite el formato |

**Desde una salida** (Biblioteca → Salidas → ábrela, o la tarjeta de la salida al terminar):

| Formato | Para qué sirve |
|---|---|
| **Exportar track GPX** | el track grabado con sus marcas de tiempo; incluye frecuencia cardiaca, cadencia, potencia y temperatura. |
| **Exportar actividad FIT** | un archivo de actividad para una plataforma de entrenamiento |
| **Exportar actividad TCX** | lo mismo en Training Center XML, una vuelta por cada vuelta que traía la salida, con frecuencia cardiaca, cadencia y potencia en cada punto |

En ambos casos Velorki escribe el archivo y se lo pasa al menú de compartir del sistema, para que puedas guardarlo en tus archivos, mandarlo por correo o enviarlo a otra app.

## Komoot, Garmin y los demás

Velorki no tiene integración con Komoot ni con Garmin, y no la necesita: todos hablan GPX y FIT, y la mayoría aún lee TCX.

- **De Komoot a Velorki**: exporta el tour como GPX en Komoot y compártelo con Velorki, o guárdalo y ábrelo con el botón **Importar archivo**.
- **De Velorki a Komoot**: exporta la ruta como **Ruta GPX** y compártela con la importación de Komoot.
- **A un ciclocomputador Garmin**: exporta la ruta como **Recorrido FIT**, o como **Ruta GPX** si tu dispositivo lo prefiere, y pásala al dispositivo como lo hagas normalmente, con Garmin Connect o copiando el archivo.
- **Desde un Garmin**: la actividad `.fit` del dispositivo se importa como salida.

Enviar una ruta **a Strava** también se hace con archivos, porque la API de Strava no permite crear rutas. Consulta [Strava y Ride with GPS](./strava-and-ridewithgps).

## Relacionado

- [Biblioteca](./library)
- [Strava y Ride with GPS](./strava-and-ridewithgps)
- [Compartir](./sharing)
- [Grabar una salida](./recording-a-ride)

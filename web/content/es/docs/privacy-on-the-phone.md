---
title: Privacidad en el teléfono
description: "En palabras de ciclista: qué se queda en tu teléfono, qué sale de él, cuándo y hacia quién. No hay cuenta y nada nos llega si no lo pides."
order: 17
---

Velorki no tiene cuenta, así que no hay nada en lo que iniciar sesión ni nada sobre ti en un servidor. Esta página es la versión en lenguaje claro de lo que eso significa en la práctica; la [política de privacidad](/privacy) es la formal.

## Qué se queda en el teléfono

Todo lo que creas y todo lo que descargas:

- las rutas planificadas, las salidas grabadas y sus tracks GPS,
- tus ajustes, incluidas las unidades y la voz que elegiste, y el peso, el año de nacimiento, el sexo, la frecuencia cardiaca máxima, el peso de la bici, el tipo de bici y la potencia umbral que puedes introducir en Ajustes → Ciclista y bici, que son ajustes del teléfono y nunca se envían a ninguna parte,
- las zonas de mapa sin conexión descargadas,
- las teselas de rutas descargadas y los índices de búsqueda de lugares que vienen con ellas,
- los tokens de acceso de Strava y Ride with GPS si los conectas, que van al almacenamiento seguro del teléfono en una forma que solo el relay de Velorki puede abrir, y se dejan fuera de las copias de seguridad.
- lo que tomas de Strava: tu nombre en Strava, la lista de tus rutas de Strava durante 48 horas como máximo, las rutas que importas y los enlaces de las salidas subidas a sus actividades de Strava. Desconectar lo elimina todo.

Nada de ello se sube a ninguna parte si no lo pides. La única excepción es la sincronización en la nube: tus rutas, salidas y algunos ajustes van a tu propio iCloud o a tu propio Google Drive, nunca a nosotros, y los datos de Strava se quedan en el teléfono. En un iPhone o iPad, iCloud está activado por defecto; en Android la sincronización está desactivada hasta que eliges una nube. **Ajustes → Sincronización → Sincronizar con** elige la nube o desactiva la sincronización, mira [la biblioteca](./library#sincronización-con-icloud-o-google-drive).

En Android, Velorki queda excluida a propósito de la copia de seguridad en la nube de Google y de la transferencia entre dispositivos, así que el sistema tampoco copia tus salidas fuera del teléfono. Para pasar a un teléfono nuevo, activa la sincronización con Google o exporta lo que quieras conservar como archivos GPX, FIT o TCX; consulta [importar y exportar](./import-and-export).

## Qué sale del teléfono, y cuándo

### Mientras miras el mapa

Las teselas del mapa se piden a OpenFreeMap, y a CyclOSM si activas **Mapa ciclista en línea** en **Capas**. El **Mapa ciclista** se dibuja en el teléfono y no le pide nada a ningún servidor. Pedir una tesela le dice al servidor qué cuadrado del mundo estás mirando e incluye tu dirección IP, como cualquier petición. Una zona que has descargado se sirve desde el teléfono y no pide nada.

### El tiempo

El mapa del tiempo (lluvia, nubes, viento) y una ruta coloreada por viento o lluvia obtienen imágenes y datos de previsión directamente de servicios meteorológicos públicos, como el Deutscher Wetterdienst, la NOAA, el KNMI, la NASA y EUMETSAT. Cada petición nombra una parte del mapa, o un recuadro alrededor de tu ruta, y una hora, e implica tu dirección IP; no se envían tu ruta, tus salidas ni tu identidad. Con Velorki Plus, la previsión más precisa y el radar de lluvia pasan en cambio por el relay de Velorki: para la previsión, los puntos a lo largo de la ruta, redondeados a una cuadrícula de unos 2,5 km, con las horas en que pasas por ellos; para el radar, la parte del mapa que miras y una hora. Los servicios meteorológicos ven nuestro servidor, no tu teléfono.

### Cuando descargas una zona

Las zonas de mapa sin conexión vienen de OpenFreeMap, como el propio mapa. Las teselas de rutas y el índice de búsqueda que las acompaña vienen del espejo de teselas en GitHub; GitHub se entera de qué teselas descargas y de tu dirección IP. Si hay datos de mapa nuevos, Velorki lo pregunta al mismo espejo; no sale nada más que esa petición.

### Mientras planificas

El cálculo de rutas se hace en tu teléfono allí donde tengas las teselas de rutas. Para una zona que no has descargado, los puntos de paso van a un servidor de rutas, que devuelve la ruta. Recibe los puntos de paso y nada más: ni identidad, ni otras rutas, ni salidas.

**Ajustes → Mapas y datos → Cálculo de rutas → Solo en el dispositivo** apaga el servidor por completo; Velorki ofrece entonces la descarga en lugar de calcular la ruta.

### Mientras buscas

La búsqueda se responde en el teléfono sobre una zona descargada, y nada de lo que escribes sale del dispositivo.

Nunca se hace en línea por sí sola: no se envía nada si no tocas **Buscar «…» en línea**. Si no hay nada descargado o el mapa está sobre una zona sin descargar, no se busca nada hasta que lo eliges; **Buscar en las zonas descargadas** se queda en el teléfono. Entonces lo que escribiste va a Photon, junto con una posición aproximada para que los resultados cercanos salgan primero.

Las [paradas en el mapa](./stops-on-the-map) se leen del índice del teléfono y no piden nada.

Tocar **Detalles** en la ficha de un lugar descarga sus detalles (horario, sitio web y similares) de OpenStreetMap.

Un enlace corto de mapa que compartes con Velorki (`maps.app.goo.gl`, `maps.apple/p`, `osm.org/go`) se abre una vez con el servicio que lo creó, para saber adónde apunta; ese servicio ve el enlace y tu dirección IP, como lo vería en un navegador.

### Mientras grabas

No sale absolutamente nada del teléfono. La grabación, las estadísticas, los gráficos y los parciales se calculan en el dispositivo. Lo mismo vale para la frecuencia cardiaca, la cadencia y la potencia de un reloj, un sensor Bluetooth o tu app de salud: se guardan con la salida y, si has activado Salud, se intercambian con Apple Health o Health Connect en el propio teléfono.

Tu posición centra el mapa y graba tus salidas, y se queda en el teléfono. Velorki pide el permiso una vez, en el primer arranque. Solo sale del teléfono en dos casos, ambos cuando tú los activas: redondeada a unos 1 km hacia el asistente, si lo permitiste, y como posición aproximada hacia Photon cuando buscas en línea.

### Cuando preguntas al asistente

Solo con tu consentimiento, y solo lo que permitiste: tu texto, opcionalmente una posición redondeada a un kilómetro más o menos, y tus ajustes de idioma y unidades. Ni nombre, ni cuenta, ni historial de rutas, y nunca tu track. Consulta [asistente](./assistant).

### Cuando conectas Strava o Ride with GPS

No va nada a ninguno de los dos hasta que conectas la cuenta y luego pides algo, una subida o una importación.

Al conectar se entrega un código de un solo uso al relay de Velorki, que lo convierte en un token de acceso añadiendo nuestro secreto de aplicación, y le da el token a tu teléfono envuelto, de forma que solo el relay puede abrirlo. No guardamos el token. A partir de ahí cada subida e importación pasa por el relay: abre el token para esa única petición y la reenvía a Strava o Ride with GPS. No guarda ni el archivo ni el token, ni ningún registro de la llamada, y no puede usar el token por su cuenta. Las conexiones son gratis, así que no se comprueba ninguna suscripción; el relay solo cuenta las llamadas por id de instalación anónimo y por dirección, durante poco tiempo, para frenar los abusos.

Los datos de Strava se quedan en tu teléfono: nunca van al asistente, a un enlace para compartir, a Ride with GPS ni a ningún otro servicio. Consulta [Strava y Ride with GPS](./strava-and-ridewithgps).

### Cuando creas un enlace para compartir

Esa ruta o salida, con su track, su nombre y sus cifras, se copia a nuestro servidor para que el enlace pueda abrirse. El enlace es público para cualquiera que lo tenga, muestra dónde empieza y termina el track, y se borra automáticamente al cabo de un año. Consulta [compartir](./sharing).

### Cuando compras Velorki Plus

La tienda gestiona el pago y nunca vemos tu tarjeta. La suscripción se comprueba con un identificador aleatorio anónimo que no está vinculado a un nombre, a una dirección de correo ni a un identificador del dispositivo. Con la sincronización activada, la app también guarda ese identificador en tu propia nube, para que el planificador en el navegador, con sesión iniciada en la misma cuenta, pueda usar tu Plus.

### Avisos de actualización y valoraciones

En un iPhone, Velorki consulta la búsqueda pública del App Store para saber si hay una versión más nueva, con el identificador de paquete de la app, tu país y tu idioma; en Android se lo dice Google Play. La hoja de valoración es la del propio sistema, Apple o Google deciden si aparece y cuándo, y una valoración nunca nos llega.

## Lo que Velorki nunca hace

- Ni cuenta, ni registro, ni dirección de correo.
- Ni publicidad, ni SDK de anuncios, ni perfiles.
- Ningún SDK de analítica ni de informes de errores en la app en el momento de escribir esto. Si alguna vez se añade uno, la política de privacidad lo nombrará y dirá qué recoge antes de que se publique.
- Ninguna venta de datos, a nadie, nunca.
- Ni funciones sociales ni mensajes entre usuarios.

## Deshacerse de las cosas

| Qué | Cómo |
|---|---|
| Una ruta o una salida | bórrala en la [biblioteca](./library); con la sincronización activada, desaparece también de tu nube y de tus otros dispositivos |
| Zonas de mapa sin conexión y teselas de rutas | bórralas en [datos sin conexión](./offline-maps-and-routing) |
| Un token de Strava o Ride with GPS, y todo lo que viene de Strava | **Desconectar** en Ajustes → Conexiones |
| Todo lo que guardó la app | desinstala la app |
| Un enlace para compartir | caduca al cabo de un año; escribe a [hello@orkitec.com](mailto:hello@orkitec.com) con el enlace para que se elimine antes |

Desinstalar no elimina los enlaces para compartir que creaste, ni nada de lo que subiste a Strava o Ride with GPS.

## Tus derechos

Si estás en la UE o en el Reino Unido, el RGPD te da derechos sobre tus datos personales. La mayoría puedes ejercerlos tú mismo, porque los datos están en tu teléfono y se exportan como GPX, FIT o TCX en cualquier momento. Para todo lo que está de nuestro lado, es decir, enlaces para compartir, entradas de registro y el registro de la suscripción, escribe a [hello@orkitec.com](mailto:hello@orkitec.com). La declaración completa, con la base jurídica y ante quién reclamar, está en la [política de privacidad](/privacy).

## Relacionado

- [Política de privacidad](/privacy)
- [Compartir](./sharing)
- [Asistente](./assistant)
- [Strava y Ride with GPS](./strava-and-ridewithgps)
- [Mapas y rutas sin conexión](./offline-maps-and-routing)

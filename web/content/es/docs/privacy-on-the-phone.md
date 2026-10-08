---
title: Privacidad en el teléfono
description: "En palabras de ciclista: qué se queda en tu teléfono, qué sale de él, cuándo y hacia quién. No hay cuenta y no se sube nada si no lo pides."
order: 15
---

Velorki no tiene cuenta, así que no hay nada en lo que iniciar sesión ni nada sobre ti en un servidor. Esta página es la versión en lenguaje claro de lo que eso significa en la práctica; la [política de privacidad](/privacy) es la formal.

## Qué se queda en el teléfono

Todo lo que creas y todo lo que descargas:

- las rutas planificadas, las salidas grabadas y sus tracks GPS,
- tus ajustes, incluidas las unidades y la voz que elegiste, y el peso, el año de nacimiento, el sexo, la frecuencia cardiaca máxima, el peso de la bici, el tipo de bici y la potencia umbral que puedes introducir en Ajustes → Ciclista, que son ajustes del teléfono y nunca se envían a ninguna parte,
- las zonas de mapa sin conexión descargadas,
- las teselas de rutas descargadas y los índices de búsqueda de lugares que vienen con ellas,
- los tokens de acceso de Strava y Ride with GPS si los conectas, que van al almacenamiento seguro del teléfono en una forma que solo el relay de Velorki puede abrir.

Nada de ello se sube a ninguna parte si no lo pides.

En Android, Velorki queda excluida a propósito de la copia de seguridad en la nube de Google y de la transferencia entre dispositivos, así que el sistema tampoco copia tus salidas fuera del teléfono. Pasar a un teléfono nuevo significa exportar lo que quieras conservar como archivos GPX, FIT o TCX; consulta [importar y exportar](./import-and-export).

## Qué sale del teléfono, y cuándo

### Mientras miras el mapa

Las teselas del mapa se piden a OpenFreeMap, y a CyclOSM si activas la capa ciclista. Pedir una tesela le dice al servidor qué cuadrado del mundo estás mirando e incluye tu dirección IP, como cualquier petición. Una zona que has descargado se sirve desde el teléfono y no pide nada.

### Mientras planificas

El cálculo de rutas se hace en tu teléfono allí donde tengas las teselas de rutas. Para una zona que no has descargado, los puntos de paso van a un servidor de rutas, que devuelve la ruta. Recibe los puntos de paso y nada más: ni identidad, ni otras rutas, ni salidas.

**Ajustes → Avanzado → Cálculo de rutas → Solo en el dispositivo** apaga el servidor por completo; Velorki ofrece entonces la descarga en lugar de calcular la ruta.

### Mientras buscas

La búsqueda se responde en el teléfono allí donde esté descargado el índice de la zona, y nada de lo que escribes sale del dispositivo.

Se hace en línea cuando tocas **Buscar «…» en línea**, o cuando no tienes índice para la zona que estás mirando. Entonces lo que escribiste va a Photon, junto con una posición aproximada para que los resultados cercanos salgan primero.

Tocar **Detalles** en la ficha de un lugar descarga sus detalles (horario, sitio web y similares) de OpenStreetMap.

Un enlace corto de mapa que compartes con Velorki (`maps.app.goo.gl`, `maps.apple/p`, `osm.org/go`) se abre una vez con el servicio que lo creó, para saber adónde apunta; ese servicio ve el enlace y tu dirección IP, como lo vería en un navegador.

### Mientras grabas

No sale absolutamente nada del teléfono. La grabación, las estadísticas, los gráficos y los parciales se calculan en el dispositivo. Lo mismo vale para la frecuencia cardiaca, la cadencia y la potencia de un reloj, un sensor Bluetooth o tu app de salud: se guardan con la salida y, si has activado Salud, se intercambian con Apple Health o Health Connect en el propio teléfono.

### Cuando preguntas al asistente

Solo con tu consentimiento, y solo lo que permitiste: tu texto, opcionalmente una posición redondeada a un kilómetro más o menos, y tus ajustes de idioma y unidades. Ni nombre, ni cuenta, ni historial de rutas, y nunca tu track. Consulta [asistente](./assistant).

### Cuando conectas Strava o Ride with GPS

No va nada a ninguno de los dos hasta que conectas la cuenta y luego pides algo, una subida o una importación.

Al conectar se entrega un código de un solo uso al relay de Velorki, que lo convierte en un token de acceso añadiendo nuestro secreto de aplicación, y le da el token a tu teléfono envuelto, de forma que solo el relay puede abrirlo. No guardamos el token. A partir de ahí cada subida e importación pasa por el relay: comprueba tu suscripción, abre el token para esa única petición y la reenvía a Strava o Ride with GPS. No guarda ni el archivo ni el token, y no puede usar el token por su cuenta.

### Cuando creas un enlace para compartir

Esa ruta o salida, con su track, su nombre y sus cifras, se copia a nuestro servidor para que el enlace pueda abrirse. El enlace es público para cualquiera que lo tenga, muestra dónde empieza y termina el track, y se borra automáticamente al cabo de un año. Consulta [compartir](./sharing).

### Cuando compras Velorki Plus

La tienda gestiona el pago y nunca vemos tu tarjeta. La suscripción se comprueba con un identificador aleatorio anónimo que no está vinculado a un nombre, a una dirección de correo ni a un identificador del dispositivo.

## Lo que Velorki nunca hace

- Ni cuenta, ni registro, ni dirección de correo.
- Ni publicidad, ni SDK de anuncios, ni perfiles.
- Ningún SDK de analítica ni de informes de errores en la app en el momento de escribir esto. Si alguna vez se añade uno, la política de privacidad lo nombrará y dirá qué recoge antes de que se publique.
- Ninguna venta de datos, a nadie, nunca.
- Ni funciones sociales ni mensajes entre usuarios.

## Deshacerse de las cosas

| Qué | Cómo |
|---|---|
| Una ruta o una salida | bórrala en la [biblioteca](./library) |
| Zonas de mapa sin conexión y teselas de rutas | bórralas en [datos sin conexión](./offline-maps-and-routing) |
| Un token de Strava o Ride with GPS | **Desconectar** en Ajustes → Conexiones |
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

---
title: Política de privacidad
description: "Qué hace Velorki con tus datos: sin cuenta, las rutas y las salidas se quedan en tu teléfono, y una lista exacta de lo que sale del dispositivo y cuándo."
draft: true
---

> **Nota sobre la traducción.** Esta es una traducción de la versión en inglés.
> En caso de discrepancia, prevalece la versión en inglés.

Fecha de entrada en vigor: 30 de septiembre de 2026.

Velorki es una app para planificar rutas en bici y grabar salidas creada por
Orkitec. Esta página explica qué ocurre con tus datos.

**Quién es el responsable.** El responsable del tratamiento de todo lo que se
describe aquí es Steffen Roemer, que opera como «Orkitec», Straße der Pariser
Kommune 27, 10243 Berlín, Alemania, ride@velorki.com. No se ha designado un
delegado de protección de datos: el tratamiento que se describe a continuación
no lo requiere según el artículo 37 del RGPD. Los datos completos del proveedor
están en la página del [aviso legal](./imprint).

## La versión corta

- **No hay cuenta.** No te registras y no sabemos quién eres.
- Tus rutas, tus salidas y tus ajustes se quedan **en tu teléfono**.
- Algunas cosas necesitan un servidor: las teselas del mapa, el enrutamiento
  fuera de las zonas que has descargado, la búsqueda cuando la pides y, si los
  usas, el asistente de IA, las conexiones con Strava y RideWithGPS y los
  enlaces compartidos. Cada uno se describe más abajo.
- Esta **web** no tiene analítica, ni publicidad, ni rastreo, así que el breve
  aviso que aparece al pie no te pide nada.
- No vendemos tus datos y no los usamos para publicidad ni para elaborar
  perfiles.

## Lo que se queda en tu dispositivo

Las rutas planificadas, las salidas grabadas, sus tracks GPS, tus ajustes, las
regiones de mapa descargadas para usar sin conexión, las teselas de
enrutamiento descargadas y los índices de búsqueda de lugares que vienen con
ellas se guardan en el almacenamiento propio de la app en tu teléfono. No se
suben a ningún sitio salvo que tú lo pidas.

La frecuencia cardiaca, la cadencia y la potencia de un Apple Watch, de un
sensor Bluetooth o de tu app de salud se guardan con la salida, en el teléfono,
igual que el propio track. Con el interruptor de Salud activado en Ajustes, la
app lee la frecuencia cardiaca de Apple Health o Health Connect y escribe allí
tus salidas terminadas como entrenamientos de ciclismo; ese intercambio ocurre
en tu teléfono y nada de ello nos llega. Los valores de los sensores solo viajan
con una salida allí donde viaja la salida: en un archivo GPX, FIT o TCX que
exportes, o en una subida a Strava o RideWithGPS que inicies tú.

Si conectas Strava o RideWithGPS, los tokens de acceso de esas cuentas se
guardan en el almacenamiento seguro del teléfono (Keychain en iOS, Keystore en
Android), cifrados de forma que solo nuestro relay puede abrirlos; consulta el
apartado de Strava y RideWithGPS más abajo.

En Android, la app está excluida de la copia de seguridad en la nube de Google
y de la transferencia entre dispositivos, así que el sistema tampoco copia
fuera del teléfono tus salidas ni tus tokens de acceso. Para pasar a un teléfono
nuevo, exporta como archivos GPX, FIT o TCX lo que quieras conservar.

## Lo que sale de tu dispositivo, y cuándo

### Enrutamiento

Normalmente el enrutamiento ocurre por completo en tu teléfono, a partir de las
teselas de enrutamiento que has descargado, y no se envía nada a ningún sitio.
Para una zona de la que no tienes teselas, la app envía las coordenadas de tus
puntos de paso a un servidor de enrutamiento (BRouter, gestionado por
nosotros), que devuelve la ruta. Necesita los puntos de paso para calcular la
ruta; no recibe tu identidad, ni tus otras rutas, ni tus salidas.

### Búsqueda

Los lugares se buscan en tu teléfono, en los índices de búsqueda que vienen con
las teselas de enrutamiento que has descargado. Nada de lo que escribes ahí
sale del dispositivo.

Si tocas «Buscar en línea…» al final de los resultados (o si no has
descargado ninguna tesela de enrutamiento, en cuyo caso el cuadro de búsqueda
busca en línea directamente), lo que has escrito se envía a Photon, un
servicio de geocodificación, junto con una posición aproximada para que los
resultados cercanos aparezcan primero. Photon devuelve sugerencias de lugares.

Al tocar «Detalles» en la ficha de un lugar se obtienen sus detalles (horario,
sitio web y similares) de OpenStreetMap.

### Teselas del mapa

El mapa se dibuja con teselas obtenidas de OpenFreeMap y, si activas la capa
ciclista, de CyclOSM. Al obtener una tesela, el proveedor de teselas sabe qué
parte del mapa estás mirando, y en ello interviene tu dirección IP, como en
cualquier petición web. Datos del mapa © colaboradores de OpenStreetMap.

### Strava y RideWithGPS (Velorki Plus)

No se envía nada a Strava ni a RideWithGPS salvo que conectes tú mismo la
cuenta y luego inicies una acción: subir una salida o importar una ruta.

Cuando conectas, la app entrega un código de un solo uso a nuestro servidor
relay, que lo canjea por un token de acceso añadiendo el secreto de nuestra
aplicación, cifra el token con una clave que solo tiene el relay y lo devuelve
a la app de esa forma. Tu teléfono guarda el token cifrado; no puede usarlo por sí
solo, y nosotros no lo guardamos en absoluto.

A partir de ahí, cada subida, transferencia de ruta, importación y
desconexión que inicias pasa por el relay: comprueba que tu suscripción está
activa, descifra el token para esa única petición, reenvía la petición a
Strava o RideWithGPS y devuelve la respuesta a la app. No conserva ni el
archivo ni el token, ni nada de la respuesta, y aplica la misma limitación de
frecuencia que a cualquier otra llamada al relay (consulta los registros del
servidor más abajo). Sus registros nunca contienen el token, el cuerpo de la
petición ni el id de suscriptor.

Lo que Strava o RideWithGPS hagan después con los datos que les envías se rige
por sus propias políticas de privacidad.

### El asistente de IA (Velorki Plus)

El asistente está desactivado hasta que lo activas, y la primera vez que lo
abres se te pide tu consentimiento. Puedes elegir enviar solo tu texto, o tu
texto junto con una posición de inicio aproximada, o rechazarlo. Puedes
revocar el consentimiento en los ajustes en cualquier momento.

Cuando lo usas, se envía lo siguiente a nuestro proveedor de IA a través de
nuestro servidor relay:

- el texto que has escrito,
- opcionalmente, una posición de inicio **redondeada a aproximadamente un
  kilómetro**,
- los ajustes de idioma y de unidades, para que la respuesta encaje,
- si pides una descripción de la ruta, un resumen de la ruta elaborado en tu
  teléfono: distancia, desnivel, proporción de cada firme, los tramos que recorre
  con su carretera, firme y pendiente, sus subidas, las localidades por las
  que pasa y los lugares para parar cerca de ella, cada uno con su distancia a
  lo largo de la ruta y su posición (con una precisión de unos 10 m). El
  proveedor de IA también los recibe; por tanto, una ruta que empieza en tu
  casa muestra dónde está tu casa.

En la petición no se incluye ningún identificador tuyo ni de tu teléfono. El
modelo devuelve una petición estructurada: una distancia, una forma, nombres
de lugares, preferencias. El enrutamiento en sí ocurre después en la app; el
modelo nunca ve tu ruta.

Nuestro relay pasa la petición a **OpenRouter, Inc.** (EE. UU.), un servicio
que da acceso a modelos de lenguaje de varios proveedores, y OpenRouter la
reenvía al proveedor que sirve el modelo que usamos. Hemos configurado
OpenRouter para que envíe peticiones solo a proveedores que no entrenan
modelos con ellas y no las conservan. La transferencia a Estados Unidos se
basa en las cláusulas contractuales tipo de la Comisión Europea. OpenRouter y
el proveedor del modelo reciben la petición de nuestro relay, no de tu teléfono,
así que ven la dirección de nuestro servidor y no la tuya.

El asistente accede al modelo mediante una interfaz compatible con OpenAI, así
que cualquiera que aloje Velorki por su cuenta puede hacer que su relay apunte
a cualquier proveedor o a su propio modelo; en ese caso se aplica la política
de ese operador, no esta.

Los datos de Strava nunca se envían al proveedor de IA.

### Enlaces compartidos (Velorki Plus)

Si creas un enlace compartido para una ruta o una salida, esa ruta o salida,
con su track, su nombre y sus estadísticas, se sube a nuestro servidor y se
guarda allí para que cualquiera que tenga el enlace pueda abrirla. La
frecuencia cardiaca, la cadencia y la potencia se excluyen: una salida
compartida lleva su track y sus tiempos, no lo que midió un sensor. El enlace
es público: cualquiera que lo tenga puede ver el contenido, incluidos los
puntos de inicio y final del track. Tenlo en cuenta antes de compartir una
salida que empieza en tu casa.

Un elemento compartido se conserva **un año** y después se elimina
automáticamente. Para que se retire antes, envía el enlace a la dirección de
contacto que figura más abajo y lo eliminamos. Ver un enlace compartido no
requiere cuenta.

### Suscripciones

Velorki Plus se vende a través del App Store y Google Play, y RevenueCat la
gestiona en nuestro nombre. RevenueCat asigna a tu instalación un **id de
usuario anónimo de la app**, una cadena aleatoria que no está vinculada a un
nombre, una dirección de correo electrónico ni un identificador del
dispositivo. RevenueCat también recibe de la tienda el recibo de compra.
Nuestro relay envía ese id anónimo a RevenueCat para comprobar si tu
suscripción está activa, y para nada más.

Nunca vemos tus datos de pago; se quedan en Apple o Google.

### Informes de errores y analítica

No hay ninguno. La app no contiene informes de errores, ni analítica, ni SDK de
publicidad, y no envía estadísticas de uso; cada petición de red que hace es
una de las que se describen arriba. Los cierres inesperados los comunican las
tiendas de apps de forma agregada a la cuenta de desarrollador, sin nada que te
identifique, y solo si lo tienes activado en los ajustes de tu propio teléfono. Si
algún día se añade un sistema de informes de errores, este apartado lo
nombrará y dirá qué recoge antes de que se publique esa versión.

### Registros del servidor

Nuestro relay y nuestro servidor de enrutamiento guardan registros operativos
(hora de la petición, endpoint, estado, dirección IP y una cabecera con la
versión del cliente) para hacer funcionar el servicio, encontrar fallos y
aplicar límites de frecuencia. No se usan para elaborar perfiles de usuarios y
nunca contienen un token de acceso, el cuerpo de una petición ni un id de
suscriptor.

- Los registros de acceso del servidor web se guardan en la máquina durante
  **14 días** y después la rotación de registros los elimina.
- Las líneas de registro propias de la aplicación las recoge Orkify, el panel
  de despliegue que el operador gestiona en la misma infraestructura de
  Hetzner, y allí se eliminan a más tardar a los **90 días**.

## Esta web

velorki.com es una web sencilla: sin cuenta, sin publicidad, sin analítica,
sin rastreo. Nada de lo que haces aquí se mide, así que el aviso que quizá
hayas visto al pie de la página es exactamente eso, un aviso: no hay ningún
consentimiento que dar o rechazar, porque no se guarda nada en tu dispositivo
hasta que tú lo pides. La entrada 🍪 Cookies del pie de página lo vuelve a
mostrar.

- **Registros del servidor.** Cada petición se registra como se describe en
  «Registros del servidor» más arriba: hora, ruta, estado, tamaño, tu
  dirección IP y el agente de usuario de tu navegador, guardados 14 días.
- **Informes de errores.** Si una página de esta web falla en tu navegador,
  envía el error, la dirección de la página y el agente de usuario de tu
  navegador a nuestro servidor, solo para que podamos corregir el fallo.
- **Cloudflare.** La web se sirve a través de Cloudflare, que termina la
  conexión, filtra ataques y pasa la petición a nuestro servidor. Por tanto,
  trata tu dirección IP y la propia petición. Cloudflare está en Estados
  Unidos; la transferencia se basa en las cláusulas contractuales tipo de la
  UE.
- **Una cookie de idioma.** Elegir un idioma en la cabecera establece una
  cookie llamada `NEXT_LOCALE` (con el código del idioma elegido, por ejemplo
  `es`, durante un año). Existe para que la web se abra en el idioma que
  elegiste. No guarda nada más, y solo se establece cuando haces esa elección:
  es estrictamente necesaria para una función que pediste y no requiere
  consentimiento según el artículo 25 (2) de la TTDSG alemana.
- **Una preferencia de tema.** Elegir claro, oscuro o un color de acento
  escribe `velorki.theme` en el almacenamiento local de tu navegador. Nunca
  sale del navegador y nosotros no podemos leerlo. Cerrar el aviso mencionado
  arriba escribe una clave más, `velorki.cookie-notice`, para que no se vuelva
  a mostrar.
- **Páginas compartidas.** Abrir un enlace `velorki.com/s/…` carga la ruta
  compartida desde nuestro servidor y las teselas del mapa desde OpenFreeMap,
  que ve tu dirección IP como en cualquier petición web. La página no tiene
  ningún otro contenido de terceros.
- **El chat de soporte.** El botón de chat de la esquina es el widget de
  Orkify. Orkitec también gestiona Orkify, así que es nuestra propia
  infraestructura, pero es un sitio distinto: el script se carga desde
  orkify.com y pide su configuración a orkify.com cuando se abre la página, lo
  que significa que tu dirección IP le llega como llega a cualquier servidor
  al que haces una petición. No ocurre nada más hasta que abres el chat.

  Cuando nos escribes, tu mensaje (y el nombre y la dirección de correo
  electrónico que escribas en su formulario) se entrega a un canal privado de
  Discord donde respondemos, y la conversación se queda allí hasta que la
  eliminamos. Pídelo en ride@velorki.com y eliminamos la tuya. El widget guarda
  el id de la conversación y el nombre y el correo que diste en el
  almacenamiento local de tu navegador, para que una respuesta te siga
  encontrando cuando vuelvas, y los borra cuando terminas el chat. Si abres el
  selector de stickers, tu búsqueda va a Klipy, que devuelve las imágenes. No
  pongas en el chat nada que no pondrías en una incidencia de soporte; para un
  informe de seguridad, usa en su lugar la dirección de
  [SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md).
- **Las tipografías y las imágenes** vienen todas de este servidor y, aparte
  del chat de soporte, no hay ningún script de terceros, ninguna CDN para
  nuestros propios recursos ni ningún servicio de tipografías.

## Conservación y eliminación

| Datos | Se conservan | Cómo eliminarlos |
|---|---|---|
| Rutas, salidas, ajustes, datos sin conexión | en tu teléfono, hasta que los eliminas | elimínalos en la app o desinstala la app |
| Tokens de Strava / RideWithGPS | en tu teléfono, cifrados de forma que solo nuestro relay puede abrirlos, hasta que desconectas; nunca se guardan en nuestro lado | desconecta en la app o desinstálala |
| Enlaces compartidos | un año, después se eliminan automáticamente | elimínalos desde la app |
| Peticiones a la IA | no las guardamos más allá de lo que contienen los registros mencionados | no aplicable |
| Datos de RevenueCat | según la propia política de RevenueCat | contáctanos y transmitiremos la solicitud |
| Conversaciones del chat de soporte | en nuestro canal de Discord hasta que las eliminamos | pídelo en ride@velorki.com |

Desinstalar la app elimina todo lo que la app guardó en el dispositivo. No
elimina los enlaces compartidos que creaste (caducan al cabo de un año, o a
petición), ni nada de lo que subiste a Strava o RideWithGPS.

## Bases jurídicas

Para lectores de la UE y del Reino Unido, las bases jurídicas según el
artículo 6 (1) del RGPD son:

| Qué | Base |
|---|---|
| Servir la web y las páginas compartidas, mantener los servidores en marcha, encontrar fallos, límites de frecuencia, defensa frente a ataques | (f) interés legítimo en ofrecer un servicio que funcione y del que no se abuse |
| Enrutamiento en línea y búsqueda en línea, cuando los pides | (b) ejecución del servicio que solicitaste, y (f) para las coordenadas estrictamente necesarias para responder |
| Velorki Plus: comprobar con RevenueCat que una suscripción está activa | (b) ejecución del contrato |
| Strava y RideWithGPS: conectar una cuenta y cada transferencia que inicias | (b) ejecución del contrato, más (a) consentimiento, dado al conectar la cuenta |
| Enlaces compartidos que creas | (b) ejecución del contrato |
| El asistente de IA | (a) consentimiento, solicitado por separado en la app y revocable en los ajustes |
| Responderte en el chat de soporte | (b) cuando se trata de una suscripción; en los demás casos, (f) interés legítimo en responder a quien nos ha escrito |
| Conservar registros de una suscripción relevantes a efectos fiscales | (c) obligación legal; y los datos de facturación los tienen Apple y Google, no nosotros |

No elaboramos perfiles, no tomamos decisiones automatizadas sobre ti y no
usamos nada de esto para marketing directo.

## Quién más recibe datos

No vendemos, alquilamos ni intercambiamos datos personales. Llegan a estas
partes, y a ninguna otra:

**Encargados del tratamiento, que actúan por cuenta nuestra en virtud de un
contrato de encargo del tratamiento**

- **Hetzner Cloud GmbH**, Gunzenhausen, Alemania: el servidor en el que
  funcionan el relay, los enlaces compartidos y esta web. Los datos se quedan
  en Alemania.
- **Cloudflare, Inc.**, San Francisco, EE. UU.: DNS, CDN y protección frente a
  ataques para velorki.com y api.velorki.com. Direcciones IP y metadatos de
  las peticiones.
- **RevenueCat, Inc.**, San Francisco, EE. UU.: la comprobación de la
  suscripción. El id de usuario anónimo de la app y el recibo de la tienda,
  sin nombre ni dirección de correo electrónico.
- **Orkify**, gestionado por el mismo operador en la infraestructura de
  Hetzner mencionada: el panel de despliegue que recoge los registros de la
  aplicación y las métricas de procesos descritos en «Registros del servidor»
  y los informes de errores de esta web, y el widget del chat de soporte.
- **Discord Netherlands B.V.** (para usuarios en Europa; Discord Inc., San
  Francisco, EE. UU., para el servicio subyacente): donde se entrega y se
  conserva una conversación del chat de soporte.
- **Klipy**: la búsqueda de stickers y GIF en el chat de soporte, y solo
  mientras ese selector está abierto.
- **OpenRouter, Inc.**, EE. UU., y el proveedor del modelo al que reenvía: el
  asistente de IA, solo después de que hayas dado tu consentimiento, limitado
  a proveedores que ni entrenan con las peticiones ni las conservan.

**Servicios con los que tu teléfono o tu navegador contacta directamente, cada
uno responsable de su propio tratamiento**

- **OpenFreeMap** (teselas del mapa) y **OpenStreetMap France** (la capa
  CyclOSM, solo cuando la activas): las teselas de la parte del mapa que estás
  mirando, y tu dirección IP.
- **komoot GmbH**, Potsdam, Alemania: el geocodificador Photon en
  `photon.komoot.io`, y solo para una búsqueda en línea que hayas pedido.
- **OpenStreetMap** (`api.openstreetmap.org`): los detalles de un lugar,
  cuando tocas «Detalles» en su ficha.
- **Apple Inc.** y **Google Ireland Ltd**: la venta de Velorki Plus. Ellos son
  los vendedores; nosotros nunca vemos tus datos de pago.
- **Strava, Inc.** y **Ride with GPS**: solo después de que conectes la cuenta
  y solo para una transferencia que inicies tú. Lo que hagan con ello se rige
  por sus propias políticas.

También entregaremos datos a un tribunal o a una autoridad cuando la ley lo
exija.

## Transferencias fuera de la UE

Cloudflare, RevenueCat, OpenRouter y el proveedor del modelo que hay detrás,
Discord, Klipy, Strava, Ride with GPS, Apple y Google están en Estados Unidos
o transfieren datos allí. Esas transferencias se basan en las cláusulas
contractuales tipo de la Comisión Europea, o en la certificación del proveedor
conforme al Marco de Privacidad de Datos UE-EE. UU. cuando la tiene, junto con
las propias salvaguardas técnicas del proveedor. Hetzner, komoot y los
servicios de teselas de mapa de los que dependemos están en la UE, y
OpenStreetMap en el Reino Unido. Todo lo que la app guarda para ti se queda en
tu teléfono y no se transfiere a ningún sitio.

## Seguridad

Todas las conexiones con nuestros servidores y con los servicios mencionados
están cifradas con TLS. Los tokens de Strava y RideWithGPS nunca están sin
cifrar en ningún sitio: tu teléfono los guarda en el almacenamiento seguro de la
plataforma, envueltos con una clave que solo tiene el relay, y el relay
desenvuelve uno para la única petición en la que se necesita y no conserva
nada. La base de datos de enlaces compartidos está en el disco del servidor,
fuera del directorio de la versión publicada, y solo la puede leer el usuario
del servicio. Los registros se depuran: sin cabecera `Authorization`, sin
cuerpo de la petición, sin id de suscriptor. El acceso al servidor requiere una
clave, no una contraseña, y está restringido al operador. Si una brecha de
seguridad pusiera en riesgo tus derechos, lo notificaremos a la autoridad de
control en un plazo de 72 horas (artículo 33 del RGPD) y, cuando la ley lo
exija, también a ti.

## Tus derechos

Si estás en la UE o en el Reino Unido, tienes derecho de acceso (artículo 15
del RGPD), rectificación (16), supresión (17), limitación del tratamiento
(18), portabilidad de los datos (20) y oposición al tratamiento basado en un
interés legítimo (21), y cuando nos basamos en tu consentimiento (el
asistente), puedes retirarlo en cualquier momento sin que ello afecte a la
licitud de lo anterior (artículo 7 (3)). La mayoría puedes ejercerlos tú
mismo, porque los datos están en tu teléfono y se pueden exportar como archivos
GPX, FIT o TCX cuando quieras.

Para cualquier cosa que esté en nuestro lado (enlaces compartidos, entradas de
registro, el registro de RevenueCat), escribe a **ride@velorki.com**.
Respondemos en un plazo de 30 días. Necesitaremos información suficiente para
identificar los datos, lo que en el caso de un enlace compartido significa el
propio enlace, ya que no hay ninguna cuenta con la que buscarte.

También puedes presentar una reclamación ante una autoridad de control. La
nuestra es la
[Berliner Beauftragte für Datenschutz und Informationsfreiheit](https://www.datenschutz-berlin.de),
y también puedes dirigirte a la autoridad del lugar donde vives.

El responsable es Steffen Roemer, que opera como «Orkitec», Straße der Pariser
Kommune 27, 10243 Berlín, Alemania.

## Menores

Velorki no está dirigida a menores y no recoge datos de ellos a sabiendas. No
tiene funciones sociales, ni mensajería entre usuarios, ni publicidad.

## Cambios

Si esta política cambia de una forma que afecte a lo que sale de tu
dispositivo, la app te lo dirá la próxima vez que la abras, y cambiará la fecha
del principio. Las versiones antiguas siguen en el historial de git del
repositorio.

## Contacto

Orkitec, ride@velorki.com; dirección postal en el [aviso legal](./imprint).
Para informes de seguridad, consulta
[SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md) en el
repositorio del código fuente.

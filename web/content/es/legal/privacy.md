---
title: Política de privacidad
description: "Qué hace Velorki con tus datos: sin cuenta, las rutas y las salidas se quedan en tu teléfono o en tu navegador salvo que las sincronices con tu propio iCloud o Google Drive, y una lista exacta de lo que sale del dispositivo y cuándo."
draft: false
---

> **Nota sobre la traducción.** Esta es una traducción de la versión en inglés.
> En caso de discrepancia, prevalece la versión en inglés.

Fecha de entrada en vigor: 23 de octubre de 2026.

Velorki es una app para planificar rutas en bici y grabar salidas creada por
Orkitec, para iPhone, iPad y Android, y un planificador web en app.velorki.com.
Esta página explica qué ocurre con tus datos.

**Quién es el responsable.** El responsable del tratamiento de todo lo que se
describe aquí es Steffen Roemer, que opera como «Orkitec», Straße der Pariser
Kommune 27, 10243 Berlín, Alemania, ride@velorki.com. No se ha designado un
delegado de protección de datos: el tratamiento que se describe a continuación
no lo requiere según el artículo 37 del RGPD. Los datos completos del prestador
están en la página del [aviso legal](./imprint).

## La versión corta

- **No hay cuenta.** No te registras y no sabemos quién eres.
- Tus rutas, tus salidas y tus ajustes se quedan **en tu teléfono**, o en tu
  navegador en el caso del planificador web. Si activas la sincronización, van
  a tu propio iCloud o a tu propio Google Drive, nunca a nosotros.
- Algunas cosas necesitan un servidor: las teselas del mapa, el cálculo de
  rutas fuera de las zonas que has descargado, la búsqueda cuando la pides y,
  si los usas, el asistente de IA, las conexiones con Strava y RideWithGPS
  (gratis) y los enlaces compartidos. Cada uno se describe más abajo.
- Esta **web** no tiene analítica, ni publicidad, ni rastreo, así que el breve
  aviso que aparece al pie no te pide nada.
- El **planificador web** en app.velorki.com funciona igual: sin cuenta, sin
  analítica, con tu biblioteca guardada en tu navegador.
- No vendemos tus datos y no los usamos para publicidad ni para elaborar
  perfiles.

## Lo que se queda en tu dispositivo

Las rutas planificadas, las salidas grabadas, sus tracks GPS, tus ajustes, las
regiones de mapa descargadas para usar sin conexión, las teselas de rutas
descargadas y los índices de búsqueda de lugares que vienen con ellas se
guardan en el almacenamiento propio de la app en tu teléfono. No se
suben a ningún sitio salvo que tú lo pidas; la única excepción es la
sincronización en la nube, descrita más abajo, que va a tu propio iCloud o
Google Drive y no a nosotros. Lo que el planificador web guarda en tu navegador
se describe en El planificador web.

La frecuencia cardiaca, la cadencia y la potencia de un Apple Watch, de un
sensor Bluetooth o de tu app de salud se guardan con la salida, en el teléfono,
igual que el propio track. Con el interruptor de Salud activado en Ajustes, la
app lee la frecuencia cardiaca de Apple Health o Health Connect y escribe allí
tus salidas terminadas como entrenamientos de ciclismo; ese intercambio ocurre
en tu teléfono y nada de ello nos llega. Los valores de los sensores solo viajan
con una salida allí donde viaja la salida: en un archivo GPX, FIT o TCX que
exportes, en una subida a Strava o RideWithGPS que inicies tú, o a tu propia
nube mientras la sincronización está activada.

Si conectas Strava o RideWithGPS, los tokens de acceso de esas cuentas se
guardan en el almacenamiento seguro del teléfono (Keychain en iOS, Keystore en
Android), cifrados de forma que solo nuestro relay puede abrirlos, y lo que
obtienes de Strava se guarda en el teléfono; consulta el apartado de Strava y
RideWithGPS más abajo.

En Android, la app está excluida de la copia de seguridad en la nube de Google
y de la transferencia entre dispositivos, así que el sistema tampoco copia
fuera del teléfono tus salidas ni tus tokens de acceso. Para pasar a un teléfono
nuevo, activa la sincronización con Google (descrita más abajo) o exporta como
archivos GPX, FIT o TCX lo que quieras conservar.

## Lo que sale de tu dispositivo, y cuándo

### Cálculo de rutas

Normalmente las rutas se calculan por completo en tu teléfono, a partir de las
teselas de rutas que has descargado, y no se envía nada a ningún sitio. Para
una zona de la que no tienes teselas, la app envía las coordenadas de tus
puntos de paso a un servidor de rutas (BRouter, gestionado por nosotros), que
devuelve la ruta. Necesita los puntos de paso para calcular la ruta; no recibe
tu identidad, ni tus otras rutas, ni tus salidas.

Las teselas de rutas y los índices de búsqueda que las acompañan se descargan
de nuestro espejo de teselas en GitHub (`raw.githubusercontent.com` y las
descargas de versiones publicadas (releases) de `github.com`). GitHub sabe qué
teselas de 5° descargas y tu dirección IP, como en cualquier petición web. El
planificador web las obtiene en cambio a través de app.velorki.com, así que
GitHub ve a Cloudflare y no a ti.

### Búsqueda

Los lugares se buscan en tu teléfono, en los índices de búsqueda que vienen con
las teselas de rutas que has descargado. Nada de lo que escribes ahí sale del
dispositivo.

Si tocas «Buscar “…” en línea» al final de los resultados (o si no has
descargado ninguna tesela de rutas, en cuyo caso el cuadro de búsqueda
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

### El tiempo

**El mapa del tiempo y el pronóstico gratuito de la ruta.** Cuando activas la
lluvia, las nubes o el viento en el mapa, o coloreas una ruta según el viento o
la lluvia sin Velorki Plus, la app obtiene imágenes y datos de pronóstico
directamente de servicios meteorológicos públicos: el Deutscher Wetterdienst
(Alemania), la National Oceanic and Atmospheric Administration de EE. UU. y la
Iowa State University (EE. UU.), la NASA, EUMETSAT, el KNMI (Países Bajos) y el
Instituto Meteorológico de Finlandia. Cada petición indica una parte del mapa, o
un recuadro alrededor de tu ruta, y una hora, y en ella interviene tu dirección
IP, como en cualquier petición web. No se envían ni tu ruta en sí, ni tus
salidas, ni tu identidad.

**Un tiempo más preciso a lo largo de la ruta (Velorki Plus).** La app envía a
nuestro relay los puntos a lo largo de la ruta redondeados a una cuadrícula de
unos 2,5 km, cada uno con su altitud redondeada a 50 m, y las horas en que
pasarás por allí; no la ruta, ni su nombre, ni tus salidas. El relay comprueba
que tu suscripción está activa y pide el pronóstico de esos puntos de la
cuadrícula al National Weather Service de EE. UU., a Bright Sky (para los
pronósticos del Deutscher Wetterdienst) y a MET Norway. Ellos ven nuestro
servidor, no tu teléfono. Cada respuesta se conserva hasta dos horas por punto
de la cuadrícula y se comparte con todos los que piden el mismo punto.

**Radar de lluvia en toda Europa (Velorki Plus).** La app pide a nuestro relay
la parte del mapa que estás mirando y una hora. El relay obtiene el radar una
sola vez para todos del archivo abierto de EUMETNET OPERA y, para Italia, del
Dipartimento della Protezione Civile, lo conserva hasta dos horas y media y
devuelve una imagen de esa parte del mapa. Los proveedores del radar ven nuestro
servidor, no tu teléfono, y el relay no guarda ningún registro de qué parte del
mapa pediste.

### Strava y RideWithGPS

Ambas conexiones son gratis. No se envía nada a Strava ni a RideWithGPS salvo
que seas tú quien conecte la cuenta y luego inicie una acción: subir una salida
o importar una ruta.

Cuando conectas, la app entrega un código de un solo uso a nuestro servidor
relay (api.velorki.com), que lo canjea por un token de acceso añadiendo el
secreto de nuestra aplicación, cifra el token con una clave que solo tiene el
relay y lo devuelve a la app de esa forma. Tu teléfono guarda el token cifrado
en su almacenamiento seguro (Keychain en iOS, Keystore en Android), excluido de
las copias de seguridad; no puede usarlo por sí solo, y nosotros no lo guardamos
en absoluto.

A partir de ahí, cada subida, transferencia de ruta, importación y
desconexión que inicias pasa por el relay: descifra el token para esa única
petición, reenvía la petición a Strava o RideWithGPS y devuelve la respuesta a
la app. No conserva ni el archivo ni el token, ni nada de la respuesta, ni
ningún registro de la llamada. Para estas llamadas no se comprueba ninguna
suscripción; para frenar los abusos, el relay solo guarda contadores de límite
de frecuencia de corta duración, asociados al id anónimo de tu instalación y a
la dirección IP (consulta «Registros del servidor» más abajo). Sus registros
nunca contienen el token, el cuerpo de la petición ni ese id.

#### Strava

**Qué pide Velorki.** Dos permisos: `read`, tu perfil público de Strava (tu id
de atleta y tu nombre), y `activity:write`, para subir las salidas que elijas
subir. Velorki no lee tus actividades.

**Qué lee y qué conserva, todo ello solo en tu teléfono:**

- tu id de atleta y tu nombre, que se muestran en Ajustes → Conexiones, hasta
  que desconectes;
- tu lista de rutas de Strava (nombre, distancia, desnivel positivo,
  descripción y fecha), que se descarga al abrir la pantalla de importación y
  se guarda en el teléfono como máximo **48 horas**;
- el archivo GPX de una ruta, cuando importas esa ruta; se guarda como ruta en
  la biblioteca de la app, y lo mismo vale para cualquier ruta que edites a
  partir de ella, solo mientras la ruta siga existiendo en Strava: mientras la
  app esté abierta, con conexión y conectada, comprueba la ruta en Strava de
  nuevo cada 48 horas, y la elimina si se borró en Strava o no se pudo
  comprobar durante 7 días, y te avisa. También se elimina cuando la eliminas o
  desconectas;
- tras una subida, el id de la actividad de Strava y su enlace, que se guardan
  con la salida para que la app pueda mostrar «View on Strava», hasta que
  desconectes.

Una salida que subes se envía a Strava, que la procesa como se describe en la
[política de privacidad de Strava](https://www.strava.com/legal/privacy). Strava
y Orkitec son responsables cada una de su propio tratamiento.

**Los datos de Strava se quedan contigo.** Los datos de Strava solo se te
muestran a ti, en la app. Nunca se envían al asistente de IA, nunca se ponen en
un enlace compartido y nunca se envían a RideWithGPS ni a ningún otro servicio.
No guardamos datos de Strava en nuestros servidores.

**Eliminación.** Desconectar Strava en Ajustes → Conexiones revoca la
autorización de Velorki en Strava, elimina los tokens y elimina del teléfono
todo lo que vino de Strava: las rutas de Strava importadas y las rutas editadas
a partir de ellas, la lista de rutas en caché y los enlaces de actividad
guardados. Después la app lo confirma: «Tus datos de Strava se han borrado de
este teléfono.» Si, en cambio, revocas el acceso de Velorki en strava.com, la
app lo nota en su siguiente llamada a Strava, elimina los mismos datos y te
avisa.
Desinstalar la app también los elimina. Como todo está en tu teléfono, estas
son las formas de eliminarlo; para preguntas o una solicitud de eliminación,
escribe a ride@velorki.com.

**Datos de uso en Strava.** Strava puede supervisar y recopilar datos sobre
cómo Velorki utiliza la API de Strava (datos de uso) y puede utilizarlos para
cualquier fin comercial, interno o externo, incluidos proporcionar mejoras a la
API de Strava o a la plataforma de Strava, prestar asistencia a desarrolladores
o usuarios y garantizar el cumplimiento de su acuerdo de API.

#### RideWithGPS

Lo que RideWithGPS hace con los datos que le envías se rige por su propia
política de privacidad.

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
de lugares, preferencias. El cálculo de la ruta en sí ocurre después en la app;
el modelo nunca ve tu ruta.

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

### Sincronización en la nube (iCloud o Google Drive)

Cada dispositivo se sincroniza como máximo con una nube, elegida en **Ajustes →
Sincronizar con**: iCloud (iPhone y iPad con iOS 17 o posterior, y el
planificador web), Google (el iPhone, el iPad, Android y el planificador web) o
desactivado. En un iPhone o iPad, iCloud está activado por defecto; en Android
y en el navegador la sincronización está desactivada hasta que eliges una nube.

**Qué se sincroniza.** Tus rutas guardadas y tus salidas grabadas, con el
track, las notas, las estadísticas y las vueltas de cada salida, y la
frecuencia cardiaca, la cadencia, la potencia y la temperatura registradas con
ella. También se sincronizan unos pocos ajustes: tema, color de acento, aspecto
del mapa, aspecto del radar de lluvia, estilo de la barra, lado en pantallas
grandes, unidades y los ajustes de giros, de voz y de recálculo de ruta. En el
navegador
con iCloud, los ajustes se quedan en el navegador. Cada app también escribe un
pequeño registro de Plus en la misma nube, descrito en Suscripciones.

**Hay cosas que nunca se sincronizan.** Las rutas leídas de Strava y las rutas
editadas a partir de ellas, y los enlaces de Strava de las salidas que subiste a
Strava, se quedan en ese único teléfono, como se describe más arriba en Strava.
Los enlaces de las subidas a Ride with GPS tampoco se sincronizan; una ruta que
importas de Ride with GPS se sincroniza como ruta tuya, sin su id de Ride with
GPS. Las regiones de mapa descargadas y las teselas de rutas, los permisos,
los sensores emparejados, la voz, el idioma, las cuentas conectadas y la propia
suscripción no forman parte de ella.

**iCloud.** Los datos pasan por CloudKit de Apple a tu propia base de datos
privada de iCloud. Apple los almacena y los transfiere, y cuentan para tu
almacenamiento de iCloud. Apple los cifra en tránsito y en sus servidores; con
la Protección avanzada de datos activada, quedan cifrados de extremo a extremo,
como describe la [descripción general de la seguridad de los datos de iCloud de
Apple](https://support.apple.com/en-us/102651). En el navegador inicias sesión
con el propio botón de Apple, en una ventana de Apple; el script CloudKit JS de
Apple se carga desde Apple solo cuando eliges iCloud, y guarda tu inicio de
sesión de Apple en una cookie en el sitio del planificador hasta que cierras
sesión (borrar los datos del sitio en el navegador también la elimina).

El servidor de subidas de Apple no acepta subidas enviadas directamente desde
nuestro sitio. Por eso, cuando el planificador web guarda una ruta o una salida
en iCloud, el archivo del registro (el track y los detalles de la ruta o de la
salida) se envía a app.velorki.com/cloudkit/upload, una pequeña función de
Cloudflare que lo pasa sin cambios a la dirección de subida de un solo uso que
Apple dio para él y devuelve el justificante de Apple. No guarda nada, y no
conservamos registros de ella. Los demás campos del registro van directamente a
Apple.

**Google Drive.** Inicias sesión con tu cuenta de Google, y Velorki pide un
único permiso: su propia carpeta de aplicación oculta en tu Drive
(`drive.appdata`). No puede ver ni cambiar ningún otro archivo de tu Drive, y
la carpeta no aparece entre tus archivos. Google almacena los datos y cuentan
para tu almacenamiento de Google; Google los cifra en tránsito y en sus
servidores, no de extremo a extremo. El teléfono guarda el id y la dirección de
correo electrónico de tu cuenta de Google para mostrar quién ha iniciado
sesión. En el navegador inicias sesión con el propio botón de Google; el script
de inicio de sesión de Google se carga solo cuando eliges Google, y su token de
acceso solo dura mientras la página está abierta, y como máximo una hora.

**Qué ve Orkitec.** Nada. Orkitec no tiene ningún servidor para la
sincronización y no puede leer, acceder ni eliminar lo que hay en tu iCloud o
en tu Drive; no hay cuenta de Velorki. Apple y Google actúan conforme a tu
propio acuerdo con ellos.

**Eliminar, desactivarla.** Mientras la sincronización está activada, eliminar
una ruta o una salida en un dispositivo la elimina en tu nube y también en tus
otros dispositivos. Elegir **Desactivado**, cerrar sesión o cambiar a la otra
nube detiene la sincronización en ese dispositivo y no elimina nada; al cambiar,
tu biblioteca se envía a la nueva nube y la copia antigua se queda donde
estaba. Lo que ya está en iCloud se queda allí hasta que lo elimines en los
ajustes de iCloud de un dispositivo Apple. Lo que está en Google Drive se queda
hasta que lo elimines: en Google Drive en la web, Configuración → Gestionar
aplicaciones → Velorki → Opciones → Eliminar datos ocultos de la aplicación;
retirar el acceso de Velorki en myaccount.google.com/permissions le impide
llegar a la carpeta.

### Suscripciones

Velorki Plus se vende a través del App Store y Google Play, y RevenueCat la
gestiona en nuestro nombre. RevenueCat asigna a tu instalación un **id de
usuario anónimo de la app**, una cadena aleatoria que no está vinculada a un
nombre, una dirección de correo electrónico ni un identificador del
dispositivo. RevenueCat también recibe de la tienda el recibo de compra.
Nuestro relay envía ese id anónimo a RevenueCat para comprobar si tu
suscripción está activa, y para nada más.

Nunca vemos tus datos de pago; se quedan en Apple o Google.

**Plus en el navegador.** Plus no se puede comprar en el planificador web. Para
usar allí el Plus comprado en una app del teléfono, cada app que se sincroniza
escribe un registro propio en la nube con la que se sincroniza: su id de
usuario de la app de RevenueCat, si es una app de iPhone o de Android, si su
tienda indicó por última vez que Plus está activo y cuándo escribió por última
vez, bajo un id aleatorio para el dispositivo. Lo vuelve a escribir cada seis
horas y cuando Plus empieza o termina. El planificador web, con sesión iniciada
en la misma cuenta de iCloud o de Google, lee estos registros, los guarda en el
navegador y envía a nuestro relay el id del más reciente con cada petición de
Plus, exactamente como lo haría la app. El relay comprueba ese id con
RevenueCat igual que para las apps; el navegador no contacta con RevenueCat, no
crea ningún id propio para Plus y nunca escribe un registro de Plus.

El registro va solo a la cuenta con la que se ejecutó la sincronización por
primera vez, o a una que elijas después en Ajustes → Sincronizar con: tras
cerrar sesión, con otra cuenta o con la sincronización desactivada, la app deja
de escribirlo y nunca lo copia por su cuenta en una segunda cuenta. No se
elimina de la nube; el planificador web ignora un registro que no se ha escrito
en 30 días, y olvida los registros que guardó cuando cierras sesión o cambias
de cuenta o de nube.

### Avisos de actualización y valoraciones

Unos segundos después del inicio, y de nuevo tras un día en segundo plano, la
app pregunta a su tienda si existe una versión más reciente. En iOS pregunta a
la búsqueda pública del App Store de Apple (`itunes.apple.com`) con el bundle id
de Velorki y los códigos de país y de idioma de tu teléfono; en Android pregunta
al servicio de actualización desde la app de Google Play, en el propio
teléfono, que solo responde para una instalación desde Play. En cada caso
interviene tu dirección IP, como en cualquier petición web, y nada más tuyo.

De vez en cuando, la app pide al sistema que muestre su propia hoja de
valoración. Apple o Google deciden si aparece y con qué frecuencia; una
valoración o reseña que des allí va a ellos con tu cuenta de la tienda, y a la
app no se le dice si valoraste ni qué. El planificador web no hace ninguna de
las dos cosas.

### Informes de errores y analítica

No hay ninguno. La app no contiene informes de errores, ni analítica, ni SDK de
publicidad, y no envía estadísticas de uso; cada petición de red que hace es
una de las que se describen arriba. Los cierres inesperados los comunican las
tiendas de apps de forma agregada a la cuenta de desarrollador, sin nada que te
identifique, y solo si lo tienes activado en los ajustes de tu propio teléfono. Si
algún día se añade un sistema de informes de errores, este apartado lo
nombrará y dirá qué recoge antes de que se publique esa versión.

### Registros del servidor

Nuestro relay y nuestro servidor de rutas guardan registros operativos
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
  «Registros del servidor» más arriba: hora, dirección de la página solicitada,
  estado, tamaño, tu dirección IP y el agente de usuario de tu navegador,
  guardados 14 días.
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
  consentimiento según el artículo 25 (2) de la TDDDG alemana.
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

## El planificador web (app.velorki.com)

app.velorki.com es la misma app funcionando en tu navegador: planifica, busca y
guarda una biblioteca, pero no graba ni navega. No hay cuenta, ni analítica, ni
publicidad. En un teléfono o una tableta, la dirección muestra la página de
descarga de la app y no carga nada más.

- **Guardado en tu navegador.** Tus rutas, salidas y ajustes se guardan en una
  base de datos en el almacenamiento propio del navegador (IndexedDB o, en
  algunos navegadores, el Origin Private File System), las teselas de rutas y
  los índices de búsqueda que descargaste en su Cache Storage, y los ajustes,
  la cuenta en la nube con la que iniciaste sesión y un id anónimo como el de
  la app en su almacenamiento local. Se quedan en ese navegador, en ese
  ordenador, hasta que los eliminas en el planificador o borras los datos del
  sitio en el navegador. Este almacenamiento es precisamente la función del
  planificador, así que no requiere consentimiento según el artículo 25 (2) de
  la TDDDG.
- **Con qué contacta.** Con los mismos servicios que la app, con las mismas
  reglas que arriba: teselas del mapa de OpenFreeMap (y de CyclOSM si lo
  activas), Photon para una búsqueda en línea, los servicios meteorológicos
  públicos para las capas del tiempo, y nuestro relay para el asistente de IA,
  el tiempo de Plus y los enlaces compartidos. Nunca usa el servidor de rutas:
  las rutas se calculan en el navegador. Las teselas de rutas llegan a través
  de app.velorki.com. Cuando un texto necesita un sistema de escritura que las
  tipografías propias de la app no tienen, el navegador carga
  una tipografía de reserva de Google Fonts (`fonts.gstatic.com`), que ve tu
  dirección IP. La sincronización en la nube contacta con Apple o con Google,
  solo cuando eliges una.
- **Cloudflare.** El planificador lo sirve Cloudflare Pages. Dos pequeñas
  funciones allí responden a `/tiles/` (obtienen las teselas de nuestro espejo
  en GitHub) y a `/cloudkit/upload` (véase Sincronización en la nube). Como
  cualquier servidor, ven tu dirección IP y la petición; no guardan nada, y no
  conservamos registros de ellas.

## Conservación y eliminación

| Datos | Se conservan | Cómo eliminarlos |
|---|---|---|
| Rutas, salidas, ajustes, datos sin conexión | en tu teléfono, hasta que los eliminas | elimínalos en la app o desinstala la app (con la sincronización activada, eliminar una ruta o una salida la elimina también en tu nube) |
| Tokens de Strava / RideWithGPS | en tu teléfono, cifrados de forma que solo nuestro relay puede abrirlos, hasta que desconectas; nunca se guardan en nuestro lado | desconecta en la app o desinstálala |
| Datos de Strava: tu nombre, enlaces de actividad | en tu teléfono, hasta que desconectas; nunca se guardan en nuestro lado | desconecta Strava en la app o desinstálala; preguntas a ride@velorki.com |
| Rutas importadas de Strava y rutas editadas a partir de ellas | en tu teléfono, solo mientras la ruta siga existiendo en Strava: se comprueba de nuevo cada 48 horas y se elimina si se borró allí o no se pudo comprobar durante 7 días; nunca se guardan en nuestro lado | elimínala en la app, desconecta Strava o desinstala la app |
| La lista en caché de tus rutas de Strava | en tu teléfono, 48 horas como máximo | desconecta Strava o desinstala la app |
| Contadores de límite de frecuencia (id de instalación anónimo, dirección IP) | en nuestro servidor, durante la ventana de recuento, un día como máximo | no aplicable |
| Enlaces compartidos | un año, después se eliminan automáticamente | elimínalos desde la app |
| Rutas, salidas y ajustes sincronizados con iCloud | en tu propio iCloud, hasta que los elimines allí; nunca se guardan en nuestro lado | elimínalos en los ajustes de iCloud de un dispositivo Apple |
| Rutas, salidas y ajustes sincronizados con Google Drive | en la carpeta oculta de Velorki de tu Drive, hasta que la elimines; nunca se guardan en nuestro lado | en Google Drive en la web: Configuración → Gestionar aplicaciones → Velorki → Opciones → Eliminar datos ocultos de la aplicación |
| Registros de Plus (id de RevenueCat, plataforma, Plus activo, última escritura) | en la nube con la que te sincronizas, hasta que elimines allí los datos de la app; el planificador web los ignora a los 30 días | como las rutas sincronizadas de arriba |
| La biblioteca, las teselas y los ajustes del planificador web | en tu navegador, hasta que los eliminas | elimínalos en el planificador o borra los datos del sitio en el navegador |
| Peticiones a la IA | no las guardamos más allá de lo que contienen los registros mencionados | no aplicable |
| Datos de RevenueCat | según la propia política de RevenueCat | contáctanos y transmitiremos la solicitud |
| Conversaciones del chat de soporte | en nuestro canal de Discord hasta que las eliminamos | pídelo en ride@velorki.com |

Desinstalar la app elimina todo lo que la app guardó en el dispositivo. Lo que la
sincronización ha puesto en tu iCloud o en tu Google Drive se queda allí; véase
Sincronización en la nube más arriba. No
elimina los enlaces compartidos que creaste (caducan al cabo de un año, o a
petición), ni nada de lo que subiste a Strava o RideWithGPS.

## Bases jurídicas

Para lectores de la UE y del Reino Unido, las bases jurídicas según el
artículo 6 (1) del RGPD son:

| Qué | Base |
|---|---|
| Servir la web y las páginas compartidas, mantener los servidores en marcha, encontrar fallos, límites de frecuencia, defensa frente a ataques | (f) interés legítimo en ofrecer un servicio que funcione y del que no se abuse |
| Cálculo de rutas en línea y búsqueda en línea, cuando los pides | (b) ejecución del servicio que solicitaste, y (f) para las coordenadas estrictamente necesarias para responder |
| Velorki Plus: comprobar con RevenueCat que una suscripción está activa | (b) ejecución del contrato |
| Velorki Plus: el tiempo más preciso a lo largo de la ruta y el radar de lluvia | (b) ejecución del contrato |
| Strava y RideWithGPS: conectar una cuenta, cada transferencia que inicias y los datos de Strava guardados en tu teléfono | (b) ejecución del servicio que solicitaste, más (a) consentimiento, dado al conectar la cuenta y retirado al desconectarla |
| Enlaces compartidos que creas | (b) ejecución del contrato |
| Sincronización en la nube con iCloud o Google Drive, mientras esté activada, incluidos los registros de Plus y la subida del planificador web a través de `/cloudkit/upload` | (b) ejecución del servicio que solicitaste; Apple y Google actúan conforme a tu propio acuerdo con ellos |
| El planificador web: servirlo, guardar tu biblioteca en tu navegador, obtener las teselas a través de app.velorki.com | (b) ejecución del servicio que solicitaste, y (f) para la dirección IP y la petición estrictamente necesarias para responder |
| Avisos de actualización | (f) interés legítimo en avisarte de una versión más reciente; solo se envían el bundle id, el país y el idioma |
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
  ataques para velorki.com y api.velorki.com, y alojamiento del planificador
  web en app.velorki.com con sus funciones `/tiles/` y `/cloudkit/upload`.
  Direcciones IP y metadatos de las peticiones, y la subida a iCloud que
  transmite sin leerla.
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
- **Servicios meteorológicos públicos** (el Deutscher Wetterdienst, la NOAA, la
  Iowa State University, la NASA, EUMETSAT, el KNMI y el Instituto Meteorológico
  de Finlandia): la parte del mapa o el recuadro alrededor de tu ruta que
  pediste, una hora y tu dirección IP, solo mientras una capa meteorológica o el
  pronóstico gratuito de la ruta están activados.
- **Apple Inc.** (iCloud): las rutas, salidas, ajustes y registros de Plus de
  la sincronización con iCloud, en tu propio iCloud y solo mientras te
  sincronizas con iCloud. No los recibimos; Apple actúa conforme a tu propio
  acuerdo de iCloud con Apple.
- **Google Ireland Ltd**, Dublín (Google LLC, EE. UU., fuera del EEE y de
  Suiza): las rutas, salidas, ajustes y registros de Plus de la sincronización
  con Google, en la carpeta de aplicación oculta de tu propio Drive, y solo
  mientras te sincronizas con Google. No los recibimos; Google actúa conforme a
  tu propio acuerdo con Google. Google también sirve las tipografías de reserva
  del planificador web (`fonts.gstatic.com`) y la comprobación de
  actualizaciones de Google Play en Android.
- **GitHub, Inc.**, San Francisco, EE. UU.: nuestro espejo de teselas, del que
  la app descarga las teselas de rutas y los índices de búsqueda; los nombres
  de las teselas y tu dirección IP.
- **Apple Inc.** y **Google Ireland Ltd**: la venta de Velorki Plus, la
  comprobación de actualizaciones y la hoja de valoración. Ellos son los
  vendedores; nosotros nunca vemos tus datos de pago.
- **Strava, Inc.** y **Ride with GPS**: solo después de que conectes la cuenta
  y solo para una transferencia que inicies tú. Lo que hagan con ello se rige
  por sus propias políticas.

También entregaremos datos a un tribunal o a una autoridad cuando la ley lo
exija.

## Transferencias fuera de la UE

Cloudflare, RevenueCat, OpenRouter y el proveedor del modelo que hay detrás,
Discord, Klipy, Strava, Ride with GPS, GitHub, Apple y Google están en Estados Unidos
o transfieren datos allí. Esas transferencias se basan en las cláusulas
contractuales tipo de la Comisión Europea, o en la certificación del proveedor
conforme al Marco de Privacidad de Datos UE-EE. UU. cuando la tiene, junto con
las propias salvaguardas técnicas del proveedor. Hetzner, komoot y los
servicios de teselas de mapa de los que dependemos están en la UE, y
OpenStreetMap en el Reino Unido. Todo lo que la app guarda para ti se queda en
tu teléfono, o en tu navegador, y no se transfiere a ningún sitio salvo que
actives la sincronización, que va a tu propio iCloud o Google Drive.

## Seguridad

Todas las conexiones con nuestros servidores y con los servicios mencionados
están cifradas con TLS. Los tokens de Strava y RideWithGPS nunca están sin
cifrar en ningún sitio: tu teléfono los guarda en el almacenamiento seguro de la
plataforma, envueltos con una clave que solo tiene el relay, y el relay
desenvuelve uno para la única petición en la que se necesita y no conserva
nada. La base de datos de enlaces compartidos está en el disco del servidor,
fuera del directorio de la versión publicada, y solo la puede leer el usuario
del servicio. En los registros se omiten los datos sensibles: ninguna cabecera
`Authorization`, ningún cuerpo de petición, ningún id de suscriptor. El acceso
al servidor requiere una
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
licitud de lo anterior (artículo 7 (3)). La mayoría de ellos puedes ejercerlos
por tu cuenta, porque los datos están en tu teléfono, en tu navegador o en tu
propia nube, y se pueden exportar como archivos GPX, FIT o TCX cuando quieras.

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

Los cambios de esta política se publican en esta página, con la fecha del
principio cambiada; los importantes también se anuncian en la web. Las
versiones antiguas siguen en el historial de git del repositorio.

## Contacto

Orkitec, ride@velorki.com; dirección postal en el [aviso legal](./imprint).
Para informes de seguridad, consulta
[SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md) en el
repositorio del código fuente.

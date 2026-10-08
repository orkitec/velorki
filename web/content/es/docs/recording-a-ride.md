---
title: Grabar una salida
description: Empieza, pausa y termina una salida, sigue grabando con la pantalla apagada, ahorra batería y recupera una salida después de que se cerrara la app.
order: 8
---

La pestaña Grabar registra tu salida y la guarda en la biblioteca cuando terminas. Sigue grabando con la pantalla apagada y con la app en segundo plano, y aguanta que la app se cierre o se mate.

Grabar es gratis y funciona sin ninguna conexión.

## Empezar, pausar, terminar

1. Abre la pestaña **Grabar**. El panel dice **Listo para rodar**, con un breve consejo debajo.
2. En **Seguir una ruta** elige qué sigue la salida: **Sin ruta**, **La ruta de la pestaña Planificar** (se ofrece mientras haya una) o una de tus rutas guardadas. Una ruta activa la guía descrita en [navegación paso a paso](./navigation). Hasta que elijas, la pestaña propone la ruta de la que vienes: la ruta cuya ficha tenías abierta en la Biblioteca, o el plan de la pestaña Planificar; tu propia elección se mantiene después hasta que se reinicie la app.
3. Toca **Iniciar salida**.
4. Durante la salida, el panel muestra una etiqueta de estado, el cronómetro y las cifras: **Distancia**, **Velocidad**, **Media**, y luego **Subida**, **Bajada**, **En movimiento**. Mientras sigues una ruta se añade una fila **Restante** y **Llegada**: la distancia que aún queda y cuándo llegarás a tu velocidad media hasta ahora, dos guiones hasta que la salida tenga una media.
5. **Pausa** detiene el track donde estás; **Reanudar** continúa. La interrupción se ve como un hueco en el track. En pausa, las cifras se atenúan y la etiqueta pasa a **EN PAUSA**, así el estado se ve de un vistazo.
6. **Terminar** guarda la salida con un nombre por defecto como **Salida 17 sept 2026** y abre su página.

Si terminas sin haber grabado nada, Velorki dice «No se grabó nada.» y no guarda ninguna salida.

### Pausa automática

Velorki se pausa sola tras unos diez segundos sin movimiento; la etiqueta dice entonces **PAUSA AUTOMÁTICA**. A diferencia de una pausa manual, sigue escuchando, y el primer movimiento de verdad la reanuda. Una pausa manual deja de escuchar hasta que pulsas **Reanudar**.

## Frecuencia cardiaca, cadencia y potencia

En cuanto activas un sensor, se añade al panel una tercera fila de cifras con lo que se ha recibido durante esta salida: **Frecuencia cardiaca**, **Cadencia** y **Potencia**, así que un reloj solo añade una casilla. La casilla de frecuencia cardiaca lleva debajo la **Pulso medio** de la salida. Un sensor que se calla a mitad de salida, un reloj fuera de alcance o una banda que se ha movido, conserva su casilla con el último valor atenuado y una marca de enlace roto, para que veas que algo ha dejado de informar; mientras la salida está en pausa el sensor descansa a propósito y no se marca nada. Pueden venir de un sensor Bluetooth, de un Apple Watch o de la app de salud del teléfono, se escriben en el track mientras pedaleas y, en un iPhone, el pulso aparece también en la tarjeta de la pantalla de bloqueo. Mientras un sensor de rueda informa, **Velocidad** muestra su velocidad.

Sin sensor no aparece nada de esto, y no se activa nada hasta que lo haces tú en **Ajustes → Sensores**. Consulta [sensores y tu reloj](./sensors-and-watch).

## El perfil de altitud y la hoja de ruta

El panel bajo el mapa tiene tres páginas, a un deslizamiento una de otra, con tres puntos bajo las cifras que indican cuál está visible. Una salida nueva empieza en las cifras. El panel se desplaza a cualquier altura y se mueve por su asa o su título, o por cualquier parte cuando no hay nada que desplazar, como durante una salida. Antes de una salida, si lo bajas del todo, se pliega en la barra de navegación y deja solo el asa sobre las pestañas, para que el mapa quede libre; arrastra el asa hacia arriba para recuperarlo. Durante una salida las pestañas desaparecen, y el panel se pliega en una barra con la misma forma con las cuatro primeras cifras de la salida, distancia, velocidad, media y subida, y el mapa encima; un punto en ella indica pausa. No tiene botones: tócala o tira de ella hacia arriba para recuperar el panel.

**El perfil de altitud**, deslizando una vez a la izquierda: la ruta seguida como altura sobre distancia, la parte ya recorrida rellena con el color de acento, lo que queda por delante en gris, una línea donde estás y, encima, lo que queda: «Quedan 12,4 km, 320 m de subida». En una subida del 3 % o más, una segunda línea indica la pendiente y lo que queda hasta arriba, «Subida del 6 %, 120 m hasta arriba», y en cuanto la salida tiene velocidad media la misma línea dice cuándo llegarás, «Llegada 14:32». Sin una ruta que seguir, la página lo dice: «Sigue una ruta para ver aquí su perfil de altitud.»

**La hoja de ruta**, un deslizamiento más: **Próximos giros**, los ocho siguientes giros de la ruta en orden con la distancia a cada uno, los puntos de interés de la ruta entre ellos, y **Llegas a tu destino** al final, con «3 más» debajo cuando quedan más. La primera línea es lo que muestra el aviso de giro. Una ruta importada con hoja de ruta muestra las palabras del propio autor para cada giro, «Gira a la izquierda por la calle Mayor», en lugar de la indicación simple.

## Lo que pide la primera vez

La primera salida provoca hasta tres solicitudes, descritas en detalle en [primeros pasos](./getting-started):

- **Ubicación**, con la explicación de Velorki primero.
- **Notificaciones** en Android, porque la grabación vive en una. Si la rechazas, Velorki avisa: «Sin el permiso de notificaciones, Android detiene la grabación cuando sales de la app.»
- **Optimización de batería** en Android, una sola vez: **Abrir ajustes** te lleva a los ajustes de batería, donde eliges Velorki y permites el uso de batería sin restricciones.

## Pantalla apagada, app cerrada

El track se escribe en el teléfono mientras pedaleas, volcándose cada pocos segundos, así que nada depende de que la app siga en primer plano.

- **Android**: la salida se ejecuta en un servicio en primer plano con una notificación permanente titulada **Grabando una salida**, cuya segunda línea lleva tu distancia y tu tiempo, y el siguiente giro cuando sigues una ruta. Al tocarla vuelves a la app.
- **iPhone**: la salida sigue con la pantalla bloqueada, y una actividad en directo muestra las mismas cifras en la pantalla de bloqueo.

**Pantalla siempre encendida** en el panel de Grabar impide que la pantalla se apague mientras una salida corre en la pestaña Grabar, lo que es práctico en un soporte de manillar y caro para la batería. Está activado hasta que lo desactives, y tu elección se mantiene para la próxima salida; **Ajustes → Grabación** tiene el mismo interruptor. La pantalla puede volver a apagarse mientras pausas la salida (no mientras se pausa sola en una parada), cuando cambias a otra pestaña y cuando termina la salida.

## Ahorro de batería

Lo que agota un teléfono en una salida larga es la pantalla, así que **Ahorro de batería** va a por la pantalla. Actívalo en el panel de Grabar o en **Ajustes → Grabación**: «Mapa oscuro, sin animaciones y, tras 30 s, una página sencilla con las cifras; la pantalla es lo que gasta la batería».

Mientras se graba una salida con el ahorro activado, Velorki:

- fuerza el tema oscuro y un mapa negro,
- dibuja un simple punto de posición, sin anillo de precisión ni cono de dirección,
- salta con la cámara en vez de animarla,
- baja el brillo al 40 % mientras **Pantalla siempre encendida** la mantiene despierta,
- y tras **30 segundos sin tocarla** lo sustituye todo por una página de un vistazo: blanco sobre negro, el siguiente giro si lo hay, luego la primera de tus cifras, por defecto **Distancia**, en grande, con la segunda, **Velocidad**, y el **Tiempo** debajo.

Toca en cualquier sitio para recuperar el mapa; la cuenta atrás vuelve a empezar. Todo vuelve a la normalidad cuando termina la salida o se desactiva el ahorro. El ahorro nunca cambia el tema que elegiste para el resto de la app.

**Precisión del GPS** en **Ajustes → Grabación** es la otra mitad: **Ahorro de batería**, **Normal** o **Precisa**, con la indicación «Precisa para senderos; Normal basta para carreteras».

## Si se interrumpe una salida

Velorki escribe el track en un archivo de registro sobre la marcha, así que un fallo, un cierre forzado o un teléfono que se quedó sin batería no pierde la salida.

- Si el servicio de grabación sigue vivo cuando vuelves, la app se abre en la pestaña Grabar, se vuelve a conectar sin decir nada y continúa.
- Si no, la app se abre en la pestaña Grabar y pregunta enseguida, **Salida sin terminar**: «Una salida del 16 sept 2026 nunca se terminó. Se han guardado 42,1 km y 2 h 10 min. ¿La continúas o la terminas ahora?», con tres respuestas:
  - **Reanudar** retoma la salida donde se detuvo,
  - **Terminar** guarda lo que hay y abre la ficha de la salida en la pestaña Biblioteca,
  - **Descartar** la tira.

El diálogo no se puede cerrar sin responder, así que una salida recuperada nunca se pierde sin avisar. Se pregunta una vez por cada inicio de la app; un archivo o una ruta compartida con la que se abrió la app espera a la respuesta y se abre después.

## Continuar una salida terminada

Una salida que ya terminaste se puede continuar: ábrela desde la biblioteca y elige **Continuar esta salida** en el menú de arriba a la derecha. «La grabación se reanuda en esta salida: su track, distancia, tiempo y desnivel siguen donde se quedaron, y el tiempo transcurrido hasta ahora cuenta como pausa.»

Si se está grabando otra salida, primero se termina y se guarda, y si esta ya se subió a Strava o Ride with GPS se te avisa de que la salida continuada habrá que enviarla otra vez.

## Salidas recientes

En **Salidas recientes**, en la pestaña Grabar, están tus cinco últimas, la más nueva primero, cada una con su fecha, distancia y tiempo en movimiento. Desliza una fila a la izquierda para borrarla, con un **Deshacer** en el mensaje que aparece. La lista completa está en la [biblioteca](./library).

## Relacionado

- [Navegación paso a paso](./navigation)
- [Sensores y tu reloj](./sensors-and-watch)
- [Biblioteca](./library)
- [Importar y exportar](./import-and-export)
- [Strava y Ride with GPS](./strava-and-ridewithgps)
- [Ajustes y apariencia](./settings-and-appearance)

---
title: Solución de problemas
description: "Soluciones para los problemas habituales: sin posición, sin ruta, el aviso de teselas que faltan, una voz muda en iOS, descargas atascadas y enlaces que no se abren."
order: 18
---

Lo que falla más a menudo y qué hacer en cada caso. Si tu problema no está aquí, la última sección explica cómo informar de él.

## Velorki no encuentra mi posición

Los síntomas son «Aún no hay posición.», un botón de ubicación que no hace nada o «Activa la ubicación o toca el mapa para fijar el inicio.»

1. **¿Se rechazó el permiso?** Velorki pregunta con su propio diálogo, **¿Mostrar tu posición?**, antes que el del sistema. Si respondiste **Ahora no**, vuelve a tocar el botón de ubicación y responde **Continuar**.
2. **¿Está desactivado para Velorki?** «El permiso de ubicación está desactivado para Velorki. Actívalo en los ajustes del sistema.» viene con una acción **Ajustes** que te lleva directamente allí. Concede «Mientras se usa la app» o «Cuando se use la app».
3. **¿Están desactivados los servicios de ubicación del teléfono?** «Los servicios de ubicación están desactivados en este dispositivo.» va del teléfono, no de Velorki. La acción **Ajustes** abre el sitio adecuado.
4. **¿Dentro de un edificio, o recién encendido?** «Aún no hay posición.» a menudo significa que el teléfono todavía no tiene ninguna posición. Sal al exterior y dale medio minuto.

Velorki nunca necesita la ubicación en segundo plano. «Mientras se usa la app» basta, también para grabar una salida.

## No aparece ninguna ruta

**«Esta ruta necesita teselas de rutas que no están en este dispositivo.»** Tu teléfono no tiene datos de rutas para la zona y no hay ningún servidor de rutas al que recurrir. Toca el botón, que cuenta las teselas y su tamaño, y descárgalas. Consulta [mapas y rutas sin conexión](./offline-maps-and-routing).

**«No hay servidor de rutas configurado; añade uno en Ajustes → Avanzado.»** Esta versión no trae ninguna dirección de servidor. Descarga las teselas de rutas de donde estés y calcula la ruta en el teléfono.

**Ajustes → Avanzado → Cálculo de rutas está en «Solo en el dispositivo».** Entonces Velorki nunca preguntará a un servidor, a propósito. Cámbialo a **Automático** o descarga las teselas.

**«No se pudo calcular la ruta:» con un motivo.** Normalmente no se pudo contactar con el servidor. Vuelve a intentarlo, y comprueba que ningún punto de paso haya caído en el mar o en una autopista por la que no puede ir ninguna bici. Mover el punto problemático unos metros a una carretera de verdad suele arreglarlo.

## El aviso de teselas que faltan no desaparece

El aviso aparece en el planificador siempre que la ruta cruza una zona cuya tesela de rutas no está en el teléfono. Velorki nunca calcula rutas con cobertura parcial, porque el enrutador trataría la tesela que falta como tierra vacía y devolvería sin decir nada una ruta equivocada.

1. Toca el botón del aviso. Abre **Datos de rutas sin conexión** con exactamente las teselas que necesita la ruta ya seleccionadas.
2. Descárgalas. Cada tesela ocupa de 125 a 250 MB, así que usa wifi.
3. Cuando llega una tesela, el planificador vuelve a calcular la ruta solo y el aviso se sustituye por las cifras de la ruta.

Si las teselas que necesitas muestran **La actualización requiere un Velorki más reciente**, actualiza primero la app; el diálogo explica por qué.

## La voz no dice nada

Comprueba en este orden:

1. **Ajustes → Navegación → Indicaciones de giro** activado, y **Voz** activado. Voz aparece en gris mientras Indicaciones de giro está desactivado.
2. **El botón de silencio del aviso de giro.** Silencia la voz solo durante el resto de esa salida. Vuelve a tocarlo.
3. **¿Estás siguiendo una ruta?** La guía necesita una ruta elegida en **Seguir una ruta** en la pestaña Grabar, y una salida que se esté grabando de verdad.
4. **El volumen del propio teléfono y el interruptor de silencio.**

### En un iPhone

Si Velorki muestra **Hay voces mejores para descargar**, el teléfono solo tiene la voz compacta de tu idioma. Sigue los pasos de la tarjeta: **Ajustes → Accesibilidad → Contenido leído → Voces → tu idioma → toca la nube** junto a una voz Mejorada o Premium. Velorki usa entonces sola la mejor voz del teléfono.

Si la voz elegida está marcada como **Necesita internet**, se genera en un servidor: sin cobertura, el giro no se anuncia o llega tarde. Para las salidas, elige una voz sin esa marca. Están ocultas salvo que **Mostrar voces en línea** esté activado al pie de la lista de voces.

«No hay ninguna voz instalada para tu idioma.» significa que el teléfono no tiene con qué hablar; añade una voz en los ajustes de texto a voz o de Contenido leído del propio teléfono.

## Una descarga se atasca o falla

- **Las descargas solo avanzan con la app abierta.** Deja Velorki en primer plano para una tesela grande. Si se detiene, lo que ya llegó se conserva y el siguiente intento continúa desde ahí.
- **«Falló la descarga:»** con un motivo. Vuelve a tocar la tesela para reintentarlo. Una descarga reanudada no empieza desde cero.
- **«No se pudo cargar la lista de teselas:»** significa que no se pudo contactar con el espejo. **Reintentar** está en la pantalla.
- **Comprueba el espacio libre del teléfono.** Una tesela de rutas de 250 MB necesita 250 MB, y la zona de mapa encima.
- **Cancela y vuelve a empezar** con el botón de cerrar de la cabecera de progreso si una descarga se ha quedado claramente parada.
- Velorki no distingue el wifi de los datos móviles, así que avisa en lugar de bloquear. Empieza tú las descargas grandes con wifi.

## Un enlace compartido no se abre en la app

- **El enlace tiene más de un año.** Lo compartido se borra automáticamente a los 365 días, y la página dice entonces que no se encuentra. Pide un enlace nuevo.
- **La app no está instalada en ese teléfono.** La página sigue funcionando en el navegador: el mapa, las cifras y **Descargar GPX**.
- **«Abrir en Velorki» no hizo nada.** Descarga el GPX desde la página y ábrelo con Velorki; llega a la misma pantalla de importación. Un enlace caducado o mal escrito se ignora sin decir nada en lugar de mostrar un error.

## Un archivo no se importa

Velorki lee GPX, FIT y TCX, y decide por el contenido, no por el nombre del archivo.

| Mensaje | Significado |
|---|---|
| «No es un archivo GPX, FIT ni TCX.» | el contenido no es ninguno de los tres formatos, diga lo que diga el nombre |
| «No se pudo leer el archivo.» | el archivo es de uno de los formatos pero está dañado |
| «El archivo no tiene puntos de track.» | un archivo vacío, o un GPX con solo puntos de paso |
| «No se pudo abrir el archivo.» | el sistema no quiso entregar el archivo |

Si un archivo se importa con el tipo equivocado, cambia **GUARDAR COMO** entre **Ruta** y **Salida** en la pantalla de importación antes de guardar. Los recorridos FIT se toman por salidas por cómo funcionan sus marcas de tiempo.

## La grabación se detuvo sola

En Android, responde **Abrir ajustes** a **Seguir grabando en segundo plano**, permite ahí a Velorki el uso de batería sin restricciones y concede el permiso de notificaciones; las dos cosas son lo que impide que el sistema mate la grabación mientras el teléfono está en reposo. En ambas plataformas el track se escribe continuamente, así que si la app se mató te aparece **Salida sin terminar** en el siguiente inicio, con **Reanudar**, **Terminar** y **Descartar**. Consulta [grabar una salida](./recording-a-ride).

## No se encuentra un sensor Bluetooth

1. **Despierta el sensor.** Una banda solo transmite con contacto con la piel, un sensor de cadencia solo con la biela girando. La pantalla lo dice: «Nada por ahora. Despierta el sensor: ponte la banda o gira las bielas.»
2. **Activa el Bluetooth.** «Activa el Bluetooth para encontrar tus sensores.» va de la radio del teléfono, no del sensor.
3. **Concede el permiso.** «Velorki no tiene permiso para usar Bluetooth.» significa que se rechazó. iOS pregunta la primera vez que tocas **Buscar**, y solo entonces.
4. **Libera el sensor.** Estos sensores atienden a un dispositivo a la vez, así que una unidad de manillar u otra app que tenga el tuyo impide que Velorki lo vea.
5. **Vuelve a buscar.** Una búsqueda dura unos quince segundos y solo lista dispositivos que hablan los perfiles estándar de frecuencia cardiaca, velocidad y cadencia, o potencia.

Un sensor emparejado que dice **No conectado** está fuera de alcance, dormido o sin batería. Velorki sigue intentándolo mientras se graba una salida o la pantalla **Sensores Bluetooth** está abierta. Consulta [sensores y tu reloj](./sensors-and-watch).

## El reloj no se conecta

- **No hay interruptor de Apple Watch.** Solo aparece en **Ajustes → Sensores** en un iPhone que tiene un reloj emparejado.
- **La app del reloj no está en el reloj.** Viene dentro de la app del iPhone; si no llegó sola, instala Velorki desde la app **Watch** del iPhone.
- **La salida está en marcha pero el reloj no mide nada.** Una salida empezada en el teléfono abre la app del reloj y la pone a medir sola. Si la app del reloj muestra dos guiones de todas formas, toca **Medir el pulso** en ella; una línea naranja bajo el corazón dice qué ha fallado, si el reloj lo sabe.
- **El reloj no muestra pulso.** El reloj pide permiso para leer tu frecuencia cardiaca la primera vez que empieza un entrenamiento en él. Si se rechazó, concédelo en los ajustes de privacidad del propio reloj.
- **«Iniciar salida» en el reloj no hace nada en el teléfono.** Con Velorki en segundo plano la salida empieza y el teléfono muestra una notificación que hay que tocar. Una app que cerraste deslizándola no la puede despertar el reloj, que es una regla de iOS: el reloj dice "El teléfono no responde", y la solución es abrir Velorki en el teléfono.
- **El track solo empieza cuando abro el teléfono.** iOS no da GPS a una app despertada en segundo plano hasta que se ha abierto una vez. Toca la notificación, o abre Velorki, y el track empieza; después el teléfono puede bloquearse.

## No llega frecuencia cardiaca de Salud

- **El interruptor está desactivado.** **Apple Health**, o **Health Connect** en Android, tiene que estar activado en **Ajustes → Sensores**. No se lee nada mientras está desactivado.
- **Se rechazó el acceso.** «Velorki no tiene acceso a tus datos de salud.» deja el interruptor desactivado. Vuelve a activarlo y permite la frecuencia cardiaca, o concédela en la propia app de salud.
- **Nada ha escrito una frecuencia cardiaca.** Velorki solo lee lo que ya está en el almacén, así que si ni un reloj ni una app ponen allí un pulso, no hay nada que leer.
- **Llega tarde.** Se consulta el almacén cada cinco segundos, o cada treinta con el ahorro de batería activado, y los huecos se rellenan otra vez al guardar la salida. Una banda o un reloj que informan directamente siempre son más rápidos.

## Falta una función de Plus

- **«No disponible en esta versión»** en una fila de conexión, o en la página de la suscripción, significa que esta copia de Velorki se compiló sin las claves de ese servicio o esa tienda. Así se ve una copia compilada por tu cuenta.
- **El botón Preguntar o el botón Compartir enlace no aparecen** en una versión sin servidor de Velorki configurado.
- **Todo lo demás** debería decir «… forma parte de Velorki Plus» y ofrecer la página de la suscripción. Si tienes suscripción y no lo hace, toca **Restaurar compras** en **Ajustes → Suscripción**.

## Informar de un error

**Ajustes → Acerca de → Informar de un problema** abre el gestor de incidencias, o ve directamente a [github.com/orkitec/velorki/issues](https://github.com/orkitec/velorki/issues).

Un buen informe tiene:

1. qué hiciste, paso a paso, y qué pasó en lugar de lo que esperabas;
2. el teléfono y la versión del sistema operativo;
3. la versión de Velorki, de **Ajustes → Acerca de**;
4. dónde pasó, si están implicados el mapa o el cálculo de rutas, porque muchos problemas son propios de un rincón concreto de los datos del mapa;
5. una captura de pantalla, que normalmente vale por todo lo anterior.

Velorki no tiene informes de fallos y no nos envía nada por sí sola, así que un informe tuyo es la única forma de que nos enteremos de un problema.

## Relacionado

- [Mapas y rutas sin conexión](./offline-maps-and-routing)
- [Navegación paso a paso](./navigation)
- [Grabar una salida](./recording-a-ride)
- [Sensores y tu reloj](./sensors-and-watch)
- [Importar y exportar](./import-and-export)
- [Primeros pasos](./getting-started)

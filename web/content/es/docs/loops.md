---
title: Rutas circulares
description: Pide a Velorki una ruta circular de una distancia dada que termine donde empezó, y ve pasando por las propuestas hasta que una te convenza.
order: 3
---

Una ruta circular es una salida que vuelve a donde empezó, y Velorki las genera a partir de una distancia en lugar de a partir de puntos que tocas. Usa el botón **Circular** cuando sepas cuánto quieres pedalear pero no por dónde, y úsalo también para cerrar una ruta que ya has dibujado.

El generador de rutas circulares es un algoritmo sencillo que funciona en tu teléfono. Es gratis, no necesita más servidor que el propio enrutamiento y no interviene ningún modelo.

## Abrirlo

Toca **Circular** en la barra de herramientas del panel de ruta, en la pestaña **Planificar**. El panel se titula **Crear ruta circular**, y lo que ofrece depende de lo que ya tenga el planificador.

## Cerrar una ruta que has dibujado

Si el planificador ya tiene dos o más puntos, el panel ofrece llevar la ruta de vuelta a su inicio.

1. Dice "Vuelve al punto de partida."
2. En **BICI**, elige el perfil. Es el mismo ajuste que los chips del planificador, así que si lo cambias aquí cambia también allí.
3. **Otro camino de vuelta** está activado por defecto, con la nota "Evita las vías por las que ya pasaste." Desactívalo y la vuelta puede repetir el camino de ida.
4. Toca **Cerrar el circuito**. Velorki añade una copia de tu primer punto, calcula el camino de vuelta y muestra el resultado como `48,2 km · 720 m de subida`.
5. **Otra vuelta** mantiene la ida exactamente como está y solo pide una vuelta distinta. Púlsalo tantas veces como quieras; cada pulsación es un paso que se puede deshacer. Está en gris mientras **Otro camino de vuelta** esté desactivado.
6. **Listo** cierra el panel. La ruta circular queda en el mapa del planificador como una ruta normal que puedes editar y guardar.

## Crear una ruta circular desde cero

Si el planificador está vacío, o tiene un solo punto, el panel pide en su lugar una distancia.

1. **Dónde empieza.** Si ya hay un punto en el mapa, ese punto es el inicio. Si no, la línea dice **Desde tu posición**, y Velorki pide la ubicación la primera vez. Si no se puede obtener una posición, usa el centro del mapa y la línea cambia a **Desde el centro del mapa**.
2. **DISTANCIA.** Arrastra el control deslizante. En métrico va de 5 a 200 km en pasos de 5 km, en imperial de 3 a 125 millas en pasos de 1 milla, y la cifra elegida se muestra en grande encima. Se abre con lo que pediste la última vez, 30 km la primera.
3. **BICI.** Los mismos cinco perfiles que el planificador.
4. **Otro camino de vuelta.** Activado significa un círculo de verdad; desactivado significa ir hasta un punto lejano y volver por el mismo camino.
5. Toca **Crear ruta circular**.

## Mientras busca

Velorki lanza la petición en ocho direcciones y calcula cada una en el teléfono, lo que tarda de segundos a un minuto o más, según la distancia y el teléfono. Una barra de progreso avanza a medida que terminan las direcciones, con una línea debajo: "Probando 8 direcciones · 3 comprobadas".

La mejor ruta circular hasta el momento está en el mapa en cuanto hay una, con su resumen, **Otra** y **Listo** junto a la barra, mientras la línea dice que la búsqueda sigue en busca de una ruta más tranquila y suave. Al terminar, la línea dice entre cuántas se eligió la que se ve, "La mejor de 6 rutas circulares". **Detener** termina la búsqueda antes de tiempo y conserva lo encontrado; **Listo** deja la ruta circular a la vista y deja que la búsqueda termine en segundo plano sin sustituirla.

## Elegir entre las propuestas

No te da una lista para leer. Cada propuesta se puntúa según lo cerca que queda de la distancia que pediste, cuánto desnivel tiene por kilómetro, qué parte es sin asfaltar, qué parte va por carriles bici y redes ciclistas, qué parte repite las mismas carreteras y qué parte va por carreteras principales. La mejor pasa directamente al planificador y se dibuja en el mapa, y el panel solo muestra su línea de resumen, `48,2 km · 720 m de subida`.

Para ver la siguiente, toca **Otra**. Eso baja un puesto en la clasificación sin volver a enrutar nada, así que es instantáneo. Cuando se acaba la clasificación, Velorki vuelve a buscar con las ocho direcciones giradas medio paso, para que los nuevos intentos caigan entre los anteriores.

Cada propuesta que miras es una ruta real en el planificador: muévete alrededor, arrastra un punto, mira su perfil de altitud y **Guárdala** cuando una te convenza.

Si el control deslizante o el perfil de bici cambian después de una búsqueda, el resultado queda desfasado y el botón vuelve a **Crear ruta circular**.

## Pedir una ruta circular que pase por un lugar concreto

El panel de rutas circulares no tiene un campo para un lugar por el que pasar, ni preferencias de desnivel o de superficie. Eso viene del [asistente](./assistant): una frase como "una ruta circular con cuestas de 60 km desde aquí pasando por el lago" se convierte en una petición con un punto de paso y preferencias, y el generador de rutas circulares hace el trabajo. El asistente forma parte de Velorki Plus; el panel de rutas circulares en sí es gratis.

## Cuando no encuentra nada

- **"No se encontró ninguna ruta circular aquí; prueba otra distancia."** Algunos lugares, una isla o un valle sin salida, simplemente no tienen red de carreteras para un círculo de esa longitud. Sube o baja bastante la distancia, o empieza en otro sitio.
- **"Activa la ubicación o toca el mapa para fijar el inicio."** No se pudo determinar un punto de inicio. Permite la ubicación o toca antes el mapa.
- **"Buscar una ruta circular tardó demasiado en este teléfono. Prueba una distancia más corta."** La búsqueda se rindió tras 30 minutos.
- **"Falló la búsqueda de ruta circular:"** con un motivo significa que ha fallado el propio enrutamiento. Consulta [solución de problemas](./troubleshooting).

Cerrar el panel cancela una búsqueda en curso, pero conserva lo que ya había encontrado.

## Relacionado

- [Planificar una ruta](./planning-a-route)
- [Asistente](./assistant)
- [Mapas y enrutamiento sin conexión](./offline-maps-and-routing)
- [Biblioteca](./library)

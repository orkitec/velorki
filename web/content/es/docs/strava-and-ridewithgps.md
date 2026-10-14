---
title: Strava y Ride with GPS
description: Velorki funciona con Strava y Ride with GPS, gratis. Conecta una cuenta para subir salidas grabadas e importar rutas, y entiende por qué enviar una ruta a Strava es un archivo.
order: 13
---

Velorki es compatible con Strava y con Ride with GPS: puede subir una salida que grabaste y traer a tu biblioteca las rutas de esas cuentas. Conectar cualquiera de los dos servicios es gratis, con o sin [Velorki Plus](./velorki-plus). Strava y Ride with GPS no han creado, respaldado ni patrocinado Velorki.

No se envía nada a ninguno de los dos servicios hasta que conectas tú la cuenta y luego pides algo.

## Conectar una cuenta

1. Abre **Ajustes** y busca la sección **Conexiones**.
2. Toca **Conectar con Strava** o **Conectar con Ride with GPS**.
3. Se abre en un navegador la propia página de inicio de sesión del servicio. Inicia sesión allí y aprueba el acceso.
4. Vuelves a Velorki, y la fila muestra tu nombre en lugar de **No conectado**.

Velorki pide a Strava solo dos permisos: **read**, tu perfil público (tu id y tu nombre, que se muestran en Ajustes), y **activity:write**, para subir las salidas que elijas subir. No lee tus actividades.

Tu teléfono guarda el token de acceso en su almacenamiento seguro, en una forma que solo el servidor de Velorki puede abrir, y lo deja fuera de las copias de seguridad. A partir de ahí cada subida e importación pasa por ese servidor, que abre el token para esa única petición y la reenvía. No guarda ni el archivo ni el token, ni ningún registro de la llamada, y no puede usar el token por su cuenta.

Si falla un intento de conexión, Velorki dice «No se pudo conectar:» con el motivo. Cancelar la página de inicio de sesión no dice nada.

Una fila que dice **No disponible en esta versión** significa que esta versión de Velorki se compiló sin las claves de ese servicio, que es lo que pasa con una copia compilada por tu cuenta hasta que pongas las tuyas.

## Desconectar

Toca **Desconectar** en la fila conectada y confirma. Desconectar también le pide al servicio que revoque el acceso de Velorki, cuando se puede contactar con el servidor. No elimina nada de tu cuenta de Strava ni de Ride with GPS.

**Strava.** Desconectar elimina del teléfono todos los datos de Strava: el token de acceso, las rutas que importaste de Strava y las rutas que editaste a partir de ellas, la lista de rutas en caché y los enlaces de tus salidas a sus actividades de Strava. Tus salidas en sí se quedan. Después Velorki dice «Tus datos de Strava se han eliminado de este teléfono.»

Si quitas Velorki de tu cuenta de Strava en strava.com, Velorki lo nota en su siguiente llamada a Strava, elimina los mismos datos y te avisa.

**Ride with GPS.** Velorki olvida el token de acceso. Las rutas y salidas que ya están en la biblioteca se quedan.

## Subir una salida

1. Abre la salida en **Biblioteca → Salidas**.
2. Toca el botón de la nube arriba a la derecha, con la etiqueta **Subir**.
3. Elige **Subir a Strava** o **Subir a Ride with GPS**.

Velorki dice «Subiendo a Strava…» y luego «Subida a Strava» con una acción **View on Strava** que la abre. Para eso Velorki guarda el enlace de la actividad con la salida, hasta que desconectes. Una salida que ya está allí nunca se sube dos veces: la entrada del menú pasa a ser **View on Strava** o **Abrir en Ride with GPS**.

Una subida a Strava puede tardar un rato, porque Strava procesa el archivo antes de que exista como actividad; Velorki lo espera y enlaza al resultado.

## Importar rutas

1. Abre la pestaña **Biblioteca**.
2. Toca el botón de la nube arriba a la derecha y elige **Importar de Strava** o **Importar de Ride with GPS**.
3. La lista se titula **Rutas de Strava** o **Rutas de Ride with GPS**. Cada fila muestra el nombre, la distancia, el desnivel y la fecha.
4. Toca **Importar** en la que quieras. Llega a tu biblioteca, y Velorki dice «Vuelta alpina importada». Una ruta importada de Strava se queda en el teléfono: nunca se envía al asistente, ni se pone en un enlace para compartir, ni se envía a Ride with GPS ni a ningún otro servicio, y desconectar Strava la elimina.

Una ruta de Strava, y cualquier ruta que edites a partir de ella, se queda solo mientras siga existiendo en Strava. Mientras Velorki esté abierto, con conexión y conectado, vuelve a comprobar esa ruta en Strava cada 48 horas; tus ediciones se quedan mientras la ruta siga allí. Si se borró en Strava, o no se pudo comprobar durante 7 días (sin conexión, desconectado o con fallos en las comprobaciones), Velorki la elimina y dice «Se eliminó una ruta de Strava: ya no existe en Strava, o no se pudo comprobar durante 7 días.»

El pie dice **Leídas 16 sept 2026**, el momento en que se descargó la lista. Velorki guarda la lista en el teléfono 48 horas como máximo, y **Actualizar** arriba a la derecha la vuelve a descargar.

Si la cuenta no está conectada, la pantalla dice «Primero conecta Strava en Ajustes → Conexiones.»

## Enviar una ruta a Ride with GPS

Abre la ruta, toca **Enviar** y elige **Enviar a Ride with GPS**. Se sube a tu cuenta y Velorki ofrece **Abrir** para verla allí.

## Enviar una ruta a Strava

La API de Strava puede leer rutas pero no crearlas, así que Velorki no tiene adónde subirla. Por eso, elegir **Enviar a Strava** abre una explicación:

> **Strava no puede recibir rutas** La API de Strava puede leer rutas, pero no crearlas. En su lugar, Velorki exporta un archivo GPX: compártelo e impórtalo en strava.com.

Toca **Exportar GPX**, guarda o envía el archivo y súbelo como ruta en strava.com. Ese camino es gratis y no necesita ninguna conexión.

## Todo es gratis

Conectar Strava o Ride with GPS, subir una salida, importar rutas y enviar una ruta a Ride with GPS son gratis, igual que los archivos GPX, FIT y TCX, que hacen lo mismo a mano. Nada de eso necesita Velorki Plus.

## Los datos de Strava se quedan en el teléfono

Los datos de Strava solo se te muestran a ti. Las condiciones de la API de Strava no permiten entregar sus datos a un proveedor de IA ni a otros servicios, así que Velorki nunca envía al asistente una ruta que vino de Strava, nunca la pone en un enlace para compartir y nunca la envía a Ride with GPS ni a ningún otro sitio. **Describir esta ruta**, por ejemplo, no se ofrece para ella.

No guardamos datos de Strava en nuestros servidores: todos están en tu teléfono. Las preguntas o una solicitud de eliminación de datos van a [ride@velorki.com](mailto:ride@velorki.com); consulta la [política de privacidad](/privacy).

## Relacionado

- [Velorki Plus](./velorki-plus)
- [Importar y exportar](./import-and-export)
- [Biblioteca](./library)
- [Asistente](./assistant)
- [Privacidad en el teléfono](./privacy-on-the-phone)

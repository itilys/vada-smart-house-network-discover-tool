# VaDa Network Discover 0.2.2

Actualización centrada en mejorar el descubrimiento de equipos lentos o saturados durante un escaneo o refresco.

Incluye:

- timeout configurable entre 1 y 30 segundos en la App;
- valor inicial de 5 segundos para nuevos escaneos;
- límites visibles de 1 y 30 segundos junto al control;
- la misma política de timeout en la App, `NetworkDiscoveryCore` y la CLI;
- validación de valores fuera de rango en `--timeout`;
- compatibilidad con documentos guardados, normalizando únicamente valores fuera del nuevo rango.

Un timeout mayor puede mejorar la detección de equipos con respuesta lenta, pero también aumenta la duración máxima del escaneo cuando un equipo o puerto no responde.

La build macOS está firmada ad-hoc y no notarizada por Apple.

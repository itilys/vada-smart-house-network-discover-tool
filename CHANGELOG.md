# Changelog

## 0.1.3 - 2026-08-03

- Añade la organización del mapa por tipo de equipo.
- Reutiliza exactamente las categorías de clasificación disponibles en el filtro de equipos.
- Aplica la nueva jerarquía al mapa interactivo y a las exportaciones Mermaid y PNG.
- Actualiza el formato de escaneo guardado conservando la lectura de documentos anteriores.

## 0.1.2 - 2026-08-02

- Añade comprobación automática semanal de nuevas versiones publicadas en GitHub.
- Añade la opción manual `Buscar actualizaciones…` al menú de la app macOS.
- Compara versiones numéricamente y muestra un enlace a la release cuando existe una actualización.
- Mantiene la comprobación sin credenciales, descargas automáticas ni envío de datos del escaneo.
- Lee la versión instalada desde el bundle para mantener sincronizado el panel Acerca de.

## 0.1.1 - 2026-07-02

- Añade clasificación específica para equipos Fronius y Victron a partir de huellas HTTP.
- Añade detección de Airzone en el puerto HTTP 3000.
- Mejora la fiabilidad del escaneo de equipos PLC/Modbus reduciendo la presión TCP por host.
- Actualiza iconos, colores, contador HTTP, apertura web y documentación para las nuevas señales.

## 0.1.0 - 2026-06-11

- Primera publicación open source como VaDa Network Discover.
- App macOS para descubrir equipos, puertos abiertos y dispositivos VaDa SolarBrain / VaDa SolarGenius.
- CLI `netdiscover`.
- Exportación de mapas a Mermaid y PNG.
- Guardado, carga y refresco de escaneos en JSON.
- Build inicial para iPad Simulator.

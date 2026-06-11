# VaDa Network Discover

VaDa Network Discover es una herramienta open source de VaDa SmartHouse para descubrir equipos en redes locales propias o autorizadas, visualizar puertos abiertos y generar un mapa sencillo de la arquitectura de red.

Su objetivo es exclusivamente inventariar y documentar redes locales autorizadas. No incluye explotación de vulnerabilidades, fuerza bruta, evasión, persistencia ni ninguna funcionalidad ofensiva.

## Estado

- Plataforma principal: macOS 14 o superior.
- Variante inicial: iPadOS/iPad Simulator como base portable experimental.
- Licencia: Apache License 2.0.
- Versión actual: 0.1.0.

## Funcionalidad

- Descubrimiento IPv4 por segmento CIDR, rango o comodín.
- Ping ICMP opcional en macOS.
- Escaneo TCP con timeout y concurrencia limitada.
- Catálogo de puertos comunes: SSH, HTTP, HTTPS, Modbus TCP, SMB, RTSP, MQTT, RDP, VNC, impresoras y bases de datos.
- DNS inverso cuando está disponible.
- MAC best-effort por ARP en redes locales.
- Huellas HTTP simples mediante cabecera `Server` y título HTML.
- Clasificación heurística del tipo de equipo.
- Detección específica de VaDa SolarBrain / VaDa SolarGenius por el puerto 8090.
- Listado filtrable por texto, tipo y puerto, con ordenación.
- Mapa visual seleccionable con router marcado, zoom, pan y export Mermaid.
- Exportación del mapa a PNG con marca VaDa SmartHouse.
- Guardado/carga de escaneos en JSON.
- Refresco de escaneo conservando anotaciones, equipos estáticos y reservas DHCP.

## Descargar la app macOS

La app empaquetada se publica como artefacto en GitHub Releases:

```text
VaDa-Network-Discover-macOS.zip
```

La build actual está firmada ad-hoc y no notarizada por Apple. En macOS, si Gatekeeper bloquea la primera apertura, usa clic derecho > Abrir, o compila localmente desde el código fuente.

## Construir en macOS

```bash
scripts/build_app_bundle.sh
open "dist/VaDa Network Discover.app"
```

También puedes instalarla en `~/Applications`:

```bash
scripts/install_macos_app.sh
open "$HOME/Applications/VaDa Network Discover.app"
```

Para desarrollo:

```bash
swift run NetworkDiscoverApp
```

## Usar desde consola

```bash
swift run netdiscover scan 192.168.1.0/24
swift run netdiscover scan 192.168.1.1-40 --ports 22,80,443,502 --json
swift run netdiscover scan 192.168.1.* --map
```

## iPad Simulator

La app compila para iPad Simulator como primera base portable:

```bash
scripts/build_ipad_sim_bundle.sh
```

El bundle queda en:

```bash
dist-ios-sim/VaDa Network Discover iPad.app
```

En iPad el descubrimiento inicial usa TCP/HTTP. Ping ICMP, ARP/MAC, abrir/guardar JSON con panel nativo y la UX táctil completa quedan como trabajo específico de iPadOS.

## Verificar

```bash
swift test
scripts/build_app_bundle.sh
```

## Uso responsable

Ejecuta VaDa Network Discover solo en redes de tu propiedad o donde tengas autorización explícita. Los resultados dependen de permisos locales, firewalls, tiempos de respuesta y políticas de cada dispositivo.

Este proyecto no sustituye una auditoría profesional de seguridad ni una herramienta de monitorización permanente. Es una utilidad de descubrimiento e inventario para VaDa SmartHouse y para instalaciones donde se quiera documentar la red.

## Contribuir

Las contribuciones son bienvenidas cuando respeten el alcance del proyecto: descubrimiento de red autorizado, documentación, mejoras de UX, compatibilidad macOS/iPadOS, rendimiento y calidad de datos. Consulta [CONTRIBUTING.md](CONTRIBUTING.md).

## Licencia y marca

El código se distribuye bajo Apache License 2.0. Consulta [LICENSE](LICENSE).

`VaDa SmartHouse`, `VaDa Network Discover`, `VaDa SolarBrain` y `VaDa SolarGenius` son nombres y marcas de VaDa SmartHouse. La licencia del código no concede permisos de marca más allá del uso razonable para describir el origen del proyecto.

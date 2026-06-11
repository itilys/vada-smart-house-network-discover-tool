# Contributing to VaDa Network Discover

Gracias por ayudar a mejorar VaDa Network Discover.

## Alcance del proyecto

Este repositorio acepta cambios orientados a:

- descubrir e inventariar equipos en redes locales autorizadas;
- mejorar la app macOS;
- avanzar la base inicial de iPadOS;
- mejorar exportaciones, mapas, persistencia y documentación;
- mejorar tests, rendimiento y fiabilidad.

No se aceptarán cambios que añadan explotación de vulnerabilidades, fuerza bruta, evasión, persistencia, abuso de credenciales o funcionalidades ofensivas.

## Desarrollo local

```bash
swift test
swift run NetworkDiscoverApp
scripts/build_app_bundle.sh
```

## Pull requests

- Describe el problema y la solución.
- Incluye tests cuando cambie lógica de red, parsing, modelos o persistencia.
- Mantén el estilo Swift existente.
- Evita subir artefactos generados como `.build/`, `dist/` o bundles `.app`.
- Respeta la licencia Apache 2.0 y conserva avisos de marca de VaDa SmartHouse.

## Seguridad

Si encuentras un comportamiento con impacto de seguridad, revisa [SECURITY.md](SECURITY.md) antes de abrir un issue público.

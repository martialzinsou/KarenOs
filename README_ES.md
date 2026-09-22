# KarenOS

<p align="center">
  <img src="docs/branding/karenos-logo.svg" alt="KarenOS — Aplicación nativa macOS de IA generativa 100% local" width="220"/>
</p>

<!--
    SEO — KarenOS · Referencia del proyecto: https://github.com/martialzinsou/KarenOs
    Canonical: https://github.com/martialzinsou/KarenOs
    Autor: Martial Zinsou
    Función: Director de Sistemas de Información (DSI / IT Director)
    Título: KarenOS — Aplicación nativa macOS de IA generativa 100% local
    Descripción: KarenOS es una aplicación nativa de macOS que permite descargar modelos GGUF desde Hugging Face y chatear con ellos de forma totalmente local. Chat en streaming vía llama.cpp, agentes autónomos, multimodal (imágenes, vídeo, audio, dictado de voz), habilidades reutilizables. Ningún dato sale de la máquina. Ideal para DSI, Directores de TI, gobernanza IT, infraestructura IA soberana.
    Palabras clave: karenos, IA local, IA offline, macos, swift, swiftui, llama.cpp, gguf, hugging face, agentes IA autónomos, multimodal, chatbot local, martial zinsou, dsi, director informático, it director, gobernanza it, transformación digital, infraestructura IA, IA soberana, llm local, IA generativa local
    Idioma: es
    robots: index, follow
    og:title: KarenOS — Aplicación nativa macOS de IA generativa 100% local
    og:description: Descarga modelos GGUF desde Hugging Face y chatea con ellos de forma totalmente local. Agentes autónomos, multimodal, habilidades, cero datos salientes.
    og:type: website
    og:url: https://github.com/martialzinsou/KarenOs
    og:image: https://raw.githubusercontent.com/martialzinsou/KarenOs/main/docs/branding/karenos-logo.png
    twitter:card: summary_large_image
    twitter:title: KarenOS — IA local macOS
    twitter:description: Aplicación nativa macOS de IA generativa 100% local con agentes autónomos y multimodal.
-->

<!-- JSON-LD Estructurado para SoftwareApplication -->
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  "name": "KarenOS",
  "applicationCategory": "DeveloperApplication",
  "operatingSystem": "macOS 13+",
  "offers": {
    "@type": "Offer",
    "price": "0",
    "priceCurrency": "EUR",
    "availability": "https://schema.org/InStock"
  },
  "author": {
    "@type": "Person",
    "name": "Martial Zinsou",
    "url": "https://github.com/martialzinsou"
  },
  "description": "Aplicación nativa macOS de IA generativa 100% local: descarga de modelos GGUF, chat streaming, agentes autónomos, multimodal, habilidades.",
  "keywords": "karenos, IA local, macos, swift, swiftui, llama.cpp, gguf, agentes IA, multimodal, dsi",
  "license": "https://opensource.org/licenses/MIT",
  "url": "https://github.com/martialzinsou/KarenOs",
  "downloadUrl": "https://github.com/martialzinsou/KarenOs/releases/tag/v1.0.0",
  "version": "1.0.0",
  "datePublished": "2026-09-21",
  "publisher": {
    "@type": "Person",
    "name": "Martial Zinsou"
  }
}
</script>

Aplicación nativa macOS para usar modelos de IA **localmente**: descargar modelos GGUF desde Hugging Face y chatear con ellos, todo en su máquina.

**Autor: Martial Zinsou**

## Capturas de pantalla

![Mis modelos — biblioteca y chat local](screenshots/1_modelles.png)

*Mis modelos: biblioteca y chat local.*

![Tienda de modelos — descarga de modelos GGUF desde Hugging Face](screenshots/2_boutique.png)

*Tienda de modelos: navegación e instalación de modelos GGUF desde Hugging Face.*

![Competencias — rol, contexto y obligaciones de resultados](screenshots/3_competencias.png)

*Habilidades: instrucciones reutilizables con cualquier modelo.*

![Agentes — misiones autónomas, desencadenante, bucle y condiciones de finalización](screenshots/4_agents.png)

*Agentes: misiones autónomas sobre un modelo elegido, con desencadenante (manual, al lanzamiento, cada X segundos), bucle infinito y condiciones de finalización (número de iteraciones, duración, palabra clave de éxito). El modelo se carga automáticamente y el anterior se restaura.*

## Características

- **Tienda**: modelos GGUF seleccionados (Qwen 0.5B a 3B, SmolLM, Phi-3…) + búsqueda en Hugging Face con indicador de tamaño, licencia y contexto.
- **Mis modelos**: modelos instalados, carga, discusión en streaming (respuesta token por token).
- **Agentes**: misiones autónomas — describa la misión, elija el modelo, el **desencadenante** (manual, al lanzamiento, cada X segundos), el **bucle infinito** y las **condiciones de finalización** (número de iteraciones, duración, palabra clave de éxito). El modelo se carga automáticamente y el anterior se restaura.
- **Multimodal**: adjunte **imágenes, vídeos, archivos de audio** a sus mensajes y **dcte su voz** (reconocimiento de voz local). En presencia de un modelo de visión (`*.mmproj`), las imágenes se analizan realmente por el modelo.
- **Habilidades**: instrucciones estructuradas (rol, contexto, obligaciones de resultados) aplicadas automáticamente independientemente del modelo.
- **Motor local**: usa `llama-server` (llama.cpp) descargado automáticamente yembarcado en la app. Ningún dato sale del computador.

📘 **Documentación completa** — arquitectura, esquemas de inferencia, flujo de habilidades, resolución de problemas: [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md) → &nbsp; **🇫🇷 Francés (FR) :** [DOCUMENTATION.md](docs/DOCUMENTATION.md) →

## Pre-requisitos

- macOS 13 o versión posterior
- Herramientas de línea de comandos (`xcode-select --install`). Xcode no es obligatorio.

## Compilar y lanzar

```bash
Scripts/make-app.sh          # compila + ensambla build/KarenOS.app
Scripts/make-app.sh --run    # compila y abre la app
Scripts/make-icon.sh         # (re)genera la hermosa icónica Packaging/KarenOS.icns
```

## Uso

1. Abrir **Tienda** → elegir un modelo (los modelos pequeños están en la parte superior de la lista) → **Instalar**.
2. Ir a **Mis modelos** → hacer clic en el modelo → la carga del chat se realiza automáticamente.
3. Escriba un mensaje y charla. Todo es local (contexto de 2048 tokens, respuesta limitada por defecto a 512 tokens, modificable en el código).

En el primer lanzamiento, la app descarga el motor de inferencia (~8 Mo) y lo instala en `~/Library/Application Support/KarenOS/`.

## Detalles técnicos

- 100% Swift / SwiftUI, ninguna dependencia externa.
- API Hugging Face (búsqueda, detalles, descarga con progreso).
- `llama-server` (llama.cpp) lanzado como subprocess, interfaz HTTP tipo OpenAI (`/v1/chat/completions`), flujo SSE.
- Compilación directa con `swiftc` (no se requiere Xcode).

## Notas

- En Mac Intel, la inferencia se ejecuta en CPU (`Accelerate`). En Apple Silicon, mismas funciones, GPU Metal via arm64.
- Los modelos van directamente a `~/Library/Application Support/KarenOS/Models/`.
- La sección **About** contiene una descripción y etiquetas, y todos los archivos `.md` se muestran correctamente en la página principal del repositorio.
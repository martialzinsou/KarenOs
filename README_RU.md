# KarenOS

<p align="center">
  <img src="docs/branding/karenos-logo.svg" alt="KarenOS — Приложение native macOS для IA generativa 100% local" width="220"/>
</p>

<!--
    SEO — KarenOS · Ссылка на проект: https://github.com/martialzinsou/KarenOs
    Canonical: https://github.com/martialzinsou/KarenOs
    Автор: Martial Zinsou
    Функция: Директор по информационным системам (DSI / IT Director)
    Тип: KarenOS — Приложение native macOS для IA generativa 100% local
    Описание: KarenOS — это нативное приложение macOS, позволяющее скачивать модели GGUF из Hugging Face и общаться с ними полностью локально. Стриминговый чат через llama.cpp, автономные агенты, multimodal (изображения, видео, аудио, голосовой ввод), навыки reutilizables. Никакие данные не покидают машину. Идеально для DSI, Directors of IT, IT-правление, sovereign infrastructure.
    Ключевые слова: karenos, локальный ИИ, offline ИИ, macos, swift, swiftui, llama.cpp, gguf, hugging face, автономные агенты IA, multimodal, локальный chatbot, martial zinsou, dsi, директор информационных систем, it director, управление IT, цифровая трансформация, sovereign infrastructure, local llm, generative ai local
    Язык: ru
    robots: index, follow
    og:title: KarenOS — Приложение native macOS для IA generativa 100% local
    og:description: Скачайте модели GGUF из Hugging Face и общайтесь с ними полностью локально. Автономные агенты, multimodal, навыки, нулевые исходящие данные.
    og:type: website
    og:url: https://github.com/martialzinsou/KarenOs
    og:image: https://raw.githubusercontent.com/martialzinsou/KarenOs/main/docs/branding/karenos-logo.png
    twitter:card: summary_large_image
    twitter:title: KarenOS — локальный AI macOS
    twitter:description: Нативное приложение macOS для IA generativa 100% local с автономными агентами и multimodal.
-->

<!-- JSON-LD Структурированные данные для SoftwareApplication -->
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
  "description": "Нативное приложение macOS для IA generativa 100% local: загрузка моделей GGUF, streaming чат, автономные агенты, multimodal, навыки.",
  "keywords": "karenos, local ai, macos, swift, swiftui, llama.cpp, gguf, agents IA, multimodal, dsi",
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

Нативное приложение macOS для использования IA **локально**: загрузка моделей GGUF из Hugging Face и общение с ними entirely локально.

**Автор: Martial Zinsou**

## Скриншоты

![Мой models — библиотека и локальный чат](screenshots/1_modelles.png)

*Мой models: библиотека и локальный чат.*

![Tienda de modelos — descarga de modelos GGUF desde Hugging Face](screenshots/2_boutique.png)

*Tienda de modelos: навигация e instalación de modelos GGUF desde Hugging Face.*

![Навыки — роль, contexto y obligaciones de resultados](screenshots/3_competencias.png)

*Навыки: reusable instructions with any model.*

![Agentes — misiones autónomas, desencadenante, bucle y condiciones de finalización](screenshots/4_agents.png)

*Agentes: автономные missions sobre un modelo elegido, con desencadenante (manual, al lanzamiento, cada X segundos), bucle infinito y condiciones de finalización (número de iteraciones, duración, palabra clave de éxito). El modelo se carga automáticamente y el anterior se restaura.*

## Características

- **Tienda**: modelos GGUF seleccionados (Qwen 0.5B a 3B, SmolLM, Phi-3…) + búsqueda en Hugging Face con indicador de tamaño, licencia y contexto.
- **Mis models**: modelos instalados, carga, discusión en streaming (respuesta token por token).
- **Agentes**: misiones autónomas sobre un modelo elegido, con desencadenante (manual, al lanzamiento, cada X segundos), bucle infinito y condiciones de finalización (número de iteraciones, duración, palabra clave de éxito). El modelo se carga automáticamente y el anterior se restaura.
- **Multimodal**: adjunte **imágenes, vídeos, archivos de audio** a sus mensajes y **dcte su voz** (reconocimiento de voz local). En presencia de un modelo de visión (`*.mmproj`), las imágenes se analizan realmente por el modelo.
- **Habilidades**: instrucciones estructuradas (rol, contexto, obligaciones de resultados) aplicadas automáticamente independientemente del modelo.
- **Motor local**: usa `llama-server` (llama.cpp) descargado automáticamente yembarcado en la app. Ningún dato sale del computador.

📘 **Documentación completa** — arquitectura, esquemas de inferencia, flujo de habilidades, resolución de problemas: [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md) → &nbsp; **🇫🇷 Francés (FR) :** [DOCUMENTATION.md](docs/DOCUMENTATION.md) →

## Предварительные требования

- macOS 13 или версия posterior
- Инструменты командной строки (`xcode-select --install`). Xcode no es obligatorio.

## Compilar y lanzar

```bash
Scripts/make-app.sh          # compila + ensambla build/KarenOS.app
Scripts/make-app.sh --run    # compila y abre la app
Scripts/make-icon.sh         # (re)genera la hermosa icónica Packaging/KarenOS.icns
```

## Использование

1. Abrir **Tienda** → elegir un modelo (los modelos pequeños están en la parte superior de la lista) → **Instalar**.
2. Ir a **Mis models** → hacer clic en el modelo → la carga del chat se realiza automáticamente.
3. Напишите сообщение и общайтесь. Todo is local (контекст 2048 tokens, respuesta limitada por defecto a 512 tokens, modificable en el código).

На первом запуске, la app descarga el motor de inferencia (~8 Mo) и lo instala en `~/Library/Application Support/KarenOS/`.

## Технические детали

- 100% Swift / SwiftUI, ninguna dependencia externa.
- API Hugging Face (búsqueda, detalles, descarga con progreso).
- `llama-server` (llama.cpp) lanzado как subprocess, interfaz HTTP tipo OpenAI (`/v1/chat/completions`), SSE streaming.
- Compilación directa con `swiftc` (no se requiere Xcode).

## Примечания

- На Mac Intel, la inferencia se ejecuta en CPU (`Accelerate`). En Apple Silicon, mismas funciones, GPU Metal via arm64.
- Los modelos van directamente a `~/Library/Application Support/KarenOS/Models/`.
- La sección **About** contiene una descripción y etiquetas, y todos los archivos `.md` se muestran correctamente на la página principal del repositorio.
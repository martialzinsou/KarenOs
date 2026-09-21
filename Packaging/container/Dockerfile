# KarenOS — moteur llama.cpp pour serveurs
#
# Image conteneur du moteur d'inférence de KarenOS : seul composant portable
# (Linux x86_64, AVX2), destiné aux serveurs d'IA locaux des DSI.
# Les modèles GGUF sont montés en volume au lancement.
#
# Build :
#   docker build -f Packaging/container/Dockerfile -t karenos-llama-server .
FROM debian:bookworm-slim AS runtime
LABEL org.opencontainers.image.title="KarenOS llama-server"
LABEL org.opencontainers.image.description="Moteur d'inference I.A. local de KarenOS (llama.cpp) — infrastructure DSI"
LABEL org.opencontainers.image.vendor="Martial Zinsou"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.source="https://github.com/martialzinsou/KarenOs"

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# llama.cpp, même révision que le moteur macOS de KarenOS
FROM debian:bookworm AS build
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates cmake build-essential \
    && rm -rf /var/lib/apt/lists/*
ARG LLAMA_COMMIT=a3e5b96ac5e278c390df429df0b68efcee3ee1b5
WORKDIR /src
RUN git clone --depth 1 https://github.com/ggml-org/llama.cpp.git . \
    && git fetch --depth 1 origin ${LLAMA_COMMIT} \
    && git checkout FETCH_HEAD
RUN cmake -B build -DCMAKE_BUILD_TYPE=Release -DLLAMA_CURL=OFF \
    && cmake --build build --target llama-server -j"$(nproc)"

FROM runtime
COPY --from=build /src/build/bin/ /usr/local/bin/
ENV LD_LIBRARY_PATH=/usr/local/bin
ENV GGML_N_CTX=2048
EXPOSE 8080
ENTRYPOINT ["llama-server"]
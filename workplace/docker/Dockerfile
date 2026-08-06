FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git pkg-config libsdl2-dev libfreetype6-dev \
    zlib1g-dev libpng-dev libvorbis-dev libmad0-dev libflac-dev libmpeg2-4-dev \
    xvfb x11-utils xdotool imagemagick ffmpeg poppler-utils \
    python3 python3-pil fonts-wqy-microhei fonts-noto-cjk \
    zstd zip unzip curl file nasm && rm -rf /var/lib/apt/lists/*

FROM node:22-bookworm-slim

# Instala ffmpeg, python3, curl e certificados no Debian 12 Bookworm (versão estável oficial)
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing \
    ffmpeg \
    python3 \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Instala o binário mais recente do yt-dlp diretamente no sistema
RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp && \
    chmod a+rx /usr/local/bin/yt-dlp

WORKDIR /app

# Copia dependências e instala
COPY package*.json ./
RUN npm install --omit=dev

# Copia código-fonte
COPY . .

# Cria pastas para binários e arquivos temporários
RUN mkdir -p /app/bin /app/temp

EXPOSE 3000

ENV PORT=3000
ENV NODE_ENV=production

CMD ["npm", "start"]

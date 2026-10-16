FROM node:20-bullseye-slim

# Instala ffmpeg e python3 (necessários para o yt-dlp converter áudio em MP3)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    python3 \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

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

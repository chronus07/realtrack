FROM node:22-bookworm-slim

# Instala ffmpeg, python3, python3-pip, curl, unzip e certificados no Debian 12 Bookworm
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing \
    ffmpeg \
    python3 \
    python3-pip \
    ca-certificates \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Instala a versão oficial completa do yt-dlp com dependências de JS e EJS
RUN pip3 install --no-cache-dir --break-system-packages -U "yt-dlp[default]"

# Instala Deno para resolver desafios de assinatura e EJS do YouTube automaticamente
RUN curl -fsSL https://deno.land/install.sh | sh && \
    cp /root/.deno/bin/deno /usr/local/bin/deno

# Configura yt-dlp globalmente para habilitar runtimes JS
RUN mkdir -p /etc && printf -- "--js-runtimes deno,node\n" > /etc/yt-dlp.conf

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

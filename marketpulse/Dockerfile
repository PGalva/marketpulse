# Imagem oficial do Ruby, versão "slim" (menor, sem ferramentas extras)
FROM ruby:3.3-slim

# Pasta de trabalho dentro do container
WORKDIR /app

# Rodar como usuário comum, não como root (boa prática de segurança)
RUN useradd --create-home app
USER app

# Copia o código do projeto para dentro da imagem
COPY --chown=app:app . .

# Comando padrão quando o container sobe
CMD ["ruby", "bin/chat"]

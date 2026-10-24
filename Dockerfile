FROM ruby:3.3-slim

# libpq-dev e build-essential compilam a gem pg (driver do PostgreSQL).
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential libpq-dev \
 && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8
WORKDIR /app

# Gemfile primeiro: enquanto ele não mudar, o Docker reaproveita esta
# camada em cache e não reinstala as gems a cada build.
COPY Gemfile ./
RUN bundle install --jobs 4

RUN useradd --create-home app
COPY --chown=app:app . .
USER app

CMD ["ruby", "bin/chat"]

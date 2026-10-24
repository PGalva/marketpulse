# frozen_string_literal: true

source "https://rubygems.org"

ruby ">= 3.2"

# Só entram quando há banco (DATABASE_URL). Sem banco, o projeto roda com a
# stdlib pura (ADR-001: dependências entram quando doem).
gem "pg", "~> 1.5"
gem "sequel", "~> 5.80"

gem "csv" # sai da stdlib padrão no Ruby 3.4
gem "minitest", "~> 5.20"
gem "rake", "~> 13.0"

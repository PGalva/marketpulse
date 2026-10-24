# frozen_string_literal: true

require_relative "../test_helper"

MD = MarketPulse::MarketData

class FakeClientTest < Minitest::Test
  def client = MD::FakeClient.new(today: Date.new(2026, 10, 23), days: 300)

  def test_historico_e_deterministico_e_so_tem_dias_uteis
    a = client.history("AAPL")
    b = client.history("AAPL")

    assert_equal a, b
    assert_equal 300, a.size
    assert a.none? { |bar| bar.date.saturday? || bar.date.sunday? }
  end

  def test_cotacao_traz_fonte_e_horario
    quote = client.quote("PETR4")
    assert_equal "BRL", quote[:currency]
    assert_equal "fake", quote[:source]
    assert quote[:fetched_at]
  end

  def test_ticker_desconhecido
    assert_raises(MD::TickerNotFound) { client.quote("XPTO") }
  end
end

class StooqClientTest < Minitest::Test
  def csv = File.read(File.join(TestHelpers::FIXTURES, "stooq_aapl.csv"))

  def test_le_o_csv_sem_rede
    stooq = MD::StooqClient.new(fetcher: ->(_symbol) { csv })
    bars = stooq.history("AAPL")

    assert_equal 3, bars.size
    assert_equal Date.new(2026, 10, 21), bars.last.date
    assert_in_delta(-1.77, stooq.quote("AAPL")[:change_pct], 0.01)
  end

  def test_usa_o_sufixo_do_mercado
    seen = nil
    MD::StooqClient.new(fetcher: ->(symbol) { seen = symbol; csv }).history("AAPL")
    assert_equal "aapl.us", seen
  end

  def test_csv_vazio_vira_ticker_nao_encontrado
    assert_raises(MD::TickerNotFound) { MD::StooqClient.new(fetcher: ->(_) { "No data" }).history("ZZZ") }
  end
end

# Contrato compartilhado pelos repositórios de preço. O teste do Postgres
# inclui este mesmo módulo, então as duas implementações provam o mesmo
# comportamento.
module PriceRepositoryContract
  def bar(date, close) = MD::Bar.new(ticker: "AAPL", date: date, open: close, high: close, low: close, close: close, volume: 1)

  def test_salvar_duas_vezes_nao_duplica
    repo.save_bars([bar(Date.new(2026, 1, 2), 10.0)])
    repo.save_bars([bar(Date.new(2026, 1, 2), 11.0)])

    assert_equal [11.0], repo.history("AAPL").map(&:close)
  end

  def test_historico_ordenado_com_limite_e_proximo_pregao
    repo.save_bars([bar(Date.new(2026, 1, 5), 3.0), bar(Date.new(2026, 1, 2), 1.0), bar(Date.new(2026, 1, 3), 2.0)])

    assert_equal [2.0, 3.0], repo.history("AAPL", limit: 2).map(&:close)
    assert_equal Date.new(2026, 1, 5), repo.bar_after("AAPL", Date.new(2026, 1, 3)).date
    assert_nil repo.bar_after("AAPL", Date.new(2026, 1, 5))
  end
end

class MemoryPriceRepositoryTest < Minitest::Test
  include PriceRepositoryContract

  def repo = @repo ||= MD::Repositories::MemoryPriceRepository.new
end

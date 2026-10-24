# frozen_string_literal: true

require_relative "../test_helper"

FC = MarketPulse::Forecasting

class OneWeightModelTest < Minitest::Test
  def test_formula_de_minimos_quadrados_em_um_caso_feito_a_mao
    # pares (hoje, amanhã): (1,-0.5) (-0.5,0.25) ... sempre amanhã = -0.5 × hoje
    returns = [1.0]
    20.times { returns << returns.last * -0.5 }
    model = FC::Models::OneWeight.new.fit(returns)

    assert_in_delta(-0.5, model.weight, 1e-9)
    assert_in_delta 0.1, model.predict(-0.2), 1e-9
  end

  def test_redescobre_a_personalidade_de_cada_ticker_simulado
    client = MarketPulse::MarketData::FakeClient.new(today: Date.new(2026, 10, 23), days: 500)
    fit = ->(t) { FC::Models::OneWeight.new.fit(FC::Features.returns(client.history(t).map(&:close))) }

    assert_equal "momentum", fit.("AAPL").pattern
    assert_equal "reversão à média", fit.("PETR4").pattern
    assert_match(/sem padrão/, fit.("MSFT").pattern)
  end

  def test_recusa_treinar_com_poucos_dados
    assert_raises(FC::Error) { FC::Models::OneWeight.new.fit([0.01, 0.02]) }
  end
end

class BacktestTest < Minitest::Test
  def test_modelo_perfeito_bate_o_baseline_e_acerta_a_direcao
    returns = [0.01]
    120.times { |i| returns << (returns.last * -0.5) + (i.even? ? 0.0 : 0.0) }
    returns.map!.with_index { |r, i| r.zero? ? 0.001 * ((-1)**i) : r }
    result = FC::Backtest.walk_forward(returns, model_factory: -> { FC::Models::OneWeight.new }, min_train: 30)

    assert result.beats_baseline
    assert_operator result.hit_rate, :>, 0.9
    assert_equal returns.size - 1 - 30, result.n_tests
  end

  def test_nunca_usa_o_futuro_no_treino
    seen = []
    spy = Class.new do
      define_method(:initialize) { |log| @log = log }
      define_method(:fit) { |train| @log << train.size; self }
      define_method(:predict) { |_| 0.0 }
    end
    returns = Array.new(50) { |i| i * 0.001 }
    FC::Backtest.walk_forward(returns, model_factory: -> { spy.new(seen) }, min_train: 10)

    # No passo i, o treino tem exatamente i+1 retornos: nada depois de i.
    assert_equal (10...49).map { |i| i + 1 }, seen
  end
end

class DailyJobTest < Minitest::Test
  def setup
    @prices = MarketPulse::MarketData::Repositories::MemoryPriceRepository.new
    @forecasts = FC::Repositories::MemoryForecastRepository.new
  end

  def job_on(day)
    client = MarketPulse::MarketData::FakeClient.new(today: day, days: 300)
    FC::DailyJob.new(client: client, prices: @prices, forecasts: @forecasts, tickers: %w[AAPL XPTO], logger: nil)
  end

  def test_gera_previsao_e_isola_ticker_com_erro
    results = job_on(Date.new(2026, 10, 21)).run

    assert_nil results["XPTO"], "ticker inexistente não derruba o job"
    forecast = @forecasts.latest("AAPL")
    assert_equal Date.new(2026, 10, 21), forecast.as_of
    assert_operator forecast.low, :<, forecast.high
    assert_includes forecast.low..forecast.high, forecast.predicted_close
  end

  def test_e_idempotente
    2.times { job_on(Date.new(2026, 10, 21)).run }
    assert_equal 1, @forecasts.pending_evaluation("AAPL").size
  end

  def test_no_dia_seguinte_avalia_a_previsao_de_ontem
    job_on(Date.new(2026, 10, 21)).run
    job_on(Date.new(2026, 10, 22)).run

    evaluated = @forecasts.evaluated("AAPL")
    assert_equal 1, evaluated.size
    assert_equal @prices.history("AAPL").last.close, evaluated.first.actual_close
    refute_nil evaluated.first.direction_hit?
    assert_equal Date.new(2026, 10, 22), @forecasts.latest("AAPL").as_of
  end
end

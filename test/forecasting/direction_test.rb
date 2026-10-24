# frozen_string_literal: true

require_relative "../test_helper"

# Previsão de direção (ADR-005).
DIR = MarketPulse::Forecasting

class HorizonFeaturesTest < Minitest::Test
  def test_calcula_razao_e_tendencia_num_caso_feito_a_mao
    closes = [10.0, 11.0, 10.0, 12.0, 12.0]
    rows = DIR::Features.horizon_rows(closes, horizons: [2])

    # linha do índice 2: média(11, 10) = 10,5; dias 1 e 2: subiu, caiu
    first = rows.first
    assert_equal 2, first.index
    assert_in_delta (10.0 / 10.5) - 1, first.values[0], 1e-12
    assert_in_delta 0.5, first.values[1], 1e-12
    assert_equal true, first.up # 12 > 10

    assert_equal [2, 3, 4], rows.map(&:index)
    assert_nil rows.last.up, "a linha de hoje ainda não tem alvo"
    assert_equal %w[ratio_2 trend_2], DIR::Features.feature_names(horizons: [2])
  end

  def test_features_nao_enxergam_o_futuro
    closes = Array.new(80) { |i| 100 + Math.sin(i) * 5 }
    before = DIR::Features.horizon_rows(closes, horizons: [2, 5, 20])
    changed = closes.dup
    changed[50..] = changed[50..].map { |c| c * 3 } # muda tudo a partir do dia 50

    after = DIR::Features.horizon_rows(changed, horizons: [2, 5, 20])
    before.zip(after).each do |b, a|
      next if b.index >= 50

      assert_equal b.values, a.values, "features do dia #{b.index} mudaram com dados do futuro"
    end
  end

  def test_recusa_serie_menor_que_o_maior_horizonte
    assert_raises(DIR::Error) { DIR::Features.horizon_rows(Array.new(60, 1.0), horizons: [60]) }
  end
end

class LogisticDirectionTest < Minitest::Test
  def row(x, up) = DIR::Features::Row.new(index: 0, values: [x, 0.5], up: up)

  def test_aprende_um_padrao_separavel
    rows = Array.new(200) { |i| x = (i % 20) - 9.5; row(x, x.positive?) }
    model = DIR::Models::LogisticDirection.new.fit(rows)

    assert_operator model.predict_proba([8.0, 0.5]), :>, 0.9
    assert_operator model.predict_proba([-8.0, 0.5]), :<, 0.1
    assert_operator model.weights.first, :>, 0, "peso positivo: quanto maior x, mais chance de alta"
  end

  def test_recusa_poucos_dados_e_previsao_sem_treino
    assert_raises(DIR::Error) { DIR::Models::LogisticDirection.new.fit([row(1, true)] * 5) }
    assert_raises(DIR::Error) { DIR::Models::LogisticDirection.new.predict_proba([1.0, 0.5]) }
  end
end

class DirectionBacktestTest < Minitest::Test
  def test_nunca_treina_com_linhas_do_bloco_de_teste
    trained_until = []
    spy = Class.new do
      define_method(:initialize) { |log| @log = log }
      define_method(:fit) { |rows| @log << rows.last.index; self }
      define_method(:predict_proba) { |_| 0.0 }
    end
    rows = Array.new(100) { |i| DIR::Features::Row.new(index: i, values: [0.0], up: i.even?) }
    DIR::Direction.walk_forward(rows, threshold: 0.6, min_train: 40, step: 20, model_factory: -> { spy.new(trained_until) })

    # blocos de teste começam em 40, 60, 80: o treino termina na linha anterior
    assert_equal [39, 59, 79], trained_until
  end

  def test_precisao_e_baseline
    always_up = Class.new do
      def fit(_) = self
      def predict_proba(_) = 1.0
    end
    rows = Array.new(60) { |i| DIR::Features::Row.new(index: i, values: [0.0], up: (i % 4).zero?) }
    result = DIR::Direction.walk_forward(rows, threshold: 0.6, min_train: 20, step: 10, model_factory: -> { always_up.new })

    # dizer "alta" todo dia acerta exatamente a taxa de dias de alta: não vence o baseline
    assert_equal 40, result.signals
    assert_in_delta result.up_rate, result.precision, 1e-12
    refute result.beats_baseline?
  end

  def test_poucos_sinais_e_inconclusivo
    result = DIR::Direction::Backtest.new(precision: 1.0, signals: 3, up_rate: 0.5, n_tests: 100)
    refute result.conclusive?
    refute result.beats_baseline?
    assert_match(/inconclusivo/, result.verdict)
  end

  def test_vantagem_pequena_com_poucos_sinais_pode_ser_sorte
    # 16 de 28 sinais certos (57%) contra 49% de dias de alta: z ≈ 0,9
    lucky = DIR::Direction::Backtest.new(precision: 16 / 28.0, signals: 28, up_rate: 0.488, n_tests: 300)
    refute lucky.beats_baseline?
    assert_match(/pode ser sorte/, lucky.verdict)

    # a mesma vantagem com 400 sinais já é distinguível de ruído
    solid = lucky.with(signals: 400)
    assert_operator solid.z, :>, 2
    assert solid.beats_baseline?
  end

  def test_encontra_a_reversao_da_petr4_e_nada_na_msft
    client = MarketPulse::MarketData::FakeClient.new(today: Date.new(2026, 10, 23), days: 500)
    run = ->(t) { DIR::Direction.run(client.history(t).map(&:close)) }

    assert run.("PETR4").backtest.beats_baseline?, "PETR4 tem reversão à média escondida"
    refute run.("MSFT").backtest.beats_baseline?, "MSFT é passeio aleatório: não há o que prever"
  end
end

class DailyJobDirectionTest < Minitest::Test
  def setup
    @prices = MarketPulse::MarketData::Repositories::MemoryPriceRepository.new
    @forecasts = DIR::Repositories::MemoryForecastRepository.new
  end

  def job(day, days: 300)
    client = MarketPulse::MarketData::FakeClient.new(today: day, days: days)
    DIR::DailyJob.new(client: client, prices: @prices, forecasts: @forecasts, tickers: %w[PETR4], logger: nil)
  end

  def test_salva_a_direcao_junto_com_a_previsao
    job(Date.new(2026, 10, 21)).run
    f = @forecasts.latest("PETR4")

    assert f.direction?
    assert_includes 0.0..1.0, f.prob_up
    assert_includes [DIR::Direction::UP, DIR::Direction::NONE], f.direction_signal
    assert_equal 0.6, f.direction_threshold
    assert_operator f.direction_n_tests, :>, 0
  end

  def test_serie_curta_mantem_a_previsao_de_retorno_sem_direcao
    job(Date.new(2026, 10, 21), days: 150).run
    f = @forecasts.latest("PETR4")

    refute_nil f, "a previsão de retorno continua sendo salva"
    refute f.direction?
    assert_nil f.direction_signal
  end

  def test_placar_do_sinal_de_alta
    up = DIR::Forecast.new(ticker: "X", as_of: Date.new(2026, 1, 1), model: "m", weight: 0, t_stat: 0, pattern: "",
                           last_close: 10.0, predicted_return: 0.0, predicted_close: 10.0, low: 9.0, high: 11.0,
                           mae: 0, baseline_mae: 0, hit_rate: 0, n_tests: 0,
                           prob_up: 0.7, direction_signal: DIR::Direction::UP, direction_threshold: 0.6,
                           direction_precision: 0.6, direction_signals: 20, direction_up_rate: 0.5, direction_n_tests: 100,
                           actual_close: nil, created_at: Time.now)

    assert_nil up.up_signal_hit?, "ainda não avaliada"
    assert_equal true, up.with(actual_close: 10.5).up_signal_hit?
    assert_equal false, up.with(actual_close: 9.5).up_signal_hit?
    assert_nil up.with(direction_signal: DIR::Direction::NONE, actual_close: 10.5).up_signal_hit?
  end
end

class DirectionConfigTest < Minitest::Test
  def test_pode_ser_desligado_e_configurado_pelo_env
    assert_nil MarketPulse.direction("DIRECTION" => "off")
    assert_respond_to MarketPulse.direction({}), :call
    assert_raises(ArgumentError) { MarketPulse.direction("DIRECTION_HORIZONS" => "2,abc") }
  end
end

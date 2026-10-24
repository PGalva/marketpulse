# frozen_string_literal: true

require "net/http"
require "json"
require_relative "types"

module MarketPulse
  module LLM
    # POST de JSON com a stdlib, compartilhado pelos providers HTTP.
    # Toda falha de rede ou HTTP vira ProviderError, para que o resto do
    # sistema trate "o provider falhou" de um jeito só.
    module HTTP
      module_function

      def post_json(url, body:, headers: {}, read_timeout: 120)
        uri = URI(url)
        request = Net::HTTP::Post.new(uri)
        request["content-type"] = "application/json"
        headers.each { |key, value| request[key] = value }
        request.body = JSON.generate(body)

        response = Net::HTTP.start(uri.host, uri.port,
                                   use_ssl: uri.scheme == "https",
                                   open_timeout: 10,
                                   read_timeout: read_timeout) { |http| http.request(request) }
        parsed = parse(response.body)

        unless response.is_a?(Net::HTTPSuccess)
          raise ProviderError, "HTTP #{response.code} em #{uri.host}: #{error_message(parsed)}"
        end

        parsed
      rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, IOError => e
        raise ProviderError, "Falha de rede em #{uri&.host}: #{e.class}: #{e.message}"
      end

      def parse(body)
        JSON.parse(body.to_s)
      rescue JSON::ParserError
        { "raw" => body.to_s[0, 300] }
      end

      def error_message(parsed)
        error = parsed["error"]
        error.is_a?(Hash) ? error["message"] : (error || parsed["raw"] || parsed).to_s
      end
    end
  end
end

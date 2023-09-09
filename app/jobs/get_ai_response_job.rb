class GetAiResponseJob < ApplicationJob
  def perform(chat_id)
    chat = Chat.find(chat_id)

    call_openai(chat: chat)
  end

  private

  def call_openai(chat:)
    snippet = find_closest_text(chat.messages.last.content)
    message_with_snippet = <<~TEXT
        #{chat.messages.last.content}

        SNIPPET:```
          #{snippet.to_json}
        ```
    TEXT
    hash = [ {:role=>"user", :content=> message_with_snippet}, {:role=>"user", :content=>Message.first.content} ]
    message = chat.messages.create(role: "assistant", content: "")
    message.broadcast_created

    client = OpenAI::Client.new
    response = client.chat(
      parameters: {
        model: "gpt-4",
        messages: hash,
        temperature: 0.7,
        stream: stream_proc(message: message)
      })
    response
  end

  def stream_proc(message:)
    proc do |chunk, _bytesize|
      new_content = chunk.dig("choices", 0, "delta", "content")
      message.update(content: message.content + new_content) if new_content
    end
  end

  # Find the closest text in the database
  def find_closest_text(text)
    return false if text == ""

    embedding = get_embeddings(text)
    @conn = connect_to_db("fasb", recreate_db: false)

    result = @conn.exec_params("SELECT metadata FROM items ORDER BY embedding <-> $1 LIMIT 1", [embedding]).first
    result ? result["metadata"] : {}
  end

  def get_embeddings(text, api_key: "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", retries: 3)
    raise ArgumentError, "text cannot be empty" if text.empty?

    uri = URI("https://api.openai.com/v1/engines/text-embedding-ada-002/embeddings")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"

    api_key ||= if Object.const_defined?("API_KEY")
                  API_KEY
                else
                  ENV["OPENAI_API_KEY"]
                end

    request["Authorization"] = "Bearer #{api_key}"

    request.body = { input: text, initial_prompt: 'You are an accounting expert. Repond to the user referencing the accounting guidlines' }.to_json

    response = nil
    retries.times do |i|
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end
      break if response.is_a?(Net::HTTPSuccess)
    rescue StandardError => e
      puts "Error: #{e.message}. Retrying in #{i + 1} seconds..."
      sleep(i + 1)
    end

    raise StandardError, "Failed to retrieve text embeddings after #{retries} retries" if response.nil?

    JSON.parse(response.body)["data"][0]["embedding"]
  end


  attr_accessor :conn

  # Set up PostgreSQL connection
  def connect_to_db(db_name, recreate_db: false)
    begin
      conn = PG.connect(dbname: db_name)
    rescue PG::Error => e
      puts "Error connecting to database: #{e.message}"
    end

    conn.exec("SET client_min_messages TO warning")
    conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
    conn.exec("CREATE TABLE IF NOT EXISTS items (id serial primary key, metadata jsonb, embedding vector(1536))")

    registry = PG::BasicTypeRegistry.new.define_default_types
    Pgvector::PG.register_vector(registry)
    conn.type_map_for_results = PG::BasicTypeMapForResults.new(conn, registry: registry)

    conn
  end
end


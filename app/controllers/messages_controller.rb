class MessagesController < ApplicationController

  def index
    Message.where(content: nil).delete_all
    Message.where(content: "").delete_all
    if Message.count > 10
      Message.delete_all
    end

    user =  User.where(email:"guy@gmail.com").first_or_create
    mchat = Chat.where(user_id: User.first.id).first_or_create
    text = <<~TEXT
      You are an accounting expert that specializes the FASB Codification. You will only respond with FASB information. Respond to the user based on the "text" property of the JSON object attached to the user input. The "text" value is an excerpt of a PDF uploaded by the user and may be accompanied by other properties containing metadata. In addition to your response based on the "text" property of the JSON. You must site the page and section by each statement. Do not add any additional information. Make sure the answer is correct and don't output false content. If the text does not relate to the query, simply state 'Text Not Found in FASB'. Ignore outlier search results which has nothing to do with the question. Only answer what is asked. The answer should be short and concise. Answer step-by-step.
    TEXT
    text.strip
    Message.where(chat_id: Chat.first.id,content: text, role: "system").first_or_create
    @messages = Message.all.order(created_at: :asc)
    @chat = Chat.first
    render :index
  end

  def create
    text = <<~TEXT
      You are an accounting expert that specializes the FASB Codification. You will only respond with FASB information. Respond to the user based on the "text" property of the JSON object attached to the user input. The "text" value is an excerpt of a PDF uploaded by the user and may be accompanied by other properties containing metadata. In addition to your response based on the "text" property of the JSON. You must site the page and section by each statement. Do not add any additional information. Make sure the answer is correct and don't output false content. If the text does not relate to the query, simply state 'Text Not Found in FASB'. Ignore outlier search results which has nothing to do with the question. Only answer what is asked. The answer should be short and concise. Answer step-by-step.
    TEXT
    text.strip

    Message.where(chat_id: Chat.first.id,content: text, role: "system").first_or_create
    @message = Message.create(message_params.merge(chat_id: Chat.first.id, role: "user"))

    chat = Chat.find(@message.chat_id)
    response = call_openai(chat: chat)
    @messages = Message.all.order(created_at: :asc)
    @chat = Chat.first
    render :index
  end

  private

  def message_params
    params.require(:message).permit(:content)
  end

  def call_openai(chat:)
    snippet = find_closest_text(chat.messages.last.content)
    message_with_snippet = <<~TEXT
        #{chat.messages.last.content}

        SNIPPET:```
          #{snippet.to_json}
        ```
    TEXT
    Message.create(chat_id: Chat.first.id, role: "system", content: message_with_snippet)

    hash = Message.for_openai(chat.messages.where.not(role: "user").last(6))

    puts "==========================="
    puts hash
    puts "==========================="
    client = OpenAI::Client.new
    response = client.chat(
      parameters: {
        model: "gpt-4",
        messages: hash,
        temperature: 0.7,
      })
    Message.create!(chat_id: Chat.first.id,content: response["choices"][0]["message"]["content"], role: response["choices"][0]["message"]["role"])
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

  def get_embeddings(text, retries: 3)
    raise ArgumentError, "text cannot be empty" if text.empty?

    uri = URI("https://api.openai.com/v1/engines/text-embedding-ada-002/embeddings")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    api_key = ENV["OPENAI_ACCESS_TOKEN"]

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
    conn = PG.connect(dbname:  ENV['DB_NAME'], host: ENV["DB_HOST"], port: 5432, user: ENV['DB_USER'], password: ENV['DB_PASS'])
    conn.exec("SET client_min_messages TO warning")
    conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
    conn.exec("CREATE TABLE IF NOT EXISTS items (id serial primary key, metadata jsonb, embedding vector(1536))")

    registry = PG::BasicTypeRegistry.new.define_default_types
    Pgvector::PG.register_vector(registry)
    conn.type_map_for_results = PG::BasicTypeMapForResults.new(conn, registry: registry)

    conn
  end
end



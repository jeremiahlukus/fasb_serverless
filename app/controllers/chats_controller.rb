class ChatsController < ApplicationController
  before_action :set_chat, only: %i[show]
  before_action :set_chats_collection, only: %i[index show]

  def index;
    mchat = Chat.where(user_id: User.first.id).first_or_create
    text = <<~TEXT
      You are an accounting expert that specializes the FASB Codification. You will only respond with FASB information. Respond to the user based on the "text" property of the JSON object attached to the user input. The "text" value is an excerpt of a PDF uploaded by the user and may be accompanied by other properties containing metadata. In addition to your response based on the "text" property of the JSON. You must site the page and section by each statement. Do not add any additional information. Make sure the answer is correct and don't output false content. If the text does not relate to the query, simply state 'Text Not Found in FASB'. Ignore outlier search results which has nothing to do with the question. Only answer what is asked. The answer should be short and concise. Answer step-by-step.
    TEXT
    text.strip
    Message.where(chat_id: mchat.id,content: text, role: "system").first_or_create
    @chats = Chat.all
  end

  def show
    respond_with(@chat)
  end

  def create
    @chat = Chat.includes(:messages).where(user: current_user, messages: { id: nil }).first_or_create
    respond_with(@chat)
  end

  private

  def set_chat
    @chat = Chat.find(params[:id])
  end

  def set_chats_collection
    @chats = Chat.all
  end
end

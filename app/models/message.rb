# == Schema Information
#
# Table name: messages
#
#  id         :bigint           not null, primary key
#  content    :string
#  role       :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  chat_id    :bigint           not null
#
# Indexes
#
#  index_messages_on_chat_id  (chat_id)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#
# app/models/message.rb
class Message < ApplicationRecord
  include ActionView::RecordIdentifier

  enum role: { system: 0, assistant: 10, user: 20 }

  belongs_to :chat

  def self.for_openai(messages)
    messages.map { |message| { role: message.role, content: message.content } }
  end
end

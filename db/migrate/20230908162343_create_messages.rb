class CreateMessages < ActiveRecord::Migration[6.1]
  def change
    create_table :messages do |t|
      t.references :chat, null: false, foreign_key: true
      t.integer :role
      t.string :content

      t.timestamps
    end
  end
end

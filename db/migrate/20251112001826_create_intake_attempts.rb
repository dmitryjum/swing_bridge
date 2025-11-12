class CreateIntakeAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :intake_attempts do |t|
      t.string  :club, null: false
      t.string  :email, null: false
      t.string  :status, null: false, default: "pending"
      t.jsonb   :request_payload, default: {}
      t.jsonb   :response_payload, default: {}
      t.text    :error_message
      t.integer :attempts_count, default: 0, null: false

      t.timestamps
    end

    add_index :intake_attempts, :email
    add_index :intake_attempts, :status
  end
end

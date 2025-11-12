class AddCompositeIndexToIntakeAttempts < ActiveRecord::Migration[8.1]
  def change
    add_index :intake_attempts, [ :club, :email ], unique: true
  end
end

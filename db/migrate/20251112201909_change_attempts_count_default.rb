class ChangeAttemptsCountDefault < ActiveRecord::Migration[8.1]
  def change
    change_column_default :intake_attempts, :attempts_count, from: 0, to: 1
  end
end

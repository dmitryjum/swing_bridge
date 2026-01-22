class AddIntakeAttemptsSearchIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :intake_attempts,
              "to_tsvector('simple', coalesce(email,'') || ' ' || coalesce(status,'') || ' ' || coalesce(error_message,'') || ' ' || coalesce(request_payload::text,'') || ' ' || coalesce(response_payload::text,''))",
              using: :gin,
              name: "index_intake_attempts_on_search_vector"
  end
end

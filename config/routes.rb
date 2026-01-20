Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  root to: "rails/health#show"
  namespace :api do
    namespace :v1 do
      mount MissionControl::Jobs::Engine, at: "/jobs"
      resources :intakes, only: :create
    end
  end

  namespace :admin do
    resources :intake_attempts, only: [ :index, :show ] do
      post :retry, on: :member
    end
    root to: "intake_attempts#index"
  end
end

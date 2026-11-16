Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Marketing site
  root "pages#home"
  get "how-it-works", to: "pages#methodology", as: :methodology

  # The app: products, mapped term, label, confidence, reasons.
  get "dashboard", to: "trends#index", as: :dashboard
  # One article's trend panel: a fragment for the in-page dialog, or a full page if opened directly.
  get "trend", to: "trends#show", as: :trend
  get "discover", to: "discover#index", as: :discover

  # Merchant corrections to the product -> Wikipedia mapping.
  resources :mapping_overrides, only: %i[create destroy]

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end

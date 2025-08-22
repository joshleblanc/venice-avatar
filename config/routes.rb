Rails.application.routes.draw do
  resources :characters do
    collection do
      post :auto_generate
    end
    resources :conversations, only: [:create]
  end

  # Separate index for Venice-provided characters
  resources :venice_characters, only: [:index]

  resources :conversations, only: [:index, :show, :destroy] do
    member do
      post :regenerate_scene
      patch :image_style
    end
    resources :messages, only: [:create]
  end

  resource :session
  resources :registrations, only: [:new, :create]
  resources :passwords, param: :token
  resource :profile, only: [:show, :edit, :update]
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "conversations#index"
end

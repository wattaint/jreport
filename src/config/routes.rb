Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  root to: 'api#index'
  get '/api/:id', to: 'api#show'

  post '/report/:report_name', to: 'report#create_by_name'
end

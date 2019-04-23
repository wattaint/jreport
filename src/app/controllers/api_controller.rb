class ApiController < ApplicationController
  def index
    render json: { message: 'hello', env: ENV }
  end

  def show
    render json: { id: params[:id] }
  end
end

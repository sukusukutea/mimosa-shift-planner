class DashboardsController < ApplicationController
  before_action :authenticate_user! # ログインしていないと入れない

  def index
  end
end

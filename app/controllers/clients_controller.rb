class ClientsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_client, only: [:edit, :update, :destroy, :pause, :restore]

  def index
    @active_clients = current_user.clients
                                  .active
                                  .includes(:client_regular_schedules)
                                  .ordered

    @inactive_clients = current_user.clients
                                    .where(active: false)
                                    .includes(:client_regular_schedules)
                                    .ordered
  end

  def new
    @client = current_user.clients.build(active: true)
    @day_service_wdays = []
    @visit_wdays = []
  end

  def create
    @client = current_user.clients.build(client_params)

    ActiveRecord::Base.transaction do
      @client.save!
      sync_regular_schedules!(@client)
    end

    redirect_to clients_path, notice: "利用者を登録しました。"
  rescue ActiveRecord::RecordInvalid
    set_regular_schedule_wdays_from_params
    render :new, status: :unprocessable_entity
  end

  def edit
    set_regular_schedule_wdays
  end

  def update
    ActiveRecord::Base.transaction do
      @client.update!(client_params)
      sync_regular_schedules!(@client)
    end

    redirect_to clients_path, notice: "利用者情報を更新しました。"
  rescue ActiveRecord::RecordInvalid
    set_regular_schedule_wdays_from_params
    render :edit, status: :unprocessable_entity
  end

  def pause
    @client.update!(active: false)
    redirect_to clients_path, notice: "利用者を休止にしました。"
  end

  def restore
    @client.update!(active: true)
    redirect_to clients_path, notice: "利用者を利用中に戻しました。"
  end

  def destroy
    @client.destroy!
    redirect_to clients_path, notice: "利用者を削除しました。"
  end

  private

  def set_client
    @client = current_user.clients.find(params[:id])
  end

  def client_params
    params.require(:client).permit(:display_name, :sort_key, :active)
  end

  def set_regular_schedule_wdays
    @day_service_wdays = regular_schedule_wdays_for("day_service")
    @visit_wdays = regular_schedule_wdays_for("visit")
  end

  def set_regular_schedule_wdays_from_params
    @day_service_wdays = selected_wdays_for("day_service")
    @visit_wdays = selected_wdays_for("visit")
  end

  def regular_schedule_wdays_for(service_kind)
    @client.client_regular_schedules
           .where(service_kind: service_kind)
           .pluck(:wday)
           .sort
  end

  def sync_regular_schedules!(client)
    sync_regular_schedule!(client, "day_service", selected_wdays_for("day_service"))
    sync_regular_schedule!(client, "visit", selected_wdays_for("visit"))
  end

  def sync_regular_schedule!(client, service_kind, selected_wdays)
    selected_wdays = selected_wdays.map(&:to_i).uniq.sort

    schedules = client.client_regular_schedules.where(service_kind: service_kind)

    if selected_wdays.empty?
        schedules.destroy_all
        return
    end

    schedules.where.not(wday: selected_wdays).destroy_all

    selected_wdays.each do |wday|
        schedules.find_or_create_by!(wday: wday) do |schedule|
        schedule.active = true
        end
    end
  end

  def selected_wdays_for(service_kind)
    Array(params.dig(:client_regular_schedules, "#{service_kind}_wdays"))
      .reject(&:blank?)
      .map(&:to_i)
      .select { |wday| wday.between?(0, 6) }
  end
end

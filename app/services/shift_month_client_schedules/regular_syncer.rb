module ShiftMonthClientSchedules
  class RegularSyncer
    def initialize(shift_month:)
      @shift_month = shift_month
      @user = shift_month.user
    end

    def call
      return if shift_month.shift_month_client_schedules.exists?

      ActiveRecord::Base.transaction do
        active_clients.each do |client|
          regular_schedules_for(client).each do |regular_schedule|
            dates_in_month.each do |date|
              next unless regular_schedule.wday == ShiftMonth.ui_wday(date)

              create_monthly_schedule!(client, regular_schedule, date)
            end
          end
        end
      end
    end

    private

    attr_reader :shift_month, :user

    def active_clients
      user.clients
          .active
          .includes(:client_regular_schedules)
          .ordered
    end

    def regular_schedules_for(client)
      service_kind_values =
        ClientRegularSchedule.service_kinds.values_at("day_service", "visit")

      client.client_regular_schedules.select do |schedule|
        schedule.active? && service_kind_values.include?(ClientRegularSchedule.service_kinds[schedule.service_kind])
      end
    end

    def dates_in_month
      first_date = Date.new(shift_month.year, shift_month.month, 1)

      first_date..first_date.end_of_month
    end

    def create_monthly_schedule!(client, regular_schedule, date)
      shift_month.shift_month_client_schedules.find_or_create_by!(
        client: client,
        date: date,
        service_kind: regular_schedule.service_kind
      ) do |schedule|
        schedule.source = :regular
        schedule.client_display_name = client.display_name
      end
    end
  end
end

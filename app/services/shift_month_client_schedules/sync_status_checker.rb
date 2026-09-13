require "set"

module ShiftMonthClientSchedules
  class SyncStatusChecker
    TARGET_SERVICE_KINDS = %w[day_service visit].freeze

    Result = Struct.new(
      :missing_schedules,
      :extra_schedules,
      :display_name_changes,
      keyword_init: true
    ) do
      def sync_required?
        missing_schedules.any? ||
          extra_schedules.any? ||
          display_name_changes.any?
      end
    end

    def initialize(shift_month:)
      @shift_month = shift_month
      @user = shift_month.user
    end

    def call
      Result.new(
        missing_schedules: missing_schedules,
        extra_schedules: extra_schedules,
        display_name_changes: display_name_changes
      )
    end

    private

    attr_reader :shift_month, :user

    def missing_schedules
      desired_regular_schedules.reject do |key, _schedule|
        existing_regular_schedules.key?(key)
      end.values
    end

    def extra_schedules
      existing_regular_schedules.reject do |key, _schedule|
        desired_regular_schedules.key?(key)
      end.values
    end

    def display_name_changes
      desired_regular_schedules.filter_map do |key, desired_schedule|
        existing_schedule = existing_regular_schedules[key]
        next if existing_schedule.blank?
        next if existing_schedule.client_display_name == desired_schedule[:client_display_name]

        {
          schedule: existing_schedule,
          new_client_display_name: desired_schedule[:client_display_name]
        }
      end
    end

    def desired_regular_schedules
      @desired_regular_schedules ||= begin
        schedules = {}

        active_clients.each do |client|
          target_regular_schedules_for(client).each do |regular_schedule|
            dates_for_wday(regular_schedule.wday).each do |date|
              key = schedule_key(client.id, date, regular_schedule.service_kind)

              next if manual_override_keys.include?(key)

              schedules[key] = {
                client_id: client.id,
                date: date,
                service_kind: regular_schedule.service_kind,
                client_display_name: client.display_name
              }
            end
          end
        end

        schedules
      end
    end

    def existing_regular_schedules
      @existing_regular_schedules ||= shift_month.shift_month_client_schedules
                                                   .regular
                                                   .where(service_kind: TARGET_SERVICE_KINDS)
                                                   .index_by do |schedule|
        schedule_key(schedule.client_id, schedule.date, schedule.service_kind)
      end
    end

    def active_clients
      user.clients
          .active
          .includes(:client_regular_schedules)
          .ordered
    end

    def target_regular_schedules_for(client)
      client.client_regular_schedules.select do |schedule|
        schedule.active? && TARGET_SERVICE_KINDS.include?(schedule.service_kind)
      end
    end

    def dates_for_wday(wday)
      dates_in_month.select do |date|
        ui_wday(date) == wday
      end
    end

    def dates_in_month
      @dates_in_month ||= begin
        first_date = Date.new(shift_month.year, shift_month.month, 1)
        first_date..first_date.end_of_month
      end
    end

    def ui_wday(date)
      if ShiftMonth.respond_to?(:ui_wday)
        ShiftMonth.ui_wday(date)
      else
        (date.wday + 6) % 7
      end
    end

    def schedule_key(client_id, date, service_kind)
      [ client_id, date, service_kind ].join(":")
    end

    def manual_override_keys
      @manual_override_keys ||= shift_month.shift_month_client_schedules
                                          .manual
                                          .where(service_kind: TARGET_SERVICE_KINDS)
                                          .map do |schedule|
        schedule_key(schedule.client_id, schedule.date, schedule.service_kind)
      end.to_set
    end
  end
end

module ShiftMonthClientSchedules
  class Synchronizer
    def initialize(shift_month:)
      @shift_month = shift_month
    end

    def call
      status = SyncStatusChecker.new(shift_month: shift_month).call

      ActiveRecord::Base.transaction do
        add_missing_schedules!(status.missing_schedules)
        remove_extra_schedules!(status.extra_schedules)
        update_display_names!(status.display_name_changes)
      end

      status
    end

    private

    attr_reader :shift_month

    def add_missing_schedules!(missing_schedules)
      missing_schedules.each do |attrs|
        shift_month.shift_month_client_schedules.find_or_create_by!(
          client_id: attrs[:client_id],
          date: attrs[:date],
          service_kind: attrs[:service_kind]
        ) do |schedule|
          schedule.source = :regular
          schedule.client_display_name = attrs[:client_display_name]
        end
      end
    end

    def remove_extra_schedules!(extra_schedules)
      extra_schedules.each(&:destroy!)
    end

    def update_display_names!(display_name_changes)
      display_name_changes.each do |change|
        change[:schedule].update!(
          client_display_name: change[:new_client_display_name]
        )
      end
    end
  end
end

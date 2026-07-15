module ShiftDrafts
  class OverstaffingBuilder
    def initialize(dates:, draft:, staff_by_id:, required_by_date:, enabled_by_date:, shift_month:)
      @dates = dates
      @draft = draft
      @staff_by_id = staff_by_id
      @required_by_date = required_by_date
      @enabled_by_date = enabled_by_date
      @shift_month = shift_month
    end

    def call
      overstaffing = {}

      @dates.each do |date|
        dkey = date.iso8601
        kinds_hash = @draft[dkey] || {}

        list = []
        day_msg = day_overstaffing_message(date, kinds_hash)
        list << day_msg if day_msg.present?

        early_over = early_overstaffing_count(date, kinds_hash)
        late_over = late_overstaffing_count(date, kinds_hash)
        night_over = night_overstaffing_count(date, kinds_hash)

        list << "早+#{early_over}" if early_over > 0
        list << "遅+#{late_over}" if late_over > 0
        list << "夜+#{night_over}" if night_over > 0

        overstaffing[date] = list if list.any?
      end

      overstaffing
    end

    private

    def day_overstaffing_message(date, kinds_hash)
      return nil unless enabled?(:day, date)

      req = @required_by_date[date] || { nurse: 0, care: 0 }
      req_nurse = req[:nurse].to_i
      req_care = req[:care].to_i

      actual = day_actual_counts(kinds_hash)

      over_nurse = [ actual[:nurse] - req_nurse, 0 ].max
      over_care = [ actual[:care] - req_care, 0 ].max

      parts = []
      parts << "看＋#{over_nurse}" if over_nurse > 0
      parts << "介＋#{over_care}" if over_care > 0

      return nil if parts.blank?

      "日勤：#{parts.join(' ')}"
    end

    def early_overstaffing_count(date, kinds_hash)
      return 0 unless enabled?(:early, date)

      actual = kind_count(kinds_hash, "early")
      [ actual - 1, 0 ].max
    end

    def late_overstaffing_count(date, kinds_hash)
      return 0 unless enabled?(:late, date)

      required = @shift_month.late_slots_for(date).to_i
      required = 1 if required <= 0
      required = 2 if required >= 2

      actual = kind_count(kinds_hash, "late")
      [ actual - required, 0 ].max
    end

    def night_overstaffing_count(date, kinds_hash)
      return 0 unless enabled?(:night, date)

      actual = kind_count(kinds_hash, "night")
      [ actual - 1, 0 ].max
    end

    def enabled?(kind_sym, date)
      map = @enabled_by_date[kind_sym]
      return false if map.nil?

      map[date] == true
    end

    def kind_count(kinds_hash, kind)
      rows = kinds_hash[kind] || kinds_hash[kind.to_sym]
      Array(rows).size
    end

    def day_actual_counts(kinds_hash)
      nurse = 0
      care = 0

      rows = kinds_hash["day"] || kinds_hash[:day]

      Array(rows).each do |row|
        sid = extract_staff_id(row)
        next if sid.nil?

        staff = @staff_by_id[sid.to_i]
        next if staff.nil?
        next unless staff.counts_toward_requirements?

        occ_name = staff.occupation&.name.to_s

        nurse += 1 if occ_name.include?("看護")
        care += 1 if occ_name.include?("介護")
      end

      { nurse: nurse, care: care }
    end

    def extract_staff_id(row)
      return nil if row.nil?
      return row.to_i unless row.is_a?(Hash)

      v = row["staff_id"] || row[:staff_id]
      v.present? ? v.to_i : nil
    end
  end
end

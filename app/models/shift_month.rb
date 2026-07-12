class ShiftMonth < ApplicationRecord
  belongs_to :user
  belongs_to :organization

  has_many :shift_day_settings, dependent: :destroy
  has_many :shift_day_assignments, dependent: :destroy
  has_many :staff_holiday_requests, dependent: :destroy
  has_many :shift_month_requirements, dependent: :destroy
  has_many :shift_day_requirements, dependent: :destroy
  has_many :shift_day_designations, dependent: :destroy
  has_many :shift_month_skill_requirements, dependent: :destroy
  has_many :shift_day_skill_requirements, dependent: :destroy
  has_many :shift_month_time_options, dependent: :destroy

  validates :year, presence: true
  validates :month, presence: true
  validates :month, inclusion: { in: 1..12 }

  SHIFT_KINDS = %i[day early late night].freeze

  # 日別の勤務ON/OFFを返す
  def enabled_map_for(date)
    setting = shift_day_settings.includes(:shift_day_styles).find_by(date: date)

    w = self.class.ui_wday(date)
    default = {
      day: true,
      early: requirements_index[[ :early, w ]]&.dig(:any).to_i > 0,
      late:  requirements_index[[ :late,  w ]]&.dig(:any).to_i > 0,
      night: requirements_index[[ :night, w ]]&.dig(:any).to_i > 0
    }

    # 設定がなければ全部の勤務をONにする（index_withで各勤務にtrueのハッシュつける）
    return default.dup if setting.nil?

    # settingがある場合：styleが欠けていても全部ONをベースに上書き
    base = default.dup
    setting.shift_day_styles.each do |style|   # その日に「設定が存在する勤務だけ」１件ずつ取り出す
      base[style.shift_kind.to_sym] = style.enabled   # style.shift_kindでenumの"day"や"night"などのStringが返る。to_symはSymbolキー（:nightなど）に変換
    end
    base
  end

  def enabled_map_for_range(dates) # 複数日まとめてenabledを取る
    dates = Array(dates)
    date_set = dates.to_set

    result = {}
    SHIFT_KINDS.each do |kind|
      if %i[early late night].include?(kind)
        result[kind] = dates.index_with do |date|
          w = self.class.ui_wday(date)
          requirements_index[[ kind, w ]]&.dig(:any).to_i > 0
        end
      else
        result[kind] = dates.index_with(true) # dayは常にtrue
      end
    end

    settings = shift_day_settings.where(date: dates).includes(:shift_day_styles)

    settings.each do |setting|
      date = setting.date
      next unless date_set.include?(date)

      setting.shift_day_styles.each do |style|
        kind = style.shift_kind.to_sym
        result[kind][date] = style.enabled
      end
    end
    result
  end

  def self.ui_wday(date) # Ruby上では日0 月1..となるため、UI上で月0 火1..となるよう変換する
    return nil if date.nil?
    (date.wday + 6) % 7
  end

  # この月のrequirementを一度だけDBから取り、参照しやすい形に整形して保持する
  # index[[shift_kind, day_of_week]][role] => required_number
  def requirements_index
    @requirements_index ||= begin
      rows = shift_month_requirements
               .select(:shift_kind, :day_of_week, :role, :required_number)

      index = Hash.new { |h, k| h[k] = {} }

      rows.each do |r|
        key = [ r.shift_kind.to_sym, r.day_of_week ]
        index[key][r.role.to_sym] = r.required_number
      end

      index
    end
  end

  def skill_requirements_index
    @skill_requirements_index ||= begin
      rows = shift_month_skill_requirements.select(:day_of_week, :skill, :role, :required_number)

      index = Hash.new { |h, k| h[k] = {} }

      rows.each do |r|
        wday = r.day_of_week
        skill = r.skill.to_sym
        role = r.role.to_sym

        key =
          if skill == :visit && %i[nurse care].include?(role)
            "#{role}_visit".to_sym
          else
            skill
          end

        index[wday][key] = r.required_number
      end

      index
    end
  end

  def clear_skill_requirements_cache!
    remove_instance_variable(:@skill_requirements_index) if instance_variable_defined?(:@skill_requirements_index)
  end

  # { nurse: 2, care: 1 } などのHashを返す
  def required_counts_for(date, shift_kind: :day)
    roles = day_requirements_index[[ date, shift_kind.to_sym ]]
    if roles.present?
      return {
        nurse: roles[:nurse].to_i,
        care:  roles[:care].to_i
      }
    end

    w = self.class.ui_wday(date)

    roles2 = requirements_index[[ shift_kind.to_sym, w ]] || {}
    {
      nurse: roles2[:nurse].to_i,
      care:  roles2[:care].to_i
    }
  end

  def clear_requirements_cache!
    remove_instance_variable(:@requirements_index) if instance_variable_defined?(:@requirements_index)
  end

  def clear_day_requirements_cache!
    remove_instance_variable(:@day_required_index) if instance_variable_defined?(:@day_required_index)
  end

  def copy_weekday_requirements_from_base!(user:)
    BaseWeekdayRequirement.transaction do
      base_rows = user.base_weekday_requirements.select(:shift_kind, :day_of_week, :role, :required_number)

      base_rows.each do |base|
        rec = shift_month_requirements.find_or_initialize_by( # rec = recordの略
          shift_kind: base.shift_kind,
          day_of_week: base.day_of_week,
          role: base.role
        )
        rec.required_number = base.required_number
        rec.save!
      end
    end

    clear_requirements_cache! # requirements_indexを使ってるならキャッシュクリア
  end

  def copy_skill_requirements_from_base!(user:)
    BaseSkillRequirement.transaction do
      base_rows = user.base_skill_requirements.select(:day_of_week, :skill, :role, :required_number)

      base_rows.each do |base|
        rec = shift_month_skill_requirements.find_or_initialize_by(
          day_of_week: base.day_of_week,
          skill: base.skill,
          role: base.role
        )

        rec.required_number = base.required_number
        rec.save!
      end
    end

    clear_skill_requirements_cache!
  end

  def day_requirements_index # 日別人員配置を一括取得して参照しやすくする index[[date, shift_kind_sym][role_sym]] => required_number
    @day_required_index ||= begin
      rows = shift_day_requirements.select(:date, :shift_kind, :role, :required_number)

      index = Hash.new { |h, k| h[k] = {} }
      rows.each do |row|
        key = [ row.date, row.shift_kind.to_sym ]
        index[key][row.role.to_sym] = row.required_number
      end
      index
    end
  end

  def day_skill_requirements_index
    @day_skill_requirements_index ||= begin
      rows = shift_day_skill_requirements.select(:date, :shift_kind, :skill, :role, :required_number)

      index = Hash.new { |h, k| h[k] = {} }

      rows.each do |row|
        key = [ row.date, row.shift_kind.to_sym ]
        skill = row.skill.to_sym
        role = row.role.to_sym

        skill_key =
          if skill == :visit && %i[nurse care].include?(role)
            "#{role}_visit".to_sym
          else
            skill
          end

        index[key][skill_key] = row.required_number
      end

      index
    end
  end

  def clear_day_skill_requirements_cache!
    remove_instance_variable(:@day_skill_requirements_index) if instance_variable_defined?(:@day_skill_requirements_index)
  end

  def required_skill_counts_for(date)
    empty = {
      drive: 0,
      cook: 0,
      nurse_visit: 0,
      care_visit: 0
    }

    return empty if date.nil?

    day_skills = day_skill_requirements_index[[ date, :day ]]
    if day_skills.present?
      return {
        drive: day_skills[:drive].to_i,
        cook: day_skills[:cook].to_i,
        nurse_visit: day_skills[:nurse_visit].to_i,
        care_visit: day_skills[:care_visit].to_i
      }
    end

    w = self.class.ui_wday(date)
    return empty if w.nil?

    skills = skill_requirements_index[w] || {}

    {
      drive: skills[:drive].to_i,
      cook: skills[:cook].to_i,
      nurse_visit: skills[:nurse_visit].to_i,
      care_visit: skills[:care_visit].to_i
    }
  end

  def late_slots_for(date)
    setting = shift_day_settings.find_by(date: date)
    value   = setting&.late_slots.to_i

    return 1 if value <= 0
    return 2 if value >= 2

    value
  end

  def default_late_time_text
    @default_late_time_text ||= begin
      option =
        shift_month_time_options
          .late
          .find_by(is_default: true)

      option&.time_text.presence || "11-20"
    end
  end
end

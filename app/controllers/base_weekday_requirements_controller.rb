class BaseWeekdayRequirementsController < ApplicationController
  before_action :authenticate_user!

  def show
    @rows = build_table
  end

  def edit
    @rows = build_table
  end

  def update
    data = params.require(:weekday_requirements)
  
    BaseWeekdayRequirement.transaction do
      data.each do |dow_str, roles_hash| # dow = day_of_weekの略
        dow = dow_str.to_i

        nurse_num = roles_hash["nurse"].to_i
        care_num = roles_hash["care"].to_i
        nurse_visit_num = roles_hash["nurse_visit"].to_i
        care_visit_num = roles_hash["care_visit"].to_i

        if nurse_visit_num > nurse_num
          redirect_to edit_base_weekday_requirements_path,
                      alert: "#{%w[月 火 水 木 金 土 日][dow]}曜の看護訪問は、看護人数以下にしてください"
          return
        end

        if care_visit_num > care_num
          redirect_to edit_base_weekday_requirements_path,
                      alert: "#{%w[月 火 水 木 金 土 日][dow]}曜の介護訪問は、介護人数以下にしてください"
          return
        end

        %w[nurse care].each do |role|
          num = roles_hash[role].to_i

          rec = current_user.base_weekday_requirements.find_or_initialize_by(
            shift_kind: :day,
            day_of_week: dow,
            role: role
          )

          rec.required_number = num
          rec.save!
        end

        %w[early late night].each do |kind|
          num = roles_hash[kind].to_i # トグル: "0"or"1"

          rec = current_user.base_weekday_requirements.find_or_initialize_by(
            shift_kind: kind,
            day_of_week: dow,
            role: :any
          )

          rec.required_number = num
          rec.save!
        end

        %w[drive cook].each do |skill|
          num = roles_hash[skill].to_i

          rec = current_user.base_skill_requirements.find_or_initialize_by(
            day_of_week: dow,
            skill: skill,
            role: :any
          )

          rec.required_number = num
          rec.save!
        end

        {
          "nurse_visit" => :nurse,
          "care_visit" => :care
        }.each do |param_key, role|
          num = roles_hash[param_key].to_i

          rec = current_user.base_skill_requirements.find_or_initialize_by(
            day_of_week: dow,
            skill: :visit,
            role: role
          )

          rec.required_number = num
          rec.save!
        end
      end
    end

    redirect_to base_weekday_requirements_path, notice: "保存しました"
  rescue ActionController::ParameterMissing
    redirect_to edit_base_weekday_requirements_path, alert: "入力が見つかりません"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_base_weekday_requirements_path, alert: "保存に失敗しました：#{e.record.errors.full_messages.join(", ")}"
  end

  private

  def build_table
    hash = (0..6).index_with {
      {
        "nurse" => 0,
        "nurse_visit" => 0,
        "care" => 0,
        "care_visit" => 0,
        "early" => 0,
        "late" => 0,
        "night" => 0,
        "drive" => 0,
        "cook" => 0
      }
    }

    current_user.base_weekday_requirements.each do |r|
      dow = r.day_of_week
      kind = r.shift_kind.to_s

      if kind == "day"
        hash[dow][r.role] = r.required_number
      else
        next unless r.role == "any"

        hash[dow][kind] = r.required_number
      end
    end

    current_user.base_skill_requirements.each do |r|
      dow = r.day_of_week
      skill = r.skill.to_s
      role = r.role.to_s

      if skill == "visit"
        next unless %w[nurse care].include?(role)

        hash[dow]["#{role}_visit"] = r.required_number
      else
        next unless role == "any"

        hash[dow][skill] = r.required_number
      end
    end

    hash
  end
end

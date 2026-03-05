# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  # before_action :configure_sign_up_params, only: [:create]
  # before_action :configure_account_update_params, only: [:update]

  # GET /resource/sign_up
  def new
    super
  end

  # POST /resource
  def create
    raw_params = sign_up_params
    build_resource(raw_params)

    unless resource.valid?
      clean_up_passwords resource
      set_minimum_password_length
      return respond_with resource, status: :unprocessable_entity do |format|
        format.html { render :new, status: :unprocessable_entity }
      end
    end

    org_name = raw_params[:organization_name]&.strip

    ActiveRecord::Base.transaction do
      # 事業所を作成
      organization = Organization.find_or_create_by!(name: org_name)
      # ユーザーを作成
      resource.organization = organization # organization_idを紐付け
      resource.save!
    end

    # Devise 標準の後処理（ログイン＆リダイレクト）
    yield resource if block_given? # ここはDevise の標準フックとして残しておく（block作ってないので実行されない）
    if resource.persisted?
      if resource.active_for_authentication?
        set_flash_message! :notice, :signed_up
        sign_up(resource_name, resource)
        respond_with resource, location: after_sign_up_path_for(resource)
      else
        set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
        expire_data_after_sign_in!
        respond_with resource, location: after_inactive_sign_up_path_for(resource)        end
    else
      clean_up_passwords resource
      set_minimum_password_length
      respond_with resource
    end

  rescue ActiveRecord::RecordInvalid => e
    # 事業所orユーザー作成で失敗した場合はフォームを再表示
    self.resource = e.record if e.respond_to?(:record) && e.record.is_a?(User) # 失敗したレコードをresourceに載せる
    clean_up_passwords resource # パスワードのフィールドをリセットして、再表示されないようにする処理
    set_minimum_password_length
    respond_with resource, status: :unprocessable_entity do |format| # エラー付きのresourceを持って、新規登録フォームを再表示する
      format.html { render :new, status: :unprocessable_entity } # unprocessable_entityはHTTP ステータスコード（422）のこと
    end
  end

  def update
    self.resource = current_user

    org_name = params[:user][:organization_name]&.strip

    ActiveRecord::Base.transaction do
      if org_name.present?
        organization = Organization.find_or_create_by!(name: org_name)
        resource.organization = organization
      end

      if params[:user][:password].present?
        ok = resource.update_with_password(account_update_params)
      else
        ok = resource.update_without_password(account_update_params.except(:current_password))
      end

      raise ActiveRecord::RecordInvalid.new(resource) unless ok
    end

    redirect_to dashboard_path, notice: "アカウントを更新しました"
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_entity
  end

  private

  def sign_up_params
    params.require(:user).permit(
      :name,
      :organization_name,
      :email,
      :password,
      :password_confirmation
    )
  end

  def account_update_params
    params.require(:user).permit(
      :name,
      :organization_name,
      # :email,
      :password,
      :password_confirmation,
      :current_password
    )
  end
end

  # GET /resource/edit
  # def edit
  #   super
  # end

  # PUT /resource
  # def update
  #   super
  # end

  # DELETE /resource
  # def destroy
  #   super
  # end

  # GET /resource/cancel
  # Forces the session data which is usually expired after sign
  # in to be expired now. This is useful if the user wants to
  # cancel oauth signing in/up in the middle of the process,
  # removing all OAuth session data.
  # def cancel
  #   super
  # end

  # protected

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_sign_up_params
  #   devise_parameter_sanitizer.permit(:sign_up, keys: [:attribute])
  # end

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_account_update_params
  #   devise_parameter_sanitizer.permit(:account_update, keys: [:attribute])
  # end

  # The path used after sign up.
  # def after_sign_up_path_for(resource)
  #   super(resource)
  # end

  # The path used after sign up for inactive accounts.
  # def after_inactive_sign_up_path_for(resource)
  #   super(resource)
  # end
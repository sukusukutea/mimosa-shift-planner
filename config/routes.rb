Rails.application.routes.draw do
  get "base_weekday_requirements/show"
  get "base_weekday_requirements/edit"
  devise_for :users, controllers: {
    registrations: "users/registrations"
  }

  root to: "pages#home"
  get "dashboard", to: "dashboards#index"
  resources :staffs, only: [ :index, :new, :create, :edit, :update, :destroy ] do
    member do
      patch :leave
      patch :restore
    end
  end

  resources :shift_months, only: [ :new, :create, :destroy, :show ] do
    member do
      get :settings             # /shift_months/:id/settings
      patch :update_settings    # /shift_months/:id/update_settings

      patch :update_weekday_requirements
      post :sync_weekday_requirements
      patch :update_daily

      post :update_designation
      delete :remove_designation

      post :bulk_add_staff_holidays
      delete :remove_staff_holiday

      post :generate_draft      # シフト案生成→previewへ
      get  :preview             # シフト案表示ページへ
      get  :edit_draft
      post :confirm_draft       # 確定してDB保存
      post :start_edit_from_confirmed # showページから手修正へ移動
      patch :update_draft_assignment

      post :add_month_time_option
      patch :set_default_month_time_option
      delete :remove_month_time_option
      get :export_excel
    end
  end

  resource :base_weekday_requirements, only: [ :show, :edit, :update ]
end

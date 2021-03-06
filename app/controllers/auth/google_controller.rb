class Auth::GoogleController < ApplicationController

  def google
    access_token = request.env['omniauth.auth']['credentials']['token']
    name, email, google_id = GoogleIntegration::Profile.fetch_name_email_and_google_id(access_token)
    if session[:role].present?
      google_sign_up(name, email, session[:role], access_token, google_id)
    else
      google_login(email, access_token, google_id)
    end
  end


  private

  def google_login(email, access_token, google_id)
    user = User.find_by(email: email.downcase)
    if user.present?
      user.google_id ? nil : user.update(google_id: google_id)
      sign_in(user)
      TestForEarnedCheckboxesWorker.perform_async(user.id)
      GoogleIntegration::Classroom::Main.pull_and_save_data(user, access_token)
      redirect_to profile_path
    else
      redirect_to new_account_path
    end
  end


  def google_sign_up(name, email, role, access_token, google_id)
    user = User.find_or_initialize_by(email: email.downcase)
    if user.new_record?
      user.attributes = {signed_up_with_google: true, name: name, role: role, google_id: google_id}
      user.save
      sign_in(user)
      ip = request.remote_ip
      GoogleIntegration::Classroom::Main.pull_and_save_data(user, access_token)
      AccountCreationCallbacks.new(user, ip).trigger
      user.subscribe_to_newsletter
      if user.role == 'teacher'
        @js_file = 'session'
        @teacherFromGoogleSignUp = true
        render 'accounts/new'
        return
      end
    end
    if user.errors.any?
      redirect_to new_account_path
      return
    else
      user.update(signed_up_with_google: true)
      GoogleIntegration::Classroom::Main.pull_and_save_data(user, access_token)
      redirect_to profile_path
      return
    end
  end

end

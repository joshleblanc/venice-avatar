class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Authentication
  after_action :verify_authorized

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
end

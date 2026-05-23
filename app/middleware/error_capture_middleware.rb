class ErrorCaptureMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  rescue => exception
    ErrorNotifier.capture(exception, env)
    raise
  end
end

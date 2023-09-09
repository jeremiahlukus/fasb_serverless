Jets.application.configure do
  # Example:
  # config.function.memory_size = 1536
   config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }
  # config.action_mailer.raise_delivery_errors = false
  # Docs: http://rubyonjets.com/docs/email-sending/
end

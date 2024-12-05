require_relative "simple_unique_jobs/version"
require_relative "simple_unique_jobs/client_middleware"
require_relative "simple_unique_jobs/server_middleware"

module SimpleUniqueJobs
  class << self
    def setup
      Sidekiq.configure_server do |config|
        config.server_middleware do |chain|
          chain.add ServerMiddleware
        end

        config.client_middleware do |chain|
          chain.add ClientMiddleware
        end
      end

      Sidekiq.configure_client do |config|
        config.client_middleware do |chain|
          chain.add ClientMiddleware
        end
      end
    end
  end
end

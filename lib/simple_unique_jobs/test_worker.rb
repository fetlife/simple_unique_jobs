require 'sidekiq'

module SimpleUniqueJobs
  class TestWorker
    include Sidekiq::Worker

    sidekiq_options queue: "test", custom: "custom", lock_timeout: 10

    def perform
      $stderr.puts "TestWorker"
    end
  end
end

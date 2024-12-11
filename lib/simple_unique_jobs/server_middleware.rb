# frozen_string_literal: true

require "sidekiq"
require_relative "lock"

module SimpleUniqueJobs
  class ServerMiddleware
    include Sidekiq::ServerMiddleware

    def call(_job_instance, job_payload, _queue, &)
      return yield unless job_payload.key?('unique_key')

      lock = Lock.new(job_payload, Sidekiq.redis_pool)
      lock.unlock_enqueue
      lock.if_runnable(&)
    end
  end
end

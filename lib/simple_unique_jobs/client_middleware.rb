# frozen_string_literal: true

require "sidekiq"
require_relative "lock"

module SimpleUniqueJobs
  class ClientMiddleware
    include Sidekiq::ClientMiddleware

    def call(_worker, job, _queue, redis_pool, &)
      Lock.new(job, redis_pool).if_enqueueable(&)
    end
  end
end

# SimpleUniqueJobs

A much, much simpler version of the (great) `sidekiq-unique-jobs` gem.

We built this because we need a simple way to ensure that only one job is
enqueued and/or running at a given time, but also do this at a scale where
there can be millions of enqueued jobs.

The gem above is overkill for our needs, and has scaling issues; in particular
it requires reaping, and that is an O(n²) operation.

Configuration: a single sidekiq_option key, `unique_for`, with subkeys:
- `queued`: (seconds) how long this job can stay enqueued before it can be
  enqueued again. Default 0 (disabled).
- `running`: (seconds) how long a job can run before it can be executed again.
  Default 0 (disabled).
- `timeout`: (boolean) when set, the `running` timeout will be applied, and an
  exception will be raised if the job takes too long. Default false.

Example:

```ruby
class MyJob
  include Sidekiq::Worker
  sidekiq_options unique_for: { queued: 300, running: 10 }

  def perform
    # ...
  end
end
```

If `queued` is enabled, only one job with the same class and arguments can be
enqueued at a time. Tentative duplicate enqueus will be cancelled without
error. If `running` is enabled, only one job with the same class and arguments
can be running at a time. Tentative duplicate runs will be aborted without
error. Both can be combined.

Redis data model:
- `unique:q:{classname}:{hash}`: (string) present while the job is enqueued
- `unique:r:{classname}:{hash}`: (string) present while the job is running

Only the `SET` and `DEL` commands are used.

Those keys have TTLs based on the configuration. It is recommended to set
"maxmemory-policy" to "volatile-ttl" to avoid memory leaks, as the keys _may_
exceptionally not get cleared if workers fail.


## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add simple_unique_jobs

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install simple_unique_jobs

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/fetlife/simple_unique_jobs.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

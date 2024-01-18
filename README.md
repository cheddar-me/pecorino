# Pecorino

Pecorino is a rate limiter based on the concept of leaky buckets. It uses your DB as the storage backend for the throttles. It is compact, easy to install, and does not require additional infrastructure. The approach used by Pecorino has been previously used by [prorate](https://github.com/WeTransfer/prorate) with Redis, and that approach has proven itself.

Pecorino is designed to integrate seamlessly into any Rails application using a PostgreSQL or SQLite database (at the moment there is no MySQL support, we would be delighted if you could add it).

If you would like to know more about the leaky bucket algorithm: [this article](http://live.julik.nl/2022/08/the-unreasonable-effectiveness-of-leaky-buckets) or the [Wikipedia article](https://en.wikipedia.org/wiki/Leaky_bucket) are both good starting points.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'pecorino'
```

And then execute:

    $ bundle install
    $ bin/rails g pecorino:install
    $ bin/rails db:migrate

## Usage

Once the installation is done you can use Pecorino to start defining your throttles. Imagine you have a resource called `vault` and you want to limit the number of updates to it to 5 per second. To achieve that, instantiate a new `Throttle` in your controller or job code, and then trigger it using `Throttle#request!`. A call to `request!` registers 1 token getting added to the bucket. If the bucket is full, or the throttle is currently in "block" mode (has recently been triggered), a `Pecorino::Throttle::Throttled` exception will be raised.

```ruby
throttle = Pecorino::Throttle.new(key: "vault", over_time: 1, capacity: 5)
throttle.request!
```
In a Rails controller you can then rescue from this exception to render the appropriate response:

```ruby
rescue_from Pecorino::Throttle::Throttled do |e|
  response.set_header('Retry-After', e.retry_after.to_s)
  render nothing: true, status: 429
end
```

and in a Rack application you can rescue inline:

```ruby
def call(env)
  # ...your code
rescue Pecorino::Throttle::Throttled => e
  [429, {"Retry-After" => e.retry_after.to_s}, []]
end
```

The exception has an attribute called `retry_after` which you can use to render the appropriate 429 response.

Although this approach might be susceptible to race conditions, you can interrogate your throttle before potentially causing an exception - and display an appropriate error message if the throttle would trigger anyway:

```ruby
return render :capacity_exceeded unless throttle.able_to_accept?
```

If you are dealing with a metered resource (like throughput, money, amount of storage...) you can supply the number of tokens to either `request!` or `able_to_accept?` to indicate the desired top-up of the leaky bucket. For example, if you are maintaining user wallets and want to ensure no more than 100 dollars may be taken from the wallet within a certain amount of time, you can do it like so:

```ruby
throttle = Pecorino::Throttle.new(key: "wallet_t_#{current_user.id}", over_time_: 1.hour, capacity: 100, block_for: 60*60*3)
throttle.request!(20) # Attempt to withdraw 20 dollars
throttle.request!(20) # Attempt to withdraw 20 dollars more
throttle.request!(20) # Attempt to withdraw 20 dollars more
throttle.request!(20) # Attempt to withdraw 20 dollars more
throttle.request!(20) # Attempt to withdraw 20 dollars more
throttle.request!(2) # Attempt to withdraw 2 dollars more, will raise `Throttled` and block withdrawals for 3 hours
```

Sometimes you don't want to use a throttle, but you want to track the amount added to the leaky bucket over time. A lower-level abstraction is available for that purpose in the form of the `LeakyBucket` class. It will not raise any exceptions and will not install blocks, but will permit you to track a bucket's state over time:


```ruby
b = Pecorino::LeakyBucket.new(key: "some_b", capacity: 100, leak_rate: 1)
b.fillup(2) #=> Pecorino::LeakyBucket::State(full?: false, level: 2.0)
sleep 0.2
b.state #=> Pecorino::LeakyBucket::State(full?: false, level: 1.8)
```

Check out the inline YARD documentation for more options.

## Cleaning out stale locks from the database

We recommend running the following bit of code every couple of hours (via cron or similar) to delete the stale blocks and leaky buckets from the system:

```ruby
Pecorino.prune!
```

## Using unlogged tables for reduced replication load (PostgreSQL)

Throttles and leaky buckets are transient resources. If you are using Postgres replication, it might be prudent to set the Pecorino tables to `UNLOGGED` which will exclude them from replication - and save you bandwidth and storage on your RR. To do so, add the following statements to your migration:

```ruby
ActiveRecord::Base.connection.execute("ALTER TABLE pecorino_leaky_buckets SET UNLOGGED")
ActiveRecord::Base.connection.execute("ALTER TABLE pecorino_blocks SET UNLOGGED")
```

## Development

After checking out the repo, run `bundle`. Then, run `rake test` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/cheddar-me/pecorino. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/cheddar-me/pecorino/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Pecorino project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/cheddar-me/pecorino/blob/main/CODE_OF_CONDUCT.md).

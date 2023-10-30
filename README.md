# Raclette

Raclette is a rate limiter based on the concept of leaky buckets. It uses your DB as the storage backend for the throttles. It is compact, easy to install, and does not require additional infrastructure. The approach used by Raclette has been previously used by [prorate](https://github.com/WeTransfer/prorate) with Redis, and that approach has proven itself.

Raclette is designed to integrate seamlessly into any Rails application using a Postgres database (at the moment there is no MySQL support, we would be delighted if you could add it).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'raclette'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install raclette

## Usage

First, add and run the migration to create the raclette tables:

    $ bin/rails g raclette:install
    $ bin/rails db:migrate

Once that is done, you can use Raclette to start defining your throttles. Imagine you have a resource called `vault` and you want to limit the number of updates to it to 5 per second. To achieve that, instantiate a new `Throttle` in your controller or job code, and then trigger it using `Throttle#request!`. A call to `request!` registers 1 token getting added to the bucket. If the bucket is full, or the throttle is currently in "block" mode (has recently been triggered), a `Raclette::Throttle::Throttled` exception will be raised.

```ruby
throttle = Raclette::Throttle.new(key: "vault", leak_rate: 5, capacity: 5)
throttle.request!
```

The exception has an attribute called `retry_after` which you can use to render the appropriate 429 response.

Although this approach might be susceptible to race conditions, you can interrogate your throttle before potentially causing an exception - and display an appropriate error message if the throttle would trigger anyway:

```ruby
return render :capacity_exceeded unless throttle.able_to_accept?
```

If you are dealing with a metered resource (like throughput, money, amount of storage...) you can supply the number of tokens to either `request!` or `able_to_accept?` to indicate the desired top-up of the leaky bucket. For example, if you are maintaining user wallets and want to ensure no more than 100 dollars may be taken from the wallet within a certain amount of time, you can do it like so:

```ruby
throttle = Raclette::Throttle.new(key: "wallet_t_#{current_user.id}", leak_rate: 100 / 60.0 / 60.0, capacity: 100, block_for: 60*60*3)
throttle.request!(20) # Attempt to withdraw 20 dollars
throttle.request!(20) # Attempt to withdraw 20 dollars more
throttle.request!(20) # Attempt to withdraw 20 dollars more
throttle.request!(20) # Attempt to withdraw 20 dollars more
throttle.request!(20) # Attempt to withdraw 20 dollars more
throttle.request!(2) # Attempt to withdraw 2 dollars more, will raise `Throttled` and block withdrawals for 3 hours
```

Sometimes you don't want to use a throttle, but you want to track the amount added to the leaky bucket over time. If this is what you need, you can use the `LeakyBucket` class:

```ruby
b = Raclette::LeakyBucket.new(key: "some_b", capacity: 100, leak_rate: 5)
b.fillup(2) #=> Raclette::LeakyBucket::State(full?: false, level: 2.0)
sleep 0.2
b.state #=> Raclette::LeakyBucket::State(full?: false, level: 1.8)
```

Check out the inline YARD documentation for more options.

## Cleaning out stale locks from the database

We recommend running the following bit of code every couple of hours (via cron or similar) to delete the stale blocks and leaky buckets from the system:

    Raclette.prune!

## Development

After checking out the repo, run `bundle. Then, run `rake test` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/julik/raclette. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/julik/raclette/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Raclette project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/julik/raclette/blob/main/CODE_OF_CONDUCT.md).

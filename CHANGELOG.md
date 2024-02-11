- Add `Throttle#throttled` for silencing alerts
- **BREAKING CHANGE** Remove `Throttle::State#retry_after`, because there is no reasonable value for that member if the throttle is not in the "blocked" state
- Allow accessing `Throttle::State` from the `Throttled` exception so that the blocked throttle state can be cached downstream (in Rails cache, for example)
- Make `Throttle#request!` return the new state if there was no exception raised

## [0.4.1] - 2024-02-11

- Make sure Pecorino works on Ruby 2.7 as well by removing 3.x-exclusive syntax

## [0.4.0] - 2024-01-22

- Use Bucket#connditional_fillup inside Throttle and throttle only when the capacity _would_ be exceeded, as opposed
  to throttling when capacity has already been exceeded. This allows for finer-grained throttles such as
  "at most once in", where filling "exactly to capacity" is a requirement. It also provides for more accurate
  and easier to understand throttling in general.
- Make sure Bucket#able_to_accept? allows the bucket to be filled to capacity, not only to below capacity
- Improve YARD documentation
- Allow "conditional fillup" - only add tokens to the leaky bucket if the bucket has enough space.
- Fix `over_time` leading to incorrect `leak_rate`. The divider/divisor were swapped, leading to the inverse leak rate getting computed.

## [0.3.0] - 2024-01-18

- Allow `over_time` in addition to `leak_rate`, which is a more intuitive parameter to tweak
- Set default `block_for` to the time it takes the bucket to leak out completely instead of 30 seconds

## [0.2.0] - 2024-01-09

- [Add support for SQLite](https://github.com/cheddar-me/pecorino/pull/9)
- [Use comparisons in SQL to determine whether the leaky bucket did overflow](https://github.com/cheddar-me/pecorino/pull/8)
- [Change the way Structs are defined to appease Tapioca/Sorbet](https://github.com/cheddar-me/pecorino/pull/6)

## [0.1.0] - 2023-10-30

- Initial release

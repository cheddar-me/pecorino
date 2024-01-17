- Allow `over_time` in addition to `leak_rate`, which is a more intuitive parameter to tweak
- Set default `block_for` to the time it takes the bucket to leak out completely instead of 30 seconds

## [0.2.0] - 2024-01-09

- [Add support for SQLite](https://github.com/cheddar-me/pecorino/pull/9)
- [Use comparisons in SQL to determine whether the leaky bucket did overflow](https://github.com/cheddar-me/pecorino/pull/8)
- [Change the way Structs are defined to appease Tapioca/Sorbet](https://github.com/cheddar-me/pecorino/pull/6)

## [0.1.0] - 2023-10-30

- Initial release

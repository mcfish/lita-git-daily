# lita-git-daily

TODO: Add a description of the plugin.

## Installation

Add lita-git-daily to your Lita instance's Gemfile:

``` ruby
gem "lita-git-daily"
```

## Configuration

``` ruby
Lita.configure do |config|
  config.handlers.git_daily.channel_config = {
    "CHANNNELID" => {
      :repos  => "/path/to/repository/",
      :github => "https://github.com/path/to/commit/",
    },
  }
end
```

## Usage

TODO: Describe the plugin's features and how to use them.

## License

[MIT](http://opensource.org/licenses/MIT)

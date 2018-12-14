# moebot

A bot that will follow accounts and like posts linked to certain hashtags of interest on [Instagram](https://www.instagram.com).

## Setup

Make sure you have Ruby and Bundler installed.

## User manual

Start the bot:
```
❯ ./instagram_daemon -p YOUR_PASSWORD -u YOUR_USERNAME -h hashtag1,hashtag2,...,hashtagN
Running instagram bot in process ID 2186
```

Tail the logs:
```
❯ tail -f instagram.log
I, [2018-12-11T10:19:13.837689 #21862]  INFO -- : ---------------------------------------------------------------------------
I, [2018-12-11T10:19:13.838933 #21862]  INFO -- : Initialized Instagram bot for moechaieb.
I, [2018-12-11T10:19:13.839319 #21862]  INFO -- : User agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_2) AppleWebKit/601.3.9 (KHTML, like Gecko) Version/9.0.2 Safari/601.3.9
I, [2018-12-11T10:19:13.839579 #21862]  INFO -- : Hashtags: ["mileend", "musicproduction", "torontomusic", "torontoproducers", "producerlife", "homestudio", "nativeinstruments", "kompletekontrol", "maschine", "torontornb", "instaminim", "minimalninja"]
I, [2018-12-11T10:19:13.839805 #21862]  INFO -- : Like limit per iteration: 10, Follow limit per iteration: 10
I, [2018-12-11T10:19:13.840108 #21862]  INFO -- : ---------------------------------------------------------------------------
```

Terminate the bot:
```
❯ ps -o pid,command | grep instagram
14004 ruby ./instagram_daemon -p [REDACTED] -u [REDACTED] -h mileend,musicproduction,torontomusic

❯ kill -SIGTERM 14004
```

### Copyright

Copyright © 2018 Mohamed Adam Chaieb

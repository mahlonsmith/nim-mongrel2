# README #

### What's this? ###

This module implements a basic framework for interacting with the
Mongrel2 webserver. (http://mongrel2.org).


### Installation ###

The easiest way to install this module is via the nimble package manager, 
by simply running 'nimble install mongrel2'.

Alternatively, you can fetch the 'mongrel2.nim' file yourself, and put it in a place of your choosing.

### Usage ###

The "bare minimum" required for testing your Mongrel2 configuration is
nearly a one-liner.

```
#!nimrod
import mongrel2
newM2Handler( "app-id", "tcp://127.0.0.1:9009", "tcp://127.0.0.1:9008" ).run
```

Assuming your Mongrel2 server is configured correctly, you should be
able to steer a browser to your handler to see a helpful message.

To do anything more complex, you'll want to look at the module
documentation.  Here's a "hello world":

```
#!nimrod
let handler = newM2Handler( "app-id", "tcp://127.0.0.1:9009", "tcp://127.0.0.1:9008" )

proc hello_world( request: M2Request ): M2Response =
    result = request.response
    result[ "Content-Type" ] = "text/plain"
    result.body = "Hello there, world!"
    result.status = HTTP_OK

handler.action = hello_world
handler.run
```

This module would be suitable to build a more elaborate framework
around, such as Ruby's "Strelka" (https://github.com/ged/strelka).  I
may eventually look into integration with Jasper, as well.


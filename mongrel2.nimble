
# Package

version       = "0.1.1"
author        = "Mahlon E. Smith <mahlon@martini.nu>"
description   = "Simplistic handler framework for the Mongrel2 webserver."
license       = "MIT"
installExt    = @["nim"]
srcDir        = "src"


# Dependencies

requires "nim >= 0.19.0"
requires "tnetstring >= 0.1.1"
requires "zmq >= 0.2.1"


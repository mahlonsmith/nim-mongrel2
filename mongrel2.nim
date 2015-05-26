#
# Copyright (c) 2015, Mahlon E. Smith <mahlon@martini.nu>
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#
#     * Neither the name of Mahlon E. Smith nor the names of his
#       contributors may be used to endorse or promote products derived
#       from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE REGENTS AND CONTRIBUTORS BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## This module is a simple interface to the Mongrel2 webserver
## environment (http://mongrel2.org/).  After a Mongrel2 server has been
## properly configured, you can use this library to easily service client
## requests.
##
## Bare minimal, do-nothing example:
##
## .. code-block:: nim
##
##    newM2Handler( "app-id", "tcp://127.0.0.1:9009", "tcp://127.0.0.1:9008" ).run
##
## Yep, that's it.  Assuming your Mongrel2 server is configured with a
## matching application identifier and request/response communication
## ports, that's enough to see the default output from the handler when
## loaded in browser.
##
## It's likely that you'll want to do something of more substance.  This
## is performed via an `action` hook, which is just a proc() reference.
## It is passed the parsed `M2Request` client request, and it needs to
## return a matching `M2Response` object.  What happens in between is
## entirely up to you.
##
## Here's a "hello world":
##
## .. code-block:: nim
##
##    let handler = newM2Handler( "app-id", "tcp://127.0.0.1:9009", "tcp://127.0.0.1:9008" )
##    
##    proc hello_world( request: M2Request ): M2Response =
##        result = request.response
##        result[ "Content-Type" ] = "text/plain"
##        result.body = "Hello there, world!"
##        result.status = HTTP_OK
##    
##    handler.action = hello_world
##    handler.run
##    
## And finally, a slightly more interesting example:
##
## .. code-block:: nim
##
##   import
##       mongrel2,
##       json,
##       re
##   
##   let handler = newM2Handler( "app-id", "tcp://127.0.0.1:9009", "tcp://127.0.0.1:9008" )
##   var data    = %*[] ## the JSON data to "remember"
##   
##   
##   proc demo( request: M2Request ): M2Response =
##       ## This is a demonstration handler action.
##       ##
##       ## It accepts and stores a JSON data structure
##       ## on POST, and returns it on GET.
##   
##       # Create a response object for the current request.
##       var response = request.response
##   
##       case request.meth
##   
##       # For GET requests, display the current JSON structure.
##       #
##       of "GET":
##           if request[ "Accept" ].match( re(".*text/(html|plain).*") ):
##               response[ "Content-Type" ] = "text/plain"
##               response.body   = "Hi there.  POST some JSON to me and I'll remember it.\n\n" & $( data )
##               response.status = HTTP_OK
##   
##           elif request[ "Accept" ].match( re("application/json") ):
##               response[ "Content-Type" ] = "application/json"
##               response.body   = $( data )
##               response.status = HTTP_OK
##   
##           else:
##               response.status = HTTP_BAD_REQUEST
##   
##       # POST requests overwrite the current JSON structure.
##       #
##       of "POST":
##           if request[ "Content-Type" ].match( re(".*application/json.*") ):
##               try:
##                   data = request.body.parse_json
##                   response.status = HTTP_OK
##                   response[ "Content-Type" ] = "application/json"
##                   response.body = $( data )
##               except:
##                   response.status = HTTP_BAD_REQUEST
##                   response[ "Content-Type" ] = "text/plain"
##                   response.body = request.body
##   
##           else:
##               response.body   = "I only accept valid JSON strings."
##               response.status = HTTP_BAD_REQUEST
##   
##       else:
##           response.status = HTTP_NOT_ACCEPTABLE
##   
##       return response
##   
##   
##   # Attach the proc reference to the handler action.
##   handler.action = demo
##   
##   # Start 'er up!
##   handler.run
##


import
    json,
    strutils,
    tables,
    times,
    tnetstring,
    zmq

type
    M2Handler* = ref object of RootObj
        handler_id:         string
        request_sock:       TConnection
        response_sock:      TConnection
        action*:            proc ( request: M2Request ): M2Response
        disconnect_action*: proc ( request: M2Request )

    M2Request* = ref object of RootObj
        sender_id*:   string  ## Mongrel2 app-id
        conn_id*:     string
        path*:        string
        meth*:        string
        version*:     string
        uri*:         string
        pattern*:     string
        scheme*:      string
        remote_addr*: string
        query*:       string
        headers*:     seq[ tuple[name: string, value: string] ]
        body*:        string 

    M2Response* = ref object of RootObj
        sender_id*: string
        conn_id*:   string
        status*:    int
        headers*:   seq[ tuple[name: string, value: string] ]
        body*:      string 
        extended:   string
        ex_data:    seq[ string ]

const 
    MAX_CLIENT_BROADCAST = 128 ## The maximum number of client to broadcast a response to
    CRLF = "\r\n"              ## Network line ending
    DEFAULT_CONTENT = """
<!DOCTYPE html>
<html lang="en">
    <head>
        <title>It works!</title>
        <link href='http://fonts.googleapis.com/css?family=Play' rel='stylesheet' type='text/css'>
        <style>
        body {
            margin: 50px;
            height: 100%;
            background-color: #ddd;
            font-family: Play, Arial, serif;
            font-weight: 400;
            background: linear-gradient( to bottom, #7db9e8 25%,#fff 100% );
        }
        a, a:hover, a:visited {
            text-decoration: none;
            color: rgb( 66,131,251 );
        }
        .content {
            font-size: 1.2em;
            border-radius: 10px;
            margin: 0 auto 0 auto;
            width: 50%;
            padding: 5px 20px 20px 20px;
            box-shadow: 1px 2px 6px #000;
            background-color: #fff;
            border: 1px;
        }
        .handler {
            font-size: 0.9em;
            padding: 2px 0 0 10px;
            color: rgb( 192,220,255 );
            background-color: rgb( 6,20,85 );
            border: 2px solid rgb( 66,131,251 );
        }
        </style>
    </head>
    <body>
        <div class="content">
            <h1>Almost there...</h1>
            <p>
                This is the default handler output.  While this is
                useful to demonstrate that your <a href="http://mongrel2.org">Mongrel2</a>
                server is indeed speaking to your <a href="http://nim-lang.org">nim</a>
                handler, you're probably going to want to do something else for production use.
            </p>
            <p>
                Here's an example handler:
            </p>

            <div class="handler">
            <pre>
import
    mongrel2,
    json,
    re

let handler = newM2Handler( "app-id", "tcp://127.0.0.1:9009", "tcp://127.0.0.1:9008" )
var data    = %*[] ## the JSON data to "remember"


proc demo( request: M2Request ): M2Response =
    ## This is a demonstration handler action.
    ##
    ## It accepts and stores a JSON data structure
    ## on POST, and returns it on GET.

    # Create a response object for the current request.
    var response = request.response

    case request.meth

    # For GET requests, display the current JSON structure.
    #
    of "GET":
        if request[ "Accept" ].match( re(".*text/(html|plain).*") ):
            response[ "Content-Type" ] = "text/plain"
            response.body   = "Hi there.  POST some JSON to me and I'll remember it.\n\n" & $( data )
            response.status = HTTP_OK

        elif request[ "Accept" ].match( re("application/json") ):
            response[ "Content-Type" ] = "application/json"
            response.body   = $( data )
            response.status = HTTP_OK

        else:
            response.status = HTTP_BAD_REQUEST

    # Overwrite the current JSON structure.
    #
    of "POST":
        if request[ "Content-Type" ].match( re(".*application/json.*") ):
            try:
                data = request.body.parse_json
                response.status = HTTP_OK
                response[ "Content-Type" ] = "application/json"
                response.body = $( data )
            except:
                response.status = HTTP_BAD_REQUEST
                response[ "Content-Type" ] = "text/plain"
                response.body = request.body

        else:
            response.body   = "I only accept valid JSON strings."
            response.status = HTTP_BAD_REQUEST

    else:
        response.status = HTTP_NOT_ACCEPTABLE

    return response


# Attach the proc reference to the handler action.
handler.action = demo

# Start 'er up!
handler.run
            </pre>
            </div>
        </div>
    </body>
</html>
    """

    HTTP_CONTINUE*                      = 100
    HTTP_SWITCHING_PROTOCOLS*           = 101
    HTTP_PROCESSING*                    = 102
    HTTP_OK*                            = 200
    HTTP_CREATED*                       = 201
    HTTP_ACCEPTED*                      = 202
    HTTP_NON_AUTHORITATIVE*             = 203
    HTTP_NO_CONTENT*                    = 204
    HTTP_RESET_CONTENT*                 = 205
    HTTP_PARTIAL_CONTENT*               = 206
    HTTP_MULTI_STATUS*                  = 207
    HTTP_MULTIPLE_CHOICES*              = 300
    HTTP_MOVED_PERMANENTLY*             = 301
    HTTP_MOVED*                         = 301
    HTTP_MOVED_TEMPORARILY*             = 302
    HTTP_REDIRECT*                      = 302
    HTTP_SEE_OTHER*                     = 303
    HTTP_NOT_MODIFIED*                  = 304
    HTTP_USE_PROXY*                     = 305
    HTTP_TEMPORARY_REDIRECT*            = 307
    HTTP_BAD_REQUEST*                   = 400
    HTTP_AUTH_REQUIRED*                 = 401
    HTTP_UNAUTHORIZED*                  = 401
    HTTP_PAYMENT_REQUIRED*              = 402
    HTTP_FORBIDDEN*                     = 403
    HTTP_NOT_FOUND*                     = 404
    HTTP_METHOD_NOT_ALLOWED*            = 405
    HTTP_NOT_ACCEPTABLE*                = 406
    HTTP_PROXY_AUTHENTICATION_REQUIRED* = 407
    HTTP_REQUEST_TIME_OUT*              = 408
    HTTP_CONFLICT*                      = 409
    HTTP_GONE*                          = 410
    HTTP_LENGTH_REQUIRED*               = 411
    HTTP_PRECONDITION_FAILED*           = 412
    HTTP_REQUEST_ENTITY_TOO_LARGE*      = 413
    HTTP_REQUEST_URI_TOO_LARGE*         = 414
    HTTP_UNSUPPORTED_MEDIA_TYPE*        = 415
    HTTP_RANGE_NOT_SATISFIABLE*         = 416
    HTTP_EXPECTATION_FAILED*            = 417
    HTTP_UNPROCESSABLE_ENTITY*          = 422
    HTTP_LOCKED*                        = 423
    HTTP_FAILED_DEPENDENCY*             = 424
    HTTP_UPGRADE_REQUIRED*              = 426
    HTTP_RECONDITION_REQUIRED*          = 428
    HTTP_TOO_MANY_REQUESTS*             = 429
    HTTP_REQUEST_HEADERS_TOO_LARGE*     = 431
    HTTP_SERVER_ERROR*                  = 500
    HTTP_NOT_IMPLEMENTED*               = 501
    HTTP_BAD_GATEWAY*                   = 502
    HTTP_SERVICE_UNAVAILABLE*           = 503
    HTTP_GATEWAY_TIME_OUT*              = 504
    HTTP_VERSION_NOT_SUPPORTED*         = 505
    HTTP_VARIANT_ALSO_VARIES*           = 506
    HTTP_INSUFFICIENT_STORAGE*          = 507
    HTTP_NOT_EXTENDED*                  = 510

    HTTPCODE = {
        HTTP_CONTINUE:                      ( desc: "Continue",                        label: "CONTINUE" ),
        HTTP_SWITCHING_PROTOCOLS:           ( desc: "Switching Protocols",             label: "SWITCHING_PROTOCOLS" ),
        HTTP_PROCESSING:                    ( desc: "Processing",                      label: "PROCESSING" ),
        HTTP_OK:                            ( desc: "OK",                              label: "OK" ),
        HTTP_CREATED:                       ( desc: "Created",                         label: "CREATED" ),
        HTTP_ACCEPTED:                      ( desc: "Accepted",                        label: "ACCEPTED" ),
        HTTP_NON_AUTHORITATIVE:             ( desc: "Non-Authoritative Information",   label: "NON_AUTHORITATIVE" ),
        HTTP_NO_CONTENT:                    ( desc: "No Content",                      label: "NO_CONTENT" ),
        HTTP_RESET_CONTENT:                 ( desc: "Reset Content",                   label: "RESET_CONTENT" ),
        HTTP_PARTIAL_CONTENT:               ( desc: "Partial Content",                 label: "PARTIAL_CONTENT" ),
        HTTP_MULTI_STATUS:                  ( desc: "Multi-Status",                    label: "MULTI_STATUS" ),
        HTTP_MULTIPLE_CHOICES:              ( desc: "Multiple Choices",                label: "MULTIPLE_CHOICES" ),
        HTTP_MOVED_PERMANENTLY:             ( desc: "Moved Permanently",               label: "MOVED_PERMANENTLY" ),
        HTTP_MOVED:                         ( desc: "Moved Permanently",               label: "MOVED" ),
        HTTP_MOVED_TEMPORARILY:             ( desc: "Found",                           label: "MOVED_TEMPORARILY" ),
        HTTP_REDIRECT:                      ( desc: "Found",                           label: "REDIRECT" ),
        HTTP_SEE_OTHER:                     ( desc: "See Other",                       label: "SEE_OTHER" ),
        HTTP_NOT_MODIFIED:                  ( desc: "Not Modified",                    label: "NOT_MODIFIED" ),
        HTTP_USE_PROXY:                     ( desc: "Use Proxy",                       label: "USE_PROXY" ),
        HTTP_TEMPORARY_REDIRECT:            ( desc: "Temporary Redirect",              label: "TEMPORARY_REDIRECT" ),
        HTTP_BAD_REQUEST:                   ( desc: "Bad Request",                     label: "BAD_REQUEST" ),
        HTTP_AUTH_REQUIRED:                 ( desc: "Authorization Required",          label: "AUTH_REQUIRED" ),
        HTTP_UNAUTHORIZED:                  ( desc: "Authorization Required",          label: "UNAUTHORIZED" ),
        HTTP_PAYMENT_REQUIRED:              ( desc: "Payment Required",                label: "PAYMENT_REQUIRED" ),
        HTTP_FORBIDDEN:                     ( desc: "Forbidden",                       label: "FORBIDDEN" ),
        HTTP_NOT_FOUND:                     ( desc: "Not Found",                       label: "NOT_FOUND" ),
        HTTP_METHOD_NOT_ALLOWED:            ( desc: "Method Not Allowed",              label: "METHOD_NOT_ALLOWED" ),
        HTTP_NOT_ACCEPTABLE:                ( desc: "Not Acceptable",                  label: "NOT_ACCEPTABLE" ),
        HTTP_PROXY_AUTHENTICATION_REQUIRED: ( desc: "Proxy Authentication Required",   label: "PROXY_AUTHENTICATION_REQUIRED" ),
        HTTP_REQUEST_TIME_OUT:              ( desc: "Request Time-out",                label: "REQUEST_TIME_OUT" ),
        HTTP_CONFLICT:                      ( desc: "Conflict",                        label: "CONFLICT" ),
        HTTP_GONE:                          ( desc: "Gone",                            label: "GONE" ),
        HTTP_LENGTH_REQUIRED:               ( desc: "Length Required",                 label: "LENGTH_REQUIRED" ),
        HTTP_PRECONDITION_FAILED:           ( desc: "Precondition Failed",             label: "PRECONDITION_FAILED" ),
        HTTP_REQUEST_ENTITY_TOO_LARGE:      ( desc: "Request Entity Too Large",        label: "REQUEST_ENTITY_TOO_LARGE" ),
        HTTP_REQUEST_URI_TOO_LARGE:         ( desc: "Request-URI Too Large",           label: "REQUEST_URI_TOO_LARGE" ),
        HTTP_UNSUPPORTED_MEDIA_TYPE:        ( desc: "Unsupported Media Type",          label: "UNSUPPORTED_MEDIA_TYPE" ),
        HTTP_RANGE_NOT_SATISFIABLE:         ( desc: "Requested Range Not Satisfiable", label: "RANGE_NOT_SATISFIABLE" ),
        HTTP_EXPECTATION_FAILED:            ( desc: "Expectation Failed",              label: "EXPECTATION_FAILED" ),
        HTTP_UNPROCESSABLE_ENTITY:          ( desc: "Unprocessable Entity",            label: "UNPROCESSABLE_ENTITY" ),
        HTTP_LOCKED:                        ( desc: "Locked",                          label: "LOCKED" ),
        HTTP_FAILED_DEPENDENCY:             ( desc: "Failed Dependency",               label: "FAILED_DEPENDENCY" ),
        HTTP_UPGRADE_REQUIRED:              ( desc: "Upgrade Required",                label: "UPGRADE_REQUIRED" ),
        HTTP_RECONDITION_REQUIRED:          ( desc: "Precondition Required",           label: "RECONDITION_REQUIRED" ),
        HTTP_TOO_MANY_REQUESTS:             ( desc: "Too Many Requests",               label: "TOO_MANY_REQUESTS" ),
        HTTP_REQUEST_HEADERS_TOO_LARGE:     ( desc: "Request Headers too Large",       label: "REQUEST_HEADERS_TOO_LARGE" ),
        HTTP_SERVER_ERROR:                  ( desc: "Internal Server Error",           label: "SERVER_ERROR" ),
        HTTP_NOT_IMPLEMENTED:               ( desc: "Method Not Implemented",          label: "NOT_IMPLEMENTED" ),
        HTTP_BAD_GATEWAY:                   ( desc: "Bad Gateway",                     label: "BAD_GATEWAY" ),
        HTTP_SERVICE_UNAVAILABLE:           ( desc: "Service Temporarily Unavailable", label: "SERVICE_UNAVAILABLE" ),
        HTTP_GATEWAY_TIME_OUT:              ( desc: "Gateway Time-out",                label: "GATEWAY_TIME_OUT" ),
        HTTP_VERSION_NOT_SUPPORTED:         ( desc: "HTTP Version Not Supported",      label: "VERSION_NOT_SUPPORTED" ),
        HTTP_VARIANT_ALSO_VARIES:           ( desc: "Variant Also Negotiates",         label: "VARIANT_ALSO_VARIES" ),
        HTTP_INSUFFICIENT_STORAGE:          ( desc: "Insufficient Storage",            label: "INSUFFICIENT_STORAGE" ),
        HTTP_NOT_EXTENDED:                  ( desc: "Not Extended",                    label: "NOT_EXTENDED" )
    }.toTable



proc newM2Handler*( id: string, req_sock: string, res_sock: string ): M2Handler =
    ## Instantiate a new `M2Handler` object.
    ## The `id` should match the app ID in the Mongrel2 config,
    ## `req_sock` is the ZMQ::PULL socket Mongrel2 sends client request
    ## data on, and `res_sock` is the ZMQ::PUB socket Mongrel2 subscribes
    ## to.  Nothing is put into action until the run() method is invoked.
    new( result )
    result.handler_id    = id
    result.request_sock  = zmq.connect( "tcp://127.0.0.1:9009", PULL )
    result.response_sock = zmq.connect( "tcp://127.0.0.1:9008", PUB )


proc parse_request( request: string ): M2Request =
    ## Parse a message `request` string received from Mongrel2,
    ## return it as a M2Request object.
    var
        reqstr     = request.split( ' ' )
        rest       = ""
        req_tnstr: TNetstringNode
        headers:   JsonNode

    new( result )
    result.sender_id = reqstr[ 0 ]
    result.conn_id   = reqstr[ 1 ]
    result.path      = reqstr[ 2 ]

    # There must be a better way to join() a seq...
    #
    for i in 3 .. reqstr.high:
        rest = rest & reqstr[ i ]
        if i < reqstr.high: rest = rest & ' '
    reqtnstr    = rest.parse_tnetstring
    result.body = reqtnstr.extra.parse_tnetstring.getStr("")

    # Pull Mongrel2 control headers into the request object.
    #
    headers = reqtnstr.getStr.parse_json

    if headers.has_key( "METHOD" ):
        result.meth = headers[ "METHOD" ].getStr
        headers.delete( "METHOD" )

    if headers.has_key( "PATTERN" ):
        result.pattern = headers[ "PATTERN" ].getStr
        headers.delete( "PATTERN" )

    if headers.has_key( "REMOTE_ADDR" ):
        result.remote_addr = headers[ "REMOTE_ADDR" ].getStr
        headers.delete( "REMOTE_ADDR" )

    if headers.has_key( "URI" ):
        result.uri = headers[ "URI" ].getStr
        headers.delete( "URI" )

    if headers.has_key( "URL_SCHEME" ):
        result.scheme = headers[ "URL_SCHEME" ].getStr
        headers.delete( "URL_SCHEME" )

    if headers.has_key( "VERSION" ):
        result.version = headers[ "VERSION" ].getStr
        headers.delete( "VERSION" )

    if headers.has_key( "QUERY" ):
        result.query = headers[ "QUERY" ].getStr
        headers.delete( "QUERY" )
    
    # Remaining headers are client supplied.
    #
    result.headers = @[]
    for key, val in headers:
        result.headers.add( ( key, val.getStr ) )


proc response*( request: M2Request ): M2Response =
    ## Instantiate a new `M2Response`, paired from an `M2Request`.
    new( result )
    result.sender_id = request.sender_id
    result.conn_id   = request.conn_id
    result.headers   = @[]


proc `[]`*( request: M2Request, label: string ): string =
    ## Defer to the underlying headers tuple array.  Lookup is case-insensitive.
    for header in request.headers:
        if cmpIgnoreCase( label, header.name ) == 0:
            return header.value
    return nil


proc is_disconnect*( request: M2Request ): bool =
    ## Returns true if this is a Mongrel2 disconnect request.
    if ( request.path == "@*" and request.meth == "JSON") :
        var body = request.body.parseJson
        if ( body.has_key( "type" ) and body[ "type" ].getStr == "disconnect" ):
            return true
    return false


proc `[]`*( response: M2Response, label: string ): string =
    ## Defer to the underlying headers tuple array.  Lookup is case-insensitive.
    for header in response.headers:
        if cmpIgnoreCase( label, header.name ) == 0:
            return header.value
    return nil


proc `[]=`*( response: M2Response, name: string, value: string ) =
    ## Set a header on the response.  Duplicates are replaced.
    var new_headers: seq[ tuple[name: string, value: string] ] = @[]
    for header in response.headers:
        if cmpIgnoreCase( name, header.name ) != 0:
            new_headers.add( header )
    response.headers = new_headers
    response.headers.add( (name, value) )


proc add_header*( response: M2Response, name: string, value: string ) =
    ## Adds a header to the response.  Duplicates are ignored.
    response.headers.add( (name, value) )


proc extend*( response: M2Response, filter: string ) =
    ## Set a response as extended.  This means different things depending on
    ## the Mongrel2 filter in use.
    response.extended = filter


proc add_extended_data*( response: M2Response, data: varargs[string, `$`] ) =
    ## Attach filter arguments to the extended response.  Arguments should
    ## be coercible into strings.
    if isNil( response.ex_data ): response.ex_data = @[]
    for arg in data:
        response.ex_data.add( arg )


proc is_extended*( response: M2Response ): bool =
    ## Predicate method to determine if a response is extended.
    return not isNil( response.extended )


proc broadcast*[T]( response: M2Response, ids: openarray[T] ) =
    ## Send the response to multiple backend client IDs.
    assert( ids.len <= MAX_CLIENT_BROADCAST, "Exceeded client broadcast maximum" )

    response.conn_id = $( ids[0] )
    for i in 1 .. ids.high:
        if i <= ids.high: response.conn_id = response.conn_id & ' '
        response.conn_id = response.conn_id & $( ids[i] )


proc format( response: M2Response ): string =
    ## Format an `M2Response` object for Mongrel2.
    var conn_id: string

    # Mongrel2 extended response.
    #
    if response.is_extended:
        conn_id = newTNetstringString( "X " & response.conn_id ).dump_tnetstring
        result = response.sender_id & ' ' & conn_id

        # 1st argument is the filter name.
        #
        var tnet_array = newTNetstringArray()
        tnet_array.add( newTNetstringString(response.extended) )

        # rest are the filter arguments, if any.
        #
        if not isNil( response.ex_data ):
            for data in response.ex_data:
                tnet_array.add( newTNetstringString(data) )

        result = result & ' ' & tnet_array.dump_tnetstring


    else:
        # Regular HTTP request/response cycle.
        #
        if isNil( response.body ):
            response.body = HTTPCODE[ response.status ].desc
            response[ "Content-Length" ] = $( response.body.len )
        else:
            response[ "Content-Length" ] = $( response.body.len )

        let code = "$1 $2" % [ $(response.status), HTTPCODE[response.status].label ]
        conn_id  = newTNetstringString( response.conn_id ).dump_tnetstring
        result   = response.sender_id & ' ' & conn_id
        result   = result & " HTTP/1.1 " & code & CRLF

        for header in response.headers:
            result = result & header.name & ": " & header.value & CRLF

        result = result & CRLF & response.body


proc handle_default( request: M2Request ): M2Response =
    ## This is the default handler, if the caller didn't install one.
    result                   = request.response
    result[ "Content-Type" ] = "text/html"
    result.body              = DEFAULT_CONTENT


proc run*( handler: M2Handler ) {. noreturn .} =
    ## Enter the request loop conversation with Mongrel2.
    ## If an action() proc is attached, run that to generate
    ## a response.  Otherwise, run the default.
    while true:
        var
            request:  M2Request
            response: M2Response
            info:     string

        request = parse_request( handler.request_sock.receive ) # block, waiting for next request

        # Ignore disconnects unless there's a separate
        # disconnect_action.
        #
        if request.is_disconnect:
            if not isNil( handler.disconnect_action ):
                discard handler.disconnect_action
            continue

        # Defer regular response content to the handler action.
        #
        if isNil( handler.action ):
            handler.action = handle_default
        response = handler.action( request )

        if response.status == 0: response.status = HTTP_OK

        if defined( testing ):
            echo "REQUEST:\n",  repr(request)
            echo "RESPONSE:\n", repr(response)

        info = "$1 $2 $3" % [
            request.remote_addr,
            request.meth,
            request.uri
        ]

        echo "$1: $2 --> $3 $4" % [
            $(get_localtime(getTime())),
            info,
            $( response.status ),
            HTTPCODE[ response.status ].label
        ]

        handler.response_sock.send( response.format )



#
# Tests!
#
when isMainModule:

    var reqstr = """host 33 /hosts 502:{"PATH":"/hosts","x-forwarded-for":"10.3.0.75","cache-control":"max-age=0","accept-language":"en-US,en;q=0.5","connection":"keep-alive","accept-encoding":"gzip, deflate","dnt":"1","accept":"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8","user-agent":"Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:35.0) Gecko/20100101 Firefox/35.0","host":"hotsoup.sunset.laika.com:8080","METHOD":"GET","VERSION":"HTTP/1.1","URI":"/hosts","PATTERN":"/hosts","URL_SCHEME":"http","REMOTE_ADDR":"10.3.0.75"},0:,"""

    var req  = parse_request( reqstr )
    var dreq = parse_request( """host 1234 @* 17:{"METHOD":"JSON"},21:{"type":"disconnect"},""" )

    # Request parsing.
    #
    doAssert( req.sender_id          == "host" )
    doAssert( req.conn_id            == "33" )
    doAssert( req.path               == "/hosts" )
    doAssert( req.remote_addr        == "10.3.0.75" )
    doAssert( req.scheme             == "http" )
    doAssert( req.meth               == "GET" )
    doAssert( req["DNT"]             == "1" )
    doAssert( req["X-Forwarded-For"] == "10.3.0.75" )

    doAssert( req.is_disconnect == false )

    var res = req.response
    res.status = HTTP_OK

    doAssert( res.sender_id == req.sender_id )
    doAssert( res.conn_id == req.conn_id )

    # Response headers
    #
    res.add_header( "alright", "yep" )
    res[ "something" ] = "nope"
    res[ "something" ] = "yep"
    doAssert( res["alright"]   == "yep" )
    doAssert( res["something"] == "yep" )

    # Client broadcasts
    #
    res.broadcast([ 1, 2, 3, 4 ])
    doAssert( res.conn_id == "1 2 3 4" )
    doAssert( res.format == "host 7:1 2 3 4, HTTP/1.1 200 OK\r\nalright: yep\r\nsomething: yep\r\nContent-Length: 2\r\n\r\nOK" )

    # Extended replies
    #
    doAssert( res.is_extended == false )
    res.extend( "sendfile" )
    doAssert( res.is_extended == true )
    doAssert( res.format == "host 9:X 1 2 3 4, 11:8:sendfile,]" )
    res.add_extended_data( "arg1", "arg2" )
    res.add_extended_data( "arg3" )
    doAssert( res.format == "host 9:X 1 2 3 4, 32:8:sendfile,4:arg1,4:arg2,4:arg3,]" )

    doAssert( dreq.is_disconnect == true )

    # Automatic body if none is specified
    #
    res.extended = nil
    res.body     = nil
    res.status   = HTTP_CREATED
    discard res.format
    doAssert( res.body == "Created" )

    echo "* Tests passed!"



import
    mongrel2,
    json,
    re

let handler = newM2Handler( "app", "tcp://127.0.0.1:9009", "tcp://127.0.0.1:9008" )
var data    = %*[] ## the JSON data to "remember"


proc demo( request: M2Request ): M2Response =
    ## This is a demonstraction handler action.
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


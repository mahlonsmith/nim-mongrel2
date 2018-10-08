
import src/mongrel2

let handler = newM2Handler( "mlist", "tcp://127.0.0.1:9019", "tcp://127.0.0.1:9018" )

proc woo( request: M2Request ): M2Response =
    var response = request.response

    response[ "Content-Type" ] = "text/plain"
    response.body   = "Hi there."
    response.status = HTTP_OK
    return response

# handler.action = woo
handler.run


import std/tables


const usingJS = defined(js)

type
  RetryStrategy* = enum
    ## Strategy to imploy when pantry gives a `too many requests` error
    ##
    ## * **Exception**: Throws an exception (default)
    ## * **Retry**: Trys again to make the request
    ## * **Sleep**: Waits until you can call pantry again but doesn't retry
    Exception
    Retry
    Sleep

when not usingJS:
  import std/httpclient
  type Clients = HttpClient or AsyncHttpClient
else:
  type Clients = void

# When using JS, `client` refers to the fetch options
type
  BasePantryClient*[T: Clients] = object
    client: T
    id*: string
    retry*: int
    strat*: RetryStrategy

when not usingJS:
  type
    PantryClient* = BasePantryClient[HttpClient]
      ## Pantry client used for interacting with the API
    AsyncPantryClient* = BasePantryClient[AsyncHttpClient]
      ## Async version of PantryClient_. Use this is you want to use async procs
    PantryClients* = PantryClient | AsyncPantryClient 
else:
  type
    PantryClient* = BasePantryClient[void]
    AsyncPantryClient* =  BasePantryClient[void]
    PantryClients* = AsyncPantryClient

# Different JSON objects used by pantry
type
  Basket* = object
    ## A basket stores json
    name*: string
    ttl*: int

  PantryDetails* = object
    ## Contains information about a pantry
    name*, description*: string
    errors*: seq[string]
    notifications*: bool
    percentFull*: int
    baskets*: Table[string, Basket]


# Exceptions
type
  PantryError* = object of CatchableError

  TooManyPantryRequests* = object of PantryError
    ## Raised when you are calling pantry too many times (limit is 2 times per second)

  BasketDoesntExist* = object of PantryError
    ## Raised if you make a request to a basket that doesn't exist

  InvalidPantryID* = object of PantryError
    ## Raised if you make a request use a pantry ID that is invalid

const 
  baseURL   = "https://getpantry.cloud/apiv1/pantry"
  userAgent = "pantry-nim (0.2.0) [https://github.com/ire4ever1190/pantry-nim]"

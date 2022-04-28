import std/httpclient
import std/tables



type
  Clients = HttpClient or AsyncHttpClient

  BasePantryClient*[T: Clients] = object
    client: T
    id*: string
    retry*: int
    strat*: RetryStrategy

  PantryClient* = BasePantryClient[HttpClient]

  AsyncPantryClient* = BasePantryClient[AsyncHttpClient]

  PantryClients* = PantryClient | AsyncPantryClient 

  Basket* = object
    ## A basket stores json
    # TODO: Cache data maybe?
    name*: string
    ttl*: int

  PantryDetails* = object
    ## Contains information about a pantry
    name*, description*: string
    errors*: seq[string]
    notifications*: bool
    percentFull*: int
    baskets*: Table[string, Basket]

  PantryError* = object of CatchableError

  TooManyPantryRequests* = object of PantryError
    ## Raised when you are calling pantry too many times (limit is 2 times per second)

  BasketDoesntExist* = object of PantryError
    ## Raised if you make a request to a basket that doesn't exist

  InvalidPantryID* = object of PantryError
    ## Raised if you make a request use a pantry ID that is invalid

  RetryStrategy* = enum
    ## Strategy to imploy when pantry gives a `too many requests` error
    ## * **Exception**: Throws an exception (default)
    ## * **Retry**: Trys again to make the request
    ## * **Sleep**: Waits until you can call pantry again but doesn't retry
    Exception
    Retry
    Sleep

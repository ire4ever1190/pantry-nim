import std/httpclient
import std/tables

type
  Clients = HttpClient or AsyncHttpClient

  BasePantryClient*[T: Clients] = ref object
    client: T
    id*: string

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


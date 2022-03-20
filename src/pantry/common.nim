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

  BaseBasket*[T: PantryClients] = object
    ## A basket stores json
    # TODO: Cache data maybe?
    client: T
    name*: string
    ttl*: int

  Basket* = BaseBasket[PantryClient] 
  AsyncBasket* = BaseBasket[AsyncPantryClient] 

  PantryDetails*[T: PantryClients] = object
    ## Contains information about a pantry
    name*, description*: string
    errors*: seq[string]
    notifications*: bool
    percentFull*: int
    baskets*: Table[string, BaseBasket[T]]

  PantryError* = object of CatchableError
